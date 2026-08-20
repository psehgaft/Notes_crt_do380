# Exercise 01: Service Account Token Authentication

## Objectives

- Create a service account for a health-check automation.
- Grant read-only cluster access through RBAC.
- Generate a bounded seven-day token.
- Build and validate an isolated kubeconfig.

## Prerequisites

- Cluster-admin access to a disposable OpenShift lab cluster.
- `oc` 4.11 or later, because this exercise uses `oc create token`.
- The current kubeconfig must contain the target cluster and its CA data.

## Scenario

A monitoring process needs to inspect cluster health without using a human account. Create a dedicated identity with the minimum permissions required for read-only health checks.

## Challenge

Create `system:serviceaccount:auth-tls:health-robot`, grant it `cluster-reader`, and build `robot-cert/health-robot.config` without modifying the active kubeconfig.

## Implementation

Set reusable values:

```bash
export LAB_NAMESPACE=auth-tls
export ROBOT_SA=health-robot
export API_SERVER=https://api.ocp4.psehgaft.org:6443
export CLUSTER_NAME="$(oc config view -o jsonpath='{.clusters[0].name}')"
```

Create the namespace, service account, and binding. Either apply the supplied template:

```bash
oc apply -f templates/authentication/health-robot-rbac.yaml
```

or create the objects imperatively:

```bash
oc create namespace "${LAB_NAMESPACE}" --dry-run=client -o yaml | oc apply -f -
oc create sa "${ROBOT_SA}" -n "${LAB_NAMESPACE}" --dry-run=client -o yaml | oc apply -f -
oc adm policy add-cluster-role-to-user cluster-reader \
  "system:serviceaccount:${LAB_NAMESPACE}:${ROBOT_SA}"
```

Extract the current cluster CA, generate a token, and protect the output directory:

```bash
HEALTHROBOT_TOKEN="$(oc create token -n "${LAB_NAMESPACE}" "${ROBOT_SA}" --duration=604800s)"
mkdir -p robot-cert
chmod 700 robot-cert
CA_DATA="$(oc config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')"
test -n "${CA_DATA}" || { echo "The active kubeconfig does not contain embedded CA data" >&2; exit 1; }
printf '%s' "${CA_DATA}" | base64 -d > robot-cert/ocp-apiserver-ca.crt
```

Configure credentials, cluster, and context:

```bash
oc config set-credentials health-robot \
  --token="${HEALTHROBOT_TOKEN}" \
  --kubeconfig=robot-cert/health-robot.config

oc config set-cluster "${CLUSTER_NAME}" \
  --server="${API_SERVER}" \
  --certificate-authority=robot-cert/ocp-apiserver-ca.crt \
  --embed-certs=true \
  --kubeconfig=robot-cert/health-robot.config

oc config set-context health-robot \
  --cluster="${CLUSTER_NAME}" \
  --namespace="${LAB_NAMESPACE}" \
  --user=health-robot \
  --kubeconfig=robot-cert/health-robot.config

oc config use-context health-robot --kubeconfig=robot-cert/health-robot.config
chmod 600 robot-cert/health-robot.config
unset HEALTHROBOT_TOKEN
```

> [!NOTE]
> If the active kubeconfig references a CA file instead of embedding `certificate-authority-data`, copy that CA file into `robot-cert/ocp-apiserver-ca.crt`.

## Validation

```bash
oc whoami --kubeconfig=robot-cert/health-robot.config
oc auth can-i get nodes --kubeconfig=robot-cert/health-robot.config
oc auth can-i create deployments -n auth-tls --kubeconfig=robot-cert/health-robot.config
oc get nodes --kubeconfig=robot-cert/health-robot.config
```

Expected results:

- `oc whoami` returns `system:serviceaccount:auth-tls:health-robot`.
- The account can read nodes.
- The account cannot create deployments.

## Troubleshooting

```bash
oc get clusterrolebinding health-robot-cluster-reader -o yaml
oc auth can-i --list --as=system:serviceaccount:auth-tls:health-robot
oc config view --kubeconfig=robot-cert/health-robot.config --minify
```

If the token expires, generate a new token and rerun `oc config set-credentials`.

## Cleanup

```bash
oc adm policy remove-cluster-role-from-user cluster-reader \
  system:serviceaccount:auth-tls:health-robot
oc delete clusterrolebinding health-robot-cluster-reader --ignore-not-found
oc delete namespace auth-tls --ignore-not-found
rm -f robot-cert/health-robot.config robot-cert/ocp-apiserver-ca.crt
rmdir robot-cert 2>/dev/null || true
```

## Review questions

1. Why is a service account preferable to a human token for automation?
2. What is the effective permission difference between `cluster-reader` and `cluster-admin`?
3. How would you shorten and rotate this token in a production integration?
