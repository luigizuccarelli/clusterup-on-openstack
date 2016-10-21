#!/bin/bash
#
# @(#)$Id$
#
# Utility to create/delete instances on OpenStack
#
# The following are set as default
# - flavor m1.large
# - image  rhel-guest-image-7.2
#

# for reference - list of flavors
# m1.miq
# m1.small
# m1.large
# c3.2xlarge
# c3.large
# c3.mxlarge
# c3.xlarge
# m1.tiny
# m1.medium
# m3.large
# m3.medium
# m3.xlarge
# r3.large
# t2.medium
# t2.micro
# t2.small

# for a list of images use

clear

cmds=( create useRc sshUtil )

# define convenience functions
function updateTime() {
  TIME=$(date +%T)
  NOW="\033[0;96m[ $(date +%Y-%m-%d) ${TIME} ]\033[0m"
  DEBUG="${NOW} \033[0;95mDEBUG\033[0m :"
  INFO="${NOW} \033[0;94mINFO\033[0m  :"
  ERROR="${NOW} \033[0;91mERROR\033[0m :"
}

KEYPAIR=osev33
SECGROUP=os3
SERVER_NAME=$OS_SERVER_NAME
RHEL_IMAGE=rhel-guest-image-7.2
FLAVOR=m1.large
AWS_HOSTED_ZONE_ID=ZO6D3A8PU8EUH
OSE_DOMAIN=cios
DNS_NODE=node1-osev31

function usage() {
  echo -e "${INFO} Usage \n"
  echo -e "        \033[0;93m./openstack-util.sh create\033[0m"
  echo " "
}

function create() {

  # check for openstack client install
  echo -e "${INFO} Checking for installed software"
  type openstack >/dev/null 2>&1 || { echo -e >&2 "${ERROR} Please install the openstack client tools - http://docs.openstack.org/user-guide/common/cli-install-openstack-command-line-clients.html\n"; exit 1; }
  type oc >/dev/null 2>&1 || { echo -e >&2 "${ERROR} Please install the openshift client tool - https://github.com/openshift/origin/releases/download/v1.3.1/openshift-origin-client-tools-v1.3.1-dad658de7465ba8a234a4fb40b5b446a45a4cee1-linux-64bit.tar.gz\n"; exit 1; }
  type git >/dev/null 2>&1 || { echo -e >&2 "${ERROR} Please install git\n"; exit 1; }

  source ./rhmobile.openrc.sh

  # alert before continuing
  echo -e "${INFO} The following settings are going to be used to create the new instances"
  echo -e " "
  echo -e "        Server Name    : ${SERVER_NAME}"
  echo -e "        Keypair        : ${KEYPAIR}"
  echo -e "        Security group : ${SECGROUP}"
  echo -e "        Image          : ${RHEL_IMAGE}"
  echo -e "        Flavor         : ${FLAVOR}"
  echo -e "        Aws zone id    : ${AWS_HOSTED_ZONE_ID}"
  echo -e "        Ose domain     : ${OSE_DOMAIN}"
  echo -e " "
  echo -e "        Remember to change the Server Name  - it must be unique"
  echo -e "        Press n to exit and make changes as needed"
  echo -e " "

  read -p "        Continue (y/n)?" choice
  case "$choice" in
    y|Y ) echo " ";;
    n|N ) exit 0; echo " ";;
    * ) echo "invalid";;
  esac

  echo -e "${INFO} Checking if keypair ${KEYPAIR} exists"

  keypairexists=$(openstack keypair list | grep ${KEYPAIR})

  if [ -z "$keypairexists" ]
  then
    #TODO create a new keypair
    echo "TODO create keypair"
  else
    echo -e "${DEBUG} keypair found"
  fi

  echo -e "${INFO} Checking if security group ${SECGROUP} exists"
  sgexists=$(openstack security group list | grep ${SECGROUP})

  if [ -z "$sgexists" ]
  then
    #TODO create a new security group
    echo "TODO create security group"
  else
    echo -e "${DEBUG} security group found"
  fi

  image=$(openstack image list --private | grep ${RHEL_IMAGE} | awk '{print $2}')
  flavor=$(openstack flavor list --private | grep m1.large | grep -v ephemeral | grep -v qeos | awk '{print $2}')

  if [ -z "$image" ]
  then
    echo -e "${ERROR} Image not found '${RHEL_IMAGE}'"
    exit 1
  fi

  if [ -z "$flavor" ]
  then
    echo -e "${ERROR} Flavor not found '${m1.large}'"
    exit 1
  fi

  echo -e "${DEBUG} Image found ${image}"
  echo -e "${DEBUG} flavor found ${flavor}"

  # boot the server
  echo -e "${INFO} Launcing the server"
  openstack server create --flavor ${flavor} --image ${image} --security-group ${SECGROUP} --security-group default --key-name ${KEYPAIR} ${SERVER_NAME}

  # check if its up
  server_id=$(openstack server list | grep ${SERVER_NAME} | awk '{ print $1 }')

  # find floating ip
  floating_ip=$(openstack floating ip list | grep None | awk '{ print $4 }')

  #TODO add a step to create floating ip if it doesn't exist

  # link it
  openstack server add floating ip $server_id $floating_ip

  # copy prerequisite
  scp remote-command.sh cloud-user@$floating_ip:/home/cloud-user
  scp pvs-remplate.yaml cloud-user@$floating_ip:/home/cloud-user

  # before launching the remote script get the latest version of the core templates
  # and install on the openstack remote server
  ssh -tt cloud-user@$floating_ip git clone https://github.com/fheng/fh-core-openshift-templates

  # update the remote-command script with the newly obtained floating-ip
  sudo sed -i -e "s|# VIRTUAL_INTERFACE_IP=|VIRTUAL_INTERFACE_IP=$floating_ip|" remote-command.sh

  # execute the script remotely
  ssh -tt cloud-user@$floating_ip sudo /home/cloud-user/remote-command.sh

}

function remove() {
  # used for testing
  # overides the previous set values
  if [  "$1" = "test" ]
  then
    KEYPAIR=abckp
    SECGROUP=abc
    INSTANCES=(abc-test1 abc-test2)
    echo -e "${INFO} Using test parameters"
  fi

  for i in ${INSTANCES[@]}; do
    echo -e "${INFO} Deleting instance ${i}"
    nova delete ${i}
  done
}

function removeKey() {
  # used for testing
  # overides the previous set values
  if [  "$1" = "test" ]
  then
    KEYPAIR=abckp
    SECGROUP=abc
    INSTANCES=(abc-test1 abc-test2)
    echo -e "${INFO} Using test parameters"
  fi

  echo -e "${INFO} Deleting keypair ${KEYPAIR}"
  nova keypair-delete ${KEYPAIR}
}

function removeSecGroup() {
  # used for testing
  # overides the previous set values
  if [  "$1" = "test" ]
  then
    KEYPAIR=abckp
    SECGROUP=abc
    INSTANCES=(abc-test1 abc-test2)
    echo -e "${INFO} Using test parameters"
  fi

  echo -e "${INFO} Deleting security group  ${SECGROUP}"
  nova secgroup-delete ${SECGROUP}
}

function deleteAll() {
  deleteVolumes
  remove
  removeKey
  sleep 20;
  removeSecGroup
  # finally clean up the openshift temp dir
  rm -rf /tmp/openshift-ansible
}

function sshUtil {
  HOSTS=$(tail -n 5 hosts.new)
  for i in ${HOSTS[@]}; do
    ssh-keygen -R ${i}
  done
}

updateTime
flag=false

if [ "$#" -eq 0 ]
then
  usage
  exit 1
else

  for var in "${cmds[@]}"
  do
    if [ "${var}" = "${1}" ]
    then
      flag=true
    fi
  done

  if [ "${flag}" = "false" ]
  then
    usage
    exit 1
  fi

  case ${1} in
    create)
      create ${2}
    ;;
    remove)
      remove ${2}
    ;;
    removeKey)
      removeKey ${2}
    ;;
    removeSecGroup)
      removeSecGroup ${2}
    ;;
    deleteAll)
      deleteAll
    ;;
    useRc)
      source ${2}
      exit 0
    ;;
    sshUtil)
      sshUtil
    ;;

  esac

fi
