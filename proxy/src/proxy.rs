use std::error::Error;
use std::fs::File;
use std::io::BufReader;
use std::net::SocketAddr;
use std::str::FromStr;
use std::sync::Arc;
use tokio::io::copy_bidirectional;
use tokio::net::{lookup_host, TcpListener, TcpStream};
use tokio::sync::RwLock;
use tokio_rustls::TlsAcceptor;
use tracing::{error, info};

use crate::State;

pub async fn start(rw_state: Arc<RwLock<State>>) {
    let state = rw_state.read().await.clone();

    let proxy_addr = SocketAddr::from_str(&state.config.proxy_addr).unwrap();
    let listener_result = TcpListener::bind(proxy_addr).await;
    if let Err(err) = listener_result {
        error!(error = err.to_string(), "fail to bind tcp server listener");
        std::process::exit(1);
    }
    let listener = listener_result.unwrap();

    let tls_acceptor_result = tls_acceptor(&state);
    if let Err(err) = tls_acceptor_result {
        error!(error = err.to_string(), "fail to configure tls");
        std::process::exit(1);
    }
    let tls_acceptor = tls_acceptor_result.unwrap();

    info!(addr = proxy_addr.to_string(), "proxy listening");

    loop {
        let accept_result = listener.accept().await;
        if let Err(err) = accept_result {
            error!(error = err.to_string(), "fail to accept client");
            continue;
        }
        let (inbound, _) = accept_result.unwrap();

        let tls_acceptor = tls_acceptor.clone();
        let state = rw_state.read().await.clone();

        tokio::spawn(async move {
            let mut tls_stream = tls_acceptor.accept(inbound).await.unwrap();
            let (_, server_connection) = tls_stream.get_ref();

            let hostname = server_connection.server_name();
            if hostname.is_none() {
                error!("hostname is not present in the certificate");
                return;
            }

            let captures_result = state.host_regex.captures(hostname.unwrap());
            if captures_result.is_none() {
                error!("invalid hostname pattern");
                return;
            }

            let captures = captures_result.unwrap();
            let network = captures.get(2).unwrap().as_str().to_string();
            let version = captures.get(3).unwrap().as_str().to_string();

            let node_host = format!("node-{network}-{version}:{}", state.config.node_port);
            let lookup_result = lookup_host(node_host).await;
            if let Err(err) = lookup_result {
                error!(error = err.to_string(), "fail to lookup ip");
                return;
            }
            let lookup: Vec<SocketAddr> = lookup_result.unwrap().collect();

            let node_addr = lookup.first().unwrap();
            let outbound_result = TcpStream::connect(node_addr).await;
            if let Err(err) = outbound_result {
                error!(error = err.to_string(), "fail to connect to the node");
                return;
            }
            let mut outbound = outbound_result.unwrap();

            if let Err(err) = copy_bidirectional(&mut tls_stream, &mut outbound).await {
                error!(error = err.to_string(), "failed to proxy data");
            }
        });
    }
}

fn tls_acceptor(state: &State) -> Result<TlsAcceptor, Box<dyn Error>> {
    let certs = rustls_pemfile::certs(&mut BufReader::new(&mut File::open(
        &state.config.ssl_crt_path,
    )?))
    .collect::<Result<Vec<_>, _>>()?;
    let private_key = rustls_pemfile::private_key(&mut BufReader::new(&mut File::open(
        &state.config.ssl_key_path,
    )?))?
    .unwrap();

    let config = rustls::ServerConfig::builder()
        .with_no_client_auth()
        .with_single_cert(certs, private_key)?;
    let acceptor = TlsAcceptor::from(Arc::new(config.clone()));

    Ok(acceptor)
}
