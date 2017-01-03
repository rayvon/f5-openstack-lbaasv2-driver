#!/usr/bin/env bash

# Copyright 2017 F5 Networks Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

set -ex

# Create a virtualenv
virtualenv ${TEMPEST_VENV_DIR}
source ${TEMPEST_VENV_ACTIVATE}

# Install tox
pip install tox

# Install tempest & its config files
git clone ${TEMPEST_REPO} ${TEMPEST_DIR}
pip install ${TEMPEST_DIR}
cp conf/tempest.conf ${TEMPEST_CONFIG_DIR}/tempest.conf.orig
cp conf/accounts.yaml ${TEMPEST_CONFIG_DIR}/accounts.yaml

# We need to deactivate the virtualenv to run TLC commands
deactivate

# Find the values for tempest.conf and substitute them

OS_CONTROLLER_IP=`tlc --session ${TEST_SESSION} symbols \
    | grep openstack_controller1ip_data_direct \
    | awk '{print $3}'`

ssh_cmd="ssh -o StrictHostKeyChecking=no testlab@${OS_CONTROLLER_IP}"

OS_PUBLIC_ROUTER_ID=`${ssh_cmd} "source ~/keystonerc_testlab && neutron router-list -F id -f value"`
OS_PUBLIC_NETWORK_ID=`${ssh_cmd} "source ~/keystonerc_testlab && neutron net-list -F name -F id -f value" \
    | grep external_network \
    | awk '{print $1}'`
OS_CIRROS_IMAGE_ID=`${ssh_cmd} "source ~/keystonerc_testlab && glance image-list" \
    | grep ${TEST_CIRROS_IMAGE} \
    | awk '{print $2}'`

cat ${TEMPEST_CONFIG_DIR}/tempest.conf.orig \
  | sed "s/{{ OS_CONTROLLER_IP }}/${OS_CONTROLLER_IP}/" \
  | sed "s/{{ OS_PUBLIC_ROUTER_ID }}/${OS_PUBLIC_ROUTER_ID}/" \
  | sed "s/{{ OS_PUBLIC_NETWORK_ID }}/${OS_PUBLIC_NETWORK_ID}/" \
  | sed "s/{{ OS_CIRROS_IMAGE_ID }}/${OS_CIRROS_IMAGE_ID}/" \
  > ${TEMPEST_CONFIG_DIR}/tempest.conf

# Install neutron at stable/mitaka because stable/liberty tests will not work
# because they use an upper contraints file in the installation script that
# neutron-lbaas uses for tox tests.
# The file that causes this to happen is: neutron-lbaas/tools/tox_install.sh
#
# The use of the liberty version of this file restricts the crpytography
# library to a low version which is not compatible with newer versions of
# OpenSSL (1.0.2g+) because of an API change in OpenSSL.
#
# See this issue for more details:
# https://github.com/pyca/cryptography/issues/2750
#
# TODO: Make a decision about not using the neutron-lbaas install script
#       and just installing from requirements files on newest versions
git clone\
  -b ${NEUTRON_LBAAS_BRANCH} \
  --single-branch \
  ${NEUTRON_LBAAS_REPO} \
  ${NEUTRON_LBAAS_DIR}

# Copy our tox.ini file to neutron so we can run py.test instead of testr
cp conf/neutron-lbaas.tox.ini ${NEUTRON_LBAAS_DIR}/f5.tox.ini

