Install OpenShift Serverless on CRC
===================================

To install Serverless Operator from its master branch check [this](./latest/README.md).

Install Service Mesh and released Serverless Operator on CRC:

1. Before starting CRC, lets increase the resource allocation to CRC
```
# set the memory to 20GB
crc config set memory 20480

# set the cpus to 6
crc config set cpus 6

# start the crc now with pull secret file (provide your pull-secret file path)
crc start -p ~/Downloads/pull-secret.txt
```

2. Login using kubeadmin (update your password as provided by latest CRC release)
```
oc login -u kubeadmin -p F44En-Xau6V-jQuyb-yuMXB https://api.crc.testing:6443
```

3. Run the install script
```
bash crc-serverless.sh
```

TODO: Add setup and teardown args to script
