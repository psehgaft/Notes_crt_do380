
# OpenShift Monitoring Essentials

## Contents

- **Monitoring Cluster Health**
- **Interactive Exercise: Cluster Observability**
- **Alerts and Alert Routing**
- **Interactive Exercise: Alerts Configuration**
- **Hands-On Lab: Monitoring with OpenShift**
- **Summary**

---

## Overview

### Purpose

Gain insights into application and cluster health by utilizing OpenShift’s integrated monitoring capabilities.

---

## Topics Covered

- Using monitoring tools to pinpoint high CPU and memory workloads.
- Investigating causes of application and node availability issues.
- Managing alerts and configuring notifications in OpenShift.

---

## Observability in OpenShift

Modern cloud-native infrastructures demand powerful tools for monitoring performance, reliability, and security. Red Hat OpenShift integrates several observability tools to gather real-time insights through logs, events, traces, and metrics.

Key observability components include:

- **OpenShift Logging** – Aggregates logs across nodes and pods for unified visualization.
- **OpenShift Monitoring** – Tracks platform-level health metrics and alerts.
- **Network Observability** – Enables visibility into network communication and potential bottlenecks.
- **Distributed Tracing** – Based on OpenTelemetry, useful for microservice debugging.

RHACM also offers multi-cluster observability support.

---

## OpenShift Monitoring Stack

Red Hat OpenShift includes a default monitoring stack powered by Prometheus, which collects metrics and generates alerts. This stack monitors both platform and user workloads, with components such as:

- **Cluster Monitoring Operator** – Manages and syncs monitoring stack versions.
- **Prometheus Operator & Alertmanager** – Handles metric collection and alert notifications.
- **Prometheus Adapter** – Supports Horizontal Pod Autoscalers (HPA).
- **Kube-State and OpenShift-State Metrics** – Export Kubernetes/OpenShift object metrics.
- **Node Exporter** – Gathers node-level statistics.
- **Thanos Querier** – Aggregates and deduplicates metrics.
- **Telemeter Client** – Reports cluster health back to Red Hat.
- **Observe Console Interface** – View dashboards, metrics, and alerts.

> Note: Resources in `openshift-monitoring` cannot be modified directly.

---

## Monitoring User Applications

To monitor custom workloads, OpenShift supports metrics in `openshift-user-workload-monitoring`. It includes:

- Prometheus
- Alertmanager
- Thanos Ruler
- Prometheus Operator

These enable project-level observability and alerting.

---

## Metrics and Prometheus

Prometheus collects time-series data (timestamp, value, labels) and enables advanced querying via **PromQL**.

### Example PromQL Queries:

- Available memory less than 50%:
  ```promQL
  node_memory_MemAvailable_bytes/node_memory_MemTotal_bytes*100 < 50
  ```

- PVC stuck in pending:
  ```promQL
  kube_persistentvolumeclaim_status_phase{phase="Pending"} == 1
  ```

- Compliance operator metrics:
  ```promQL
  {name=~"compliance.*"}
  ```

PromQL operators support arithmetic (`+`, `-`, `*`, `/`) and comparison (`==`, `!=`, `<`, `>`) as well as functions like:

- `sum()`
- `count()`
- `rate()`
- `max()`

---

## Observability via Web Console

### Navigate to:

- **Observe > Dashboards** – Interactive cluster visualizations
- **Observe > Metrics** – Run custom PromQL queries
- **Observe > Alerts** – View triggered alerts with metadata
- **Observe > Targets** – See metric sources and scrape status

---

## Dashboards Overview

OpenShift includes several default dashboards. Notable ones include:

### Kubernetes / Compute Resources / Cluster

Shows high-level cluster resource metrics (CPU/Memory usage, quota, etc.). Click “Inspect” to see query and visualization behind each graph.

### Kubernetes / Compute Resources / Namespace (Workloads)

Filters usage by namespace and deployment type.

### USE Method / Cluster

Displays **Utilization**, **Saturation**, and **Errors** for all nodes. Useful for identifying anomalies across compute nodes.

---

## Example URLs and Domain

This guide assumes the OpenShift Console is accessed via:

```
https://console-openshift-console.apps.openshift.training
```

And workloads are reachable at:

```
http://<service-name>.apps.openshift.training
```

---

## Summary

OpenShift Monitoring, built on Prometheus, enables teams to visualize performance data, write alerting rules, and troubleshoot with deep metrics insights. Combined with network observability and logging, it provides full-stack observability for containerized workloads.

For more details, refer to:

- [Monitoring Architecture (OpenShift Docs)](https://docs.openshift.com/container-platform/latest/monitoring/)
- [Prometheus Documentation](https://prometheus.io/)
- [OpenTelemetry Project](https://opentelemetry.io/)
