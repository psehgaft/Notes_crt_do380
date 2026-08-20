# Exercise 05: Configure OIDC and Group-Based RBAC

## Objectives

- Add an OpenID Connect identity provider without discarding existing providers.
- Map OIDC group claims to OpenShift groups.
- Grant namespace-scoped `edit` and `view` access.
- Validate both allowed and denied operations.

## Prerequisites

- Cluster-admin access.
- An OIDC provider with a confidential client and redirect URI returned by `oc get oauth cluster` documentation for your cluster.
- Test users whose `groups` claim contains `contractors` or `partners`.

## Scenario

Contractors may modify resources in `auth-oidc`; partners may inspect them but must not modify them.

## Challenge

Add the provider while preserving the current OAuth configuration. Never place the client secret in Git or command history.

## Implementation

Back up and inspect the current OAuth object:

```bash
oc get oauth cluster -o yaml > /tmp/oauth-cluster.before.yaml
oc get oauth cluster -o jsonpath='{range .spec.identityProviders[*]}{.name}{"\t"}{.type}{"\n"}{end}'
```

Create the client secret from an interactive environment variable:

```bash
read -r -s -p 'OIDC client secret: ' OIDC_CLIENT_SECRET; echo
oc -n openshift-config create secret generic oidc-client-secret \
  --from-literal=clientSecret="${OIDC_CLIENT_SECRET}" \
  --dry-run=client -o yaml | oc apply -f -
unset OIDC_CLIENT_SECRET
```

The supplied OAuth file is a reference template, not a safe full replacement when other identity providers already exist. Add its `identityProviders` entry to the current list by using the web console or a reviewed JSON patch. For example, after replacing `<CLIENT_ID>`:

```bash
cp templates/identity/openid-provider.yaml.tpl /tmp/openid-provider.yaml
sed -i 's/<CLIENT_ID>/<YOUR_CLIENT_ID>/' /tmp/openid-provider.yaml
less /tmp/openid-provider.yaml
```

For a cluster with no existing providers, apply the completed file. Otherwise, edit the current resource and append only the new entry:

```bash
oc edit oauth cluster
```

Wait for authentication to reconcile:

```bash
oc -n openshift-authentication get pods
oc get clusteroperator authentication
oc wait clusteroperator/authentication --for=condition=Available=True --timeout=10m
```

Create the namespace and RBAC bindings:

```bash
oc create namespace auth-oidc --dry-run=client -o yaml | oc apply -f -
oc apply -f templates/identity/group-rbac.yaml
```

## Validation

After each test user logs in through OIDC, inspect identity and groups:

```bash
oc whoami
oc whoami --show-groups
```

An administrator can validate authorization without sharing user credentials:

```bash
oc auth can-i create deployments -n auth-oidc --as=<CONTRACTOR_USER> --as-group=contractors
oc auth can-i create deployments -n auth-oidc --as=<PARTNER_USER> --as-group=partners
oc auth can-i get deployments -n auth-oidc --as=<PARTNER_USER> --as-group=partners
```

Expected: contractors can create, partners cannot create, and partners can read.

## Troubleshooting

```bash
oc get clusteroperator authentication -o yaml
oc -n openshift-authentication get events --sort-by=.lastTimestamp
oc -n openshift-authentication logs deployment/oauth-openshift -c oauth-openshift --tail=100
oc get group contractors partners -o yaml
```

Confirm the issuer is exact, its TLS chain is trusted, the redirect URI matches, and the ID token actually includes the configured `groups` claim.

## Cleanup

Remove the OIDC entry from `oauth/cluster` without changing other providers, then:

```bash
oc delete namespace auth-oidc --ignore-not-found
oc -n openshift-config delete secret oidc-client-secret --ignore-not-found
rm -f /tmp/openid-provider.yaml /tmp/oauth-cluster.before.yaml
```

## Review questions

1. Why is applying a full OAuth template dangerous when another provider exists?
2. What is the difference between authentication group claims and OpenShift RBAC bindings?
3. How should access be removed when the upstream group membership changes?

