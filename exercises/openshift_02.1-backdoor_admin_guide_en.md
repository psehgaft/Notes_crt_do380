# Backdoor Admin Client Certificate Creation Guide - OpenShift 4.14

This guide provides a simplified, step-by-step procedure for generating an X.509 client certificate (valid for 1 week) in Red Hat OpenShift 4.14, granting full administrative privileges via the `backdoor-administrators` group.

---

## 1. Group and RBAC Configuration

1. **Create the backdoor administrators group:**
   ```bash
   oc adm groups new backdoor-administrators
   ```

2. **Assign the `cluster-admin` role to the group:**
   ```bash
   oc adm policy add-cluster-role-to-group cluster-admin backdoor-administrators
   ```

---

## 2. Generate Private Key and Certificate Signing Request (CSR)

1. **Create the working directory:**
   ```bash
   mkdir -p admin-cert
   ```

2. **Generate the private key and OpenSSL CSR:**
   *(User CN is `admin-backdoor` and Organization/Group is `backdoor-administrators`)*
   ```bash
   openssl req -newkey rsa:4096 -noenc \
     -keyout tls.key -subj "/O=backdoor-administrators/CN=admin-backdoor" \
     -out admin-cert/admin-backdoor-auth.csr
   ```

3. **Define the CSR resource in Kubernetes/OpenShift:**
   ```bash
   cat << EOF > admin-cert/admin-backdoor-csr.yaml
   apiVersion: certificates.k8s.io/v1
   kind: CertificateSigningRequest
   metadata:
     name: admin-backdoor-access
   spec:
     signerName: kubernetes.io/kube-apiserver-client
     expirationSeconds: 604800  # 7 days (1 week)
     request: $(base64 -w0 admin-cert/admin-backdoor-auth.csr)
     usages:
     - client auth
   EOF
   ```

---

## 3. Approve Certificate in the Cluster

1. **Submit the CSR to the cluster:**
   ```bash
   oc create -f admin-cert/admin-backdoor-csr.yaml
   ```

2. **Approve the CSR:**
   ```bash
   oc adm certificate approve admin-backdoor-access
   ```

3. **Verify CSR status (`Approved,Issued`):**
   ```bash
   oc get csr admin-backdoor-access
   ```

---

## 4. `kubeconfig` File Setup

1. **Extract the signed client certificate:**
   ```bash
   oc get csr admin-backdoor-access -o jsonpath='{.status.certificate}' | base64 -d > admin-cert/admin-backdoor-access.crt
   ```

2. **Fetch the public certificate from the API Server:**
   ```bash
   openssl s_client -showcerts -connect api.ocp4.example.com:6443 </dev/null 2>/dev/null | openssl x509 -outform PEM > ocp-apiserver-cert.crt
   ```

3. **Set credentials in the `kubeconfig` file:**
   ```bash
   oc config set-credentials admin-backdoor \
     --client-certificate admin-cert/admin-backdoor-access.crt \
     --client-key tls.key \
     --embed-certs \
     --kubeconfig admin-cert/admin-backdoor.config
   ```

4. **Set cluster configuration:**
   ```bash
   oc config set-cluster $(oc config view -o jsonpath='{.clusters[0].name}') \
     --certificate-authority ocp-apiserver-cert.crt \
     --embed-certs=true \
     --server https://api.ocp4.example.com:6443 \
     --kubeconfig admin-cert/admin-backdoor.config
   ```

5. **Set and switch context:**
   ```bash
   oc config set-context admin-backdoor \
     --cluster $(oc config view -o jsonpath='{.clusters[0].name}') \
     --namespace default \
     --user admin-backdoor \
     --kubeconfig admin-cert/admin-backdoor.config

   oc config use-context admin-backdoor --kubeconfig admin-cert/admin-backdoor.config
   ```

---

## 5. Permissions Verification

1. **Verify user identity:**
   ```bash
   oc whoami --kubeconfig admin-cert/admin-backdoor.config
   ```

2. **Verify permissions via user impersonation:**
   ```bash
   oc auth can-i get users -A --as admin-backdoor --as-group backdoor-administrators
   oc auth can-i create users -A --as admin-backdoor --as-group backdoor-administrators
   oc auth can-i create project -A --as admin-backdoor --as-group backdoor-administrators
   ```

---

## 📑 Red Hat OpenShift 4.14 Official Documentation Reference

* **API Resource:** `CertificateSigningRequest` [certificates.k8s.io/v1]
* **Official Documentation Link:**
  [Red Hat OpenShift Container Platform 4.14 - CertificateSigningRequest API](https://docs.redhat.com/en/documentation/openshift_container_platform/4.14/html/security_apis/certificatesigningrequest-certificates-k8s-io-v1)

### Key Technical Details from Official Docs:
* **`signerName: kubernetes.io/kube-apiserver-client`**: Issues client certificates for direct authentication against the `kube-apiserver`.
* **`expirationSeconds`**: Optional field in `spec` defining the requested lifetime of the signed certificate (604,800 seconds = 7 days).
* **CSR Object Workflow**: Allows submitting an X.509 request for cluster administrators to approve (`oc adm certificate approve`) and asynchronously issue a client access certificate.
