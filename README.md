# MultiBase

Multi-site Postgres platform you run and break on purpose: 2 EC2 Graviton nodes (us-east-1, eu-west-1) plus a home node, joined by Tailscale, MicroK8s, CloudNativePG, Argo CD, Prometheus/Grafana/Alloy, ClickHouse, and a Go `tsnet` prober.

## Layout

| Path                         | Purpose                                                                    |
| ---------------------------- | -------------------------------------------------------------------------- |
| `infra/terraform/persistent` | S3 backups, node IAM role, Roles Anywhere (optional), budget. Cents/month. |
| `infra/terraform/compute`    | VPC, SG, EC2 in two regions. Destroyable.                                  |
| `infra/tailscale`            | ACL policy as code (+ tests).                                              |
| `infra/home`, `infra/k8s`    | Home-node setup, MicroK8s join + Calico MTU fix.                           |
| `gitops/`                    | Argo CD root app, apps, Helm charts (postgres, observability, prober).     |
| `prober/`                    | Go service (tsnet) writing probe results to ClickHouse + Prometheus.       |
| `drills/`, `docs/`           | Failure drills, SLOs, runbooks, postmortems.                               |

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

## Golden path for a feature

1. Branch from `main` and write down the user-visible behavior and a test that would fail without it. Keep the change in its owning component (`prober/`, `gitops/charts/`, `infra/terraform/`, or `drills/`).
2. Implement the smallest vertical slice, including tests and configuration. Never commit credentials; use Kubernetes Secrets/SOPS or the existing AWS role flows.
3. Run the relevant local checks:
   - Go: `cd prober && gofmt -w *.go && go vet ./... && go test -race ./...`
   - Helm: `helm lint gitops/charts/<chart> && helm template test gitops/charts/<chart>`
   - Terraform: `terraform fmt -check -recursive infra/terraform`, then `terraform -chdir=infra/terraform/<persistent|compute> init -backend=false -input=false && terraform -chdir=infra/terraform/<persistent|compute> validate`
   - Shell: `bash -n path/to/script.sh`
4. Open a pull request. CI runs Go tests, Terraform formatting/validation, and Helm lint. Review the rendered manifests and the Terraform plan for unintended resource or cost changes. AWS plan access is read-only; apply stays an explicit operator action.
5. After merge, the image workflow publishes the prober tagged with the commit SHA. Update `gitops/charts/prober/values.yaml` to that tag in a reviewed change before expecting Argo CD to deploy it; image publishing does not currently bump the chart automatically.
6. Validate runtime behavior with Compose first. Only use AWS when needed, confirm the plan, and run `scripts/stop.sh --destroy` afterward if you want compute storage charges removed too. Add observed results and follow-up actions to the relevant runbook or postmortem.

## Known gaps

- Log shipping to ClickHouse (`multibase.logs`) has no ingester yet; Alloy currently ships host metrics only.
- Supabase image under CNPG is untested; default is the stock CNPG image (see `gitops/charts/postgres/values.yaml`).
- The MicroK8s control plane is stretched across regions; record behaviour in a drill.
