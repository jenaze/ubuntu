#!/bin/bash

##################### Ftp Section ######################
## wget https://raw.githubusercontent.com/jenaze/Ubunto/master/upload/SelfFakeUp.sh
## bash <(curl -Ls https://raw.githubusercontent.com/jenaze/Ubunto/master/upload/SelfFakeUp.sh)
## chmod +x SelfFakeUp.sh
## screen -r
## Ctrl-a c: Create a new window with a shell in it.
## Ctrl-a n: Switch to the next window.
## Ctrl-a p: Switch to the previous window.
## Ctrl-a d: Detach from the current screen session.
## Ctrl-a k: Kill the current window.


readonly addr_1=217.144.107.50
readonly username_1=sid@novinlike.ir
readonly password_1=xxxxxx



readonly addr_2=88.135.68.72
readonly username_2=sid@hshasti.ir
readonly password_2=xxxxxx

##################### File Section ######################

MinimumFileSize=400
MaximumFileSize=500

##################### Upload Section ######################
readonly ExteraDownloadMb=0
readonly ExteraUploadMb=0
###########################################################
NormalUploadSpeed=20m
readonly randomSizeUpload=true
readonly MaximumRandomSpeed=150
readonly MinimumRandomSpeed=60
readonly DIRECTORY=/root/dl/2/

readonly UploadEx=12 #1*10

LastSavedDl=0
LastSavedUP=0

$i = 0
while true
do
    name=$RANDOM
    
    # if [ -f "$DIRECTORY/info.txt" ]; then
    #     LastSavedDl=$(awk 'NR==1{print $1}' "$DIRECTORY/info.txt")
    #     LastSavedUP=$(awk 'NR==2{print $1}' "$DIRECTORY/info.txt")
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
    #echo "download=$RX" > "$DIRECTORY/info.txt"
    #echo "upload=$TX" >> "$DIRECTORY/info.txt"
    # echo "should_upload=$SDL"
    
    if awk 'BEGIN {exit !('"$SDL"' > '"$TX"')}'
    then
        
        ((i++))
        
        
        if (( $i % 2 == 1 )); then
            addr=$addr_1
            username=$username_1
            password=$password_1
        else
            MinimumFileSize=800
            MaximumFileSize=1200
            addr=$addr_2
            username=$username_2
            password=$password_2
        fi
        
        
        size=$[ $MinimumFileSize + $name % ($MaximumFileSize + 1 - $MinimumFileSize) ]
        
        if $randomSizeUpload
        then
            # NormalUploadSpeed=$[ 2 + $name % ($MaximumRandomSpeed + 1 - 2) ]m
            NormalUploadSpeed=$(( RANDOM % (MaximumRandomSpeed - MinimumRandomSpeed + 1) + MinimumRandomSpeed ))"m"
            # echo "Set UploadSpeed To "$NormalUploadSpeed
        fi
        
        
        
        
        
        truncate -s $size'MB' "$DIRECTORY/$name.zip"
        echo "$name.zip ===> $size'Mb' ==> speed : $NormalUploadSpeed"
        # echo $name".zip uploading..."
        curl --limit-rate $NormalUploadSpeed -T "$DIRECTORY/$name.zip" ftp://$addr --user $username:$password &> /dev/null
        curl -v -u $username:$password ftp://$addr -Q 'DELE '$name'.zip' &> /dev/null
        rm -rf "$DIRECTORY/$name.zip"
        echo "Done"
    fi
    
done
