# SLOs

| SLI | Objective | Window |
|---|---|---|
| Successful `SELECT 1` through the primary service, from every site | 99.9% | 30 days |
| Query p95 latency (connect + query) | < 50 ms same-region, < 250 ms cross-region | 30 days |
| Replica replay lag | < 5 s | 99% of samples |
| Auth endpoint availability | 99.5% | 30 days |

Source: `multibase_probe_*` metrics from the prober; raw rows in ClickHouse `multibase.probe_results`.
Alerts: multi-window burn rate in `gitops/charts/observability/templates/config.yaml`.
