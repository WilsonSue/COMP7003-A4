## Setting Up:

### Proxy:
```shell
# Enable IP forwarding
sudo sysctl -w net.ipv4.ip_forward=1

# Set longer TCP timeout
sudo sysctl -w net.ipv4.tcp_retries2=15

# any new incoming TCP traffic on port 5201, change the destination to 192.168.1.78
sudo iptables -t nat -A PREROUTING -p tcp --dport 5201 -j DNAT --to-destination 192.168.1.78:5201

# allow the newly translated packet to be forwarded by the proxy
sudo iptables -A FORWARD -p tcp -d 192.168.1.78 --dport 5201 -j ACCEPT

# Verify interface name
ip a
# Look for your interface (likely eth0, ens33, enp0s3, etc.)
```

### Server:
```shell
# Add route to client through proxy
sudo ip route add 192.168.1.88 via 192.168.1.92

# Verify
ip route | grep 192.168.1.88
```

### Client:
```shell
# Add route to server through proxy
sudo ip route add 192.168.1.78 via 192.168.1.92

# Verify
ip route | grep 192.168.1.78
```

## After tests server & client run:

```shell
sudo pkill tcpdump
ps aux | grep tcpdump 
```

## Test 1 & 2

### Proxy
```shell
sudo ./proxy.sh -m clean
```

### Start Server
```shell
sudo ./server.sh -c exp1_baseline
```

### TCP Test Client
```shell
sudo ./client.sh -t 20 -c exp1_baseline_tcp -P 192.168.1.92 192.168.1.78
```

### UDP Test Client
```shell
sudo ./client.sh -t 20 -u -b 5M -c exp1_baseline_udp -P 192.168.1.92 192.168.1.78
```

## Test 3 & 4

### Proxy apply 1% loss
```shell
sudo ./proxy.sh -m loss -l 1

# Verify it's applied
sudo tc qdisc show
```

### Start Server
```shell
sudo ./server.sh -c exp2_loss
```

### TCP Test
```shell
sudo ./client.sh -t 20 -c exp2_loss_tcp -P 192.168.1.92 192.168.1.78
```

### UDP Test
```shell
sudo ./client.sh -t 20 -u -b 5M -c exp2_loss_udp -P 192.168.1.92 192.168.1.78
```

### Server
Press Ctrl+C

### Clean Proxy
```shell
sudo ./proxy.sh -m clean
```

## Test 5 & 6

### Apply 10 Mbit/s Bottleneck on Proxy
```shell
sudo ./proxy.sh -m bottleneck -r 10mbit

# Verify it's applied
sudo tc qdisc show
```

### Start Server
```shell
sudo ./server.sh -c exp3_bottleneck
```

### TCP test
```shell
sudo ./client.sh -t 20 -c exp3_bottleneck_tcp -P 192.168.1.92 192.168.1.78
```

### UDP test at 20Mbit/s
```shell
sudo ./client.sh -t 20 -u -b 20M -c exp3_bottleneck_udp -P 192.168.1.92 192.168.1.78
```

### Stop Server
Press Ctrl+C

### Clean Proxy
```shell
sudo ./proxy.sh -m clean


sudo iptables -t nat -D PREROUTING -p tcp --dport 5201 -j DNAT --to-destination 192.168.1.78:5201
sudo iptables -D FORWARD -p tcp -d 192.168.1.78 --dport 5201 -j ACCEPT

# Verify cleanup
sudo tc qdisc show
```