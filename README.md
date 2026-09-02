# NSX-T Policy Migration Demo for OpenShift 4.20

GitHub-ready demo that maps common NSX-T segmentation and distributed-firewall concepts to OpenShift networking and network security controls.

The repository targets the **OpenShift 4.20 feature/API set** and has been exercised on an **OpenShift 4.21.10 lab** with OVN-Kubernetes and OpenShift Virtualization.

## Final validated architecture

Live testing established two separate, reliable policy planes:

| Demo plane | Network | Workloads | Policy API |
|---|---|---|---|
| Workload microsegmentation | Primary Layer2 CUDN `192.0.2.0/24` | Windows APP, Windows DB, RHEL and CUDN client probes | `NetworkPolicy` |
| Administrative policy hierarchy | Cluster default network | dedicated `nsx-admin-*` pods | `AdminNetworkPolicy` + `BaselineAdminNetworkPolicy` |

The dedicated admin namespaces **do not** have the `k8s.ovn.org/primary-user-defined-network` label. They are ordinary default-network-only namespaces. This is deliberate.

A Primary-CUDN pod also receives an infrastructure-locked cluster-network address, but validation showed that address is not a suitable workload endpoint for this demo. The final repository never uses it for ANP/BANP connectivity tests.

## Topology

```text
                        OpenShift cluster

     WORKLOAD PLANE                         ADMIN POLICY PLANE
     --------------                         ------------------

 Primary Layer2 CUDN                     Cluster default network
 nsx-demo 192.0.2.0/24                   dedicated nsx-admin-* namespaces
          |                                       |
   +------+------+                         +------+------+------+
   |             |                         |      |      |      |
Win APP       Win DB                    target   corp  jenkins rogue
:8443        :1435/:61435/:8080         :8443
   |             |                         |
   +-- NetworkPolicy                      +-- BANP / ANP
```

## Workloads

### Primary CUDN workload plane

| Namespace | Workload | Purpose |
|---|---|---|
| `nsx-demo-app` | `win2022-app` | Windows Server 2022 APP VM, TCP/8443 |
| `nsx-demo-db` | `win2022-db` | Windows Server 2022 DB VM, TCP/1435, 61435, 8080 |
| `nsx-demo-ops` | `rhel9-ops` | RHEL 9 OPS VM, TCP/9090 |
| `nsx-demo-app` | `app-probe` | APP-group CUDN source |
| `nsx-demo-ops` | `jenkins-probe` | Jenkins-style CUDN source |
| `nsx-demo-corp` | `corporate-client` | corporate CUDN source |
| `nsx-demo-rogue` | `rogue-client` | rogue CUDN source |

### Dedicated default-network admin policy plane

| Namespace | Workload | Purpose |
|---|---|---|
| `nsx-admin-app` | `admin-app-target` | ANP/BANP target, TCP/8443 |
| `nsx-admin-corp` | `admin-corporate-client` | corporate admin-policy source |
| `nsx-admin-ops` | `admin-jenkins-client` | Jenkins admin-policy source |
| `nsx-admin-rogue` | `admin-rogue-client` | rogue admin-policy source |

## NSX-T mapping

| NSX-T concept | OpenShift demo equivalent |
|---|---|
| Segment / logical switch | `ClusterUserDefinedNetwork` |
| Security Group | labels |
| Dynamic Group | label selectors |
| IP Group | `NetworkPolicy` `ipBlock` example |
| Application DFW microsegmentation | namespace `NetworkPolicy` on the Primary CUDN |
| Mandatory central admin rule | `AdminNetworkPolicy` on dedicated default-network workloads |
| Baseline/fallback guardrail | `BaselineAdminNetworkPolicy` on dedicated default-network workloads |
| VLAN-backed secondary network | optional Localnet CUDN + `MultiNetworkPolicy` example |

## Requirements

- OpenShift 4.20 or 4.21 lab
- OVN-Kubernetes
- OpenShift Virtualization
- `ClusterUserDefinedNetwork` API
- `AdminNetworkPolicy` API
- `BaselineAdminNetworkPolicy` API
- RHEL 9 DataSource
- generalized Windows Server 2022 DataSource
- permissions to create namespaces, deployments, CUDN, NetworkPolicy, ANP and BANP

Default Windows DataSource:

```text
openshift-virtualization-os-images/win2022-demo-v2
```

Override values in `config/lab.env` if needed.

## Existing working VM lab: upgrade to this final demo

If your Windows/RHEL VMs are already running, you do **not** need to recreate them.

```bash
./scripts/validate-repo.sh
./scripts/preflight.sh
./scripts/refresh-policy-demo.sh
```

`refresh-policy-demo.sh`:

1. resets only demo policy objects;
2. creates the four new `nsx-admin-*` default-network namespaces;
3. updates the CUDN client probes;
4. creates the dedicated admin-policy probes;
5. proves the admin target is reachable before policy;
6. runs the full baseline test.

It does not recreate the Windows or RHEL VMs.

Then:

```bash
./scripts/show-policy-paths.sh
./scripts/demo.sh
```

## Fresh deployment

```bash
./scripts/validate-repo.sh
./scripts/preflight.sh
./scripts/setup.sh
./scripts/demo.sh
```

## Demo stages

### Stage 0 — topology only

No firewall policies are present.

Expected examples:

```text
CUDN Corporate -> WinAPP:8443    ALLOW
CUDN APP -> WinDB:1435           ALLOW
CUDN Rogue -> WinDB:1435         ALLOW
ADMIN Corporate -> target:8443   ALLOW
ADMIN Jenkins -> target:8443     ALLOW
ADMIN Rogue -> target:8443       ALLOW
```

Talking point: the CUDN is the NSX Segment equivalent; creating the logical network does not itself create firewall rules.

### Stage 1 — BANP baseline

Applies `manifests/policies/10-banp-app-guardrail.yaml`.

```text
ADMIN Corporate -> target:8443   DENY
ADMIN Jenkins -> target:8443     DENY
ADMIN Rogue -> target:8443       ALLOW
CUDN Corporate -> WinAPP:8443    ALLOW
```

Talking point: BANP supplies a cluster-admin baseline on the admin policy plane, independently of the VM CUDN workload plane.

### Stage 2 — Windows APP NetworkPolicy

Applies `manifests/policies/20-networkpolicy-app.yaml`.

```text
CUDN Corporate -> WinAPP:8443    DENY
CUDN APP -> WinAPP:8443          ALLOW
```

This is the real Windows VM microsegmentation demonstration.

### Stage 3 — Windows DB NetworkPolicy

Applies `manifests/policies/30-networkpolicy-db.yaml`.

```text
CUDN APP -> WinDB:1435           ALLOW
CUDN APP -> WinDB:61435          ALLOW
CUDN APP -> WinDB:8080           DENY
CUDN Jenkins -> WinDB:1435       ALLOW
CUDN Jenkins -> WinDB:61435      DENY
CUDN Rogue -> WinDB:1435         DENY
```

The manifest also includes the simplified SQL/MSDTC ranges TCP/135, 10000-11000 and 49152-65535 for APP-group sources.

### Stage 4 — ANP + BANP precedence

Applies `manifests/policies/40-adminnetworkpolicy-default-network.yaml` while the Stage 1 BANP remains present.

```text
ADMIN Corporate -> target:8443   ALLOW  # ANP Allow overrides lower BANP Deny
ADMIN Rogue -> target:8443       DENY   # ANP Deny
ADMIN Jenkins -> target:8443     DENY   # ANP Pass -> BANP Deny
```

The Windows VM NetworkPolicies remain active at the same time.

## Run individual tests

```bash
./scripts/test.sh baseline
./scripts/test.sh banp
./scripts/test.sh app-np
./scripts/test.sh db-np
./scripts/test.sh final
```

## Diagnostics

```bash
./scripts/show-vms.sh
./scripts/show-policy-paths.sh
./scripts/check-windows-bootstrap.sh
./scripts/doctor.sh
```

Show the dedicated admin namespaces and verify that they have no Primary UDN label:

```bash
oc get ns nsx-admin-app nsx-admin-corp nsx-admin-ops nsx-admin-rogue --show-labels
```

Show policies:

```bash
oc get banp
oc get anp
oc get networkpolicy -A | grep nsx-demo
```

## Windows fixes retained in this build

The Windows VM templates use a **SATA root disk** because the generalized lab image did not have the VirtIO block boot driver staged as a boot-critical driver. Using VirtIO for the root disk produced `INACCESSIBLE_BOOT_DEVICE`.

Sysprep media contains:

```text
unattend.xml
bootstrap.ps1
```

`FirstLogonCommands` contains only a short command that locates and executes `bootstrap.ps1`, avoiding the Windows unattend `CommandLine` length problem.

See `docs/WINDOWS-BOOT-SOURCE.md` and `docs/FIXES-IN-THIS-BUILD.md`.

## Cleanup

```bash
./scripts/cleanup.sh
```

The cleanup order is deliberate: remove policy/workloads, remove the CUDN and generated NADs, then remove both the CUDN and admin demo namespaces. Reusable OS DataSources remain untouched.

## MultiNetworkPolicy

`MultiNetworkPolicy` is not required for the main demo. `optional/localnet/` remains a separate secondary Localnet/VLAN example.

## Scope

The CUDN and policy-path decisions in this repo reflect behavior validated in the OCP 4.21.10 lab while keeping the demo on the OCP 4.20 API/feature set. Re-test behavior when moving the demo to a materially newer OpenShift release.
