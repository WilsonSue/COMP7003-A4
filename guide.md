#!/bin/bash
# server.sh - iperf3 server with optional proxy support
# Usage: ./server.sh [OPTIONS]
#   -p PORT        Server port (default: 5201)
#   -c CAPTURE     Capture file prefix (default: server_capture)
#   -h             Show help

set -e

# Default values
PORT=5201
CAPTURE_PREFIX="server_capture"
INTERFACE=""

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Help function
show_help() {
echo "Usage: $0 [OPTIONS]"
echo ""
echo "Options:"
echo "  -p PORT        Server port (default: 5201)"
echo "  -c CAPTURE     Capture file prefix (default: server_capture)"
echo "  -i INTERFACE   Network interface for capture (auto-detect if not specified)"
echo "  -h             Show this help message"
echo ""
echo "Examples:"
echo "  $0                           # Start with defaults"
echo "  $0 -p 5201 -c my_test        # Custom port and capture name"
echo "  $0 -i eth0                   # Specify interface"
echo ""
echo "The server works with or without a proxy in the path."
echo "Press Ctrl+C to stop server and captures."
}

# Parse arguments
while getopts "p:c:i:h" opt; do
case $opt in
p) PORT="$OPTARG" ;;
c) CAPTURE_PREFIX="$OPTARG" ;;
i) INTERFACE="$OPTARG" ;;
h) show_help; exit 0 ;;
*) show_help; exit 1 ;;
esac
done

# Auto-detect interface if not specified
if [ -z "$INTERFACE" ]; then
echo -e "${YELLOW}Auto-detecting network interface...${NC}"
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n 1)
if [ -z "$INTERFACE" ]; then
echo -e "${RED}Error: Could not auto-detect interface. Use -i to specify.${NC}"
exit 1
fi
fi

echo -e "${GREEN}=== iperf3 Server Configuration ===${NC}"
echo "Port: $PORT"
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

# Kill any existing iperf3 servers on this port
echo -e "${YELLOW}Checking for existing iperf3 processes...${NC}"
pkill -f "iperf3 -s.*$PORT" 2>/dev/null || true
sleep 1

# Cleanup function
cleanup() {
echo -e "\n${YELLOW}Shutting down...${NC}"
pkill -f "iperf3 -s.*$PORT" 2>/dev/null || true
$SUDO pkill -f "tcpdump.*$PORT" 2>/dev/null || true
echo -e "${GREEN}Server stopped.${NC}"
exit 0
}

trap cleanup SIGINT SIGTERM

# Start tcpdump in background
PCAP_FILE="${CAPTURE_PREFIX}_$(date +%Y%m%d_%H%M%S).pcap"
echo -e "${GREEN}Starting packet capture: $PCAP_FILE${NC}"
$SUDO tcpdump -i "$INTERFACE" -w "$PCAP_FILE" port "$PORT" &
TCPDUMP_PID=$!
sleep 2

# Verify tcpdump is running
if ! ps -p $TCPDUMP_PID > /dev/null; then
echo -e "${RED}Error: tcpdump failed to start${NC}"
exit 1
fi

echo -e "${GREEN}Packet capture started (PID: $TCPDUMP_PID)${NC}"
echo ""

# Start iperf3 server
echo -e "${GREEN}Starting iperf3 server on port $PORT...${NC}"
echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
echo ""

iperf3 -s -p "$PORT"

# This line is reached when iperf3 exits
cleanup