# apb-base

This is a base image that can be used to create an [Ansible Playbook
Bundle](https://github.com/ansibleplaybookbundle/ansible-playbook-bundle).

## Debug

To turn on debug mode, set the environment variable `BUNDLE_DEBUG=true`. This
may be easiest to do in the Dockerfile for your APB.

```
ENV BUNDLE_DEBUG=true
```

Currently this behavior sets `-x` for the entrypoint, which the bash
documentation explains will "Print commands and their arguments as they are
executed". 
