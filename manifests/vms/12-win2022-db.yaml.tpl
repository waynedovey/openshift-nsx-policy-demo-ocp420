apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: win2022-db
  namespace: nsx-demo-db
  labels:
    demo.openshift.io/owner: nsx-policy-demo
spec:
  runStrategy: Always
  dataVolumeTemplates:
    - metadata:
        name: win2022-db-root
      spec:
        sourceRef:
          kind: DataSource
          name: __WINDOWS_DATASOURCE__
          namespace: __WINDOWS_DATASOURCE_NS__
        storage:
          resources: {}
  template:
    metadata:
      labels:
        demo.openshift.io/security-group: db
        demo.openshift.io/service: database
        demo.openshift.io/component: vm
    spec:
      domain:
        cpu:
          cores: __WINDOWS_CORES__
        memory:
          guest: __WINDOWS_MEMORY__
        firmware:
          bootloader:
            efi:
              secureBoot: false
        devices:
          disks:
            - name: rootdisk
              disk:
                bus: virtio
            - name: sysprep
              cdrom:
                bus: sata
          interfaces:
            - name: primary
              binding:
                name: l2bridge
      networks:
        - name: primary
          pod: {}
      terminationGracePeriodSeconds: 180
      volumes:
        - name: rootdisk
          dataVolume:
            name: win2022-db-root
        - name: sysprep
          sysprep:
            secret:
              name: win2022-db-sysprep
