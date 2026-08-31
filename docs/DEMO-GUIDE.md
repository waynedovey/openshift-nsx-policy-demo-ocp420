# Presenter guide

## Before the session

```bash
./scripts/preflight.sh
./scripts/setup.sh
./scripts/show-vms.sh
```

Confirm all three VMs have a `192.0.2.x` CUDN address.

## Stage 0 - CUDN only

Run:

```bash
./scripts/test.sh baseline
```

Say:

> CUDN is replacing the logical network/segment. It gives the VMs connectivity across the cluster. It is not itself the firewall.

## Stage 1 - BANP

Apply/run through `./scripts/demo.sh`.

Say:

> BANP is the bottom-level platform guardrail. Here we make Corporate-to-APP denied by default.

Expected Corporate -> APP:8443: **DENY**.

## Stage 2 - NetworkPolicy

Say:

> The APP team adds a namespace NetworkPolicy. Because NetworkPolicy sits above BANP, the application can override this baseline rule.

Expected Corporate -> APP:8443: **ALLOW**.

## Stage 3 - DB NetworkPolicy

Say:

> The database team now isolates the Windows DB VM. Jenkins gets only 1435. Rogue is deliberately allowed for a moment so we can prove central security wins in the next stage.

## Stage 4 - ANP

Say:

> This is the closest equivalent to centrally managed NSX-T DFW. Security can make a strong Allow, a strong Deny, or Pass the decision down to the namespace owner.

Show:

```text
APP -> DB:1435       ALLOW
APP -> DB:61435      ALLOW
APP -> DB:8080       DENY
Rogue -> DB:1435     DENY
Jenkins -> DB:1435   ALLOW
Jenkins -> DB:61435  DENY
```

## Finish with the VM view

```bash
./scripts/show-vms.sh
oc get pods -A -l demo.openshift.io/component=vm \
  -L demo.openshift.io/security-group \
  -L demo.openshift.io/service
```

Point out that `win2022-app`, `win2022-db`, and `rhel9-ops` are real OpenShift Virtualization guests and their launcher pods carry the security-group labels.

For a manual guest-side check:

```bash
./scripts/manual-vm-tests.sh
```
