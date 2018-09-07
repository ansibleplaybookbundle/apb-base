FROM ansible/ansible-runner:latest
MAINTAINER Ansible Playbook Bundle Community
LABEL "com.redhat.apb.runtime"="2"

ENV USER_NAME=apb \
    USER_UID=1001 \
    BASE_DIR=/opt/apb
ENV HOME=${BASE_DIR}

RUN curl https://copr.fedorainfracloud.org/coprs/g/ansible-service-broker/ansible-service-broker-nightly/repo/epel-7/group_ansible-service-broker-ansible-service-broker-nightly-epel-7.repo -o /etc/yum.repos.d/asb.repo
RUN yum -y install epel-release centos-release-openshift-origin git \
    && yum -y install --setopt=tsflags=nodocs origin-clients python-openshift ansible ansible-kubernetes-modules ansible-asb-modules apb-base-scripts \
    && yum clean all

RUN mkdir -p /usr/share/ansible/openshift \
             /etc/ansible /opt/apb /opt/ansible \
             ${BASE_DIR}/{etc,.kube,.ansible/tmp} \
             && chown -R ${USER_NAME}:0 /opt/{ansible,apb} \
             && chmod -R g=u /opt/{ansible,apb} /etc/passwd

WORKDIR /opt/apb
ENTRYPOINT ["entrypoint.sh"]
