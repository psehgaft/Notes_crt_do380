# Exercise 06: Centralize Logs with Loki

## Objectives

- Configure a LokiStack backed by S3-compatible object storage.
- Collect application, infrastructure, and audit logs with Vector.
- Query application logs through the OpenShift console.

## Prerequisites

- Loki Operator and Red Hat OpenShift Logging Operator versions compatible with the cluster.
- An S3-compatible bucket and a supported storage class.
- Cluster-admin access.

> [!NOTE]
> The supplied `ClusterLogForwarder` uses the current `observability.openshift.io/v1` API. Check the installed Logging Operator CRDs before applying it because older releases use a different API and schema.

## Scenario

The platform team needs short-term, centralized log access for troubleshooting while retaining namespace-aware authorization.

## Challenge

Create the storage secret without exposing credentials, deploy Loki, configure collection, generate a test event, and locate it in the console.

## Implementation

Check installed APIs:

```bash
oc api-resources | grep -E 'LokiStack|ClusterLogForwarder'
oc explain clusterlogforwarder.spec
```

Create the collector service account and grant the roles advertised by the installed operator documentation:

```bash
oc -n openshift-logging create serviceaccount collector --dry-run=client -o yaml | oc apply -f -
oc adm policy add-cluster-role-to-user collect-application-logs system:serviceaccount:openshift-logging:collector
oc adm policy add-cluster-role-to-user collect-infrastructure-logs system:serviceaccount:openshift-logging:collector
oc adm policy add-cluster-role-to-user collect-audit-logs system:serviceaccount:openshift-logging:collector
```

Create the object-storage secret interactively. Confirm the exact secret keys required by the installed Loki Operator:

```bash
read -r -p 'S3 access key ID: ' ACCESS_KEY_ID
read -r -s -p 'S3 secret access key: ' SECRET_ACCESS_KEY; echo

oc -n openshift-logging create secret generic logging-loki-s3 \
  --from-literal=access_key_id="${ACCESS_KEY_ID}" \
  --from-literal=access_key_secret="${SECRET_ACCESS_KEY}" \
  --from-literal=bucketnames='<BUCKET_NAME>' \
  --from-literal=endpoint='https://s3.psehgaft.org' \
  --from-literal=region='<REGION>' \
  --dry-run=client -o yaml | oc apply -f -

unset ACCESS_KEY_ID SECRET_ACCESS_KEY
```

Copy the combined template, replace the storage class, review it, and apply it:

```bash
sed 's/<STORAGE_CLASS>/<YOUR_STORAGE_CLASS>/' \
  templates/logging/centralized-logging.yaml > /tmp/centralized-logging.yaml
oc apply -f /tmp/centralized-logging.yaml
```

## Validation

```bash
oc -n openshift-logging get lokistack,clusterlogforwarder,pod
oc -n openshift-logging get lokistack logging-loki -o jsonpath='{.status.conditions}{"\n"}'
oc -n openshift-logging get clusterlogforwarder collector -o yaml

oc create namespace logging-test --dry-run=client -o yaml | oc apply -f -
oc -n logging-test run log-generator --image=registry.access.redhat.com/ubi9/ubi-minimal \
  --restart=Never -- sh -c 'echo DO380-LOG-TEST; sleep 30'
oc -n logging-test logs pod/log-generator
```

In the console, open **Observe → Logs**, select application logs, filter for namespace `logging-test`, and search for `DO380-LOG-TEST`.

## Troubleshooting

```bash
oc -n openshift-logging describe lokistack logging-loki
oc -n openshift-logging describe clusterlogforwarder collector
oc -n openshift-logging get events --sort-by=.lastTimestamp
oc -n openshift-logging logs -l app.kubernetes.io/component=collector --tail=100
```

Check object-storage DNS, TLS trust, credentials, bucket permissions, storage class availability, and CRD/schema compatibility.

## Cleanup

```bash
oc delete namespace logging-test --ignore-not-found
oc -n openshift-logging delete clusterlogforwarder collector --ignore-not-found
oc -n openshift-logging delete lokistack logging-loki --ignore-not-found
oc -n openshift-logging delete secret logging-loki-s3 --ignore-not-found
oc -n openshift-logging delete serviceaccount collector --ignore-not-found
rm -f /tmp/centralized-logging.yaml
```

## Review questions

1. Why does Loki require object storage?
2. How does namespace authorization affect application-log visibility?
3. Which signals distinguish a collector problem from a Loki ingestion problem?

