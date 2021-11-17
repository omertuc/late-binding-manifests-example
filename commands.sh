#!/bin/bash

set -euxo pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# xq is needed later on
pip install yq

# Destroy previous work
make delete_all_virsh_resources
minikube stop
minikube delete

# Start minikube
make start_minikube   

# Launch service on minikube, with CRDs
ENABLE_KUBE_API=true make run

# < Manually modify service configmap to auth none and restart deployment >

# Delete old demo CRs
rm -rf demo
oc delete -f demo -R    

# <Perform ns.sh here>

# Apply new demo CRS
oc apply -f demo -R    

# Download ISO
rm -rf demo.iso
curl $(oc get -n swarm infraenv demo -ojson | jq '.status.isoDownloadURL' -r) -o demo.iso

# Boot machine from ISO
virt-install \
  --autostart \
  --virt-type=kvm \
  --name demo_master \
  --memory 33000 \
  --vcpus=8 \
  --cdrom=demo.iso \
  --disk path=/var/lib/libvirt/images/master0.qcow2,size=240,bus=virtio,format=qcow2 \
  --events on_reboot=restart \
  --boot hd,cdrom \
  --noautoconsole

# Find agent
agent_name=$(oc get agents -n swarm -oname)

# Approve agent
oc patch $agent_name -n swarm --type='json' --patch '[{
        "op": "add",
        "path": "/spec/approved",
        "value": true
    }]'

# Set hostname
oc patch $agent_name -n swarm --type='json' --patch '[{
        "op": "add",
        "path": "/spec/hostname",
        "value": "demoplane"
    }]'

# Get virtual machine IP / subnet for machine network
ip_addr=$(virsh net-dhcp-leases default | grep $(virsh dumpxml demo_master | xq '.domain.devices.interface.mac."@address"' -r) | cut -d' ' -f16 | cut -d'/' -f1)
subnet=$(echo $ip_addr | cut -d'.' -f1-3)".0/24"

# Set machine network CIDR (Doesn't really work)
oc patch agentclusterinstall/demo -n swarm --type='json' --patch '[
    {
        "op": "add",
        "path": "/spec/networking/machineNetwork/-",
        "value": {"cidr": "'$subnet'"}
    }
]'

# Finally - bind to cluster deployment
oc patch $agent_name -n swarm --type='json' --patch '[{
        "op": "add",
        "path": "/spec/clusterDeploymentName",
        "value": {
          "name": "demo",
          "namespace": "swarm"
        }
    }]
'

