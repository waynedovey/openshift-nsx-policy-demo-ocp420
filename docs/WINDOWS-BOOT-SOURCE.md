# Preparing the Windows Server 2022 boot source

Windows installation media is not bundled with OpenShift Virtualization. This demo expects a reusable, generalized Windows Server 2022 image.

## Required state of the image

Before using the image as the demo golden source, make sure it contains:

- Windows Server 2022
- QEMU guest agent installed and configured for automatic startup
- the Windows storage/network drivers required by the source VM
- a system disk that can boot when presented as SATA (the demo clones use SATA deliberately)
- successful boot on OpenShift Virtualization

Then generalize it from Windows:

```text
%WINDIR%\System32\Sysprep\sysprep.exe /generalize /shutdown /oobe /mode:vm
```

Before running Sysprep on the source VM, set its run strategy so a guest shutdown is not immediately restarted (for example `RerunOnFailure`). Do not boot the generalized disk again before capturing/exporting it as the golden source.

## Option 1 - upload a QCOW2

```bash
./scripts/import-windows-image.sh /path/to/generalized-win2022.qcow2
```

The default source becomes:

```text
openshift-virtualization-os-images/win2022-demo-v2
```

The helper uses the OpenShift Virtualization supported `virtctl image-upload dv --datasource` workflow.

## Option 2 - reuse an existing PVC

If the generalized disk already exists as a PVC:

```bash
./scripts/register-windows-pvc.sh <namespace> <pvc-name> win2022-demo-v2
```

Then export:

```bash
export WINDOWS_DATASOURCE_NS=<namespace>
export WINDOWS_DATASOURCE=win2022-demo-v2
```

or put those values in `config/lab.env`.

## What setup does to the clones

`setup.sh` creates two DataVolumes from the source and two VMs:

```text
win2022-app
win2022-db
```

Each VM receives sysprep media from a Secret containing `unattend.xml` and `bootstrap.ps1`. The answer file:

- gives the clone a unique hostname
- sets a lab-only Administrator password
- invokes the separate `bootstrap.ps1` at first logon

The bootstrap script then opens the demo TCP ports in Windows Firewall, creates a scheduled PowerShell listener task, and starts the QEMU guest agent service if installed.

The generated password is never stored in Git. It is written to:

```text
.demo-state/credentials.env
```

with local file mode `0600`.

## Lab console login

The demo specialization file intentionally configures the built-in Windows
`Administrator` account with a **generated lab password with AutoLogon** and enables console autologon.
This is for the isolated demo only. The password is retained only as a lab credential; AutoLogon means it is not entered during normal demo startup. Use the OpenShift Virtualization console for interactive administration.

## Bootstrap marker

After a successful first logon, the specialization script creates:

```text
C:\NSXDemo\configured.txt
```

and registers the scheduled task `NSXDemoListeners`. If the VM is running but a
demo port is not listening, run `scripts/check-windows-bootstrap.sh` and inspect
those two items from the Windows console.
