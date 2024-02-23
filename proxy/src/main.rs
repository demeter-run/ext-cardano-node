use std::fs::File;
use std::io::BufReader;
use std::net::SocketAddr;
use std::str::FromStr;
use std::sync::Arc;

use futures::FutureExt;
use tokio::io::copy_bidirectional;
use tokio::net::{TcpListener, TcpStream};
use tokio_rustls::TlsAcceptor;

use crate::config::Config;

mod config;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let config = Config::new();

    let listen_addr = SocketAddr::from_str(&config.proxy_addr).unwrap();
    let server_addr = SocketAddr::from_str(&config.node_addr).unwrap();

    let listener = TcpListener::bind(listen_addr).await?;
    let certs = rustls_pemfile::certs(&mut BufReader::new(&mut File::open(config.ssl_crt_path)?))
        .collect::<Result<Vec<_>, _>>()?;
    let private_key =
        rustls_pemfile::private_key(&mut BufReader::new(&mut File::open(config.ssl_key_path)?))?
            .unwrap();

    let config = rustls::ServerConfig::builder()
        .with_no_client_auth()
        .with_single_cert(certs, private_key)?;
    let acceptor = TlsAcceptor::from(Arc::new(config.clone()));

    format!("Proxy server listening");

    loop {
        let (inbound, _) = listener.accept().await?;
        let acceptor = acceptor.clone();

        let mut outbound = TcpStream::connect(server_addr.clone()).await?;

        tokio::spawn(async move {
            let mut tls_stream = acceptor.accept(inbound).await.unwrap();
            let (_, server_connection) = tls_stream.get_ref();
            println!("Server name {:?}", server_connection.server_name());

            copy_bidirectional(&mut tls_stream, &mut outbound)
                .map(|r| {
                    dbg!(&r);

                    if let Err(e) = r {
                        println!("Failed to transfer; error={}", e);
                    }
                })
                .await;
        });
    }
}
