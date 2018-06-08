#!/bin/bash

# TODO: Don't forget to add this back
#if [[ $BUNDLE_DEBUG == "true" ]]; then
#    set -x
#fi
set -x

ACTION=$1
EXTRA_VARS=$3

RUNNER_DIR=/opt/apb/
RUNNER_PROJECT_DIR="$RUNNER_DIR/project"
RUNNER_EXTRA_VARS="$RUNNER_DIR/env/extravars"
TEST_RESULT="/var/tmp/test-result"

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

# Move playbooks to the action dir
mv /opt/apb/actions $RUNNER_PROJECT_DIR

# Write extra vars as YAML
echo "$EXTRA_VARS" | python -c 'import sys, yaml, json; yaml.safe_dump(json.load(sys.stdin), sys.stdout, default_flow_style=False)' > $RUNNER_EXTRA_VARS

# Add secrets to extra vars
SECRETS_DIR=/etc/apb-secrets
mounted_secrets=$(ls $SECRETS_DIR)
if [[ ! -z "$mounted_secrets" ]] ; then

    echo 'no_log: True' >> $RUNNER_EXTRA_VARS

    for key in ${mounted_secrets} ; do
      for file in $(ls ${SECRETS_DIR}/${key}/..data); do
        echo "$file: $(cat ${SECRETS_DIR}/${key}/..data/${file})" >> $RUNNER_EXTRA_VARS
      done
    done
fi
cat $RUNNER_EXTRA_VARS

if [[ -e "$RUNNER_PROJECT_DIR/$ACTION.yaml" ]]; then
    PLAYBOOK="$ACTION.yaml"
elif [[ -e "$RUNNER_PROJECT_DIR/$ACTION.yml" ]]; then
    PLAYBOOK="$ACTION.yml"
else
  echo "'$ACTION' NOT IMPLEMENTED" # TODO
  exit 8 # action not found
fi

ansible-runner run --playbook $PLAYBOOK /opt/apb/
EXIT_CODE=$?

if [ -f $TEST_RESULT ]; then
   test-retrieval-init
fi

exit $EXIT_CODE
