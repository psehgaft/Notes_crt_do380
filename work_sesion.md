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

```
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: rox-pipeline
  namespace: app-380
spec:
  description: Rox demo pipeline
  params:
    - name: image
      type: string
      description: quay.io/psehgaft/lab-sample-workshop
  tasks:
  - name: image-scan
    taskRef:
      name: rox-image-scan
      kind: ClusterTask
    params:
    - name: image
      value: $(params.image)
    - name: rox_api_token
      value: roxsecrets
    - name: rox_central_endpoint
      value: roxsecrets
    - name: output_format
      value: json
  - name: image-check
    taskRef:
      name: rox-image-check
      kind: ClusterTask
    params:
    - name: image
      value: $(params.image)
    - name: rox_api_token
      value: roxsecrets
    - name: rox_central_endpoint
      value: roxsecrets
```

```sh

cd openshift-cns-testdrive
export QUAY_USER=psehgaft
export BRANCH=$(git branch --show-current)
podman build -t quay.io/${QUAY_USER}/ocp-workshop:${BRANCH} .

oc login -u kubeadmin -p $KUBEADMIN_PASSWORD

oc new-project lab-ocp-cns

# This part is needed if you're running on a "local" or "self-provisioned" cluster
oc adm policy add-role-to-user admin kube:admin -n lab-ocp-cns

# Create deployment.
oc new-app -n lab-ocp-cns https://raw.githubusercontent.com/redhat-cop/agnosticd/development/ansible/roles/ocp4-workload-workshop-admin-storage/files/production-cluster-admin.json \
--param TERMINAL_IMAGE="quay.io/${QUAY_USER}/lab-sample-workshop:${BRANCH}" --param PROJECT_NAME="lab-ocp-cns" \
--param WORKSHOP_ENVVARS="$(cat ./workshop-settings.sh)"

# Wait for deployment to finish.

oc rollout status dc/dashboard -n lab-ocp-cns

```
