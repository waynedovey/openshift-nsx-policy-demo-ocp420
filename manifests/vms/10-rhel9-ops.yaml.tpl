apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: rhel9-ops
  namespace: nsx-demo-ops
  labels:
    demo.openshift.io/owner: nsx-policy-demo
spec:
  runStrategy: Always
  dataVolumeTemplates:
    - metadata:
        name: rhel9-ops-root
      spec:
        sourceRef:
          kind: DataSource
          name: __RHEL9_DATASOURCE__
          namespace: __RHEL9_DATASOURCE_NS__
        storage:
          resources: {}
  template:
    metadata:
      labels:
        demo.openshift.io/security-group: jenkins
        demo.openshift.io/service: rhel9-ops
        demo.openshift.io/component: vm
    spec:
      domain:
        cpu:
          cores: __RHEL_CORES__
        memory:
          guest: __RHEL_MEMORY__
        devices:
          disks:
            - name: rootdisk
              disk:
                bus: virtio
            - name: cloudinitdisk
              disk:
                bus: virtio
          interfaces:
            - name: primary
              binding:
                name: l2bridge
      networks:
        - name: primary
          pod: {}
      terminationGracePeriodSeconds: 120
      volumes:
        - name: rootdisk
          dataVolume:
            name: rhel9-ops-root
        - name: cloudinitdisk
          cloudInitNoCloud:
            userData: |-
              #cloud-config
              user: demo
              password: __DEMO_PASSWORD__
              chpasswd:
                expire: false
              ssh_pwauth: true
              write_files:
                - path: /etc/systemd/system/nsx-demo-listener.service
                  permissions: '0644'
                  content: |
                    [Unit]
                    Description=NSX Demo TCP/HTTP Listener
                    After=network-online.target
                    Wants=network-online.target

                    [Service]
                    Type=simple
                    ExecStart=/bin/bash -lc 'if command -v python3 >/dev/null; then exec python3 -m http.server 9090 --bind 0.0.0.0; else exec /usr/libexec/platform-python -m http.server 9090 --bind 0.0.0.0; fi'
                    Restart=always
                    RestartSec=2

                    [Install]
                    WantedBy=multi-user.target
              runcmd:
                - [ bash, -lc, 'systemctl enable --now qemu-guest-agent || true' ]
                - [ bash, -lc, 'firewall-cmd --permanent --add-port=9090/tcp && firewall-cmd --reload || true' ]
                - [ bash, -lc, 'systemctl daemon-reload && systemctl enable --now nsx-demo-listener.service' ]
