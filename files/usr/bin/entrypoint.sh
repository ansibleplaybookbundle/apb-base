#!/bin/bash

if [[ $BUNDLE_DEBUG == "true" ]]; then
    set -x
fi

usage() {
    echo -n 'Usage: entrypoint.sh ACTION FLAG JSONSTRING
      ACTION     - one of [provision, deprovision, bind, unbind, test] verbs
      FLAG       - deprecated and will be dropped in the future
      JSONSTRING - a valid json string to be used as extra args for the playbook execution

      The command line args are positional.
      Please see the this for reference - https://github.com/openshift/ansible-service-broker/blob/ansible-service-broker-1.4.1-1/docs/service-bundle.md#input
'
}

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
FLAG=$2
JSONSTRING=$3
[[ "$#" -lt 3 ]] && usage && exit 1

PLAYBOOKS="/opt/apb/project"
PASSWORDS="/opt/apb/env/passwords"
EXTRAVARS="/opt/apb/env/extravars"
CREDS="/var/tmp/bind-creds"
TEST_RESULT="/var/tmp/test-result"
SECRETS_DIR="/etc/apb-secrets"
GALAXY_URL=$(echo $JSONSTRING | python -c 'import sys, json; print json.load(sys.stdin)["galaxy_url"]' 2>/dev/null || echo "null")
ROLE_NAME=$(echo $JSONSTRING | python -c 'import sys, json; print json.load(sys.stdin)["role_name"]' 2>/dev/null || echo "null")
ROLE_NAMESPACE=$(echo $JSONSTRING | python -c 'import sys, json; print json.load(sys.stdin)["role_namespace"]' 2>/dev/null || echo "null")

# Handle mounted secrets
mounted_secrets=$(ls $SECRETS_DIR)
if [[ ! -z "$mounted_secrets" ]] ; then
    echo '---' > $PASSWORDS
    for key in ${mounted_secrets} ; do
      for file in $(ls ${SECRETS_DIR}/${key}/..data); do
        echo "$file: $(cat ${SECRETS_DIR}/${key}/..data/${file})" >> $PASSWORDS
      done
    done
fi

# Add extravars
echo $JSONSTRING > $EXTRAVARS

# Install role from galaxy
# Used when apb-base is the runner image for the ansible-galaxy adapter
if [[ $ROLE_NAME != "null" ]] && [[ $ROLE_NAMESPACE != "null" ]]; then
    PROPER_ROLE_NAME=${ROLE_NAME//_/-}

    # Since the galaxy_url is passed from the broker, it should never be null
    # If absent though, we should just assume we are using galaxy.ansible.com
    if [[ $GALAXY_URL != "null" ]]; then
        ansible-galaxy install -s $GALAXY_URL $ROLE_NAMESPACE.$ROLE_NAME -p /opt/ansible/roles
    else
        ansible-galaxy install $ROLE_NAMESPACE.$ROLE_NAME -p /opt/ansible/roles
    fi

    mv /opt/ansible/roles/$ROLE_NAMESPACE.$ROLE_NAME /opt/ansible/roles/$PROPER_ROLE_NAME
    mv /opt/ansible/roles/$PROPER_ROLE_NAME/playbooks $PLAYBOOKS
fi

# Move the playbooks if necessary
if [[ ! -d "/opt/apb/project" ]]; then
    echo "DEPRECATED: APB playbooks should be stored at /opt/apb/project"
    mkdir -p /opt/apb/project
    cp /opt/apb/actions/* $PLAYBOOKS
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
ansible-runner run --ident $ACTION --playbook $PLAYBOOK /opt/apb
EXIT_CODE=$(cat /opt/apb/artifacts/$ACTION/rc)

set +e
rm -f /tmp/secrets
set -e

if [ -f $TEST_RESULT ]; then
    test-retrieval-init
fi

exit $EXIT_CODE
