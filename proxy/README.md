# Node Proxy

This proxy will allow Node to be accessed externally.

## Environment

| Key              | Value                   |
| ---------------- | ----------------------- |
| PROXY_ADDR       | 0.0.0.0:5000            |
| PROXY_NAMESPACE  |                         |
| PROMETHEUS_ADDR  | 0.0.0.0:9090            |
| SSL_CRT_PATH     | /localhost.crt          |
| SSL_KEY_PATH     | /localhost.key          |
| NODE_PORT        |                         |
| NODE_DNS         | internal k8s dns        |
| PROXY_TIERS_PATH | path of tiers toml file |

## Rate limit

To define rate limits, it's necessary to create a file with the limiters available that the ports can use. The limit of each tier can be configured using `s = second`, `m = minute`, `h = hour` and `d = day` eg: `5s` bucket of 5 seconds. The limiter will be by bytes. The max_connections will limit the number of connections

```toml
[[tiers]]
name = "tier0"
max_connections = 1
[[tiers.rates]]
interval = "1s"
limit = 1024 
[[tiers.rates]]
interval = "1m"
limit = 1024
[[tiers.rates]]
interval = "1h"
limit = 1024
[[tiers.rates]]
interval = "1d"
limit = 1024

[[tiers]]
name = "tier1"
max_connections = 1
[[tiers.rates]]
interval = "5s"
limit = 1024
```

after configuring, the file path must be set at the env `PROXY_TIERS_PATH`.

## Commands

To generate the CRD will need to execute `crdgen`

```bash
cargo run --bin=crdgen
```

and execute the operator

```bash
cargo run
```

## Metrics

to collect metrics for Prometheus, an HTTP API will enable the route /metrics.

```
/metrics
```
