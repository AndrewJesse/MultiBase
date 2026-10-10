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

## Cost control
- `scripts/stop.sh` (default `--pause`): stops EC2 in both regions, then audits. Remaining cost is EBS (~$0.08/GB-month, 60 GB total by default) plus pennies of S3.
- `scripts/stop.sh --destroy`: removes compute entirely; `scripts/stop.sh --audit` reports billable resources.
- `scripts/start.sh`: resumes paused nodes or recreates them.

## First run
1. `aws login`; `BUDGET_EMAIL=you@example.com scripts/bootstrap.sh`
2. Create an ephemeral, reusable, tagged (`tag:node`) Tailscale auth key; `TS_AUTHKEY=... scripts/start.sh`
3. Run `infra/home/setup.sh` on the home node; `infra/k8s/cluster-join.sh`
4. Replace the bucket name in `gitops/`; `gitops/bootstrap/install.sh`

## Milestones
1. Nodes, tailnet, MicroK8s, Argo CD. 2. CNPG + S3 backups + restore proof. 3. Alloy, Prometheus, ClickHouse, Grafana. 4. Prober + SLOs (`docs/slo.md`). 5. Drills (`drills/`) + postmortems.

## Known gaps
- Log shipping to ClickHouse (`multibase.logs`) has no ingester yet; Alloy currently ships host metrics only.
- Supabase image under CNPG is untested; default is the stock CNPG image (see `gitops/charts/postgres/values.yaml`).
- The MicroK8s control plane is stretched across regions; record behaviour in a drill.
