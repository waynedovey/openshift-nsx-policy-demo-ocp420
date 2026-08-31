# Preparing the Windows Server 2022 boot source

Windows installation media is not bundled with OpenShift Virtualization. This demo expects a reusable, generalized Windows Server 2022 image.

## Required state of the image

Before using the image as the demo golden source, make sure it contains:

- Windows Server 2022
- VirtIO storage driver
- VirtIO NetKVM network driver
- QEMU guest agent
- successful boot on OpenShift Virtualization

Then generalize it from Windows:

```text
%WINDIR%\System32\Sysprep\sysprep.exe /generalize /shutdown /oobe /mode:vm
```

Do not boot the generalized disk again before capturing/exporting it as the golden source.

## Option 1 - upload a QCOW2

```bash
./scripts/import-windows-image.sh /path/to/generalized-win2022.qcow2
```

The default source becomes:

```text
openshift-virtualization-os-images/win2022-demo
```

The helper uses the OpenShift Virtualization supported `virtctl image-upload dv --datasource` workflow.

## Option 2 - reuse an existing PVC

If the generalized disk already exists as a PVC:

```bash
./scripts/register-windows-pvc.sh <namespace> <pvc-name> win2022-demo
```

Then export:

```bash
export WINDOWS_DATASOURCE_NS=<namespace>
export WINDOWS_DATASOURCE=win2022-demo
```

or put those values in `config/lab.env`.

## What setup does to the clones

`setup.sh` creates two DataVolumes from the source and two VMs:

```text
win2022-app
win2022-db
```

Each VM receives a generated `unattend.xml` sysprep secret that:

- gives the clone a unique hostname
- sets a lab-only Administrator password
- opens the demo TCP ports in Windows Firewall
- creates a scheduled PowerShell listener task
- starts the QEMU guest agent service if installed

The generated password is never stored in Git. It is written to:

```text
.demo-state/credentials.env
```

with local file mode `0600`.
