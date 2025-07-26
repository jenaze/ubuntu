#!/bin/bash
##################### Ftp Section ######################
## wget https://raw.githubusercontent.com/jenaze/Ubunto/master/upload/fakeupload.sh
## bash <(curl -Ls https://raw.githubusercontent.com/jenaze/Ubunto/master/upload/fakeupload.sh)
## chmod +x fakeupload.sh
## */2 * * * * /dl/1/fakeupload.sh >> /dl/1/my.log 2>&1

addr=217.xxx.xxx.xxx
username=xxxxxxxxxx
password=xxxxxxxxxx

##################### File Section ######################
name=$RANDOM
x=3
y=50
size=$[ $x + $name % ($y + 1 - $x) ]
##################### Upload Section ######################

randomSizeUpload=true
uploadspeed=3m

MaximumRandomSpeed=10
if $randomSizeUpload
then
uploadspeed=$[ 2 + $name % ($MaximumRandomSpeed + 1 - 2) ]m
echo "Set UploadSpeed To "$uploadspeed
fi




truncate -s $size'MB' $name.zip

echo $name".zip ===> "$size"Mb"


echo $name".zip uploading..."
curl --limit-rate $uploadspeed -T /dl/1/$name.zip ftp://$addr --user $username:$password &> /dev/null
curl -v -u $username:$password ftp://$addr -Q 'DELE '$name'.zip' &> /dev/null
rm -rf $name.zip
echo "Done"
echo ""
