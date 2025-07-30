
# Retrieving Alerts in OpenShift via CLI

This guide explains how to retrieve active alerts in an OpenShift cluster using the `oc` CLI tool. It focuses on extracting alerts directly from **Prometheus** and **Alertmanager**, both part of the OpenShift Monitoring stack.

---

## 1. Get Active Alerts from Prometheus

Prometheus exposes alerts via its API. You can query them like this:

```bash
oc -n openshift-monitoring exec -c prometheus prometheus-k8s-0 -- \
curl -s http://localhost:9090/api/v1/alerts | jq
```

> Note: You can also use `prometheus-k8s-1`. Ensure you have `jq` installed for clean JSON formatting.

If `jq` is not installed, use this to get the raw output:

```bash
oc -n openshift-monitoring exec -c prometheus prometheus-k8s-0 -- \
curl -s http://localhost:9090/api/v1/alerts
```

---

## 2. Get Alerts from Alertmanager

To retrieve alerts processed by Alertmanager:

```bash
oc -n openshift-monitoring exec -c alertmanager alertmanager-main-0 -- \
curl -s http://localhost:9093/api/v2/alerts | jq
```

---

## 3. Filter Alerts by State (e.g., firing)

To filter only alerts in the "firing" state:

```bash
oc -n openshift-monitoring exec -c prometheus prometheus-k8s-0 -- \
curl -s http://localhost:9090/api/v1/alerts | jq '.data.alerts[] | select(.state=="firing")'
```

---

## 4. Quick Summary without jq (Only Names and States)

```bash
oc -n openshift-monitoring exec -c prometheus prometheus-k8s-0 -- \
curl -s http://localhost:9090/api/v1/alerts | \
grep '"name"\|\"state"\|\"description"'
```

---

## Tip: Query Specific Alert Types (PromQL)

Example to query only firing alerts via Prometheus API using PromQL:

```bash
oc -n openshift-monitoring exec -c prometheus prometheus-k8s-0 -- \
curl -s 'http://localhost:9090/api/v1/query?query=ALERTS{alertstate="firing"}' | jq
```

---

Would you like a script that summarizes alerts daily or pushes them to Slack, Discord, or another webhook? Feel free to reach out or extend this README.
