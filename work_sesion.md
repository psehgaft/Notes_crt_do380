# Work Sesion

- Install GitOps
- Test Playbooks

```
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
