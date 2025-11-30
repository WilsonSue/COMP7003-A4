# TCP vs UDP Transport Comparison Lab

Complete lab setup with modular scripts for comparing TCP and UDP behavior under various network conditions.

## 📁 Files Overview

| Script | Purpose | Runs On |
|--------|---------|---------|
| `server.sh` | iperf3 server with packet capture | Host B (Server) |
| `client.sh` | iperf3 client with packet capture | Host A (Client) |
| `proxy.sh` | Network impairment controller | Proxy Host (optional) |
| `run_experiments.sh` | Automated experiment runner | Host A (Client) |

## 🏗️ Architecture

### Direct Connection (No Proxy)
```
Host A (Client) ←→ Host B (Server)
   client.sh        server.sh
```

### With Proxy (Recommended)
```
Host A (Client) ←→ Proxy ←→ Host B (Server)
   client.sh      proxy.sh    server.sh
```

The proxy allows controlled network impairments (delay, loss, bandwidth limits) while keeping client and server code simple.

## 🚀 Quick Start

### 1. Setup Server (Host B)
```bash
chmod +x server.sh
./server.sh
```

Server will:
- Start iperf3 on port 5201
- Begin packet capture automatically
- Run until you press Ctrl+C

### 2. Run Client Tests (Host A)

**Direct connection (no proxy):**
```bash
chmod +x client.sh

# TCP test
./client.sh 192.168.1.100

# UDP test at 10 Mbit/s
./client.sh -u -b 10M 192.168.1.100
```

**Through proxy:**
```bash
# TCP through proxy
./client.sh -P 192.168.1.50 192.168.1.100

# UDP through proxy
./client.sh -u -b 10M -P 192.168.1.50 192.168.1.100
```

### 3. Configure Proxy (If Using)

**On the proxy host:**
```bash
chmod +x proxy.sh

# Clean path (baseline)
sudo ./proxy.sh -m clean

# Add 1% packet loss
sudo ./proxy.sh -m loss -l 1

# Add 10 Mbit/s bottleneck
sudo ./proxy.sh -m bottleneck -r 10mbit

# Always clean up after testing!
sudo ./proxy.sh -m clean
```

### 4. Run Full Experiment Suite

**Automated runner (recommended):**
```bash
chmod +x run_experiments.sh

# Through proxy (recommended)
./run_experiments.sh -s 192.168.1.100 -P 192.168.1.50

# Direct connection
./run_experiments.sh -s 192.168.1.100

# Run specific experiment only
./run_experiments.sh -s 192.168.1.100 -P 192.168.1.50 -e 2
```

## 📊 Experiments

### Experiment 1: Baseline (Clean Path)
**Goal:** Establish baseline behavior without impairments

**What happens:**
- TCP: Shows slow start (exponential ramp), then congestion avoidance (linear growth)
- UDP: Immediate constant rate at configured bitrate

**Look for:**
- TCP cwnd growth in Wireshark time-sequence graphs
- UDP perfectly spaced packet intervals

---

### Experiment 2: Moderate Random Loss (1%)
**Goal:** Observe protocol reactions to packet loss

**What happens:**
- TCP: Detects loss via duplicate ACKs, retransmits, reduces cwnd (sawtooth pattern)
- UDP: Maintains send rate, receiver sees ~1% loss

**Look for:**
- TCP: ~30 duplicate ACKs per 1000 packets (3 per lost packet)
- TCP: Fast retransmissions and recovery
- UDP: Gaps in sequence numbers at receiver

**Quick math:**
```
1% loss on 1000 packets = ~10 lost packets
Each lost packet triggers 3 duplicate ACKs
Expected duplicate ACKs: ~30
```

---

### Experiment 3: Bottlenecked Link
**Goal:** Show TCP adaptation vs UDP overload

**Configuration:**
- Link capacity: 10 Mbit/s
- TCP test: Default (will adapt)
- UDP test: 20 Mbit/s (2x capacity)

**What happens:**
- TCP: Converges to ~9-10 Mbit/s through self-throttling
- UDP: Sends at 20 Mbit/s, causes ~50% loss and high jitter

**Look for:**
- TCP: Throughput approaching bottleneck limit
- UDP: Send rate remains constant, massive receiver loss

---

## 🔧 Detailed Script Usage

### server.sh

```bash
./server.sh [OPTIONS]

Options:
  -p PORT        Server port (default: 5201)
  -c CAPTURE     Capture file prefix (default: server_capture)
  -i INTERFACE   Network interface (auto-detect if not specified)
  -h             Show help

Examples:
  ./server.sh                    # Default settings
  ./server.sh -p 5201 -c test1   # Custom port and capture name
  ./server.sh -i ens33           # Specify interface
```

**What it does:**
- Starts iperf3 server
- Captures packets on specified interface
- Saves pcap file with timestamp
- Cleans up on Ctrl+C

---

### client.sh

```bash
./client.sh [OPTIONS] SERVER_IP

Options:
  -t TIME        Test duration in seconds (default: 20)
  -p PORT        Server port (default: 5201)
  -u             Use UDP instead of TCP
  -b BITRATE     UDP bitrate, e.g., 5M, 10M (default: 5M)
  -c CAPTURE     Capture file prefix (default: client_capture)
  -i INTERFACE   Network interface (auto-detect if not specified)
  -P PROXY       Proxy IP address (optional)
  -h             Show help

Examples:
  ./client.sh 192.168.1.100                     # TCP, 20 seconds
  ./client.sh -u -b 10M 192.168.1.100           # UDP, 10 Mbit/s
  ./client.sh -t 30 -P 192.168.1.50 192.168.1.100  # 30s through proxy
```

**What it does:**
- Tests connectivity
- Starts packet capture
- Runs iperf3 test
- Saves pcap with protocol and timestamp
- Provides analysis commands

---

### proxy.sh

```bash
sudo ./proxy.sh [OPTIONS]

Options:
  -m MODE        Impairment mode: clean, loss, bottleneck (default: clean)
  -l LOSS        Loss percentage for loss mode (default: 1)
  -r RATE        Rate limit for bottleneck mode (default: 10mbit)
  -i INTERFACE   Interface to apply rules (auto-detect if not specified)
  -d             Dry run - show commands without executing
  -h             Show help

Examples:
  sudo ./proxy.sh -m clean                  # Remove all impairments
  sudo ./proxy.sh -m loss -l 1              # Add 1% loss
  sudo ./proxy.sh -m loss -l 5 -i eth0      # Add 5% loss on eth0
  sudo ./proxy.sh -m bottleneck -r 10mbit   # Limit to 10 Mbit/s
  sudo ./proxy.sh -d -m loss -l 2           # Dry run (preview only)
```

**What it does:**
- Enables IP forwarding
- Sets longer TCP timeout (proxy waits longer than clients)
- Applies tc/netem rules for impairments
- Shows current state and statistics

**⚠️ IMPORTANT:** Always run `sudo ./proxy.sh -m clean` after experiments!

---

### run_experiments.sh

```bash
./run_experiments.sh [OPTIONS]

Options:
  -s SERVER_IP   Server IP address (required)
  -P PROXY_IP    Proxy IP address (optional)
  -e EXPERIMENT  Run specific experiment: 1, 2, 3, or all (default: all)
  -h             Show help

Examples:
  ./run_experiments.sh -s 192.168.1.100                    # Direct, all experiments
  ./run_experiments.sh -s 192.168.1.100 -e 1               # Direct, baseline only
  ./run_experiments.sh -s 192.168.1.100 -P 192.168.1.50    # Via proxy, all experiments
```

**What it does:**
- Runs complete experiment suite automatically
- Configures proxy for each experiment
- Captures all data
- Creates organized results directory
- Generates summary and analysis guide

---

## 📈 Analysis Guide

### Wireshark Analysis

**TCP Analysis:**
1. Open capture: `wireshark results_*/exp1_baseline_tcp_*.pcap`
2. View time-sequence graph:
    - Statistics → TCP Stream Graphs → Time-Sequence Graph (Stevens)
    - Shows bytes in flight, reveals slow start and AIMD
3. Filter for issues:
    - Retransmissions: `tcp.analysis.retransmission`
    - Duplicate ACKs: `tcp.analysis.duplicate_ack`
    - Fast retransmit: `tcp.analysis.fast_retransmission`
4. Window scaling:
    - Statistics → TCP Stream Graphs → Window Scaling
    - Shows cwnd vs rwnd evolution

**UDP Analysis:**
1. IO Graph:
    - Statistics → IO Graph
    - Shows constant rate vs time
2. Calculate loss:
    - Compare sent (client) vs received (server) packet counts
    - Loss % = (sent - received) / sent × 100
3. Jitter:
    - Statistics → IO Graph → Interval=10ms
    - Look for variance in packet arrival times

### Command-Line Analysis

**Count packets:**
```bash
tshark -r capture.pcap | wc -l
```

**Find retransmissions:**
```bash
tshark -r capture.pcap -Y 'tcp.analysis.retransmission'
```

**Count duplicate ACKs:**
```bash
tshark -r capture.pcap -Y 'tcp.analysis.duplicate_ack' | wc -l
```

**IO Statistics:**
```bash
tshark -r capture.pcap -q -z io,stat,1
```

**Extract sequence numbers (if in UDP payload):**
```bash
tshark -r capture.pcap -T fields -e frame.number -e udp.length
```

---

## 🔍 Expected Results Summary

| Experiment | TCP Behavior | UDP Behavior |
|------------|--------------|--------------|
| **Baseline** | Slow start → congestion avoidance | Immediate constant rate |
| **1% Loss** | Retransmits, cwnd drops, ~5-10% ↓ throughput | No adaptation, visible 1% loss |
| **10M bottleneck (20M UDP)** | Converges to ~9-10 Mbit/s | Maintains 20M send, ~50% loss |

### Key Insights

1. **TCP is self-regulating** but conservative
    - AIMD causes sawtooth throughput pattern
    - May underutilize available bandwidth
    - Guarantees reliability and ordering

2. **UDP preserves timing** but requires app control
    - No built-in congestion control
    - Application must manage rate
    - Can be unfair to TCP flows

3. **Head-of-line blocking** in TCP
    - Lost packets block later data
    - Adds latency during recovery
    - Not an issue for UDP

4. **Proxy timeout configuration**
    - Proxy timeout > client timeout
    - Allows observation of retry behavior
    - Prevents premature connection drops

---

## 🛠️ Troubleshooting

### No traffic captured
```bash
# Check interface name
ip a

# Verify iperf3 is listening
netstat -tulpn | grep 5201

# Test connectivity
ping SERVER_IP
```

### tc rules not applying
```bash
# Check current rules
sudo tc qdisc show

# Verify correct interface
ip route

# See if packets are hitting qdisc
sudo tc -s qdisc show
```

### Permission errors
```bash
# Server and client may need sudo for tcpdump
sudo ./server.sh
sudo ./client.sh ...

# Proxy MUST run as root
sudo ./proxy.sh ...
```

### Proxy not forwarding traffic
```bash
# Verify IP forwarding
cat /proc/sys/net/ipv4/ip_forward
# Should output: 1

# Enable if needed
sudo sysctl -w net.ipv4.ip_forward=1

# Check iptables
sudo iptables -L -n -v
```

---

## 📝 Important Notes

### Timeout Configuration
The proxy should have a **longer timeout** than client/server:
- **Proxy:** `tcp_retries2=15` (~13-30 minutes)
- **Client/Server:** Default `tcp_retries2=5` (~3-6 minutes)

This ensures the proxy doesn't drop connections before endpoints retry, allowing proper observation of TCP retry behavior.

### Cleanup Checklist
After experiments, always:
1. ✅ Clean proxy: `sudo ./proxy.sh -m clean`
2. ✅ Stop server: Ctrl+C on server.sh
3. ✅ Kill tcpdump: `sudo pkill tcpdump`
4. ✅ Verify tc rules removed: `sudo tc qdisc show`

### Common Pitfalls
- **Forgetting to clean tc rules:** Will affect all traffic!
- **Wrong interface:** Use `-i` to specify or check auto-detection
- **Insufficient test duration:** Use at least 20s for meaningful results
- **Not waiting between tests:** Use 5s gap to let state clear

---

## 🎓 Learning Objectives

By completing this lab, you should understand:

1. **TCP Mechanisms:**
    - Slow start and congestion avoidance
    - AIMD (Additive Increase, Multiplicative Decrease)
    - Fast retransmit and fast recovery
    - Head-of-line blocking

2. **UDP Behavior:**
    - No congestion control
    - Constant send rate
    - Packet loss visibility
    - Timing preservation

3. **Protocol Trade-offs:**
    - Reliability vs latency
    - Self-regulation vs flexibility
    - Fairness considerations

4. **Network Impairments:**
    - Loss detection and recovery
    - Bandwidth adaptation
    - Queue management

---

## 📚 Additional Resources

**Wireshark Documentation:**
- https://www.wireshark.org/docs/

**iperf3 Manual:**
- https://iperf.fr/iperf-doc.php

**tc/netem Guide:**
- https://man7.org/linux/man-pages/man8/tc-netem.8.html

**TCP Congestion Control:**
- RFC 5681 (TCP Congestion Control)
- RFC 6298 (Computing TCP's RTO)

---

## 📄 License

These scripts are provided for educational purposes. Modify as needed for your environment.

**Remember:** Always clean up tc rules after experiments to avoid impacting other users!