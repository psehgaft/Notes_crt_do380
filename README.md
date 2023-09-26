# Notes_crt_do380


```yml
apiVersion: v1
kind: Namespace
metadata:
  labels:
    openshift.io/cluster-monitoring: "true"
  name: openshift-metering
```


```yml
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - name: ldapidp
    mappingMethod: claim
    type: LDAP
    ldap:
      attributes:
        id:
        - dn
        email:
        - mail
        name:
        - cn
        preferredUsername:
        - uid
      bindDN: "uid=admin,cn=users,cn=accounts,dc=ocp4,dc=example,dc=com"
      bindPassword:
        name: ldap-secret
      ca:
        name: ca-config-map
      insecure: false
      url: "ldaps://idm.ocp4.example.com/cn=users,cn=accounts,dc=ocp4,dc=example,dc=com?uid"
```

```sh

ssh core@wnode "sudo systemctl is-active kubelet"
ssh core@wnode "sudo systemctl start kubelet"
ssh core@wnode "sudo systemctl is-active kubelet"
```
## Ansible

```yml
- name: Deploying the 370 application
  hosts: localhost
  become: false
  gather_facts: false
  vars:
    project: automation-ansible
    app-name: 370

  tasks:
    - name: Create a project
      redhat.openshift.k8s:
        state: present
        resource_definition:
          apiVersion: project.openshift.io/v1
          kind: Project
          metadata:
            name: "{{ project }}"

    - name: Deploy app 
      redhat.openshift.k8s:
        state: present
        src: "{{  app-name }}.yml"

    - name: Scaled up app
      kubernetes.core.k8s_scale:
        kind: Deployment
        name: "{{  app-name }}"
        replicas: 3

   -  name: Create a route
      redhat.openshift.openshift_route:
        service: "{{  app-name }}-svc"
      register: route
  ```
