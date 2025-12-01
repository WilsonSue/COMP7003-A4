#!/bin/bash
# client.sh - iperf3 client with optional proxy support
# Usage: ./client.sh [OPTIONS] SERVER_IP
#   -t TIME        Test duration in seconds (default: 20)
#   -p PORT        Server port (default: 5201)
#   -u             Use UDP instead of TCP
#   -b BITRATE     UDP bitrate (default: 5M)
#   -c CAPTURE     Capture file prefix (default: client_capture)
#   -P PROXY       Proxy IP (optional, connects directly if not specified)
#   -h             Show help

set -e

# Default values
DURATION=20
PORT=5201
PROTOCOL="tcp"
BITRATE="5M"
CAPTURE_PREFIX="client_capture"
INTERFACE=""
PROXY=""

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper function
show_help() {
    echo "Usage: $0 [OPTIONS] SERVER_IP"
    echo ""
    echo "Options:"
    echo "  -t TIME        Test duration in seconds (default: 20)"
    echo "  -p PORT        Server port (default: 5201)"
    echo "  -u             Use UDP instead of TCP"
    echo "  -b BITRATE     UDP bitrate, e.g., 5M, 10M (default: 5M)"
    echo "  -c CAPTURE     Capture file prefix (default: client_capture)"
    echo "  -i INTERFACE   Network interface for capture (auto-detect if not specified)"
    echo "  -P PROXY       Proxy IP address (optional, direct connection if not specified)"
    echo "  -h             Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 192.168.1.100                              # Direct TCP connection"
    echo "  $0 -u -b 10M 192.168.1.100                    # Direct UDP at 10 Mbit/s"
    echo "  $0 -P 192.168.1.50 192.168.1.100              # TCP through proxy"
    echo "  $0 -u -t 30 -P 192.168.1.50 192.168.1.100     # UDP through proxy, 30 seconds"
    echo ""
    echo "The client works with or without a proxy. If -P is specified, traffic routes"
    echo "through the proxy; otherwise, it connects directly to the server."
}

# Parse arguments
while getopts "t:p:ub:c:i:P:h" opt; do
    case $opt in
        t) DURATION="$OPTARG" ;;
        p) PORT="$OPTARG" ;;
        u) PROTOCOL="udp" ;;
        b) BITRATE="$OPTARG" ;;
        c) CAPTURE_PREFIX="$OPTARG" ;;
        i) INTERFACE="$OPTARG" ;;
        P) PROXY="$OPTARG" ;;
        h) show_help; exit 0 ;;
        *) show_help; exit 1 ;;
    esac
done

shift $((OPTIND-1))

# Check if server IP is provided
if [ -z "$1" ]; then
    echo -e "${RED}Error: SERVER_IP is required${NC}"
    show_help
    exit 1
fi

SERVER_IP="$1"

# Auto-detect interface if not specified
if [ -z "$INTERFACE" ]; then
    echo -e "${YELLOW}Auto-detecting network interface...${NC}"
    INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n 1)
    if [ -z "$INTERFACE" ]; then
        echo -e "${RED}Error: Could not auto-detect interface. Use -i to specify.${NC}"
        exit 1
    fi
fi

# Determine target IP for iperf3 connection
if [ -n "$PROXY" ]; then
    TARGET_IP="$PROXY"
    ROUTING_MODE="via proxy $PROXY"
else
    TARGET_IP="$SERVER_IP"
    ROUTING_MODE="direct connection"
fi

echo -e "${GREEN}=== iperf3 Client Configuration ===${NC}"
echo "Protocol: $(echo $PROTOCOL | tr '[:lower:]' '[:upper:]')"
echo "Server IP: $SERVER_IP"
echo "Routing: $ROUTING_MODE"
echo "Port: $PORT"
echo "Duration: ${DURATION}s"
if [ "$PROTOCOL" = "udp" ]; then
    echo "Bitrate: $BITRATE"
fi
echo "Interface: $INTERFACE"
echo "Capture prefix: $CAPTURE_PREFIX"
echo ""

# Check if iperf3 is installed
if ! command -v iperf3 &> /dev/null; then
    echo -e "${RED}Error: iperf3 is not installed${NC}"
    echo "Install with: sudo apt-get install iperf3"
    exit 1
fi

# Check if tcpdump is installed
if ! command -v tcpdump &> /dev/null; then
    echo -e "${RED}Error: tcpdump is not installed${NC}"
    echo "Install with: sudo apt-get install tcpdump"
    exit 1
fi

# Check if running as root for tcpdump
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}Warning: Not running as root. tcpdump may require sudo.${NC}"
    SUDO="sudo"
else
    SUDO=""
fi

# Verify connectivity
echo -e "${YELLOW}Testing connectivity to $TARGET_IP...${NC}"
if ping -c 2 -W 2 "$TARGET_IP" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Host reachable${NC}"
else
    echo -e "${RED}Warning: Host $TARGET_IP not responding to ping${NC}"
    echo -e "${YELLOW}Continuing anyway (ping may be blocked)...${NC}"
fi
echo ""

# Cleanup function
cleanup() {
    echo -e "\n${YELLOW}Cleaning up...${NC}"
    # Kill the specific tcpdump process we started
    if [ ! -z "$TCPDUMP_PID" ] && ps -p $TCPDUMP_PID > /dev/null 2>&1; then
        echo "Stopping tcpdump (PID: $TCPDUMP_PID)..."
        $SUDO kill -SIGTERM $TCPDUMP_PID 2>/dev/null || true
        sleep 2
    fi
    echo -e "${GREEN}Client stopped.${NC}"
    exit 0
}

trap cleanup SIGINT SIGTERM

# Start tcpdump in background
PROTOCOL_NAME=$(echo $PROTOCOL | tr '[:lower:]' '[:upper:]')
PCAP_FILE="${CAPTURE_PREFIX}_${PROTOCOL_NAME}_$(date +%Y%m%d_%H%M%S).pcap"
echo -e "${GREEN}Starting packet capture: $PCAP_FILE${NC}"
$SUDO tcpdump -i "$INTERFACE" -w "$PCAP_FILE" host "$TARGET_IP" and port "$PORT" &
TCPDUMP_PID=$!
sleep 2

# Verify tcpdump is running
if ! ps -p $TCPDUMP_PID > /dev/null; then
    echo -e "${RED}Error: tcpdump failed to start${NC}"
    exit 1
fi

echo -e "${GREEN}Packet capture started (PID: $TCPDUMP_PID)${NC}"
echo ""

# Build iperf3 command
IPERF_CMD="iperf3 -c $TARGET_IP -p $PORT -t $DURATION"

if [ "$PROTOCOL" = "udp" ]; then
    IPERF_CMD="$IPERF_CMD -u -b $BITRATE"
fi

# If using proxy, add bind option to route through proxy
if [ -n "$PROXY" ]; then
    echo -e "${BLUE}Note: Ensure routing is configured to forward traffic through proxy${NC}"
    echo -e "${BLUE}You may need static routes or iptables DNAT rules${NC}"
    echo ""
fi

# Run iperf3 test
echo -e "${GREEN}Starting iperf3 $PROTOCOL_NAME test...${NC}"
echo -e "${YELLOW}Command: $IPERF_CMD${NC}"
echo ""

$IPERF_CMD

# Test completed
echo ""
echo -e "${GREEN}=== Test Complete ===${NC}"
echo "Capture file: $PCAP_FILE"
echo ""
echo -e "${YELLOW}Analyze with Wireshark:${NC}"
echo "  wireshark $PCAP_FILE"
echo ""
echo -e "${YELLOW}Or use tshark for command-line analysis:${NC}"
if [ "$PROTOCOL" = "tcp" ]; then
    echo "  tshark -r $PCAP_FILE -q -z io,stat,1"
    echo "  tshark -r $PCAP_FILE -Y 'tcp.analysis.retransmission'"
else
    echo "  tshark -r $PCAP_FILE -q -z io,stat,1"
    echo "  tshark -r $PCAP_FILE | wc -l  # Count packets"
fi

# Stop tcpdump gracefully
echo -e "${YELLOW}Stopping packet capture...${NC}"
if ps -p $TCPDUMP_PID > /dev/null 2>&1; then
    $SUDO kill -SIGTERM $TCPDUMP_PID 2>/dev/null || true
    sleep 2
else
    echo -e "${YELLOW}Warning: tcpdump process already stopped${NC}"
fi