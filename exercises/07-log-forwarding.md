# Exercise 07: Forward Logs to External Syslog

## Objectives

- Select application logs by label.
- Forward application, infrastructure, and audit logs to syslog.
- Validate delivery and diagnose collector failures.

## Prerequisites

- Red Hat OpenShift Logging Operator and a configured collector service account.
- A reachable syslog listener at `syslog.psehgaft.org:514`.
- Authorization to collect audit logs.

## Scenario

Security operations requires platform and audit events, while application operations wants logs only from workloads labeled `logging=critical`.

## Challenge

Apply one forwarder with two pipelines and prove that labeled logs arrive while unlabeled application logs do not.

## Implementation

Validate DNS and network reachability from a temporary pod:

```bash
oc -n openshift-logging run syslog-connectivity \
  --image=registry.access.redhat.com/ubi9/ubi-minimal --restart=Never \
  --command -- sh -c 'getent hosts syslog.psehgaft.org; timeout 5 bash -c "</dev/tcp/syslog.psehgaft.org/514"'
oc -n openshift-logging logs pod/syslog-connectivity
oc -n openshift-logging delete pod syslog-connectivity
```

Review and apply the template:

```bash
oc apply -f templates/logging/syslog-forwarding.yaml
oc -n openshift-logging get clusterlogforwarder syslog-forwarder -o yaml
```

Generate labeled and unlabeled application logs:

```bash
oc create namespace forwarding-test --dry-run=client -o yaml | oc apply -f -
oc -n forwarding-test run critical-log --labels=logging=critical \
  --image=registry.access.redhat.com/ubi9/ubi-minimal --restart=Never \
  -- sh -c 'echo DO380-CRITICAL-LOG; sleep 30'
oc -n forwarding-test run normal-log \
  --image=registry.access.redhat.com/ubi9/ubi-minimal --restart=Never \
  -- sh -c 'echo DO380-NORMAL-LOG; sleep 30'
```

## Validation

On the authorized syslog receiver, search for `DO380-CRITICAL-LOG` and confirm `DO380-NORMAL-LOG` is absent from the application pipeline. Also confirm recent infrastructure and audit events arrive.

On OpenShift:

```bash
oc -n openshift-logging describe clusterlogforwarder syslog-forwarder
oc -n openshift-logging get events --sort-by=.lastTimestamp
```

## Troubleshooting

```bash
oc -n openshift-logging logs -l app.kubernetes.io/component=collector --tail=200
oc -n forwarding-test get pods --show-labels
oc auth can-i use clusterrole/collect-audit-logs \
  --as=system:serviceaccount:openshift-logging:collector
```

Check egress network policy, firewalls, DNS, TLS requirements, the forwarder status conditions, and whether the receiver expects TCP, UDP, or TLS.

## Cleanup

```bash
oc delete namespace forwarding-test --ignore-not-found
oc -n openshift-logging delete clusterlogforwarder syslog-forwarder --ignore-not-found
```

## Review questions

1. Why should audit logs be routed separately from ordinary application logs?
2. How would you configure TLS and receiver authentication?
3. What prevents an application from adding `logging=critical` to itself?

