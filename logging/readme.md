
# OpenShift Logging - Log Forwarding with External Aggregators

## Objectives

Set up OpenShift Logging to forward logs to external aggregators in the `psehgaft.open` domain.

---

## 1. Overview

OpenShift Logging collects logs from pods and nodes. Depending on the workload, log processing may require substantial resources. To mitigate this, logs can be forwarded to external aggregators such as:

- Elasticsearch
- Grafana Loki
- Splunk
- Amazon CloudWatch
- Google Cloud Logging

---

## 2. Components of OpenShift Logging

### 2.1 Log Collector (Vector)

- Replaces Fluentd
- Collects logs from:
  - **Infrastructure**: openshift-*, kube*, default
  - **Audit**: Kubernetes/OpenShift API and Linux audit logs
  - **Application**: User project logs
- Adds metadata and forwards logs to a store

### 2.2 Log Store (Grafana Loki)

- Centralized log aggregation
- Replaces Elasticsearch
- Optional component

### 2.3 Visualization

- OpenShift Console plug-in
- Replaces Kibana

---

## 3. Installation & Configuration

Install via OperatorHub or `oc` CLI. Managed by the `ClusterLogging` and `ClusterLogForwarder` custom resources.

### Example ClusterLogging CR:

```yaml
apiVersion: logging.openshift.io/v1
kind: ClusterLogging
metadata:
  name: instance
  namespace: openshift-logging
spec:
  managementState: Managed
  collection:
    type: vector
    tolerations:
    - effect: NoSchedule
      key: node-role.kubernetes.io/infra
      value: reserved
    - effect: NoExecute
      key: node-role.kubernetes.io/infra
      value: reserved
```

---

## 4. Log Forwarding Configuration

Define inputs, outputs, and pipelines using `ClusterLogForwarder`.

### Example: Forward to Splunk

```yaml
apiVersion: logging.openshift.io/v1
kind: ClusterLogForwarder
metadata:
  name: instance
  namespace: openshift-logging
spec:
  outputs:
    - name: splunk-receiver
      secret:
        name: splunk-auth-token
      type: splunk
      url: https://mysplunkserver.psehgaft.open:8088/services/collector
  pipelines:
    - name: to-splunk
      inputRefs:
        - audit
        - infrastructure
      outputRefs:
        - splunk-receiver
```

---

## 5. Multi-Destination Forwarding

Send different logs to multiple aggregators:

```yaml
outputs:
- name: audit-rsyslog
  type: syslog
  url: tcp://audit-store.psehgaft.open:5514
- name: splunk-receiver
  type: splunk
  url: https://mysplunkserver.psehgaft.open:8088/services/collector
pipelines:
- name: audit-to-syslog
  inputRefs: [audit]
  outputRefs: [audit-rsyslog]
- name: admin-logs
  inputRefs: [audit, infrastructure]
  outputRefs: [default]
- name: app-logs
  inputRefs: [application]
  outputRefs: [splunk-receiver]
```

---

## 6. Kubernetes Event Logging

Deploy **Event Router** manually to collect Kubernetes events and route them through the infrastructure category.

---

## 7. Filtering Logs

Create filters in `ClusterLogForwarder` to exclude unnecessary logs.

### Example: Application log filters

```yaml
inputs:
- name: production-apps
  application:
    selector:
      matchLabels:
        environment: production
- name: qa-chain
  application:
    selector:
      matchLabels:
        environment: development
    namespaces:
    - qa-testing
    - builders
```

---

## 8. Audit Event Filtering

Reduce audit noise with `filterRefs`.

### Example: Remove low-value audit logs

```yaml
filters:
- name: unwanted-events
  type: kubeAPIAudit
  kubeAPIAudit:
    rules:
    - level: None
      namespaces: [openshift-*, kube*]
      userGroups: [system:serviceaccounts:openshift-*, system:nodes]
    - level: None
      resources:
      - group: coordination.k8s.io
        resources: [leases]
      users: [system:kube*, system:apiserver]
      verbs: [update]
pipelines:
- name: audit-to-syslog
  inputRefs: [audit]
  filterRefs: [unwanted-events]
  outputRefs: [audit-rsyslog]
```

---

## 9. Troubleshooting Log Forwarding

### Check Configuration:

```bash
oc -n openshift-logging describe clusterlogforwarder/instance
```

### Check Events:

```bash
oc get event -n openshift-logging --field-selector=involvedObject.name=instance
```

### Check Collector Logs:

```bash
oc -n openshift-logging logs daemonset/collector
```

### Enable Cluster Monitoring:

Label the namespace:

```bash
oc label namespace openshift-logging openshift.io/cluster-monitoring=true
```

Use the **Logging / Collection** dashboard to inspect metrics.

---

## References

- [OpenShift Logging Docs](https://docs.openshift.com/container-platform/latest/logging/)
- [Vector Docs](https://vector.dev/docs/)
- [Loki Docs](https://grafana.com/docs/loki/)
- [Kubernetes Audit Policy](https://kubernetes.io/docs/tasks/debug/debug-cluster/audit/)
