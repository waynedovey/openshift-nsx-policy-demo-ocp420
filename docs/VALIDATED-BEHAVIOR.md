# Validated Policy Behavior

Lab used during correction:

- OpenShift 4.21.10
- demo constrained to OpenShift 4.20 APIs/features
- OVN-Kubernetes
- Primary Layer2 CUDN `192.0.2.0/24`

## 1. Standard NetworkPolicy controls the real Windows VM

Observed Windows APP address: `192.0.2.17` during one validation run.

Without the temporary ingress-isolating NetworkPolicy:

```text
Corporate -> WinAPP:8443  CONNECTED
```

With the NetworkPolicy targeting the Windows APP launcher labels:

```text
Corporate -> WinAPP:8443  TIMEOUT
```

After deleting it:

```text
Corporate -> WinAPP:8443  CONNECTED
```

This proved the Primary CUDN + Windows VM NetworkPolicy path.

## 2. Primary-CUDN pod infrastructure address is not a workload endpoint

A Primary-CUDN APP probe had both:

```text
cluster infrastructure address: 10.135.1.43
Primary CUDN address:             192.0.2.20
```

With no ANP, BANP or NetworkPolicy present and with TCP/8443 listening on all interfaces:

```text
Corporate -> 10.135.1.43:8443   TIMEOUT
Corporate -> 192.0.2.20:8443    CONNECTED
```

Therefore the final demo does not use the infrastructure-locked address as an ANP/BANP workload path.

## 3. Final design decision

The final repository creates dedicated ordinary default-network namespaces for the administrative policy demonstration:

```text
nsx-admin-app
nsx-admin-corp
nsx-admin-ops
nsx-admin-rogue
```

These namespaces intentionally have no Primary UDN label.

Final policy split:

```text
Primary CUDN + real VMs         -> NetworkPolicy
Dedicated default-network pods -> ANP / BANP
```

This records what was actually validated rather than inferring reachability from the extra infrastructure address of a Primary-UDN pod.
