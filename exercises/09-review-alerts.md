# Exercise 09: Review Active Alerts from the CLI

## Objectives

- Retrieve firing alerts through supported OpenShift access paths.
- Filter Prometheus and Alertmanager JSON with `jq`.
- Produce a concise operational summary.

## Prerequisites

- Permission to access monitoring APIs.
- `oc`, `curl`, and `jq`.

## Scenario

The web console is unavailable, but operations needs a list of firing alerts, severity, namespace, and description.

## Challenge

Query alerts without hard-coding a Prometheus pod name and produce a tab-separated summary.

## Implementation

Use the Thanos Querier route through `oc proxy`, which keeps authentication in the local `oc` session:

```bash
oc proxy --port=8001
```

In another terminal, query firing alert series:

```bash
curl --fail --silent --show-error --get \
  --data-urlencode 'query=ALERTS{alertstate="firing"}' \
  'http://127.0.0.1:8001/api/v1/namespaces/openshift-monitoring/services/https:thanos-querier:9091/proxy/api/v1/query' \
  | jq .
```

Create a compact summary:

```bash
curl --fail --silent --show-error --get \
  --data-urlencode 'query=ALERTS{alertstate="firing"}' \
  'http://127.0.0.1:8001/api/v1/namespaces/openshift-monitoring/services/https:thanos-querier:9091/proxy/api/v1/query' \
  | jq -r '.data.result[] | [
      .metric.alertname,
      (.metric.severity // "unknown"),
      (.metric.namespace // "cluster"),
      (.metric.pod // "-")
    ] | @tsv'
```

For full annotations and Alertmanager grouping, establish a local port-forward:

```bash
oc -n openshift-monitoring port-forward service/alertmanager-main 9093:9094
```

Then query alerts in another terminal:

```bash
curl --fail --silent --show-error http://127.0.0.1:9093/api/v2/alerts \
  | jq -r '.[] | select(.status.state=="active") | [
      .labels.alertname,
      (.labels.severity // "unknown"),
      (.labels.namespace // "cluster"),
      (.annotations.summary // .annotations.description // "-")
    ] | @tsv'
```

## Validation

- Compare the CLI results with **Observe → Alerting → Alerts**.
- Select one alert and confirm its labels, active time, and runbook link.
- Record whether it is actionable, expected, silenced, or stale.

## Troubleshooting

```bash
oc auth can-i get services/proxy -n openshift-monitoring
oc -n openshift-monitoring get service thanos-querier alertmanager-main
oc get clusteroperator monitoring
```

Service names and ports can vary across releases. Inspect the Services instead of hard-coding pod names.

## Cleanup

Stop `oc proxy` and `oc port-forward` with `Ctrl+C`. This exercise creates no cluster resources.

## Review questions

1. What information is present in Alertmanager that is not available from the `ALERTS` metric alone?
2. Why is selecting a pod by a fixed ordinal fragile?
3. Which labels should be included in an operations handoff?

