# GOLDEN

The canonical path for understanding this repo and for shipping a feature that touches every part of it.

## 1. Understand the repo (read in this order)

1. `README.md`: what MultiBase is and how to start it locally.
2. `docker-compose.yml`: the whole local system (Postgres primary + replica, ClickHouse, prober, optional Grafana/Prometheus). Run `docker compose up -d --build` and confirm `docker compose ps` is healthy.
3. `prober/`: Go service. Read `main.go` (wiring, metrics, `/healthz`), `probes.go` (probe definitions), `clickhouse.go` (result writer), `probes_test.go`.
4. `clickhouse/schema.sql`: where probe results land (`multibase.probe_results`).
5. `local/`: local Postgres config, Prometheus scrape config, Grafana dashboards.
6. `gitops/`: how the same pieces run in Kubernetes. `bootstrap/` installs Argo CD, `apps/` are Argo applications, `charts/{postgres,observability,prober}` are the Helm charts.
7. `infra/`: `terraform/persistent` (S3, IAM, budget), `terraform/compute` (VPC, EC2, destroyable), `tailscale/` (ACL as code), `k8s/` and `home/` (node setup).
8. `drills/` and `docs/`: failure drills, `docs/slo.md`, runbooks, postmortems. These define what "healthy" means and how it gets broken.
9. `scripts/`: `start.sh`/`stop.sh` (cost control), `bootstrap.sh`, `new-feature.sh`.
10. `.github/workflows/`: what CI enforces (Go vet/test, Terraform fmt/validate, Helm lint, Tailscale ACL).

Rule of thumb: local Compose needs no AWS, Tailscale, or Kubernetes. Only touch cloud pieces when the feature needs them, and review any Terraform plan before applying.

## 2. Add a feature end to end

Example feature: a new probe, `replica_lag`.

1. **Draft.** `scripts/new-feature.sh "replica lag probe"` creates `features/replica-lag-probe.md`. Fill in the goal and acceptance checks (each verifiable locally).
2. **Prober (Go).** Add the probe in `prober/probes.go`, register it in `main.go`, and expose its Prometheus metric. Add a unit test in `probes_test.go`. Run `cd prober && go vet ./... && go test -race ./...`.
3. **ClickHouse.** If the probe needs new columns or tables, update `clickhouse/schema.sql` and the writer in `prober/clickhouse.go`.
4. **Local stack.** Update `docker-compose.yml` and `local/` (Postgres config, `prometheus.yml`, Grafana dashboard) so the feature is visible. Verify with `docker compose up -d --build`, `curl localhost:9100/metrics`, and a ClickHouse query.
5. **GitOps.** Mirror the change in `gitops/charts/` (prober values/templates, observability rules and dashboards, postgres values). Check with `helm lint` and `helm template`.
6. **Infra (only if needed).** Terraform in `infra/terraform/*`, Tailscale ACL in `infra/tailscale`. Run `terraform fmt -check`, `terraform validate`, and review the plan.
7. **Reliability.** Add or update an SLO in `docs/slo.md`, a drill in `drills/` if the feature has a failure mode, and a runbook in `docs/runbooks/`.
8. **CI.** Confirm `.github/workflows/` covers the new paths.
9. **Ship.** Stage only intended files, commit, open a PR, wait for CI green.

Definition of done: acceptance checks pass locally, tests pass, charts lint, docs/SLO/runbook updated, CI green.
