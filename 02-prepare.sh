#!/bin/bash
rhel_dpdk_img="/home/stack/images/rhel-7.3-dpdk.qcow2"


NONSTOP="no"

source overcloudrc

prompt_cond (){
  if [ $NONSTOP = "no" ] ; then
    echo -e "\e[40;38;5;82m $@\e[0m"
    read -p "## [S]kip, [CTRL+C] to break, Enter to continue : " skip
    [ x$skip = "xS" ] && continue
  fi
}

disable_compute (){
  prompt_cond "## Disable nova-compute on overcloud-compute-1.localdomain?"
  nova service-disable overcloud-compute-1.localdomain nova-compute
}

create_provider_nets (){
  prompt_cond "## Create provider networks?"
  openstack network create dpdk0 --external --provider-network-type flat --provider-physical-network dpdk0 --disable-port-security
  openstack network create dpdk1 --external --provider-network-type flat --provider-physical-network dpdk1 --disable-port-security
}

create_provider_subnets (){
  prompt_cond "## Create subnets under provider networks?"
  openstack subnet create dpdk0-subnet --network dpdk0 --no-dhcp --allocation-pool start=10.1.0.51,end=10.1.0.250 --gateway 10.1.0.1 --subnet-range 10.1.0.0/24
  openstack subnet create dpdk1-subnet --network dpdk1 --no-dhcp --allocation-pool start=10.1.1.51,end=10.1.1.250 --gateway 10.1.1.1 --subnet-range 10.1.1.0/24
}

create_dpdk_flavor (){
  prompt_cond "## Create flavor for DPDK instances?"
  openstack flavor create  m1.medium_huge_4cpu_numa0 --ram 4096 --disk 50 --vcpus 4
  openstack flavor set --property hw:cpu_policy=dedicated \
     --property hw:mem_page_size=large \
     --property hw:numa_nodes=1 \
     --property hw:numa_mempolicy=preferred \
     --property hw:numa_cpus.0=4,5,6,7 \
     --property hw:numa_mem.0=4096 \
     --property aggregate_instance_extra_specs:pinned=true \
     m1.medium_huge_4cpu_numa0
}

upload_dpdk_image (){
  prompt_cond "## Upload pre-pared RHEL 7.3 with DPDK to glance?"
  if [ -f "$rhel_dpdk_img" ]; then
   openstack image delete "RHEL-DPDK-7.3"
   openstack image create --disk-format qcow2 --container-format bare --public --file "$rhel_dpdk_img" RHEL-DPDK-7.3
  else
   echo "DPDK image $rhel_dpdk_img does not exists"
  fi
}

create_instance (){
  prompt_cond "## Create an instance using RHEL+DPDK image?"
  #echo -e "Trying to delete any existing instance with name RHEL-DPDK."
  #openstack server delete RHEL-DPDK
  echo -e "Creating a new instance out of RHEL+DPDK images."
  openstack server create --image RHEL-DPDK-7.3  --flavor m1.medium_huge_4cpu_numa0 $(openstack network list -c ID -f value|awk '{printf "--nic net-id="$1" "}') RHEL-DPDK
}

prepare_compute1_moongen (){
  prompt_cond "## Prepare Compute 1 as MoonGen traffic generator?"
  source ~/stackrc
  ssh_opts='-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o User=heat-admin'
  compute1="$(nova list|grep overcloud-compute-1|awk -F "ctlplane=" '{print $2}'|cut -f1 -d " ") $ssh_opts"

  echo -e "Stopping openvswitch and neutron-openvswitch-agent on compute-1"
  ssh $compute1 'sudo systemctl stop openvswitch && sudo systemctl stop neutron-openvswitch-agent.service'
  echo -e "Installing lua-packetgen on compute-1"
  ssh $compute1 'sudo yum install -y cmake screen'
  ssh $compute1 'sudo git clone https://github.com/atheurer/lua-trafficgen && cd lua-trafficgen && sudo screen -d -m ./setup.sh'
  cat defs/opnfv-vsperf-cfg.lua |ssh $compute1 'cat >/tmp/opnfv-vsperf-cfg.lua && sudo mv /tmp/opnfv-vsperf-cfg.lua ~/lua-trafficgen/'
  echo -e "*************
  Setup of lua-trafficgen is started on compute-1.
  Please login to compute-1 and check 'screen -rd' to view the status.
  If there is no active screen session then probably the installation is already complete.\n*************"
}

for func in $(egrep "\(\)" $0 |awk '{print $1}'|egrep -v "(prompt_cond)") ; do
 $func
done
