# Dedicated default-network-only workloads for ANP/BANP validation.
#
# These pods live in nsx-admin-* namespaces, which are NOT selected by the
# Primary CUDN. Their normal pod IPs are therefore routable workload addresses
# on the cluster default network. This avoids the infrastructure-locked address
# of a Primary-UDN pod, which is deliberately not used as a workload path.
#
# Rendered by scripts/setup.sh or scripts/refresh-policy-demo.sh.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: admin-app-target
  namespace: nsx-admin-app
  labels:
    demo.openshift.io/owner: nsx-policy-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: admin-app-target
  template:
    metadata:
      labels:
        app: admin-app-target
        demo.openshift.io/component: admin-probe
        demo.openshift.io/policy-target: admin-app
        demo.openshift.io/security-group: app
    spec:
      containers:
        - name: target
          image: "__DEMO_IMAGE__"
          command: ["/bin/sh", "-c"]
          args:
            - |
              nc -lk 8443 >/tmp/listener-8443.log 2>&1 &
              exec sleep 2147483647
          resources:
            requests: {cpu: 10m, memory: 32Mi}
            limits: {memory: 128Mi}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: admin-corporate-client
  namespace: nsx-admin-corp
  labels:
    demo.openshift.io/owner: nsx-policy-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: admin-corporate-client
  template:
    metadata:
      labels:
        app: admin-corporate-client
        demo.openshift.io/component: admin-probe
        demo.openshift.io/security-group: corporate
    spec:
      containers:
        - name: client
          image: "__DEMO_IMAGE__"
          command: ["/bin/sh", "-c"]
          args: ["exec sleep 2147483647"]
          resources:
            requests: {cpu: 10m, memory: 32Mi}
            limits: {memory: 128Mi}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: admin-jenkins-client
  namespace: nsx-admin-ops
  labels:
    demo.openshift.io/owner: nsx-policy-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: admin-jenkins-client
  template:
    metadata:
      labels:
        app: admin-jenkins-client
        demo.openshift.io/component: admin-probe
        demo.openshift.io/security-group: jenkins
    spec:
      containers:
        - name: client
          image: "__DEMO_IMAGE__"
          command: ["/bin/sh", "-c"]
          args: ["exec sleep 2147483647"]
          resources:
            requests: {cpu: 10m, memory: 32Mi}
            limits: {memory: 128Mi}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: admin-rogue-client
  namespace: nsx-admin-rogue
  labels:
    demo.openshift.io/owner: nsx-policy-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: admin-rogue-client
  template:
    metadata:
      labels:
        app: admin-rogue-client
        demo.openshift.io/component: admin-probe
        demo.openshift.io/security-group: rogue
    spec:
      containers:
        - name: client
          image: "__DEMO_IMAGE__"
          command: ["/bin/sh", "-c"]
          args: ["exec sleep 2147483647"]
          resources:
            requests: {cpu: 10m, memory: 32Mi}
            limits: {memory: 128Mi}
