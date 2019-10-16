Install OpenShift Serverless on CRC
===================================

Install Service Mesh and Serverless Operator on CRC:

1. Login using kubeadmin (update your password as provided by latest CRC release)
```
oc login -u kubeadmin -p F44En-Xau6V-jQuyb-yuMXB https://api.crc.testing:6443
```

2. Run the install script
```
bash crc-serverless.sh
```

TODO: Add setup and teardown args to script
