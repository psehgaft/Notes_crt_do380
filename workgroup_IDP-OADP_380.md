
# Workgroup OpenShift Operations Guide  

# Notes_crt_do380

## Agenda 
1. **Intro & Environment Check **  
2. **Exercise 1 — OADP Backup & Restore **  
3. **Exercise 2 — OIDC Setup & Group Sync **  
4. **Review & Troubleshooting **

### Configure OADP to back up a sample application, schedule backups, run hooks, and perform a restore into a staging namespace.

1. Deploy or verify the OADP operator.
2. Validate CSI snapshot support for the cluster’s StorageClasses.
3. Prepare an S3 bucket configuration and secret.
4. Complete the Velero/OADP CR using valid values:
   - S3 bucket 
   - credentials secret 
   - snapshot locations 
   - backup storage locations 
5. Create a **scheduled backup**: 
   - Runs at **23:00 daily** 
   - Includes resources filtered by labels: 
     - `app.kubernetes.io/part-of=mediawiki` 
     - `app.kubernetes.io/name=mediawiki` 
     - `app.kubernetes.io/name=postgresql` 
6. Add **backup hooks**:
   - Lock MediaWiki (write a lock file) 
   - Trigger PostgreSQL `CHECKPOINT` 
7. Trigger the backup manually using Velero. 
8. Restore into **wiki-staging** project. 
9. Add a **restore hook** to remove the MediaWiki lock file. 
10. Update deployment environment variables: 
    ```
    MEDIAWIKI_SITE_NAME="DO380 Team Wiki Staging"
    MEDIAWIKI_SITE_SERVER="https://mediawiki-wiki-staging.apps.example.com"
    ```

### Configure an OIDC provider, synchronize groups, and validate permissions behavior.

### ✔ Tasks  
1. Retrieve SSO client details:
   - clientId  
   - secret  
   - issuer URL  
2. Create OpenShift secret:  
   ```
   oc create secret generic rhsso-oidc-client-secret      --from-literal clientSecret=<SECRET> -n openshift-config
   ```
3. Modify OAuth CR to include the new IdP while preserving existing LDAP IdP.  
4. Verify OAuth rollout (pods in `openshift-authentication`).  
5. Log in using the following test users:  
   - **contractors** group → `edit` role  
   - **partners** group → `view` role  
6. Validate:  
   - Contractors can create/edit objects  
   - Partners can view but cannot edit  
7. Remove users and group memberships in SSO and observe propagation delay.  
8. Force logout in OpenShift by deleting tokens:  
   ```
   oc delete oauthaccesstoken $(oc get oauthaccesstoken -o jsonpath='{...}')
   ```
---

# 1. Project Creation

```bash
oc new-project mediawiki
oc new-project wiki-staging
oc new-project oadp
oc new-project rhsso
```

---

# 2. Operator Installation (OADP + RH‑SSO)

## 2.1 OperatorGroup

```yaml
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: og-oadp
  namespace: oadp
spec:
  targetNamespaces:
  - oadp
  - mediawiki
  - wiki-staging
```

Apply:

```bash
oc apply -f operatorgroup-oadp.yaml
```

## 2.2 OADP Subscription (replace package/channel)

```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: oadp-sub
  namespace: oadp
spec:
  channel: "stable"
  name: "oadp-operator"
  source: "redhat-operators"
  sourceNamespace: "openshift-marketplace"
  installPlanApproval: Automatic
```

## 2.3 RH‑SSO Subscription

```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: rhsso-sub
  namespace: rhsso
spec:
  channel: "stable"
  name: "rhsso-operator"
  source: "redhat-operators"
  sourceNamespace: "openshift-marketplace"
  installPlanApproval: Automatic
```

---

# 3. OADP / Velero Setup (Backup & Restore)

## 3.1 S3 Credentials Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: cloud-credentials
  namespace: oadp
stringData:
  credentials: |
    [default]
    aws_access_key_id = <ACCESS_KEY_ID>
    aws_secret_access_key = <SECRET_ACCESS_KEY>
```

## 3.2 BackupStorageLocation

```yaml
apiVersion: velero.io/v1
kind: BackupStorageLocation
metadata:
  name: default
  namespace: oadp
spec:
  provider: aws
  objectStorage:
    bucket: <BUCKET_NAME>
    prefix: velero
  config:
    region: <REGION>
    s3Url: https://<S3_ENDPOINT>
    s3ForcePathStyle: "true"
  accessMode: ReadWrite
```

## 3.3 VolumeSnapshotLocation

```yaml
apiVersion: velero.io/v1
kind: VolumeSnapshotLocation
metadata:
  name: csi-snap
  namespace: oadp
spec:
  provider: csi
  config:
    driver: rook-ceph.rbd.csi.ceph.com
```

---

# 4. MediaWiki + PostgreSQL Deployment

### MediaWiki Deployment (from DO380 references)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mediawiki
  namespace: mediawiki
  labels:
    app.kubernetes.io/part-of: mediawiki
    app.kubernetes.io/name: mediawiki
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mediawiki
  template:
    metadata:
      labels:
        app: mediawiki
        app.kubernetes.io/part-of: mediawiki
        app.kubernetes.io/name: mediawiki
    spec:
      containers:
      - name: mediawiki
        image: docker.io/mediawiki:1.35
        env:
        - name: MEDIAWIKI_SITE_NAME
          value: "DO380 Team Wiki"
        - name: MEDIAWIKI_SITE_SERVER
          value: "https://mediawiki-wiki.apps.example.com"
        volumeMounts:
        - name: images
          mountPath: /data/images
      volumes:
      - name: images
        persistentVolumeClaim:
          claimName: mediawiki-images-pvc
```

### PostgreSQL StatefulSet (from DO380 references)

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgresql
  namespace: mediawiki
  labels:
    app.kubernetes.io/part-of: mediawiki
    app.kubernetes.io/name: postgresql
spec:
  serviceName: postgresql
  replicas: 1
  selector:
    matchLabels:
      app: postgresql
  template:
    metadata:
      labels:
        app: postgresql
        app.kubernetes.io/part-of: mediawiki
        app.kubernetes.io/name: postgresql
    spec:
      containers:
      - name: postgresql
        image: registry.redhat.io/rhscl/postgresql-10-rhel7
        env:
        - name: POSTGRES_PASSWORD
          value: postgres
        volumeMounts:
        - name: pgdata
          mountPath: /var/lib/pgsql/data
  volumeClaimTemplates:
  - metadata:
      name: pgdata
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 5Gi
```

---

# 5. Velero Backup Schedule with Hooks (from DO380 Lab)

```yaml
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: mediawiki-daily-paused
  namespace: oadp
spec:
  schedule: "0 23 * * *"
  paused: true
  template:
    includedNamespaces:
    - mediawiki
    includedResources:
    - deployments
    - statefulsets
    - secrets
    - services
    - routes
    - persistentvolumeclaims
    labelSelector:
      matchLabels:
        app.kubernetes.io/part-of: mediawiki
    hooks:
      resources:
      - name: mediawiki
        labelSelector:
          matchLabels:
            app.kubernetes.io/name: mediawiki
        pre:
        - exec:
            command:
            - /bin/sh
            - -c
            - "echo 'backup in progress' > /data/images/lock_yBgMBwiR"
            container: mediawiki
        post:
        - exec:
            command:
            - /bin/sh
            - -c
            - "rm -f /data/images/lock_yBgMBwiR || true"
            container: mediawiki
      - name: postgresql
        labelSelector:
          matchLabels:
            app.kubernetes.io/name: postgresql
        pre:
        - exec:
            command:
            - /bin/sh
            - -c
            - "psql -c "CHECKPOINT;""
            container: postgresql
```

---

# 6. Restore with Restore Hooks

```yaml
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: restore-mediawiki-to-staging
  namespace: oadp
spec:
  backupName: mediawiki-manual-12345
  namespaceMapping:
    mediawiki: wiki-staging
  restorePVs: true
  hooks:
    resources:
    - name: mediawiki
      includedNamespaces:
      - wiki-staging
      labelSelector:
        matchLabels:
          app.kubernetes.io/name: mediawiki
      post:
      - exec:
          command:
          - /bin/sh
          - -c
          - "rm -f /data/images/lock_yBgMBwiR || true"
          container: mediawiki
```

---

# 7. RH‑SSO / OIDC Integration (from DO380 Chapter 1)

## 7.1 Create OAuth Secret

```bash
oc create secret generic rhsso-oidc-client-secret   --from-literal=clientSecret=<CLIENT_SECRET>   -n openshift-config
```

## 7.2 Add OIDC Identity Provider

```yaml
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - name: RHSSO_OIDC
    mappingMethod: claim
    type: OpenID
    openID:
      clientID: ocp_rhsso
      clientSecret:
        name: rhsso-oidc-client-secret
      issuer: https://rhsso.apps.example.com/auth/realms/external_providers
      claims:
        email:
        - email
        name:
        - name
        preferredUsername:
        - preferred_username
        groups:
        - groups
```

---

# 8. RBAC Assignments

```bash
# Contractors = edit
oc adm policy add-role-to-group edit contractors -n auth-oidc

# Partners = view
oc adm policy add-role-to-group view partners -n auth-oidc
```

---

# 9. Cleanup (from DO380)

```bash
oc delete schedule mediawiki-daily-paused -n oadp
oc delete backups --all -n oadp
oc delete restores --all -n oadp
```

---

# 10. Validation Checklist

- Operators installed
- Velero ready and BSL valid
- Backup schedule created
- Backup hooks executed
- Restore successful
- OIDC login working
- Group sync functional
- RBAC verified

---

End of Workgroup Guide  
