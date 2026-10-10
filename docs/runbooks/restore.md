# Runbook: restore from S3

1. Scale a scratch cluster: apply a CNPG `Cluster` with `bootstrap.recovery` pointing at `ObjectStore/pg-backups` (optionally `recoveryTarget.targetTime`) in a `restore-test` namespace.
2. Wait for the cluster to become healthy, then compare row counts / checksums with the source.
3. Delete the namespace.

`scripts/stop.sh --destroy` followed by `scripts/start.sh` and re-applying the postgres app with `bootstrap.recovery` exercises the same path.
