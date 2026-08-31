# Optional Localnet / physical VLAN extension

The main demo uses a **Primary Layer2 CUDN** and does not require MultiNetworkPolicy.

If you later add a secondary Localnet CUDN for a physical VLAN, OpenShift 4.20 and 4.21 use `MultiNetworkPolicy` for that secondary interface. In this lab `spec.useMultiNetworkPolicy` is currently `false`; do not enable it unless you are deliberately adding the Localnet part of the demo.

A real Localnet deployment also needs an OVN bridge mapping / NMState configuration for the physical underlay. The YAML in this directory is therefore an example, not part of `setup.sh`.
