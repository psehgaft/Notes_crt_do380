# Work Sesion

- Install GitOps
- Test Playbooks

```
- name: Deploying the 380 application
  hosts: localhost
  become: false
  gather_facts: false
  vars:
    project: "automation-ansible"
    appname: "app-380"

  tasks:

    - name: Create a project
      # redhat.openshift.k8s:
      community.kubernetes.k8s:
        state: present
        resource_definition:
          apiVersion: project.openshift.io/v1
          kind: Project
          metadata:
            name: "{{ appname }}"

    - name: Deploy app
      # redhat.openshift.k8s:
      community.kubernetes.k8s:
        state: present
        src: "{{ appname }}.yml"

```
