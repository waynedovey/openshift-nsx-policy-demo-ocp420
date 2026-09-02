# Fixes in the Final Build

This build consolidates all fixes found during live testing.

## Windows boot and Sysprep

- Windows Server 2022 root disk uses SATA to avoid `INACCESSIBLE_BOOT_DEVICE` with the generalized lab image.
- Sysprep unattend element ordering corrected.
- Large PowerShell payload removed from `FirstLogonCommands`.
- Sysprep media now contains `unattend.xml` plus `bootstrap.ps1`.
- The FirstLogon command is short and locates `bootstrap.ps1` on the Sysprep CD.
- PowerShell uses valid PowerShell continuation/command syntax.
- Windows APP listener: TCP/8443.
- Windows DB listeners: TCP/1435, 61435 and 8080.

## CUDN lifecycle

- Uses the full `clusteruserdefinednetworks.k8s.ovn.org` resource name where required.
- Cleanup removes CUDN-attached workloads before the CUDN and waits for generated NAD removal before deleting CUDN namespaces.

## Policy architecture

- Removed the invalid assumption that ANP/BANP should be demonstrated through the extra infrastructure address of Primary-CUDN pods.
- Added four dedicated default-network-only `nsx-admin-*` namespaces.
- ANP/BANP tests use only those dedicated workloads.
- Real Windows VM CUDN microsegmentation uses standard NetworkPolicy, which was validated live.
- `refresh-policy-demo.sh` upgrades an existing working VM lab without recreating VMs.
- `doctor.sh` shows both policy planes and current connectivity.
- `validate-repo.sh` now rejects stale versions of the old policy-path design.
