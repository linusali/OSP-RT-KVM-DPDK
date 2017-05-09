#!/bin/bash
openstack overcloud deploy \
--templates \
-e /usr/share/openstack-tripleo-heat-templates/environments/neutron-ovs-dpdk.yaml \
-e ~/templates/network-isolation.yaml \
-e ~/templates/rhel-registration/environment-rhel-registration.yaml \
-e ~/templates/rhel-registration/rhel-registration-resource-registry.yaml \
-e ~/templates/scheduler_hints_env.yaml \
-e ~/templates/network-environment.yaml \
-e ~/templates/first-boot-env.yaml \
--control-scale 1 \
--compute-scale 2 \
--ntp-server 192.168.1.1
