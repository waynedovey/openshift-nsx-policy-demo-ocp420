# Architecture

## Final two-plane design

```text
                    OpenShift

 PRIMARY CUDN WORKLOAD PLANE           DEFAULT-NETWORK ADMIN PLANE
 ---------------------------           ---------------------------
 nsx-demo 192.0.2.0/24                 nsx-admin-* namespaces
          |                                     |
  Windows APP / DB / RHEL               admin-app-target:8443
          ^                                     ^
          |                                     |
 CUDN client probes                    corp / jenkins / rogue
          |                                     |
   NetworkPolicy                         ANP / BANP
```

The admin namespaces are intentionally not selected by the CUDN. They have no `k8s.ovn.org/primary-user-defined-network` label.

## CUDN workload topology

```text
                         CUDN nsx-demo
                         192.0.2.0/24
                               |
        +----------------------+----------------------+
        |                      |                      |
  nsx-demo-app            nsx-demo-db            nsx-demo-ops
        |                      |                      |
   win2022-app             win2022-db              rhel9-ops
     :8443            :1435/:61435/:8080             :9090
        |
   app-probe client

  nsx-demo-corp -> corporate-client
  nsx-demo-rogue -> rogue-client
```

## Admin policy topology

```text
nsx-admin-corp/admin-corporate-client -----+
                                            |
nsx-admin-ops/admin-jenkins-client ---------+--> nsx-admin-app/admin-app-target:8443
                                            |
nsx-admin-rogue/admin-rogue-client --------+

Stage 1: BANP
  Corporate DENY
  Jenkins   DENY
  Rogue     ALLOW

Stage 4: ANP + existing BANP
  Corporate ANP Allow -> ALLOW
  Rogue     ANP Deny  -> DENY
  Jenkins   ANP Pass  -> BANP Deny -> DENY
```

## Real VM policy matrix

| Source | Target | Port | Result after Stage 3 | Enforcement |
|---|---|---:|---:|---|
| Corporate | Win2022 APP | 8443 | DENY | APP NetworkPolicy |
| APP | Win2022 APP | 8443 | ALLOW | APP NetworkPolicy |
| APP | Win2022 DB | 1435 | ALLOW | DB NetworkPolicy |
| APP | Win2022 DB | 61435 | ALLOW | DB NetworkPolicy |
| APP | Win2022 DB | 8080 | DENY | absent from DB allow list |
| Jenkins | Win2022 DB | 1435 | ALLOW | DB NetworkPolicy |
| Jenkins | Win2022 DB | 61435 | DENY | absent from Jenkins allow list |
| Rogue | Win2022 DB | 1435 | DENY | no Rogue allow rule |

## Policy hierarchy concept

```text
AdminNetworkPolicy
        |
        v
namespace NetworkPolicy
        |
        v
BaselineAdminNetworkPolicy
```

The final demo does not claim that all three APIs act on the same network attachment. It uses NetworkPolicy for the validated Primary-CUDN VM workload path and uses dedicated default-network workloads to demonstrate ANP/BANP behavior and precedence.
