
# Exercise Short-Term Log Retention and Aggregation with OpenShift Logging

## Objectives

- Use Loki as the log store.
- Use Vector as the log collector.
- Enable OpenShift web console for log visualization.
- Assign `cluster-logging-application-view` role to the `ocpdevs` group.

---

## 1. Environment Preparation

```bash
lab start logging-central
```

---

## 2. Install Loki Operator (Web Console)

1. Navigate to:
   ```
   https://console-openshift-console.apps.ocp4.example.com
   ```

2. Login as:
   ```
   user: admin
   password: redhatocp
   ```

3. Go to **Operators > OperatorHub**, search for **Loki Operator**, and click **Install** (select cluster monitoring checkbox).

---

## 3. Create Object Storage Bucket with ODF

```yaml
# objectbucket.yaml
apiVersion: objectbucket.io/v1alpha1
kind: ObjectBucketClaim
metadata:
  name: loki-bucket-odf
  namespace: openshift-logging
spec:
  generateBucketName: loki-bucket-odf
  storageClassName: openshift-storage.noobaa.io
```

```bash
oc create -f objectbucket.yaml
oc get obc -n openshift-logging
```

### Export Bucket Credentials

```bash
BUCKET_HOST=$(oc get -n openshift-logging configmap loki-bucket-odf -o jsonpath='{.data.BUCKET_HOST}')
BUCKET_NAME=$(oc get -n openshift-logging configmap loki-bucket-odf -o jsonpath='{.data.BUCKET_NAME}')
BUCKET_PORT=$(oc get -n openshift-logging configmap loki-bucket-odf -o jsonpath='{.data.BUCKET_PORT}')
ACCESS_KEY_ID=$(oc get -n openshift-logging secret loki-bucket-odf -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)
SECRET_ACCESS_KEY=$(oc get -n openshift-logging secret loki-bucket-odf -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)
```

### Create Secret

```bash
oc create secret generic logging-loki-odf -n openshift-logging \
  --from-literal=access_key_id=${ACCESS_KEY_ID} \
  --from-literal=access_key_secret=${SECRET_ACCESS_KEY} \
  --from-literal=bucketnames=${BUCKET_NAME} \
  --from-literal=endpoint=https://${BUCKET_HOST}:${BUCKET_PORT}
```

---

## 4. Deploy LokiStack

```yaml
# lokistack.yaml
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

```bash
oc create -f lokistack.yaml
oc get pods -n openshift-logging
```

---

## 5. Deploy ClusterLogging Instance

```yaml
# clusterlogging.yaml
apiVersion: logging.openshift.io/v1
kind: ClusterLogging
metadata:
  name: instance
  namespace: openshift-logging
spec:
  managementState: Managed
  logStore:
    type: lokistack
    lokistack:
      name: logging-loki
  collection:
    type: vector
  visualization:
    type: ocp-console
```

```bash
oc create -f clusterlogging.yaml
```

---

## 6. Enable Console Plugin

1. Go to **Operators > Installed Operators > All Projects**.
2. Select **Red Hat OpenShift Logging** > **Console plugin** > Enable.
3. Navigate to **Observe > Logs** in the web console.

---

## 7. Forward Audit Logs

```yaml
# forwarder.yaml
apiVersion: logging.openshift.io/v1
kind: ClusterLogForwarder
metadata:
  name: instance
  namespace: openshift-logging
spec:
  pipelines:
  - name: all-to-default
    inputRefs:
      - application
      - infrastructure
      - audit
    outputRefs:
      - default
```

```bash
oc create -f forwarder.yaml
```

---

## 8. Verify Logs in Console

1. Attempt SSH connection:

```bash
ssh worker01.ocp4.example.com
```

2. In **Observe > Logs**, filter:
   - `log_type="infrastructure"` → `sshd`
   - `log_type="application", kubernetes_namespace_name="testing-logs"`

---

## 9. Developer Access to Logs

```bash
oc login -u developer -p developer
oc new-project testing-logs
oc run test-date --restart=Never --image registry.ocp4.example.com:8443/ubi9/ubi -- date
oc logs test-date
oc delete pod test-date
```

### Verify Access Denied in Console

Login as `developer`, go to **Observe > Logs**, and verify log access is denied.

---

## 10. Admin Logs Review

Login as admin, go to **Observe > Logs** and search:

```
{ log_type="application", kubernetes_namespace_name="testing-logs" } | json
```

---

## 11. Grant Access to Developer Group

```yaml
# ocpdevs-role.yaml
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

```bash
oc create -f ocpdevs-role.yaml
```

---

## 12. Cleanup

```bash
cd
lab finish logging-central
```
