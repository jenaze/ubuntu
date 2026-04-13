
Test
```
bash <(curl -s https://raw.githubusercontent.com/jenaze/ubuntu/refs/heads/main/spoof/setup_spoof_test.sh) Target_ip Spoof_ip
```
Remove iptables Role
```
sudo iptables -t nat -D POSTROUTING 1
```
