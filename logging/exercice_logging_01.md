
# Guided Exercise: Log Forwarding to External Syslog Server

## Objectives

- Deploy OpenShift Logging operator
- Configure log forwarding to a remote syslog server (`utility.lab.psehgaft.open`)
- Verify forwarding of:
  - Kubernetes API audit logs
  - Kubernetes events
  - CoreOS journal and audit logs
  - Infrastructure container logs
  - Critical application logs (labeled `logging: critical`)

---

## 1. Environment Setup

```bash
lab start logging-forward
```

---

## 2. Install OpenShift Logging Operator (as admin)

1. Navigate to:
   ```
   https://console-openshift-console.apps.ocp4.psehgaft.open
   ```

2. Login as:
   ```
   user: admin
   password: redhatocp
   ```

3. Go to **Operators > OperatorHub**, search for **OpenShift Logging**, and click **Install**.

---

## 3. Configure Logging with Vector Collector

```yaml
# clusterlogging.yml
apiVersion: logging.openshift.io/v1
kind: ClusterLogging
metadata:
  name: instance
  namespace: openshift-logging
spec:
  managementState: Managed
  collection:
    type: vector
```

```bash
oc apply -f clusterlogging.yml
```

---

## 4. Configure Log Forwarding to Syslog

```yaml
# clusterlogforwarder.yml
apiVersion: logging.openshift.io/v1
kind: ClusterLogForwarder
metadata:
  name: instance
  namespace: openshift-logging
spec:
  inputs:
  - name: critical-apps
    application:
      selector:
        matchLabels:
          logging: critical
  outputs:
  - name: audit-syslog
    type: syslog
    url: tcp://utility.lab.psehgaft.open:514
    syslog:
      msgID: audit
  - name: apps-syslog
    type: syslog
    url: tcp://utility.lab.psehgaft.open:514
    syslog:
      msgID: apps
  - name: infra-syslog
    type: syslog
    url: tcp://utility.lab.psehgaft.open:514
    syslog:
      msgID: infra
  pipelines:
  - name: critical-apps-syslog
    inputRefs: [critical-apps]
    outputRefs: [apps-syslog]
  - name: infra-syslog
    inputRefs: [infrastructure]
    outputRefs: [infra-syslog]
  - name: audit-syslog
    inputRefs: [audit]
    outputRefs: [audit-syslog]
```

```bash
oc apply -f clusterlogforwarder.yml
```

---

## 5. Deploy Event Router

```bash
oc process -f eventrouter.yml | oc apply -f -
```

Verify:

```bash
oc get pod -l component=eventrouter
```

---

## 6. Verify Logs on Syslog Server

SSH into utility node:

```bash
ssh root@utility
ls -l /var/log/openshift
```

### Journal Logs:

```bash
cd /var/log/openshift
tail -f infra.log | egrep -o "\{.*}$" | jq '. | select(.systemd.u.SYSLOG_IDENTIFIER=="sshd") | .hostname + " " + .message'
```

Open SSH session:

```bash
ssh core@master01.ocp4.psehgaft.open
exit
```

### Audit Logs:

```bash
egrep -ho "\{.*}$" audit.log* | jq '. | select(."audit.linux".type == "USER_LOGIN") | ."@timestamp" + " " + .hostname + " " + .message'
```

### Infrastructure Container Logs:

```bash
tail -f infra.log | egrep -o "\{.*}$" | jq '. | select(.kubernetes.namespace_name == "openshift-storage") | .kubernetes.pod_name + " " + .message'
```

### Audit Events (Developer User):

```bash
tail -f audit.log | egrep -o "\{.*}$" | jq -c '.|select(.user.username == "developer") | [.user.username, .annotations, .verb, .objectRef]'
```

```bash
oc login -u developer -p developer https://api.ocp4.psehgaft.open:6443
oc new-project logger-app
```

### Kubernetes Events:

```bash
tail -f infra.log | egrep -o "\{.*}$" | jq -c '. | select(.kubernetes.event.involvedObject.namespace == "logger-app") | [.kubernetes.event.involvedObject.kind, .kubernetes.event.involvedObject.name, .message]'
```

```bash
oc apply -f logger.yml
```

### Application Logs:

```bash
grep -m1 shop-web apps.log | egrep -o "\{.*}" | jq
grep logger-app apps.log
```

---

## 7. Cleanup

```bash
cd ~
oc login -u admin -p redhatocp https://api.ocp4.psehgaft.open:6443
oc delete project logger-app
oc -n openshift-logging delete clusterlogging,clusterlogforwarder --all
oc -n openshift-logging delete deployment eventrouter
lab finish logging-forward
```
