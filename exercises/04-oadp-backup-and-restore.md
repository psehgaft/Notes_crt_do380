# Exercise 04: Back Up and Restore an Application with OADP

## Objectives

- Validate OADP and backup storage readiness.
- Create a scheduled, label-selected backup with application hooks.
- Trigger an on-demand backup.
- Restore the application into a different namespace.

## Prerequisites

- The OADP Operator is installed and a `DataProtectionApplication` is reconciled in `openshift-adp`.
- A valid `BackupStorageLocation` is available.
- CSI snapshots are supported if persistent volumes will be snapshotted.
- A MediaWiki and PostgreSQL lab workload labeled `app.kubernetes.io/part-of=mediawiki` exists in namespace `mediawiki`.

## Scenario

Protect a stateful wiki application every day at 23:00, quiesce its workloads with hooks, and test a restore into `wiki-staging`.

## Challenge

Do not begin a backup until the storage location reports `Available`. Keep the schedule paused while testing, then restore and verify both data and application configuration.

## Implementation

Validate OADP:

```bash
oc -n openshift-adp get dataprotectionapplication
oc -n openshift-adp get backupstoragelocation
oc -n openshift-adp get backupstoragelocation -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\n"}{end}'
oc get volumesnapshotclass
```

Inspect labels and hook prerequisites:

```bash
oc -n mediawiki get all -l app.kubernetes.io/part-of=mediawiki --show-labels
oc -n mediawiki exec deployment/mediawiki -- test -w /data/images
oc -n mediawiki exec statefulset/postgresql -- sh -c 'command -v psql'
```

Apply the paused schedule:

```bash
oc apply -f templates/oadp/backup-schedule.yaml
oc -n openshift-adp get schedule mediawiki-daily -o yaml
```

Create an on-demand backup from the schedule:

```bash
BACKUP_NAME="mediawiki-manual-$(date +%Y%m%d%H%M%S)"
velero backup create "${BACKUP_NAME}" --from-schedule mediawiki-daily --namespace openshift-adp
velero backup describe "${BACKUP_NAME}" --details --namespace openshift-adp
velero backup logs "${BACKUP_NAME}" --namespace openshift-adp
```

Render and apply the restore:

```bash
oc create namespace wiki-staging --dry-run=client -o yaml | oc apply -f -
sed "s/<BACKUP_NAME>/${BACKUP_NAME}/" templates/oadp/restore.yaml.tpl > /tmp/mediawiki-restore.yaml
oc apply -f /tmp/mediawiki-restore.yaml
oc -n openshift-adp wait --for=jsonpath='{.status.phase}'=Completed \
  restore/mediawiki-restore-to-staging --timeout=20m
```

Update staging-only values after the restore:

```bash
oc -n wiki-staging set env deployment/mediawiki \
  MEDIAWIKI_SITE_NAME='DO380 Team Wiki Staging' \
  MEDIAWIKI_SITE_SERVER='https://mediawiki-wiki-staging.apps.ocp4.psehgaft.org'
oc -n wiki-staging rollout status deployment/mediawiki --timeout=180s
```

## Validation

```bash
oc -n openshift-adp get backup "${BACKUP_NAME}" -o jsonpath='{.status.phase}{"\n"}'
oc -n openshift-adp get restore mediawiki-restore-to-staging -o jsonpath='{.status.phase}{"\n"}'
oc -n wiki-staging get deployment,statefulset,pvc,pod
oc -n wiki-staging exec deployment/mediawiki -- test ! -e /data/images/backup.lock
```

Verify application data through the staging route and compare a known test record created before the backup.

## Troubleshooting

```bash
oc -n openshift-adp describe backupstoragelocation
velero backup logs "${BACKUP_NAME}" --namespace openshift-adp
velero restore describe mediawiki-restore-to-staging --details --namespace openshift-adp
velero restore logs mediawiki-restore-to-staging --namespace openshift-adp
oc -n openshift-adp get pod
```

Common failures include invalid object-storage credentials, an unavailable snapshot class, hook commands that do not exist in the container, and immutable fields after namespace mapping.

## Cleanup

```bash
oc -n openshift-adp delete restore mediawiki-restore-to-staging --ignore-not-found
oc -n openshift-adp delete schedule mediawiki-daily --ignore-not-found
oc -n openshift-adp delete backup "${BACKUP_NAME}" --ignore-not-found
oc delete namespace wiki-staging --ignore-not-found
rm -f /tmp/mediawiki-restore.yaml
```

## Review questions

1. Why should backup success be validated with an actual restore?
2. What consistency risk do the pre-backup hooks address?
3. Which resources or secrets should be excluded or transformed during a cross-environment restore?

