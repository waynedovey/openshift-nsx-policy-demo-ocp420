# Architecture

## Lab network

```text
Physical / node network   10.10.10.0/24
OpenShift pod network     10.132.0.0/14
OpenShift service network 172.31.0.0/16

NSX demo Primary Layer2 CUDN
192.0.2.0/24
Persistent IPAM
```

## VM layout

```text
                          CUDN nsx-demo
                          192.0.2.0/24
                                  |
                  +---------------+---------------+
                  |               |               |
                  v               v               v
             WIN2022-APP      WIN2022-DB       RHEL9-OPS
             namespace app    namespace db     namespace ops
             sg=app           sg=db            sg=jenkins
             TCP/8443         TCP/1435          TCP/9090
                              TCP/61435
                              TCP/8080
```

The VM template labels propagate to the `virt-launcher` pods. OVN policy selectors therefore provide the NSX-style dynamic-group behavior.

## Policy hierarchy

```text
AdminNetworkPolicy          centrally owned / strongest
          |
          | Pass or no decision
          v
namespace NetworkPolicy     application-owned
          |
          | no decision
          v
BaselineAdminNetworkPolicy  lowest / baseline guardrail
```

## Final expected matrix

| Source | Destination | Port | Result | Reason |
|---|---|---:|:---:|---|
| APP | Win2022 DB | 1435 | ALLOW | ANP `Allow` |
| APP | Win2022 DB | 61435 | ALLOW | ANP `Allow` |
| APP | Win2022 DB | 8080 | DENY | DB NetworkPolicy does not permit it |
| Rogue | Win2022 DB | 1435 | DENY | ANP `Deny` overrides namespace allow |
| Jenkins | Win2022 DB | 1435 | ALLOW | ANP `Pass` -> NetworkPolicy allows |
| Jenkins | Win2022 DB | 61435 | DENY | ANP `Pass` -> NetworkPolicy does not allow |
| Corporate | Win2022 APP | 8443 | ALLOW | NetworkPolicy overrides BANP |
