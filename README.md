# NSX-T -> OpenShift Network Policy Demo

A working OpenShift Virtualization demo that shows how an NSX-T style security policy maps to:

- `ClusterUserDefinedNetwork` (CUDN)
- `AdminNetworkPolicy` (ANP)
- namespace `NetworkPolicy`
- `BaselineAdminNetworkPolicy` (BANP)
- workload labels as security-group membership

The lab cluster is **OpenShift 4.21.10**, while the demo is deliberately constrained to the feature/API set used for an **OpenShift 4.20 target**.

## The actual lab this repo targets

| Item | Lab value |
|---|---|
| OpenShift server | 4.21.10 |
| Target design | OpenShift 4.20 |
| Kubernetes | v1.34.6 |
| Network provider | OVN-Kubernetes |
| Node / underlay network | 10.10.10.0/24 |
| Cluster pod network | 10.132.0.0/14 |
| Service network | 172.31.0.0/16 |
| Demo CUDN | 192.0.2.0/24 |
| OpenShift Virtualization | Installed |
| Default storage | `ocs-external-storagecluster-ceph-rbd` |
| MultiNetworkPolicy | Disabled; not required for the main demo |

## What is deployed

This version uses **real virtual machines** as the protected workloads:

```text
                         Primary Layer2 CUDN
                            192.0.2.0/24
                       Persistent IP allocation
                                   |
             +---------------------+---------------------+
             |                     |                     |
             v                     v                     v
      Windows Server 2022   Windows Server 2022        RHEL 9
         win2022-app           win2022-db            rhel9-ops
         sg = app              sg = db              sg = jenkins
         TCP/8443         TCP/1435,61435,8080        TCP/9090
```

Four tiny probe pods are also created. They exist only to automate the connectivity matrix during the presentation:

- `app-probe`
- `jenkins-probe`
- `corporate-client`
- `rogue-client`

The policy **destinations are the Windows VM launcher pods / guest interfaces**, not fake application server pods.

## NSX-T mapping

```text
NSX-T                              OpenShift
-----------------------------------------------------------------
NSX Segment                  ->    ClusterUserDefinedNetwork
NSX Security Group           ->    VM / pod labels
NSX Dynamic Group            ->    label selectors
NSX IP Group                 ->    NetworkPolicy ipBlock
Central DFW rule             ->    AdminNetworkPolicy
Application firewall rule    ->    namespace NetworkPolicy
Bottom/default guardrail     ->    BaselineAdminNetworkPolicy
VLAN-backed segment          ->    Localnet CUDN + MultiNetworkPolicy
```

## Why the CUDN uses 192.0.2.0/24

The real cluster already uses:

```text
Nodes:       10.10.10.0/24
Pods:        10.132.0.0/14
Services:    172.31.0.0/16
```

The demo CUDN uses `192.0.2.0/24` (TEST-NET-1), which is intentionally obvious as documentation/demo addressing and does not overlap those lab ranges.

The CUDN is a **Primary Layer2** network with:

```yaml
ipam:
  lifecycle: Persistent
```

That is the VM-friendly design because a VM keeps a consistent address across restarts and migration scenarios.

# Important Windows prerequisite

OpenShift does not provide Microsoft Windows Server media for you. The repo therefore expects one **generalized Windows Server 2022 boot source**.

The Windows image should already contain:

- VirtIO storage driver
- VirtIO `NetKVM` network driver
- QEMU guest agent
- Windows Server 2022 already installed
- UEFI-bootable system disk (the demo VM explicitly uses UEFI with Secure Boot disabled)
- `sysprep /generalize` completed before it becomes the golden source

The setup clones that source twice and specializes the clones as:

```text
WIN2022-APP
WIN2022-DB
```

The generated sysprep configuration also starts simple TCP listeners so the network-policy demo can test real guest traffic.

## Check available boot sources

```bash
./scripts/discover-boot-sources.sh
```

The default expected RHEL source is:

```text
openshift-virtualization-os-images/rhel9
```

The default Windows source is:

```text
openshift-virtualization-os-images/win2022-demo
```

## If you already have a generalized Windows 2022 QCOW2

Upload it once:

```bash
./scripts/import-windows-image.sh /path/to/generalized-win2022.qcow2
```

or:

```bash
make import-windows WINDOWS_IMAGE=/path/to/generalized-win2022.qcow2
```

This uses `virtctl image-upload --datasource` and creates a reusable `DataSource` named `win2022-demo`.

If your image needs more than the default 64 GiB target:

```bash
WINDOWS_IMAGE_SIZE=100Gi \
  ./scripts/import-windows-image.sh /path/to/generalized-win2022.qcow2
```

## If a generalized Windows PVC already exists in the cluster

Register it as a DataSource instead of uploading it again:

```bash
./scripts/register-windows-pvc.sh <namespace> <pvc-name> win2022-demo
```

Then set the source namespace for the current shell or in `config/lab.env`:

```bash
export WINDOWS_DATASOURCE_NS=<namespace>
export WINDOWS_DATASOURCE=win2022-demo
```

# Deploy the lab

## 1. Optional configuration

```bash
cp config/lab.env.example config/lab.env
```

Edit only if your boot-source names differ.

Load it:

```bash
source config/lab.env
```

## 2. Preflight

```bash
./scripts/preflight.sh
```

The preflight verifies:

- 4.20 or 4.21 lab version
- OVN-Kubernetes
- CUDN API
- ANP and BANP APIs
- OpenShift Virtualization
- permissions
- no conflicting BANP
- RHEL 9 DataSource
- Windows Server 2022 DataSource

## 3. Setup

```bash
./scripts/setup.sh
```

or:

```bash
make setup
```

Setup creates:

1. five demo namespaces
2. `nsx-demo` Primary Layer2 CUDN
3. four tiny network probe pods
4. RHEL 9 VM x1
5. Windows Server 2022 VM x2
6. sysprep secrets for the Windows VMs
7. TCP listeners in the guests
8. a baseline connectivity smoke test

Initial Windows clone/specialization can take several minutes.

## 4. Show the VMs

```bash
./scripts/show-vms.sh
```

Example output:

```text
NAMESPACE        VM                 OS           CUDN-IP          STATUS
nsx-demo-app     win2022-app        Windows-2022 192.0.2.x        True
nsx-demo-db      win2022-db         Windows-2022 192.0.2.x        True
nsx-demo-ops     rhel9-ops          RHEL-9       192.0.2.x        True
```

# Run the live policy demo

```bash
./scripts/demo.sh
```

For a non-interactive run:

```bash
DEMO_AUTO=true ./scripts/demo.sh
```

## Stage 0 - CUDN only

No policy is present.

```text
Corporate -> Win2022 APP:8443       ALLOW
APP       -> Win2022 DB:1435        ALLOW
Rogue     -> Win2022 DB:1435        ALLOW
Jenkins   -> Win2022 DB:61435       ALLOW
```

Talking point:

> CUDN creates the network. It is not the firewall.

## Stage 1 - BANP

BANP says:

```text
Corporate -> Win2022 APP:8443       DENY
```

Talking point:

> BANP is the bottom-level cluster guardrail.

## Stage 2 - namespace NetworkPolicy

The APP namespace explicitly permits corporate traffic:

```text
Corporate -> Win2022 APP:8443       ALLOW
```

Talking point:

> Namespace NetworkPolicy can override the lower-tier BANP.

## Stage 3 - DB NetworkPolicy

```text
Jenkins -> Win2022 DB:1435          ALLOW
Jenkins -> Win2022 DB:61435         DENY
Rogue  -> Win2022 DB:1435           ALLOW
APP    -> Win2022 DB:1435           DENY
```

Rogue is deliberately allowed here to set up the ANP demonstration.

## Stage 4 - AdminNetworkPolicy

Central security applies the NSX-style DFW policy:

```text
APP     -> Win2022 DB:1435          ALLOW   ANP Allow
APP     -> Win2022 DB:61435         ALLOW   ANP Allow
APP     -> Win2022 DB:8080          DENY
Rogue   -> Win2022 DB:1435          DENY    ANP Deny
Jenkins -> Win2022 DB:1435          ALLOW   ANP Pass -> NP Allow
Jenkins -> Win2022 DB:61435         DENY    ANP Pass -> NP no allow
Corporate -> Win2022 APP:8443       ALLOW   NP overrides BANP
```

This is the key showcase:

```text
              AdminNetworkPolicy
             /         |          \
          Allow       Deny        Pass
            |           |           |
          ALLOW        DENY         v
                               NetworkPolicy
                                   |
                                   v
                     BaselineAdminNetworkPolicy
```

# Prove actual VM guest networking

The automated harness uses probe pods so the presentation is repeatable. You can also prove **VM-to-VM** connectivity from inside the guests.

Print the exact commands and current VM IPs:

```bash
./scripts/manual-vm-tests.sh
```

Examples:

### From `WIN2022-APP` PowerShell

```powershell
Test-NetConnection <win2022-db-ip> -Port 1435
Test-NetConnection <win2022-db-ip> -Port 61435
Test-NetConnection <win2022-db-ip> -Port 8080
```

### From `rhel9-ops`

```bash
timeout 3 bash -c '</dev/tcp/<win2022-db-ip>/1435' && echo ALLOW || echo DENY
```

For primary UDN VMs, use the OpenShift Virtualization web/VNC/serial console. `virtctl ssh` and `oc port-forward` are not supported for this primary UDN design.

# Useful presentation commands

```bash
oc get cudn nsx-demo -o yaml
oc get vm -A -l demo.openshift.io/owner=nsx-policy-demo
oc get vmi -A
oc get pods -A -l demo.openshift.io/component=vm --show-labels
oc get anp
oc get banp
oc get networkpolicy -A
```

Show the security-group labels on VM launcher pods:

```bash
oc get pods -A -l demo.openshift.io/component=vm \
  -L demo.openshift.io/security-group \
  -L demo.openshift.io/service
```

Re-run the final matrix:

```bash
./scripts/test.sh final
```

Reset only policy:

```bash
./scripts/reset-policies.sh
```

Remove the demo:

```bash
./scripts/cleanup.sh
```

`cleanup.sh` intentionally **does not delete reusable OS boot sources**.

# MultiNetworkPolicy / Localnet

Your current lab has:

```text
useMultiNetworkPolicy=false
```

Leave it that way for the main demo.

Primary Layer2 CUDN uses normal `NetworkPolicy`. `MultiNetworkPolicy` is only needed if you later add a **secondary Localnet CUDN / physical VLAN** interface. OpenShift 4.20 and 4.21 use the iptables implementation for that MultiNetworkPolicy path.

See `optional/localnet/`.

# Repository layout

```text
.
├── README.md
├── Makefile
├── config
│   └── lab.env.example
├── docs
│   ├── ARCHITECTURE.md
│   ├── DEMO-GUIDE.md
│   └── WINDOWS-BOOT-SOURCE.md
├── manifests
│   ├── base
│   │   ├── 00-namespaces.yaml
│   │   ├── 01-cudn.yaml
│   │   └── 02-probes.yaml.tpl
│   ├── vms
│   │   ├── 10-rhel9-ops.yaml.tpl
│   │   ├── 11-win2022-app.yaml.tpl
│   │   ├── 12-win2022-db.yaml.tpl
│   │   └── sysprep/unattend.xml.tpl
│   ├── policies
│   │   ├── 10-banp-app-guardrail.yaml
│   │   ├── 20-networkpolicy-app.yaml
│   │   ├── 30-networkpolicy-db.yaml
│   │   └── 40-adminnetworkpolicy-db.yaml
│   └── examples
├── optional/localnet
└── scripts
    ├── preflight.sh
    ├── discover-boot-sources.sh
    ├── import-windows-image.sh
    ├── register-windows-pvc.sh
    ├── setup.sh
    ├── show-vms.sh
    ├── demo.sh
    ├── test.sh
    ├── manual-vm-tests.sh
    ├── reset-policies.sh
    └── cleanup.sh
```

# Red Hat references

- OpenShift 4.20 Virtualization networking: https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/virtualization/networking
- OpenShift 4.21 Virtualization networking: https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html/virtualization/networking
- OpenShift 4.20 advanced VM creation: https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/virtualization/advanced-vm-creation
- OpenShift 4.21 advanced VM creation: https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html/virtualization/advanced-vm-creation
- OpenShift 4.21 AdminNetworkPolicy: https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html/network_security/admin-network-policy

## Windows VM says Ready but demo port is closed

`VirtualMachine Ready=True` means the VMI is running; it does not prove Windows
completed OOBE/specialization or ran `FirstLogonCommands`.

Run:

```bash
./scripts/check-windows-bootstrap.sh
```

Then open the Windows console and check:

```powershell
Test-Path C:\NSXDemo\configured.txt
Get-Content C:\NSXDemo\configured.txt
Get-ScheduledTask -TaskName NSXDemoListeners
Get-ScheduledTaskInfo -TaskName NSXDemoListeners
Get-NetTCPConnection -State Listen | Where-Object LocalPort -in 8443,1435,61435,8080
Get-Content C:\Windows\Panther\UnattendGC\setupact.log -Tail 100
```

If `C:\NSXDemo\configured.txt` does not exist, Windows did not run the attached
specialization answer file. Re-check that the source image was generalized with
`sysprep /generalize /oobe /shutdown /mode:vm` and that no cached answer file
was left in `C:\Windows\Panther` when the golden image was generalized.
