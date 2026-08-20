# OpenShift Automation and Integration Practice Labs

Hands-on exercises for practicing OpenShift administration, automation, authentication, backup, logging, and monitoring workflows relevant to DO380-style objectives.

> [!IMPORTANT]
> This is an independent study repository. It is not an official Red Hat course, exam guide, or exam dump. Run privileged exercises only in a disposable lab cluster that you are authorized to administer.

## Lab conventions

- Commands use Bash and the `oc` CLI.
- The example cluster API is `https://api.ocp4.psehgaft.org:6443`.
- Replace values written as `<VALUE>` before applying a template.
- Every exercise follows the same structure: objectives, prerequisites, challenge, implementation, validation, troubleshooting, and cleanup.
- Generated tokens, private keys, kubeconfigs, and object-storage credentials must never be committed.

## Exercise catalog

| # | Exercise | Primary skills | Supporting files |
|---:|---|---|---|
| 01 | [Service account token authentication](exercises/01-service-account-token-authentication.md) | ServiceAccounts, RBAC, bounded tokens, kubeconfig | [`templates/authentication/health-robot-rbac.yaml`](templates/authentication/health-robot-rbac.yaml) |
| 02 | [Client certificate authentication](exercises/02-client-certificate-authentication.md) | CSR API, groups, RBAC, kubeconfig | [`templates/authentication/client-csr.yaml.tpl`](templates/authentication/client-csr.yaml.tpl) |
| 03 | [Automate an application deployment](exercises/03-ansible-application-deployment.md) | Ansible, idempotency, OpenShift objects | [`templates/automation/`](templates/automation/) |
| 04 | [Back up and restore an application with OADP](exercises/04-oadp-backup-and-restore.md) | OADP, Velero, hooks, namespace mapping | [`templates/oadp/`](templates/oadp/) |
| 05 | [Configure OIDC and group-based RBAC](exercises/05-oidc-and-group-rbac.md) | OAuth, OIDC claims, groups, authorization | [`templates/identity/`](templates/identity/) |
| 06 | [Centralize logs with Loki](exercises/06-centralized-logging.md) | ODF/NooBaa, LokiStack, Vector, console plug-in, RBAC | [`templates/logging/`](templates/logging/) |
| 07 | [Forward logs to external syslog](exercises/07-log-forwarding.md) | ClusterLogForwarder, pipelines, selectors | [`templates/logging/syslog-forwarding.yaml`](templates/logging/syslog-forwarding.yaml) |
| 08 | [Troubleshoot cluster monitoring](exercises/08-cluster-monitoring.md) | Dashboards, PromQL, resources, node health | [`templates/monitoring/`](templates/monitoring/) |
| 09 | [Review active alerts from the CLI](exercises/09-review-alerts.md) | Prometheus API, Alertmanager API, JSON filtering | No manifest required |
| 10 | [Administer cluster resources with OpenShift GitOps](exercises/10-openshift-gitops-cluster-administration.md) | Argo CD RBAC, trusted CA, Applications, synchronization | [`templates/gitops/`](templates/gitops/) |

## Prerequisites

- An OpenShift cluster and an account with the permissions required by each exercise.
- `oc`, `openssl`, `base64`, `curl`, `jq`, `git`, and `ansible-core` where applicable.
- The `kubernetes.core` Ansible collection for Exercise 03.
- Installed operators and storage integrations where explicitly listed.

Check the local tools:

```bash
for command in oc openssl base64 curl jq git; do
  command -v "${command}" >/dev/null || echo "Missing: ${command}"
done

oc whoami
oc cluster-info
```

## Recommended workflow

```bash
git clone https://github.com/psehgaft/Notes_crt_do380.git
cd Notes_crt_do380

# Read an exercise before applying its resources.
less exercises/01-service-account-token-authentication.md
```

Use a dedicated lab namespace and complete the cleanup section after every exercise.

## Repository layout

```text
.
├── exercises/                 # Numbered hands-on exercise guides
├── templates/                 # Reusable manifests and automation examples
│   ├── authentication/
│   ├── automation/
│   ├── gitops/
│   ├── identity/
│   ├── logging/
│   ├── monitoring/
│   └── oadp/
├── .gitignore
├── .markdownlint.yaml
├── CONTRIBUTING.md
└── README.md
```

## Security notes

- Exercise 01 grants only `cluster-reader` and uses a seven-day token.
- Exercise 02 intentionally demonstrates a seven-day administrative client certificate. Treat it as a break-glass lab credential, not as a normal user-authentication pattern.
- Keep private keys and kubeconfigs at mode `0600`.
- Do not use `--insecure-skip-tls-verify` unless a troubleshooting step explicitly explains the risk.
- Prefer identity-provider authentication and short-lived credentials in production.

## References

- [OpenShift product documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/)
- [Kubernetes certificate signing requests](https://kubernetes.io/docs/reference/access-authn-authz/certificate-signing-requests/)
- [Ansible Kubernetes collection](https://docs.ansible.com/ansible/latest/collections/kubernetes/core/)
