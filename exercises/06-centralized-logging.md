# Exercise 06: Centralize Logs with Loki and OpenShift Data Foundation

## Objectives

- Provision S3-compatible object storage with an ObjectBucketClaim.
- Create the Loki object-storage secret without exposing credentials.
- Deploy a LokiStack backed by OpenShift Data Foundation.
- Configure Vector to forward application, infrastructure, and audit logs.
- Enable the OpenShift console logging plug-in.
- Grant a developer group namespace-scoped access to application logs.

## Prerequisites

- Cluster-admin access to a disposable OpenShift lab cluster.
- The Loki Operator and Red Hat OpenShift Logging Operator are installed at compatible versions.
- The Cluster Observability Operator is installed for the `UIPlugin` resource.
- OpenShift Data Foundation provides the `openshift-storage.noobaa.io` ObjectBucketClaim storage class.
- Block storage class `ocs-external-storagecluster-ceph-rbd` exists, or the LokiStack template has been adjusted to the cluster's supported class.
- The group `ocpdevs` exists or will be created for the lab.

> [!IMPORTANT]
> This exercise targets the Logging 6.x API `observability.openshift.io/v1`. Inspect the installed CRDs and documentation before using the templates with a different operator release.

## Scenario

The platform team needs short-term centralized logging. Logs must be stored in Loki, backed by an ODF S3-compatible bucket, and queried from the OpenShift console. Developers in `ocpdevs` may view application logs only in `testing-logs`.

## Challenge

Deploy the complete logging data path, prove that every component is ready, generate application logs, and confirm that namespace-scoped RBAC allows the developer group to query only the intended tenant data.

## Implementation

### Step 1: Validate the environment

```bash
oc project openshift-logging

oc api-resources | grep -E 'ObjectBucketClaim|LokiStack|ClusterLogForwarder|UIPlugin'
oc get csv -A | grep -E 'loki|cluster-logging|cluster-observability'
oc get storageclass openshift-storage.noobaa.io
oc get storageclass ocs-external-storagecluster-ceph-rbd
```

The Loki Operator and Logging Operator should use compatible major and minor versions. If the block storage class is different, copy and edit `templates/logging/lokistack-odf.yaml` before applying it.

### Step 2: Create the S3 ObjectBucketClaim and Loki secret

Apply the supplied OBC:

```bash
oc apply -f templates/logging/object-bucket-claim.yaml
oc -n openshift-logging wait \
  --for=jsonpath='{.status.phase}'=Bound \
  objectbucketclaim/loki-bucket-odf \
  --timeout=5m
```

The equivalent resource is:

```yaml
apiVersion: objectbucket.io/v1alpha1
kind: ObjectBucketClaim
metadata:
  name: loki-bucket-odf
  namespace: openshift-logging
spec:
  generateBucketName: loki-bucket-odf
  storageClassName: openshift-storage.noobaa.io
```

Load the generated bucket values into the current shell. The script validates that the OBC is bound and does not print secret values:

```bash
source templates/logging/get-bucket-creds.sh
```

Create or update the Loki object-storage secret idempotently:

```bash
oc -n openshift-logging create secret generic logging-loki-odf \
  --from-literal=access_key_id="${ACCESS_KEY_ID}" \
  --from-literal=access_key_secret="${SECRET_ACCESS_KEY}" \
  --from-literal=bucketnames="${BUCKET_NAME}" \
  --from-literal=endpoint="https://${BUCKET_HOST}:${BUCKET_PORT}" \
  --from-literal=forcepathstyle=true \
  --dry-run=client -o yaml | oc apply -f -

unset ACCESS_KEY_ID SECRET_ACCESS_KEY BUCKET_NAME BUCKET_HOST BUCKET_PORT
```

Validate the object-storage CA ConfigMap and secret without displaying credentials:

```bash
oc -n openshift-logging get configmap openshift-service-ca.crt
oc -n openshift-logging get secret logging-loki-odf \
  -o jsonpath='{range $key,$value := .data}{$key}{"\n"}{end}'
```

### Step 3: Deploy LokiStack

Review the configured block storage class and apply the LokiStack:

```bash
oc apply -f templates/logging/lokistack-odf.yaml
oc -n openshift-logging get lokistack logging-loki -o yaml
```

Equivalent resource:

```yaml
apiVersion: loki.grafana.com/v1
kind: LokiStack
metadata:
  name: logging-loki
  namespace: openshift-logging
spec:
  size: 1x.demo
  storage:
    secret:
      name: logging-loki-odf
      type: s3
    tls:
      caName: openshift-service-ca.crt
  storageClassName: ocs-external-storagecluster-ceph-rbd
  tenants:
    mode: openshift-logging
```

Wait until Loki reports ready and inspect its pods:

```bash
oc -n openshift-logging wait lokistack/logging-loki \
  --for=condition=Ready --timeout=15m
oc -n openshift-logging get pods -l app.kubernetes.io/managed-by=lokistack-controller
oc -n openshift-logging get configmap logging-loki-gateway-ca-bundle
```

Use `oc get pods -n openshift-logging -w` only while actively observing rollout; stop the watch with `Ctrl+C`.

### Step 4: Create the collector ServiceAccount and RBAC

Create the ServiceAccount idempotently:

```bash
oc create serviceaccount log-collector -n openshift-logging \
  --dry-run=client -o yaml | oc apply -f -
```

Grant every permission required by the inputs and LokiStack output before creating the ClusterLogForwarder:

```bash
oc adm policy add-cluster-role-to-user collect-audit-logs \
  -z log-collector -n openshift-logging
oc adm policy add-cluster-role-to-user collect-infrastructure-logs \
  -z log-collector -n openshift-logging
oc adm policy add-cluster-role-to-user collect-application-logs \
  -z log-collector -n openshift-logging
oc adm policy add-cluster-role-to-user logging-collector-logs-writer \
  -z log-collector -n openshift-logging
```

Verify that the four ClusterRoles are bound to the ServiceAccount:

```bash
oc get clusterrolebinding -o json | jq -r '
  .items[]
  | select(.subjects[]? |
      .kind == "ServiceAccount" and
      .name == "log-collector" and
      .namespace == "openshift-logging")
  | .roleRef.name' | sort -u
```

> [!WARNING]
> Do not add `audit` to `inputRefs` before granting `collect-audit-logs`. Logging 6.x can remove the collector DaemonSet as a protective response when a referenced source lacks authorization.

### Step 5: Configure ClusterLogForwarder

Apply the supplied forwarding configuration:

```bash
oc apply -f templates/logging/clusterlogforwarder-to-loki.yaml
```

The resource is named `instance` because current Logging 6.x documentation defines ClusterLogForwarder as a singleton. The Loki gateway CA is `logging-loki-gateway-ca-bundle`; it is distinct from the object-storage CA referenced by the LokiStack.

Verify readiness and the generated collector workload:

```bash
oc -n openshift-logging get clusterlogforwarder instance \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}{"\n"}'
oc -n openshift-logging get daemonset
oc -n openshift-logging get pods -l app.kubernetes.io/component=collector -o wide
```

### Step 6: Enable the logging plug-in in the web console

```bash
oc apply -f templates/logging/logging-ui-plugin.yaml
oc get uiplugin logging -o yaml
```

The supplied template uses the `viaq` schema for compatibility with namespace-scoped access. If the cluster uses GitOps to manage `console.operator.openshift.io/cluster`, also ensure the generated logging console plug-in remains present in `spec.plugins`.

### Step 7: Grant developers application-log access

Apply the namespace and RoleBinding:

```bash
oc apply -f templates/logging/application-log-view-rbac.yaml
```

Equivalent RoleBinding:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: view-application-logs
  namespace: testing-logs
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-logging-application-view
subjects:
  - kind: Group
    name: ocpdevs
    apiGroup: rbac.authorization.k8s.io
```

Generate a recognizable application log:

```bash
oc -n testing-logs run log-generator \
  --image=registry.access.redhat.com/ubi9/ubi-minimal \
  --restart=Never \
  -- sh -c 'echo DO380-LOKI-APPLICATION-TEST; sleep 30'
oc -n testing-logs logs pod/log-generator
```

## Validation

Check the complete data path:

```bash
oc -n openshift-logging get obc loki-bucket-odf
oc -n openshift-logging get lokistack logging-loki
oc -n openshift-logging get clusterlogforwarder instance
oc get uiplugin logging
oc -n testing-logs get rolebinding view-application-logs
```

In **Observe → Logs**, use these LogQL queries:

```logql
{ log_type="infrastructure" } | json | systemd_u_SYSLOG_IDENTIFIER="sshd"
```

```logql
{ log_type="application", kubernetes_namespace_name="testing-logs" } | json
```

```logql
{ log_type="application", kubernetes_namespace_name="testing-logs" } |= "DO380-LOKI-APPLICATION-TEST"
```

Deleting a namespace does not immediately delete already ingested Loki records. They remain queryable until the configured retention period expires.

Validate authorization as a member of `ocpdevs`: application logs for `testing-logs` should be available, while other namespaces and infrastructure/audit tenants should remain inaccessible unless separately authorized.

## Troubleshooting

Inspect conditions and events first:

```bash
oc -n openshift-logging describe obc loki-bucket-odf
oc -n openshift-logging describe lokistack logging-loki
oc -n openshift-logging describe clusterlogforwarder instance
oc -n openshift-logging get events --sort-by=.lastTimestamp
```

Check Loki storage and collector errors:

```bash
oc -n openshift-logging logs -l app.kubernetes.io/component=ingester --tail=100 | grep -iE 'error|x509|s3'
oc -n openshift-logging logs -l app.kubernetes.io/component=querier --tail=100 | grep -iE 'error|x509|s3'
oc -n openshift-logging logs -l app.kubernetes.io/component=collector --tail=200
```

Common causes include:

- The OBC is not `Bound` or its generated Secret/ConfigMap has a different name.
- The S3 endpoint requires `forcepathstyle=true`.
- The object-storage CA ConfigMap does not contain the correct key.
- The Loki gateway CA is incorrectly configured as `openshift-service-ca.crt` instead of `logging-loki-gateway-ca-bundle` for the ClusterLogForwarder output.
- One of the collector roles is missing.
- The configured block storage class does not exist.
- Loki and Logging Operator versions are incompatible.

## Cleanup

The following removes log data and the provisioned bucket. Use it only in the disposable lab:

```bash
oc delete uiplugin logging --ignore-not-found
oc -n openshift-logging delete clusterlogforwarder instance --ignore-not-found
for role in collect-audit-logs collect-infrastructure-logs collect-application-logs logging-collector-logs-writer; do
  oc adm policy remove-cluster-role-from-user "${role}" \
    -z log-collector -n openshift-logging
done
oc -n openshift-logging delete serviceaccount log-collector --ignore-not-found
oc -n openshift-logging delete lokistack logging-loki --ignore-not-found
oc -n openshift-logging delete secret logging-loki-odf --ignore-not-found
oc -n openshift-logging delete objectbucketclaim loki-bucket-odf --ignore-not-found
oc delete namespace testing-logs --ignore-not-found
```

Review the ODF reclaim policy and confirm whether the backing bucket and its data were deleted.

## Review questions

1. Why does Loki require both object storage and a block storage class?
2. What is the difference between the object-storage CA and the Loki gateway CA?
3. Why must collector RBAC be configured before the audit input is enabled?
4. How does a namespaced RoleBinding restrict application-log visibility?
5. Why can logs remain available after their source namespace is deleted?

## References

- [Red Hat OpenShift Logging quick start](https://docs.redhat.com/en/documentation/red_hat_openshift_logging/6.3/html/about_openshift_logging/quick-start)
- [Configuring log forwarding](https://docs.redhat.com/en/documentation/red_hat_openshift_logging/6.4/html/configuring_logging/configuring-log-forwarding)
- [Configuring object storage for LokiStack](https://docs.redhat.com/en/documentation/red_hat_openshift_logging/6.5/html/installing_logging/configuring-storage-for-lokistack)
- [Cluster Observability Operator logging UI plug-in](https://docs.redhat.com/en/documentation/red_hat_openshift_cluster_observability_operator/1-latest/html/ui_plugins_for_red_hat_openshift_cluster_observability_operator/logging-ui-plugin)
