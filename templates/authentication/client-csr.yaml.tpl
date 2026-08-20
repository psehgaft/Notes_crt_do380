apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: admin-backdoor-access
spec:
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 604800
  request: <BASE64_ENCODED_CSR>
  usages:
    - client auth

