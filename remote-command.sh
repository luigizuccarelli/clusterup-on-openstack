#!/bin/bash
#
# @(#)$Id$

set -e

function prerequisite() {
  sudo subscription-manager register --username=qa@redhat.com --password=NWmfx9m28UWzxuvh
  sudo subscription-manager attach --pool=8a85f9823e3d5e43013e3ddd4e2a0977

  sudo subscription-manager repos --disable="*"
  sudo subscription-manager repos \
    --enable="rhel-7-server-rpms" \
    --enable="rhel-7-server-extras-rpms" \
    --enable="rhel-7-server-optional-rpms" \
    --enable="rhel-7-server-ose-3.3-rpms"

  sudo yum install -y docker gcc bind-utils wget git
  sudo yum clean all

  sudo sed -i -e 's|--selinux-enabled ||' /etc/sysconfig/docker
  sudo sed -i -e "s|# INSECURE_REGISTRY='--insecure-registry'|INSECURE_REGISTRY='--insecure-registry 172.30.0.0/16'|" /etc/sysconfig/docker
  #sudo sed -i -e "s|# setsebool|setsebool|" /etc/sysconfig/docker

  sudo groupadd docker
  sudo usermod -aG docker cloud-user

  sudo systemctl start docker

  docker images

  mkdir /home/cloud-user/bin
  wget https://github.com/openshift/origin/releases/download/v1.3.1/openshift-origin-client-tools-v1.3.1-dad658de7465ba8a234a4fb40b5b446a45a4cee1-linux-64bit.tar.gz 

  tar -xvf openshift-origin-client-tools-v1.3.1-dad658de7465ba8a234a4fb40b5b446a45a4cee1-linux-64bit.tar.gz
  cp openshift-origin-client-tools-v1.3.1-dad658de7465ba8a234a4fb40b5b446a45a4cee1-linux-64bit/oc /home/cloud-user/bin/

  export PATH=$PATH:/home/cloud-user/bin

  sudo subscription-manager unregister

  # call the cluster up command
  clusterup
}

function asDeveloper {
  oc login -u developer -p developer
}

function asSysAdmin {
  echo "Switching to system:admin in oc"
  oc login -u system:admin
  echo "Done."
}

function clusterup() {

  # used this from the fh-cup project :)

  SCRIPT_DIR="$( cd $( dirname "${BASH_SOURCE[0]}" ) && pwd)"
  CLUSTER_DIR="$SCRIPT_DIR/cluster"
  VOLUMES_DIR="$SCRIPT_DIR/cluster/volumes"
  # VIRTUAL_INTERFACE_IP=
  FH_CORE_OPENSHIFT_TEMPLATES="./fh-core-openshift-templates"
  export CORE_PROJECT_NAME=core
  export CLUSTER_DOMAIN=$VIRTUAL_INTERFACE_IP.xip.io

  FLUSH_IPTABLES=${FLUSH_IPTABLES:-"false"}

  echo "Checking pre-requisities..."
  echo "Done."

  echo "Enabling promiscuous mode for docker0 - may be prompted for password"
  sudo ip link set docker0 promisc on

  # If this workaround is enabled, flush ip tables
  # This works around dns issues in containers e.g. 'cannot clone from github.com' when doing an s2i build
  if [ "$FLUSH_IPTABLES" == "true" ]; then
    echo "Flushing iptables"
    sudo iptables-save > $CLUSTER_DIR/iptables.backup.$(date +"%s")
    sudo iptables -F
  fi

  echo "Creating cluster directories if they do not exist..."
  mkdir -p $CLUSTER_DIR/data $CLUSTER_DIR/config $CLUSTER_DIR/volumes

  echo "Updating hostname "
  sudo hostnamectl set-hostname $CLUSTER_DOMAIN 
  echo "Running 'oc cluster up'..."

  oc cluster up --host-data-dir=$CLUSTER_DIR/data --host-config-dir=$CLUSTER_DIR/config --public-hostname=$(hostname)
  # TODO: Check !=0 return
  echo "Cluster up, continuing."

  echo "Creating PVs..."

  for i in {1..10}; do mkdir -p $VOLUMES_DIR/devpv${i} && rm -rf $VOLUMES_DIR/devpv${i}/* && chmod 777 $VOLUMES_DIR/devpv${i} && chcon -R -t svirt_sandbox_file_t $VOLUMES_DIR/devpv${i}; done

  cp ./pvs-template.json ./pvs.json
  sed -i -e 's@REPLACE_ME@'"$VOLUMES_DIR"'@' pvs.json
  rm -f pvs.json-e
  asSysAdmin
  sleep 1
  oc create -f ./pvs.json
  echo "Done."

  echo "Creating Core Project..."
  asDeveloper
  oc new-project $CORE_PROJECT_NAME
  echo "Done."

  echo "Running Core setup scripts...."

  cd $FH_CORE_OPENSHIFT_TEMPLATES/scripts/core
  echo "Running prerequisites.sh..."
  ./prerequisites.sh
  echo "Done."

  echo "Updating Security Context Constraints..."
  asSysAdmin
  oc create -f $FH_CORE_OPENSHIFT_TEMPLATES/gitlab-shell/scc-anyuid-with-chroot.json
  oc adm policy add-scc-to-user anyuid-with-chroot system:serviceaccount:${CORE_PROJECT_NAME}:default
  asDeveloper
  echo "Done."

  # TODO: Check for dockercfg
  echo "Creating private-docker-cfg secret from ~/.docker/config.json ..."
  oc secrets new-dockercfg import-image-secret --docker-server=https://index.docker.io/v1/ --docker-username=fhteameng --docker-password=VNXVA9]+k6*XA+ --docker-email=fh.team.eng-group@redhat.com
  oc secrets link default import-image-secret --for=pull
  echo "Done."

  echo "To get events, run: oc get events -w"

  # TODO: Loops for status checking
  echo "Running infra setup..."
  ./infra.sh
  echo "Waiting."
  sleep 60
  oc get po

  echo "Running backend setup..."
  ./backend.sh
  echo "Waiting."
  sleep 60
  oc get po

  echo "Running frontend setup..."
  ./frontend.sh
  echo "Waiting."
  sleep 60
  oc get po

  echo "Running monitoring setup..."
  ./monitoring.sh
  echo "Waiting."
  sleep 60
  oc get po

  # TODO: MBaaS creation & hook up

  cd $SCRIPT_DIR
}

# entrypoint 
prerequisite