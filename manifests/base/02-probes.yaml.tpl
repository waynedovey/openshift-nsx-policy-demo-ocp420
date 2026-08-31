# Tiny automation clients. The protected endpoints are real VMs.
# Rendered by scripts/setup.sh. Override DEMO_IMAGE if required.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-probe
  namespace: nsx-demo-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: app-probe
  template:
    metadata:
      labels:
        app: app-probe
        demo.openshift.io/security-group: app
        demo.openshift.io/component: probe
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
  name: jenkins-probe
  namespace: nsx-demo-ops
spec:
  replicas: 1
  selector:
    matchLabels:
      app: jenkins-probe
  template:
    metadata:
      labels:
        app: jenkins-probe
        demo.openshift.io/security-group: jenkins
        demo.openshift.io/component: probe
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
  name: corporate-client
  namespace: nsx-demo-corp
spec:
  replicas: 1
  selector:
    matchLabels:
      app: corporate-client
  template:
    metadata:
      labels:
        app: corporate-client
        demo.openshift.io/security-group: corporate
        demo.openshift.io/component: probe
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
  name: rogue-client
  namespace: nsx-demo-rogue
spec:
  replicas: 1
  selector:
    matchLabels:
      app: rogue-client
  template:
    metadata:
      labels:
        app: rogue-client
        demo.openshift.io/security-group: rogue
        demo.openshift.io/component: probe
    spec:
      containers:
        - name: client
          image: "__DEMO_IMAGE__"
          command: ["/bin/sh", "-c"]
          args: ["exec sleep 2147483647"]
          resources:
            requests: {cpu: 10m, memory: 32Mi}
            limits: {memory: 128Mi}
