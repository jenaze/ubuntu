install:

```
bash <(curl -Ls https://raw.githubusercontent.com/jenaze/ubuntu/refs/heads/main/xray-core/setup.sh) --help
```
xray-config:

```
wget https://raw.githubusercontent.com/jenaze/ubuntu/refs/heads/main/xray-core/xray_config.json
```

بررسی وضعیت سرویس:
```
sudo systemctl status xray.service
```
مشاهده لاگ‌های زنده:
```
journalctl -u xray.service -f
```
