# Exercise 10: Administer Cluster Resources with OpenShift GitOps

## Objectives

- Grant an OpenShift group administrative access to the default Argo CD instance.
- Inject the OpenShift trusted CA bundle into the repository server.
- Manage a cluster-scoped `Console` resource and OpenShift groups from Git.
- Create, synchronize, and verify an Argo CD `Application`.

## Prerequisites

- The Red Hat OpenShift GitOps Operator and the default `openshift-gitops` Argo CD instance.
- Cluster-admin access to a disposable OpenShift lab cluster.
- Group `ocpadmins` and repository `https://git.ocp4.psehgaft.org/developer/gitops-admin.git`.
- Git credentials with permission to push to the exercise repository.

## Scenario

The platform team wants cluster configuration to be reconciled from Git. Members of `ocpadmins` must administer Argo CD, and the repository server must trust the organization's internal Git certificate authority.

> [!WARNING]
> This exercise manages cluster-scoped resources and grants Argo CD administrative access. Use an authorized lab and review every patch before applying it.

## Challenge

Configure Argo CD without accidentally deleting existing RBAC rules or repository-server configuration. Commit the desired cluster configuration, create the Application, synchronize it, and verify the resulting resources.

## Implementation

### Step 1: Configure RBAC on the default Argo CD instance

Select the namespace and save the current custom resource:

```bash
oc project openshift-gitops
oc get argocd openshift-gitops -o yaml > /tmp/openshift-gitops.before.yaml
oc get argocd openshift-gitops -o jsonpath='{.spec.rbac.policy}{"\n"}'
```

The supplied merge patch sets the complete `spec.rbac.policy` value. If the current policy contains additional rules, add them to the patch before continuing:

```bash
oc patch argocd openshift-gitops --type=merge \
  --patch-file templates/gitops/argocd-rbac-patch.yaml
```

Equivalent inline patch:

```bash
oc patch argocd openshift-gitops --type merge -p '
spec:
  rbac:
    policy: |
      g, system:cluster-admins, role:admin
      g, cluster-admins, role:admin
      g, ocpadmins, role:admin
'
```

Verify the resulting policy:

```bash
oc get argocd openshift-gitops -o jsonpath='{.spec.rbac.policy}{"\n"}'
```

### Step 2: Inject the custom CA into the repository server

Create the ConfigMap idempotently and enable trusted-bundle injection:

```bash
oc create configmap cluster-root-ca-bundle -n openshift-gitops \
  --dry-run=client -o yaml | oc apply -f -

oc label configmap cluster-root-ca-bundle \
  config.openshift.io/inject-trusted-cabundle=true \
  -n openshift-gitops --overwrite
```

Wait for CA data to be injected:

```bash
oc -n openshift-gitops get configmap cluster-root-ca-bundle \
  -o jsonpath='{.data.ca-bundle\.crt}' | grep -q 'BEGIN CERTIFICATE'
```

Review existing repository-server volumes and apply the patch. If other volumes or mounts are already configured, merge them into the supplied file first because these lists are replaced by a JSON merge patch:

```bash
oc get argocd openshift-gitops \
  -o jsonpath='{.spec.repo.volumeMounts}{"\n"}{.spec.repo.volumes}{"\n"}'

oc patch argocd openshift-gitops --type=merge \
  --patch-file templates/gitops/argocd-repo-ca-patch.yaml
```

Equivalent inline patch:

```bash
oc patch argocd openshift-gitops --type merge -p '
spec:
  repo:
    volumeMounts:
      - mountPath: /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem
        name: cluster-root-ca-bundle
        subPath: ca-bundle.crt
    volumes:
      - configMap:
          name: cluster-root-ca-bundle
        name: cluster-root-ca-bundle
'
```

Wait for the repository server rollout and validate the mounted bundle:

```bash
oc -n openshift-gitops rollout status deployment/openshift-gitops-repo-server --timeout=5m
oc -n openshift-gitops exec deployment/openshift-gitops-repo-server -- \
  test -s /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem
```

### Step 3: Clone the Git repository and update manifests

```bash
git clone https://git.ocp4.psehgaft.org/developer/gitops-admin.git
cd gitops-admin

cp ../Notes_crt_do380/templates/gitops/console.yaml ./console.yaml
cp ../Notes_crt_do380/templates/gitops/groups.yaml ./groups.yaml

git diff --check
git status --short
git add -- console.yaml groups.yaml
git diff --cached
git commit -m "Manage console customization and groups with GitOps"
git push
```

If this training repository is not adjacent to the cloned repository, create `console.yaml` with the contents of [`templates/gitops/console.yaml`](../templates/gitops/console.yaml) and `groups.yaml` with the contents of [`templates/gitops/groups.yaml`](../templates/gitops/groups.yaml).

The `Console` annotations request server-side apply and disable client-side schema validation for that resource:

```yaml
annotations:
  argocd.argoproj.io/sync-options: ServerSideApply=true,Validate=false
```

### Step 4: Create the Argo CD Application

```bash
oc apply -f templates/gitops/application.yaml
```

Equivalent inline manifest:

```bash
oc apply -f - <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gitops-admin
  namespace: openshift-gitops
spec:
  project: default
  source:
    repoURL: https://git.ocp4.psehgaft.org/developer/gitops-admin.git
    targetRevision: HEAD
    path: .
  destination:
    server: https://kubernetes.default.svc
EOF
```

### Step 5: Synchronize and verify

Request a synchronization with pruning:

```bash
oc patch application gitops-admin -n openshift-gitops --type merge \
  -p '{"operation":{"sync":{"prune":true}}}'
```

Wait for the operation to finish:

```bash
oc -n openshift-gitops wait application/gitops-admin \
  --for=jsonpath='{.status.operationState.phase}'=Succeeded \
  --timeout=5m
```

## Validation

Inspect health and synchronization state:

```bash
oc -n openshift-gitops get application gitops-admin \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REVISION:.status.sync.revision

oc -n openshift-gitops get application gitops-admin \
  -o jsonpath='{range .status.conditions[*]}{.type}{": "}{.message}{"\n"}{end}'
```

Verify the Git-managed resources:

```bash
oc get console.operator.openshift.io cluster \
  -o jsonpath='{.spec.customization.customProductName}{"\n"}'
oc get groups developers1 operators1
```

Expected results:

- Application sync is `Synced` and health is `Healthy`.
- The custom product name is `Production`.
- Groups `developers1` and `operators1` exist.

## Troubleshooting

```bash
oc -n openshift-gitops describe application gitops-admin
oc -n openshift-gitops logs deployment/openshift-gitops-repo-server --tail=200
oc -n openshift-gitops logs statefulset/openshift-gitops-application-controller --tail=200
oc -n openshift-gitops get configmap cluster-root-ca-bundle -o yaml
oc get argocd openshift-gitops -o yaml
```

Typical causes include an untrusted Git TLS chain, invalid repository credentials, a replaced RBAC or volume list, missing Argo CD permissions for cluster-scoped resources, and a manifest absent from the Git revision Argo CD resolved.

## Cleanup

Deleting the Application with its resources is destructive. Use foreground cascading deletion only in the disposable lab:

```bash
oc -n openshift-gitops patch application gitops-admin --type=merge \
  -p '{"metadata":{"finalizers":["resources-finalizer.argocd.argoproj.io"]}}'
oc -n openshift-gitops delete application gitops-admin

oc -n openshift-gitops delete configmap cluster-root-ca-bundle --ignore-not-found
oc patch argocd openshift-gitops --type=merge \
  -p '{"spec":{"repo":{"volumeMounts":null,"volumes":null}}}'
```

Restore the original RBAC and repository-server configuration from `/tmp/openshift-gitops.before.yaml` by reviewing and patching only the fields changed in this exercise. Revert the Git commit if the shared repository should return to its initial state.

## Review questions

1. Why can a JSON merge patch replace existing RBAC policy or volume lists?
2. What is the difference between OpenShift's trusted CA bundle and the service-serving certificate CA?
3. Why should cluster-scoped resources be isolated in a tightly controlled Argo CD project?
4. What are the effects and risks of enabling pruning?

