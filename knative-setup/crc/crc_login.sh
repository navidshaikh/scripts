CRC_USER="kubeadmin"
CRC_PASSWORD=$(crc console --credentials | grep $CRC_USER | cut -d ' ' -f12)
CRC_URL=$(crc console --credentials | grep $CRC_USER | cut -d ' ' -f 13 | tr -d \')
# complete oc login command
#CMD=$(crc console --credentials | grep $CRC_USER | cut -d ' ' -f 7-13|tr -d \')

echo "Logging into CRC using $CRC_USER and $CRC_PASSWORD"
oc login -u $CRC_USER -p $CRC_PASSWORD $CRC_URL
