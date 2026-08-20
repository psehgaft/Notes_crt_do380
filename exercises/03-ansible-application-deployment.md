# Exercise 03: Automate an Application Deployment with Ansible

## Objectives

- Use `kubernetes.core` modules to manage OpenShift resources.
- Keep the playbook idempotent.
- Validate an application through Deployment, Service, and Route objects.

## Prerequisites

- An authenticated `oc` session with permission to create projects.
- `ansible-core`, Python Kubernetes dependencies, and the `kubernetes.core` collection.

```bash
ansible-galaxy collection install kubernetes.core
python3 -m pip install --user kubernetes
```

## Scenario

The operations team needs a repeatable deployment rather than a sequence of manual `oc` commands.

## Challenge

Deploy the supplied application, prove that a second playbook run makes no changes, scale it, and validate its route.

## Implementation

Inspect the input files:

```bash
less templates/automation/deploy-app.yaml
less templates/automation/app-380.yaml
```

Run the playbook:

```bash
ansible-playbook templates/automation/deploy-app.yaml
```

Run it a second time and confirm `changed=0` for already converged resources:

```bash
ansible-playbook templates/automation/deploy-app.yaml
```

Scale the application and wait for rollout:

```bash
oc -n app-380 scale deployment/app-380 --replicas=3
oc -n app-380 rollout status deployment/app-380 --timeout=180s
```

## Validation

```bash
oc -n app-380 get deployment,service,route
oc -n app-380 get pods -l app.kubernetes.io/name=app-380
APP_HOST="$(oc -n app-380 get route app-380 -o jsonpath='{.spec.host}')"
curl --fail --silent --show-error "https://${APP_HOST}" >/dev/null
```

## Troubleshooting

```bash
ansible-playbook templates/automation/deploy-app.yaml -vv
oc -n app-380 describe deployment/app-380
oc -n app-380 get events --sort-by=.lastTimestamp
oc auth can-i create projects
```

If Ansible cannot find the active cluster, confirm that `KUBECONFIG` references the same configuration used by `oc`.

## Cleanup

```bash
oc delete project app-380 --ignore-not-found
```

## Review questions

1. Which module behavior makes the playbook idempotent?
2. Why are readiness and rollout checks necessary after an API object is accepted?
3. How would you move environment-specific values into inventory or variable files?

