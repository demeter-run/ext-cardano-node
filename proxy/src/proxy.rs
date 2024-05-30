use async_trait::async_trait;
use futures_util::future::join_all;
use leaky_bucket::RateLimiter;
use pingora::{
    apps::ServerApp, connectors::TransportConnector, protocols::Stream, server::ShutdownWatch,
    tls::ssl::NameType, upstreams::peer::BasicPeer, Error, Result,
};
use regex::Regex;
use std::{net::SocketAddr, sync::Arc};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::lookup_host,
    select,
};
use tracing::{error, info};

use crate::{config::Config, Consumer, State, Tier};

struct Context {
    consumer: Consumer,
    namespace: String,
    instance: String,
}
impl Context {
    pub fn new(consumer: &Consumer, instance: &str, namespace: &str) -> Self {
        Self {
            consumer: consumer.clone(),
            namespace: namespace.into(),
            instance: instance.into(),
        }
    }
}

enum DuplexEvent {
    ClientRead(usize),
    InstanceRead(usize),
}

pub struct ProxyApp {
    client_connector: TransportConnector,
    host_regex: Regex,
    state: Arc<State>,
    config: Arc<Config>,
}
impl ProxyApp {
    pub fn new(config: Arc<Config>, state: Arc<State>) -> Self {
        ProxyApp {
            client_connector: TransportConnector::new(None),
            host_regex: Regex::new(r"(dmtr_[\w\d-]+)\..+").unwrap(),
            config,
            state,
        }
    }

    async fn duplex(
        &self,
        mut io_client: Stream,
        mut io_instance: Stream,
        state: Arc<State>,
        mut ctx: Context,
    ) -> Result<()> {
        ctx.consumer.inc_connections(self.state.clone()).await;

        state
            .metrics
            .inc_total_connections(&ctx.consumer, &ctx.namespace, &ctx.instance);

        let mut io_client_buf = [0; 1024];
        let mut io_instance_buf = [0; 1024];

        loop {
            let event: DuplexEvent;

            select! {
                n = io_client.read(&mut io_client_buf) => {
                    match n {
                        Ok(b) => event = DuplexEvent::ClientRead(b),
                        Err(err) => {
                            error!(error = err.to_string(), "client read error");
                            event = DuplexEvent::ClientRead(0);
                        },
                    }
                },
                n = io_instance.read(&mut io_instance_buf) => {
                    match n {
                        Ok(b) => event = DuplexEvent::InstanceRead(b),
                        Err(err) => {
                            error!(error = err.to_string(), "instance read error");
                            event = DuplexEvent::InstanceRead(0);
                        },
                    }
                },
            }

            match event {
                DuplexEvent::ClientRead(0) | DuplexEvent::InstanceRead(0) => {
                    ctx.consumer.dec_connections(self.state.clone()).await;
                    state.metrics.dec_total_connections(
                        &ctx.consumer,
                        &ctx.namespace,
                        &ctx.instance,
                    );

                    let active_connections =
                        ctx.consumer.get_active_connections(state.clone()).await;
                    info!(
                        consumer = ctx.consumer.to_string(),
                        active_connections, "client disconnected"
                    );
                    return Ok(());
                }
                DuplexEvent::ClientRead(bytes) => {
                    state.metrics.count_total_packages_bytes(
                        &ctx.consumer,
                        &ctx.namespace,
                        &ctx.instance,
                        bytes,
                    );

                    let _ = io_instance.write_all(&io_client_buf[0..bytes]).await;
                    let _ = io_instance.flush().await;
                }
                DuplexEvent::InstanceRead(bytes) => {
                    self.limiter(&ctx.consumer, bytes).await?;

                    state.metrics.count_total_packages_bytes(
                        &ctx.consumer,
                        &ctx.namespace,
                        &ctx.instance,
                        bytes,
                    );

                    let _ = io_client.write_all(&io_instance_buf[0..bytes]).await;
                    let _ = io_client.flush().await;
                }
            }
        }
    }

    async fn has_limiter(&self, consumer: &Consumer) -> bool {
        let rate_limiter_map = self.state.limiter.read().await;
        rate_limiter_map.get(&consumer.key).is_some()
    }

    async fn add_limiter(&self, consumer: &Consumer, tier: &Tier) {
        let rates = tier
            .rates
            .iter()
            .map(|r| {
                Arc::new(
                    RateLimiter::builder()
                        .initial(r.limit)
                        .interval(r.interval)
                        .refill(r.limit)
                        .build(),
                )
            })
            .collect();

        self.state
            .limiter
            .write()
            .await
            .insert(consumer.key.clone(), rates);
    }

    async fn limiter(&self, consumer: &Consumer, amount_of_bytes: usize) -> Result<()> {
        if !self.has_limiter(consumer).await {
            let tiers = self.state.tiers.read().await.clone();
            let tier = tiers.get(&consumer.tier);
            if tier.is_none() {
                return Err(Error::new(pingora::ErrorType::AcceptError));
            }
            let tier = tier.unwrap();

            let refreshed_consumer = match self.state.get_consumer(&consumer.key).await {
                Some(consumer) => consumer,

                // Port was deleted.
                None => return Err(Error::new(pingora::ErrorType::ConnectRefused)),
            };

            self.add_limiter(&refreshed_consumer, tier).await;
        }

        let rate_limiter_map = self.state.limiter.read().await.clone();
        let rates = rate_limiter_map.get(&consumer.key).unwrap();

        join_all(
            rates
                .iter()
                .map(|r| async { r.acquire(amount_of_bytes).await }),
        )
        .await;

        Ok(())
    }

    async fn get_tier(&self, tier: &str) -> Result<Tier> {
        let tiers = self.state.tiers.read().await.clone();
        let tier = tiers.get(tier);
        if tier.is_none() {
            return Err(Error::new(pingora::ErrorType::AcceptError));
        }
        let tier = tier.unwrap().clone();
        Ok(tier)
    }

    async fn limiter_connection(&self, consumer: &Consumer) -> Result<()> {
        let tier = self.get_tier(&consumer.tier).await?;

        if consumer.active_connections >= tier.max_connections {
            return Err(Error::new(pingora::ErrorType::Custom(
                "Connections tier exceeded for consumer",
            )));
        }

        Ok(())
    }
}

#[async_trait]
impl ServerApp for ProxyApp {
    async fn process_new(
        self: &Arc<Self>,
        io_client: Stream,
        _shutdown: &ShutdownWatch,
    ) -> Option<Stream> {
        let hostname = io_client.get_ssl()?.servername(NameType::HOST_NAME);
        if hostname.is_none() {
            error!("hostname is not present in the certificate");
            return None;
        }

        let captures_result = self.host_regex.captures(hostname?);
        if captures_result.is_none() {
            error!("invalid hostname pattern");
            return None;
        }
        let captures = captures_result?;

        let token = captures.get(1)?.as_str().to_string();

        let consumer = self.state.get_consumer(&token).await?;
        let instance = format!(
            "node-{}-{}.{}:{}",
            consumer.network, consumer.version, self.config.node_dns, self.config.node_port
        );

        let namespace = self.config.proxy_namespace.clone();
        if let Err(err) = self.limiter_connection(&consumer).await {
            self.state
                .metrics
                .count_total_connections_denied(&consumer, &namespace, &instance);

            let tier_result = self.get_tier(&consumer.tier).await;
            if let Err(err) = tier_result {
                error!(
                    error = err.to_string(),
                    consumer = consumer.to_string(),
                    "Error to get the tier"
                );
                return None;
            }

            let tier = tier_result.unwrap();
            error!(
                error = err.to_string(),
                consumer = consumer.to_string(),
                active_connections = consumer.active_connections,
                max_connections = tier.max_connections
            );

            return None;
        }

        let context = Context::new(&consumer, &instance, &namespace);

        let lookup_result = lookup_host(&instance).await;
        if let Err(err) = lookup_result {
            error!(error = err.to_string(), "fail to lookup ip");
            return None;
        }
        let lookup: Vec<SocketAddr> = lookup_result.unwrap().collect();
        let node_addr = lookup.first()?;

        let proxy_to = BasicPeer::new(&node_addr.to_string());

        let io_instance = self.client_connector.new_stream(&proxy_to).await;

        match io_instance {
            Ok(io_instance) => {
                if let Err(err) = self
                    .duplex(io_client, io_instance, self.state.clone(), context)
                    .await
                {
                    error!(error = err.to_string(), "proxy duplex error");
                }

                None
            }
            Err(e) => {
                error!("failed to create instance session: {}", e);
                None
            }
        }
    }
}
