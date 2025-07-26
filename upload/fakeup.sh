#!/bin/bash

##################### Ftp Section ######################
## wget https://raw.githubusercontent.com/jenaze/Ubunto/master/upload/fakeup.sh
## bash <(curl -Ls https://raw.githubusercontent.com/jenaze/Ubunto/upload/master/fakeup.sh)
## chmod +x fakeup.sh
## touch /tmp/fakeup.lock
## */2 * * * * /root/dl/1/fakeup.sh >> /root/dl/1/my.log 2>&1

readonly addr=217.144.107.50
readonly username=sid@novinlike.ir
readonly password=xxxx

##################### File Section ######################
readonly name=$RANDOM

readonly MinimumFileSize=200
readonly MaximumFileSize=300

##################### Upload Section ######################
readonly ExteraDownloadMb=0
readonly ExteraUploadMb=0
###########################################################
NormalUploadSpeed=20m
readonly randomSizeUpload=true
readonly MaximumRandomSpeed=60
readonly MinimumRandomSpeed=20


readonly UploadEx=10 #1*10


LastSavedDl=0
LastSavedUP=0


if [ -f /tmp/fakeup.lock ]; then
    exit 0
else
    touch /tmp/fakeup.lock
fi


# if [ -f "/root/dl/1/info.txt" ]; then
#     LastSavedDl=$(awk 'NR==1{print $1}' /root/dl/1/info.txt)
#     LastSavedUP=$(awk 'NR==2{print $1}' /root/dl/1/info.txt)
#     echo "file_download=$LastSavedDl"
#     echo "file_upload=$LastSavedUP"
# fi


RX_bytes=$(/usr/sbin/ifconfig eth0 | awk '/RX packets/ {print $5}')
TX_bytes=$(/usr/sbin/ifconfig eth0 | awk '/TX packets/ {print $5}')

# Convert RX and TX statistics from bytes to megabytes (MB)
RX=$(echo "scale=2; $RX_bytes/1048576" | bc -l)
TX=$(echo "scale=2; $TX_bytes/1048576" | bc -l)

RX=$(echo "$RX+($ExteraDownloadMb)" | bc)
TX=$(echo "$TX+($ExteraUploadMb)" | bc)

SDL=$(echo "$RX*$UploadEx" | bc)


# Save download and upload info to file
echo "download=$RX" > /root/dl/1/info.txt
echo "upload=$TX" >> /root/dl/1/info.txt
echo "should_upload=$SDL"

if awk 'BEGIN {exit !('"$SDL"' > '"$TX"')}'
then
    size=$[ $MinimumFileSize + $name % ($MaximumFileSize + 1 - $MinimumFileSize) ]
    
    if $randomSizeUpload
    then
        # NormalUploadSpeed=$[ 2 + $name % ($MaximumRandomSpeed + 1 - 2) ]m
        NormalUploadSpeed=$(( RANDOM % (MaximumRandomSpeed - MinimumRandomSpeed + 1) + MinimumRandomSpeed ))"m"
        echo "Set UploadSpeed To "$NormalUploadSpeed
    fi
    
    truncate -s $size'MB' /root/dl/1/$name.zip
    echo $name".zip ===> "$size"Mb"
    echo $name".zip uploading..."
    curl --limit-rate $NormalUploadSpeed -T /root/dl/1/$name.zip ftp://$addr --user $username:$password &> /dev/null
    curl -v -u $username:$password ftp://$addr -Q 'DELE '$name'.zip' &> /dev/null
    rm -rf /root/dl/1/$name.zip
    echo "Done"
fi


rm /tmp/fakeup.lock
