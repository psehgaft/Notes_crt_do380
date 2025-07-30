
# Exercise: Cluster Monitoring with OpenShift Console

## Objectives

- Use OpenShift Monitoring Stack to identify high resource usage
- Troubleshoot availability issues using dashboards and metrics

---

## 1. Environment Preparation

```bash
lab start monitoring-cluster
```

---

## 2. Run Load Generator

```bash
cd ~/DO380/labs/monitoring-cluster
./traffic-simulator.sh
```

---

## 3. Access Web Console

1. Go to: `https://console-openshift-console.apps.ocp4.openshift.training`
2. Login as:
   ```
   user: admin
   password: redhatocp
   ```

---

## 4. View Cluster CPU and Memory Usage

Navigate to:
**Observe → Dashboards → Kubernetes / Compute Resources / Cluster**

- **CPU Quota**: Sort by CPU Usage ↓ — Check for `dev-monitor` over 100%
- **Memory Requests**: Sort by Memory Usage ↓ — Look for `dev-monitor` over 100%

---

## 5. Identify High Resource Workload

Navigate to:
**Kubernetes / Compute Resources / Namespace (Workloads)**

- Select **Namespace**: `dev-monitor`
- Leave **Workload Type**: Deployment

### CPU Quota:
- `python-app` consumes >2 CPUs but requests only 0.1

### Memory Usage:
- `frontend`: ~63 MiB
- `exoplanets-db`: ~129 MiB
- `python-app`: spiky and erratic memory

> ⚠ Add resource limits to `python-app` and possibly define namespace-level `ResourceQuota`.

---

## 6. Stop Load Generator

```bash
Ctrl+C
```

---

## 7. Verify Application Unavailability

- `http://budget-test-monitor.apps.ocp4.openshift.training` → "Application Not Available"
- `http://frontend-test-monitor.apps.ocp4.openshift.training` → "Application Not Available"

---

## 8. Investigate `test-monitor` Namespace

Navigate to:
**Observe → Dashboards → Kubernetes / Compute Resources / Namespace (Workloads)**

- Select **Namespace**: `test-monitor`
- Both `frontend-test` and `budget-test` show **0 CPU**, **0 Memory**, **0 Network**

---

## 9. Investigate Node Health

Navigate to:
**Observe → Dashboards → Node / Cluster**

- **NotReadyNodesCount**: Shows 1 not-ready node

### Metric Query

```promQL
kube_node_status_condition{condition="Ready", status=~"unknown|false"} == 1
```

- Run query to identify node
-  `worker02` node is not ready

> Root cause: `worker02` is the only node in the test pool and it's NotReady. No pods can be scheduled.

---

## 10. Recommendations

- Fix `worker02` or add new healthy node to `env=test` pool
- Set resource limits and quotas for `python-app` and dev workloads

---

## 11. Clean Up

```bash
cd
lab finish monitoring-cluster
```
