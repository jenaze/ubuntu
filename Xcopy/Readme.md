install :

```
bash <(curl -s https://raw.githubusercontent.com/jenaze/ubuntu/Xcopy/refs/heads/main/setup.sh) \
  --user root \
  --host 10.10.10.1 \
  --pass mySecretPw \
  --dir /etc/x-ui \
  --dbname x-ui.db \
  --newIp 10.10.10.2 \
  --update true
```
