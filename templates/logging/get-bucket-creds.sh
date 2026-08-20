#!/usr/bin/env bash

# Source this file from Bash after the ObjectBucketClaim is Bound:
#   source templates/logging/get-bucket-creds.sh

OBC_NAMESPACE="${OBC_NAMESPACE:-openshift-logging}"
OBC_NAME="${OBC_NAME:-loki-bucket-odf}"

_obc_read_configmap() {
  oc -n "${OBC_NAMESPACE}" get configmap "${OBC_NAME}" \
    -o "jsonpath={.data.$1}"
}

_obc_read_secret() {
  oc -n "${OBC_NAMESPACE}" get secret "${OBC_NAME}" \
    -o "jsonpath={.data.$1}" | base64 -d
}

if [[ "$(oc -n "${OBC_NAMESPACE}" get obc "${OBC_NAME}" -o jsonpath='{.status.phase}')" != "Bound" ]]; then
  echo "ObjectBucketClaim ${OBC_NAMESPACE}/${OBC_NAME} is not Bound." >&2
  return 1 2>/dev/null || exit 1
fi

export BUCKET_HOST="$(_obc_read_configmap BUCKET_HOST)"
export BUCKET_NAME="$(_obc_read_configmap BUCKET_NAME)"
export BUCKET_PORT="$(_obc_read_configmap BUCKET_PORT)"
export ACCESS_KEY_ID="$(_obc_read_secret AWS_ACCESS_KEY_ID)"
export SECRET_ACCESS_KEY="$(_obc_read_secret AWS_SECRET_ACCESS_KEY)"

for variable_name in BUCKET_HOST BUCKET_NAME BUCKET_PORT ACCESS_KEY_ID SECRET_ACCESS_KEY; do
  if [[ -z "${!variable_name}" ]]; then
    echo "Required value ${variable_name} is empty." >&2
    return 1 2>/dev/null || exit 1
  fi
done

unset -f _obc_read_configmap _obc_read_secret
echo "Bucket credentials loaded into the current shell. Secret values were not printed."

