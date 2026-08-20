apiVersion: velero.io/v1
kind: Restore
metadata:
  name: mediawiki-restore-to-staging
  namespace: openshift-adp
spec:
  backupName: <BACKUP_NAME>
  namespaceMapping:
    mediawiki: wiki-staging
  restorePVs: true
  hooks:
    resources:
      - name: remove-mediawiki-lock
        includedNamespaces:
          - wiki-staging
        labelSelector:
          matchLabels:
            app.kubernetes.io/name: mediawiki
        postHooks:
          - exec:
              container: mediawiki
              command:
                - /bin/sh
                - -c
                - rm -f /data/images/backup.lock
              waitTimeout: 5m

