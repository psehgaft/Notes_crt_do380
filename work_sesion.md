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
kind: ClusterTask
metadata:
  name: rox-deployment-check
  namespace: app-380
spec:
  params:
    - name: rox_central_endpoint
      type: string
      description: Secret containing the address:port tuple for StackRox Central (example - rox.stackrox.io:443)
    - name: rox_api_token
      type: string
      description: Secret containing the StackRox API token with CI permissions
    - name: file
      type: string
      description: YAML file in the deployfiles workspace
  results:
      - name: check_output
        description: Output of `roxctl deployment check`
  workspaces:
    - name: deployfiles
      description: |
        The folder containing deployment files
      mountPath: /deployfile
  steps:
    - name: rox-deployment-check
      image: centos:8
      env:
        - name: ROX_API_TOKEN
          valueFrom:
            secretKeyRef:
              name: $(params.rox_api_token)
              key: rox_api_token
        - name: ROX_CENTRAL_ENDPOINT
          valueFrom:
            secretKeyRef:
              name: $(params.rox_central_endpoint)
              key: rox_central_endpoint
      script: |
        #!/usr/bin/env bash
        set +x
        cat /deployfile/deploy.yml
        curl -k -L -H "Authorization: Bearer $ROX_API_TOKEN" https://$ROX_CENTRAL_ENDPOINT/api/cli/download/roxctl-linux --output ./roxctl  > /dev/null; echo "Getting roxctl"
        chmod +x ./roxctl  > /dev/null
        ./roxctl deployment check --insecure-skip-tls-verify -e $ROX_CENTRAL_ENDPOINT -f /deployfile/$(params.file) 
```

```
apiVersion: tekton.dev/v1beta1
kind: ClusterTask
metadata:
  name: rox-image-check
  namespace: app-380
spec:
  params:
    - name: rox_central_endpoint
      type: string
      description: Secret containing the address:port tuple for StackRox Central (example - rox.stackrox.io:443)
    - name: rox_api_token
      type: string
      description: Secret containing the StackRox API token with CI permissions
    - name: image
      type: string
      description: Full name of image to scan (example -- gcr.io/rox/sample:5.0-rc1)
  results:
      - name: check_output
        description: Output of `roxctl image check`
  steps:
    - name: rox-image-check
      image: centos:8
      env:
        - name: ROX_API_TOKEN
          valueFrom:
            secretKeyRef:
              name: $(params.rox_api_token)
              key: rox_api_token
        - name: ROX_CENTRAL_ENDPOINT
          valueFrom:
            secretKeyRef:
              name: $(params.rox_central_endpoint)
              key: rox_central_endpoint
      script: |
        #!/usr/bin/env bash
        set +x
        curl -k -L -H "Authorization: Bearer $ROX_API_TOKEN" https://$ROX_CENTRAL_ENDPOINT/api/cli/download/roxctl-linux --output ./roxctl  > /dev/null; echo "Getting roxctl"
        chmod +x ./roxctl  > /dev/null
        ./roxctl image check --insecure-skip-tls-verify -e $ROX_CENTRAL_ENDPOINT --image $(params.image) 
```

```
apiVersion: tekton.dev/v1beta1
kind: ClusterTask
metadata:
  name: rox-image-scan
  namespace: app-380
spec:
  params:
    - name: rox_central_endpoint
      type: string
      description: Secret containing the address:port tuple for StackRox Central (example - rox.stackrox.io:443)
    - name: rox_api_token
      type: string
      description: Secret containing the StackRox API token with CI permissions
    - name: image
      type: string
      description: Full name of image to scan (example -- gcr.io/rox/sample:5.0-rc1)
    - name: output_format
      type: string
      description:  Output format (json | csv )
      default: json
  steps:
    - name: rox-image-scan
      image: centos:8
      env:
        - name: ROX_API_TOKEN
          valueFrom:
            secretKeyRef:
              name: $(params.rox_api_token)
              key: rox_api_token
        - name: ROX_CENTRAL_ENDPOINT
          valueFrom:
            secretKeyRef:
              name: $(params.rox_central_endpoint)
              key: rox_central_endpoint
      script: |
        #!/usr/bin/env bash
        set +x
        export NO_COLOR="False"
        curl -k -L -H "Authorization: Bearer $ROX_API_TOKEN" https://$ROX_CENTRAL_ENDPOINT/api/cli/download/roxctl-linux --output ./roxctl  > /dev/null; echo "Getting roxctl" 
        chmod +x ./roxctl > /dev/null
        ./roxctl image scan --insecure-skip-tls-verify -e $ROX_CENTRAL_ENDPOINT --image $(params.image) --output $(params.output_format) 
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
