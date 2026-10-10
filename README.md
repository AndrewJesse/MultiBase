# MultiBase

Multi-site Postgres platform you run and break on purpose: 2 EC2 Graviton nodes (us-east-1, eu-west-1) plus a home node, joined by Tailscale, MicroK8s, CloudNativePG, Argo CD, Prometheus/Grafana/Alloy, ClickHouse, and a Go `tsnet` prober.

## Layout
| Path | Purpose |
|---|---|
| `infra/terraform/persistent` | S3 backups, node IAM role, Roles Anywhere (optional), budget. Cents/month. |
| `infra/terraform/compute` | VPC, SG, EC2 in two regions. Destroyable. |
| `infra/tailscale` | ACL policy as code (+ tests). |
| `infra/home`, `infra/k8s` | Home-node setup, MicroK8s join + Calico MTU fix. |
| `gitops/` | Argo CD root app, apps, Helm charts (postgres, observability, prober). |
| `prober/` | Go service (tsnet) writing probe results to ClickHouse + Prometheus. |
| `drills/`, `docs/` | Failure drills, SLOs, runbooks, postmortems. |

## Cheap local learning loop
You do not need AWS, Tailscale, Kubernetes, or cloud credentials for normal feature work. Docker Compose runs a local PostgreSQL primary and streaming replica, ClickHouse, and the Go prober; Prometheus and Grafana are optional. All published ports bind to `127.0.0.1`, and the local-only passwords are not for reuse elsewhere.

```sh
docker compose up -d --build
docker compose ps
curl -fsS http://localhost:9100/healthz
curl -fsS http://localhost:9100/metrics | grep multibase_probe_total
docker compose exec replica psql -U app -d app -c 'SELECT pg_is_in_recovery();'
curl -fsS 'http://localhost:8123/?query=SELECT%20count()%20FROM%20multibase.probe_results'
```

The replica query should return `t`; probe results appear in ClickHouse after a flush. Add the dashboards when you want them: `docker compose --profile dashboards up -d`, then open Grafana at `http://localhost:3000` (`admin` / `localdev`) or Prometheus at `http://localhost:9090`. No Supabase auth endpoint is configured locally, so the auth probe is omitted.

Stop containers with `docker compose down`; named volumes persist locally. To reset all local database and dashboard data, use `docker compose down -v`.

## Cost control
- The local Compose workflow makes no AWS calls and incurs no AWS charges.
- `scripts/stop.sh` (default `--pause`): stops EC2 in both regions, then audits. Paused EC2 still retains billable EBS; destroy compute with `scripts/stop.sh --destroy` to remove those volumes too.
- `scripts/stop.sh --destroy`: removes compute entirely; `scripts/stop.sh --audit` reports billable resources.
- `scripts/start.sh`: resumes paused nodes or recreates them.

## Optional AWS and multi-site work
Only use AWS when you specifically want to practice cloud infrastructure or cross-region drills. The persistent S3/IAM/OIDC/budget foundation exists, but EC2 and Kubernetes have not been deployed. `scripts/start.sh` creates paid resources; check its Terraform plan first, and use `scripts/stop.sh --destroy` when done to remove EC2 and EBS. The budget is an alert, not a spending cap. For the local feature workflow, start with Compose above.

## Milestones
1. Nodes, tailnet, MicroK8s, Argo CD. 2. CNPG + S3 backups + restore proof. 3. Alloy, Prometheus, ClickHouse, Grafana. 4. Prober + SLOs (`docs/slo.md`). 5. Drills (`drills/`) + postmortems.

## Project status
The repository has Terraform for the persistent AWS foundation and the two-region compute stack, GitOps charts, the Go prober, CI checks, and drill/runbook scaffolding. The persistent stack (S3 backup bucket, IAM/OIDC roles, and budget) was applied; the compute stack and Kubernetes platform have not been deployed or end-to-end verified. Treat Supabase-on-CNPG compatibility, backups/restores, monitoring ingestion, and failure drills as unproven until their acceptance checks have passed.

## Add a feature
Run `scripts/new-feature.sh "replica lag alert"`. It creates a short draft in `features/` and makes it visible in `git diff` without staging its contents. Edit that draft, then implement the change and its test.

For normal feature work, stay local: `cd prober && go test ./...`, then use `docker compose up -d --build` to try the feature with Postgres, its replica, and ClickHouse. Use `docker compose --profile dashboards up -d` when you need Grafana and Prometheus. Terraform or AWS is optional and only needed for cloud-specific features; review the plan before applying. Once satisfied, stage the files you want, commit, and open a PR; CI runs the Go, Terraform, and Helm checks.

## Known gaps
- Log shipping to ClickHouse (`multibase.logs`) has no ingester yet; Alloy currently ships host metrics only.
- Supabase image under CNPG is untested; default is the stock CNPG image (see `gitops/charts/postgres/values.yaml`).
- The MicroK8s control plane is stretched across regions; record behaviour in a drill.
