# Exercise 02: Client Certificate Authentication

## Objectives

- Generate a private key and certificate signing request.
- Submit and approve a Kubernetes client CSR.
- Map certificate organization membership to an OpenShift group.
- Build a certificate-based kubeconfig and verify authorization.

## Prerequisites

- Cluster-admin access to a disposable OpenShift lab cluster.
- `oc`, `openssl`, and `base64`.
- API endpoint `https://api.ocp4.psehgaft.org:6443` must resolve from the workstation.

## Scenario

Create a seven-day break-glass client certificate. The certificate common name is the OpenShift username and its organization is interpreted as a group.

> [!WARNING]
> This exercise intentionally grants `cluster-admin`. Use it only in an authorized lab. In production, use an approved identity provider and a formally governed break-glass process with auditing, rotation, and revocation.

## Challenge

Create group `backdoor-administrators`, bind it to `cluster-admin`, issue a certificate for `CN=admin-backdoor/O=backdoor-administrators`, and authenticate with an isolated kubeconfig.

## Implementation

Set values and create the group binding:

```bash
export API_SERVER=https://api.ocp4.psehgaft.org:6443
export API_HOST=api.ocp4.psehgaft.org
export CLUSTER_NAME="$(oc config view -o jsonpath='{.clusters[0].name}')"

oc adm groups new backdoor-administrators 2>/dev/null || true
oc adm policy add-cluster-role-to-group cluster-admin backdoor-administrators
```

Generate the key and CSR in the protected directory:

```bash
mkdir -p admin-cert
chmod 700 admin-cert

openssl req -new -newkey rsa:4096 -noenc \
  -keyout admin-cert/admin-backdoor.key \
  -subj "/O=backdoor-administrators/CN=admin-backdoor" \
  -out admin-cert/admin-backdoor-auth.csr

chmod 600 admin-cert/admin-backdoor.key
```

Render and submit the CSR:

```bash
CSR_REQUEST="$(base64 -w0 admin-cert/admin-backdoor-auth.csr)"

sed "s|<BASE64_ENCODED_CSR>|${CSR_REQUEST}|" \
  templates/authentication/client-csr.yaml.tpl \
  > admin-cert/admin-backdoor-csr.yaml

oc delete csr admin-backdoor-access --ignore-not-found
oc create -f admin-cert/admin-backdoor-csr.yaml
oc describe csr admin-backdoor-access
oc adm certificate approve admin-backdoor-access
```

Download and inspect the signed certificate:

```bash
oc get csr admin-backdoor-access \
  -o jsonpath='{.status.certificate}' \
  | base64 -d > admin-cert/admin-backdoor-access.crt

openssl x509 -in admin-cert/admin-backdoor-access.crt \
  -noout -subject -issuer -dates
```

Optionally inspect the certificate chain presented by the API endpoint. This is a connectivity and chain diagnostic only; do not automatically trust its first certificate as a CA:

```bash
openssl s_client -showcerts \
  -connect api.ocp4.psehgaft.org:6443 \
  -servername api.ocp4.psehgaft.org </dev/null
```

Extract the trusted cluster CA from the active kubeconfig. This is safer than treating the leaf certificate returned by `openssl s_client` as a CA:

```bash
CA_DATA="$(oc config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')"
test -n "${CA_DATA}" || { echo "The active kubeconfig does not contain embedded CA data" >&2; exit 1; }
printf '%s' "${CA_DATA}" | base64 -d > admin-cert/ocp-apiserver-ca.crt
```

Build the kubeconfig:

```bash
oc config set-credentials admin-backdoor \
  --client-certificate=admin-cert/admin-backdoor-access.crt \
  --client-key=admin-cert/admin-backdoor.key \
  --embed-certs=true \
  --kubeconfig=admin-cert/admin-backdoor.config

oc config set-cluster "${CLUSTER_NAME}" \
  --server="${API_SERVER}" \
  --certificate-authority=admin-cert/ocp-apiserver-ca.crt \
  --embed-certs=true \
  --kubeconfig=admin-cert/admin-backdoor.config

oc config set-context admin-backdoor \
  --cluster="${CLUSTER_NAME}" \
  --user=admin-backdoor \
  --kubeconfig=admin-cert/admin-backdoor.config

oc config use-context admin-backdoor --kubeconfig=admin-cert/admin-backdoor.config
chmod 600 admin-cert/admin-backdoor.config
```

## Validation

```bash
oc whoami --kubeconfig=admin-cert/admin-backdoor.config
oc whoami --show-groups --kubeconfig=admin-cert/admin-backdoor.config
oc auth can-i '*' '*' --all-namespaces --kubeconfig=admin-cert/admin-backdoor.config
oc get clusterversion --kubeconfig=admin-cert/admin-backdoor.config
```

Expected results:

- Username: `admin-backdoor`.
- Groups include `backdoor-administrators`.
- The authorization check returns `yes`.

## Troubleshooting

```bash
oc get csr admin-backdoor-access -o yaml
openssl verify -CAfile admin-cert/ocp-apiserver-ca.crt admin-cert/admin-backdoor-access.crt
openssl x509 -in admin-cert/admin-backdoor-access.crt -noout -subject
oc get clusterrolebinding -o json \
  | jq -r '.items[] | select(.subjects[]? | .name=="backdoor-administrators") | .metadata.name'
```

An approved CSR can still be unusable if the signer has not populated `.status.certificate`. Wait briefly and inspect the CSR conditions before continuing.

## Cleanup

Switch back to the original kubeconfig before removing access:

```bash
oc delete csr admin-backdoor-access --ignore-not-found
oc adm policy remove-cluster-role-from-group cluster-admin backdoor-administrators
oc adm groups delete backdoor-administrators

rm -f admin-cert/admin-backdoor.key \
  admin-cert/admin-backdoor-auth.csr \
  admin-cert/admin-backdoor-csr.yaml \
  admin-cert/admin-backdoor-access.crt \
  admin-cert/ocp-apiserver-ca.crt \
  admin-cert/admin-backdoor.config
rmdir admin-cert 2>/dev/null || true
```

Deleting the CSR does not revoke an already issued client certificate. Removing the group binding immediately removes its administrative authorization; a production revocation design may also require CA or API-server controls.

## Review questions

1. How do the certificate `CN` and `O` fields map to Kubernetes identity data?
2. Why does deleting the CSR not revoke the certificate?
3. Which controls would you add to a production break-glass credential process?
