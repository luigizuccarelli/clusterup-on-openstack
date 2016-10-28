# clusterup-on-openstack

A set of scripts to create a single node on OpenStack install the pre-requisite software
and then deploy and launch the oc cluster up with fh-core components
  		  
## Prerequisites

* Export Unique Server Name

 ```bash
 export OPENSTACK_SERVER_NAME="MyCustomValue"
 ```
 
* Install OpenStack Client Tools
 
 _ Install for Mac OS X_
 
 ```bash
 brew install python
 pip install --upgrade pip
 pip install --upgrade python-openstackclient
 ```
 
## Usage
 
 Run the following script to create the OpenStack instance. Also remember to change the Server Name value (it must be unique)
  		  
 ```
 ./openstack-util.sh create
 ```
