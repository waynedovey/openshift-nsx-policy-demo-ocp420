# Live Demo Guide

## Prepare an existing VM lab

```bash
./scripts/validate-repo.sh
./scripts/preflight.sh
./scripts/refresh-policy-demo.sh
./scripts/show-policy-paths.sh
./scripts/test.sh baseline
```

Do not proceed if `refresh-policy-demo.sh` cannot prove that the dedicated `nsx-admin-*` target is reachable before policy.

## Stage 0 — network topology only

```bash
./scripts/reset-policies.sh
./scripts/test.sh baseline
```

Say: the Primary Layer2 CUDN is the NSX Segment equivalent. It provides the VM workload network. No policy has been applied yet. The separate `nsx-admin-*` namespaces are ordinary default-network workloads reserved for the administrative-policy demonstration.

## Stage 1 — BANP baseline

```bash
oc apply -f manifests/policies/10-banp-app-guardrail.yaml
./scripts/test.sh banp
```

Expected:

```text
ADMIN Corporate -> target:8443  DENY
ADMIN Jenkins -> target:8443    DENY
ADMIN Rogue -> target:8443      ALLOW
CUDN Corporate -> WinAPP:8443   ALLOW
```

Say: BANP is a cluster-admin fallback/baseline. Here it is demonstrated on ordinary default-network workloads so the path is deterministic and testable.

## Stage 2 — Windows APP microsegmentation

```bash
oc apply -f manifests/policies/20-networkpolicy-app.yaml
./scripts/test.sh app-np
```

Expected:

```text
CUDN Corporate -> WinAPP:8443  DENY
CUDN APP -> WinAPP:8443        ALLOW
```

Say: this is the actual NSX DFW-to-OpenShift workload migration path. Standard NetworkPolicy is enforcing traffic to a real Windows VM on the Primary CUDN.

## Stage 3 — Windows DB microsegmentation

```bash
oc apply -f manifests/policies/30-networkpolicy-db.yaml
./scripts/test.sh db-np
```

Expected:

```text
CUDN APP -> WinDB:1435          ALLOW
CUDN APP -> WinDB:61435         ALLOW
CUDN APP -> WinDB:8080          DENY
CUDN Jenkins -> WinDB:1435      ALLOW
CUDN Jenkins -> WinDB:61435     DENY
CUDN Rogue -> WinDB:1435        DENY
```

## Stage 4 — ANP / BANP precedence

```bash
oc apply -f manifests/policies/40-adminnetworkpolicy-default-network.yaml
./scripts/test.sh final
```

Expected:

```text
ADMIN Corporate -> target:8443  ALLOW
ADMIN Rogue -> target:8443      DENY
ADMIN Jenkins -> target:8443    DENY
```

Say: ANP Allow is authoritative over the lower BANP Deny for Corporate. ANP Deny centrally blocks Rogue. ANP Pass for Jenkins delegates to lower policy, where BANP still denies it.

## One-command presentation

```bash
./scripts/demo.sh
```

Non-interactive:

```bash
DEMO_AUTO=true ./scripts/demo.sh
```

## Troubleshooting

```bash
./scripts/doctor.sh
```

The most important check is that all `nsx-admin-*` namespaces are default-network-only. None should have the Primary UDN label.
