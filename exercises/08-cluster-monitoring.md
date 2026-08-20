# Exercise 08: Troubleshoot Cluster Monitoring

## Objectives

- Use OpenShift dashboards and PromQL to locate resource pressure.
- Identify unschedulable workloads and unhealthy nodes.
- Add namespace resource guardrails.
- Distinguish symptoms, root cause, and remediation.

## Prerequisites

- Access to **Observe** pages and metrics in the OpenShift console.
- A lab namespace `dev-monitor` with a load-generating workload.
- A lab namespace `test-monitor` whose workload demonstrates a scheduling or node-availability problem.

## Scenario

Users report high latency in development and unavailable routes in test. Use monitoring data and Kubernetes status to determine why.

## Challenge

Find the high-usage deployment without being told its name, identify the unavailable workload's scheduling constraint, and add safe default resources.

## Implementation

In the console, open:

1. **Observe → Dashboards → Kubernetes / Compute Resources / Cluster**.
2. Sort namespaces by CPU and memory utilization.
3. Drill into **Kubernetes / Compute Resources / Namespace (Workloads)**.
4. Compare usage, requests, and limits in `dev-monitor`.

Run equivalent queries:

```promql
sum by (namespace, pod) (
  rate(container_cpu_usage_seconds_total{container!="", image!=""}[5m])
)
```

```promql
sum by (namespace, pod) (
  container_memory_working_set_bytes{container!="", image!=""}
)
```

Identify unhealthy nodes:

```promql
kube_node_status_condition{condition="Ready",status=~"unknown|false"} == 1
```

Correlate metrics with API state:

```bash
oc -n dev-monitor top pod --containers
oc -n dev-monitor get deployment -o custom-columns=NAME:.metadata.name,REQUESTS:.spec.template.spec.containers[*].resources.requests,LIMITS:.spec.template.spec.containers[*].resources.limits
oc get nodes
oc -n test-monitor get pod -o wide
oc -n test-monitor get events --sort-by=.lastTimestamp
oc -n test-monitor get deployment -o yaml | grep -A8 -E 'nodeSelector:|affinity:|tolerations:'
```

Apply namespace defaults only after reviewing their impact:

```bash
oc apply -f templates/monitoring/python-app-resources.yaml
oc -n dev-monitor get resourcequota,limitrange
```

The template sets defaults for newly created pods. Existing pods must be recreated to inherit them, and existing explicit resources are not overwritten.

## Validation

```bash
oc -n dev-monitor describe resourcequota dev-monitor-compute
oc -n dev-monitor describe limitrange dev-monitor-defaults
oc -n test-monitor get pod -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,NODE:.spec.nodeName
```

Document:

- the affected namespace and workload;
- observed usage versus requested resources;
- the unavailable pods' scheduler events;
- the unhealthy node or constraint;
- immediate mitigation and long-term remediation.

## Troubleshooting

If `oc top` has no data, check the monitoring stack and metrics API:

```bash
oc get apiservice v1beta1.metrics.k8s.io
oc -n openshift-monitoring get pods
oc get clusteroperator monitoring
```

Do not restart a node or remove scheduling constraints until evidence identifies the cause and the change is approved.

## Cleanup

```bash
oc -n dev-monitor delete resourcequota dev-monitor-compute --ignore-not-found
oc -n dev-monitor delete limitrange dev-monitor-defaults --ignore-not-found
```

## Review questions

1. Why can high CPU utilization be acceptable while CPU throttling is not?
2. What is the difference between a `NotReady` node and an unschedulable pod?
3. How do `LimitRange` and `ResourceQuota` complement one another?

