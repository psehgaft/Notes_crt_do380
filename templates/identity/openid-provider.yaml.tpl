apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
    - name: oidc
      mappingMethod: claim
      type: OpenID
      openID:
        clientID: <CLIENT_ID>
        clientSecret:
          name: oidc-client-secret
        issuer: https://sso.psehgaft.org/realms/openshift
        claims:
          email:
            - email
          name:
            - name
          preferredUsername:
            - preferred_username
          groups:
            - groups

