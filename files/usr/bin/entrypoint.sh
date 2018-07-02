#!/bin/bash

if [[ $BUNDLE_DEBUG == "true" ]]; then
    set -x
fi

# Work-Around
# The OpenShift's s2i (source to image) requires that no ENTRYPOINT exist
# for any of the s2i builder base images.  Our 's2i-apb' builder uses the
# apb-base as it's base image.  But since the apb-base defines its own
# entrypoint.sh, it is not compatible with the current source-to-image.
#
# The below work-around checks if the entrypoint was called within the
# s2i-apb's 'assemble' script process. If so, it skips the rest of the steps
# which are APB run-time specific.
#
# Details of the issue in the link below:
# https://github.com/openshift/source-to-image/issues/475
#
if [[ $@ == *"s2i/assemble"* ]]; then
    echo "---> Performing S2I build... Skipping server startup"
    exec "$@"
    exit $?
fi

if ! whoami &> /dev/null; then
    if [ -w /etc/passwd ]; then
        echo "${USER_NAME:-apb}:x:$(id -u):0:${USER_NAME:-apb} user:${HOME}:/sbin/nologin" >> /etc/passwd
    fi
fi

ACTION=$1
shift
EXTRA_ARGS="${@}"
PLAYBOOKS="/opt/apb/project"
PASSWORDS="/opt/apb/env/passwords"
CMDLINE="/opt/apb/env/cmdline"
CREDS="/var/tmp/bind-creds"
TEST_RESULT="/var/tmp/test-result"
SECRETS_DIR="/etc/apb-secrets"
ROLE_NAME=$(echo $2 | jq -r .role_name 2>/dev/null || echo "null")
ROLE_NAMESPACE=$(echo $2 | jq -r .role_namespace 2>/dev/null || echo "null")

# Handle mounted secrets
mounted_secrets=$(ls $SECRETS_DIR)
if [[ ! -z "$mounted_secrets" ]] ; then

    echo '---' > $PASSWORDS
    for key in ${mounted_secrets} ; do
      for file in $(ls ${SECRETS_DIR}/${key}/..data); do
        echo "$file: $(cat ${SECRETS_DIR}/${key}/..data/${file})" >> $PASSWORDS
      done
    done
    EXTRA_ARGS="${EXTRA_ARGS} --extra-vars no_log=true"
fi
echo "${EXTRA_ARGS}" > $CMDLINE

# Install role from galaxy
# Used when apb-base is the runner image for the ansible-galaxy adapter
if [[ $ROLE_NAME != "null" ]] && [[ $ROLE_NAMESPACE != "null" ]]; then
    ansible-galaxy install -s https://galaxy-qa.ansible.com $ROLE_NAMESPACE.$ROLE_NAME -p /opt/ansible/roles
    mv /opt/ansible/roles/$ROLE_NAMESPACE.$ROLE_NAME /opt/ansible/roles/$ROLE_NAME
    mv /opt/ansible/roles/$ROLE_NAME/playbooks $PLAYBOOKS
fi

# Move the playbooks if necessary
if [[ ! -d "/opt/apb/project" ]]; then
    echo "DEPRECATED: APB playbooks should be stored at /opt/apb/project"
    mv /opt/apb/actions $PLAYBOOKS
fi

# Determine the playbook to be executed
if [[ -e "$PLAYBOOKS/$ACTION.yaml" ]]; then
    PLAYBOOK="$ACTION.yaml"
elif [[ -e "$PLAYBOOKS/$ACTION.yml" ]]; then
    PLAYBOOK="$ACTION.yml"
else
  echo "'$ACTION' NOT IMPLEMENTED"
  exit 8 # action not found
fi

# Invoke ansible-runner
ansible-runner run --playbook $PLAYBOOK /opt/apb
EXIT_CODE=$?

set +e
rm -f /tmp/secrets
set -e

if [ -f $TEST_RESULT ]; then
    test-retrieval-init
fi

exit $EXIT_CODE
