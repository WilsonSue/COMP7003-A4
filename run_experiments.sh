#!/bin/bash
# run_experiments.sh - Automated experiment runner
# Usage: ./run_experiments.sh [OPTIONS]
#   -s SERVER_IP   Server IP address (required)
#   -P PROXY_IP    Proxy IP address (optional, for proxy mode)
#   -e EXPERIMENT  Run specific experiment: 1, 2, 3, or all (default: all)
#   -h             Show help

set -e

# Default values
SERVER_IP=""
PROXY_IP=""
EXPERIMENT="all"
RESULTS_DIR="results_$(date +%Y%m%d_%H%M%S)"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Help function
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -s SERVER_IP   Server IP address (required)"
    echo "  -P PROXY_IP    Proxy IP address (optional)"
    echo "  -e EXPERIMENT  Run specific experiment: 1, 2, 3, or all (default: all)"
    echo "  -h             Show this help message"
    echo ""
    echo "Experiments:"
    echo "  1 - Baseline (Clean Path)"
    echo "  2 - Moderate Random Loss (1%)"
    echo "  3 - Bottlenecked Link (10 Mbit/s with 20 Mbit/s UDP)"
    echo ""
    echo "Examples:"
    echo "  $0 -s 192.168.1.100                           # Direct connection, all experiments"
    echo "  $0 -s 192.168.1.100 -e 1                      # Direct connection, baseline only"
    echo "  $0 -s 192.168.1.100 -P 192.168.1.50           # Through proxy, all experiments"
    echo "  $0 -s 192.168.1.100 -P 192.168.1.50 -e 2      # Through proxy, loss experiment"
    echo ""
    echo "Prerequisites:"
    echo "  - Server must be running: ./server.sh"
    echo "  - If using proxy, it should be accessible and forwarding enabled"
    echo "  - All scripts (client.sh, proxy.sh) must be in current directory or PATH"
}

# Parse arguments
while getopts "s:P:e:h" opt; do
    case $opt in
        s) SERVER_IP="$OPTARG" ;;
        P) PROXY_IP="$OPTARG" ;;
        e) EXPERIMENT="$OPTARG" ;;
        h) show_help; exit 0 ;;
        *) show_help; exit 1 ;;
    esac
done

# Check required arguments
if [ -z "$SERVER_IP" ]; then
    echo -e "${RED}Error: Server IP is required${NC}"
    show_help
    exit 1
fi

# Validate experiment number
if [[ ! "$EXPERIMENT" =~ ^(1|2|3|all)$ ]]; then
    echo -e "${RED}Error: Invalid experiment '$EXPERIMENT'${NC}"
    echo "Valid values: 1, 2, 3, all"
    exit 1
fi

# Determine connection mode
if [ -n "$PROXY_IP" ]; then
    CONNECTION_MODE="proxy"
    PROXY_OPTION="-P $PROXY_IP"
else
    CONNECTION_MODE="direct"
    PROXY_OPTION=""
fi

echo -e "${MAGENTA}╔════════════════════════════════════════════╗${NC}"
echo -e "${MAGENTA}║  TCP vs UDP Transport Comparison Lab      ║${NC}"
echo -e "${MAGENTA}╚════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Configuration:${NC}"
echo "  Server IP: $SERVER_IP"
echo "  Connection: $CONNECTION_MODE"
if [ "$CONNECTION_MODE" = "proxy" ]; then
    echo "  Proxy IP: $PROXY_IP"
fi
echo "  Experiment(s): $EXPERIMENT"
echo "  Results directory: $RESULTS_DIR"
echo ""

# Create results directory
mkdir -p "$RESULTS_DIR"
echo -e "${YELLOW}Created results directory: $RESULTS_DIR${NC}"
echo ""

# Wait function with countdown
wait_between_tests() {
    local seconds=5
    echo ""
    echo -e "${YELLOW}Waiting ${seconds} seconds before next test...${NC}"
    for i in $(seq $seconds -1 1); do
        echo -ne "${YELLOW}  $i...${NC}\r"
        sleep 1
    done
    echo -e "${GREEN}  Ready!${NC}    "
    echo ""
}

# Log function
log_test() {
    local message="$1"
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo -e "${BLUE}$message${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo "$message" >> "$RESULTS_DIR/test_log.txt"
}

# Experiment 1: Baseline (Clean Path)
experiment_1() {
    log_test "EXPERIMENT 1: BASELINE (Clean Path)"
    echo ""

    # Clean proxy if using one
    if [ "$CONNECTION_MODE" = "proxy" ]; then
        echo -e "${YELLOW}Configuring proxy for clean path...${NC}"
        ssh root@"$PROXY_IP" "bash -s" < proxy.sh -m clean || {
            echo -e "${RED}Failed to configure proxy. Ensure proxy.sh is available on proxy host.${NC}"
            echo -e "${YELLOW}Run manually: scp proxy.sh root@$PROXY_IP:/tmp/ && ssh root@$PROXY_IP /tmp/proxy.sh -m clean${NC}"
            return 1
        }
        echo ""
    fi

    # TCP Test
    echo -e "${CYAN}Running TCP baseline test (20 seconds)...${NC}"
    ./client.sh -t 20 -c "$RESULTS_DIR/exp1_baseline_tcp" $PROXY_OPTION "$SERVER_IP"

    wait_between_tests

    # UDP Test
    echo -e "${CYAN}Running UDP baseline test (5 Mbit/s, 20 seconds)...${NC}"
    ./client.sh -t 20 -u -b 5M -c "$RESULTS_DIR/exp1_baseline_udp" $PROXY_OPTION "$SERVER_IP"

    echo ""
    echo -e "${GREEN}✓ Experiment 1 Complete${NC}"
    echo -e "${YELLOW}Expected observations:${NC}"
    echo "  - TCP: Exponential ramp-up (slow start), then linear growth"
    echo "  - UDP: Immediate constant rate at 5 Mbit/s"
    echo ""
}

# Experiment 2: Moderate Random Loss (1%)
experiment_2() {
    log_test "EXPERIMENT 2: MODERATE RANDOM LOSS (1%)"
    echo ""

    # Configure proxy with loss
    if [ "$CONNECTION_MODE" = "proxy" ]; then
        echo -e "${YELLOW}Configuring proxy for 1% packet loss...${NC}"
        ssh root@"$PROXY_IP" "bash -s" < proxy.sh -m loss -l 1 || {
            echo -e "${RED}Failed to configure proxy.${NC}"
            return 1
        }
        echo ""
    else
        echo -e "${YELLOW}Note: For loss experiment without proxy, configure tc locally${NC}"
        echo -e "${YELLOW}This would require modifying the local interface.${NC}"
        echo -e "${RED}Skipping - proxy recommended for this experiment${NC}"
        return 1
    fi

    # TCP Test
    echo -e "${CYAN}Running TCP with 1% loss (20 seconds)...${NC}"
    ./client.sh -t 20 -c "$RESULTS_DIR/exp2_loss_tcp" $PROXY_OPTION "$SERVER_IP"

    wait_between_tests

    # UDP Test
    echo -e "${CYAN}Running UDP with 1% loss (5 Mbit/s, 20 seconds)...${NC}"
    ./client.sh -t 20 -u -b 5M -c "$RESULTS_DIR/exp2_loss_udp" $PROXY_OPTION "$SERVER_IP"

    echo ""
    echo -e "${GREEN}✓ Experiment 2 Complete${NC}"
    echo -e "${YELLOW}Expected observations:${NC}"
    echo "  - TCP: Duplicate ACKs, retransmissions, cwnd reductions (sawtooth)"
    echo "  - UDP: Constant send rate, ~1% loss at receiver"
    echo ""
    echo -e "${YELLOW}Quick check - Expected duplicate ACKs:${NC}"
    echo "  With 1% loss on 1000 packets:"
    echo "  - ~10 lost packets"
    echo "  - Each triggers 3 duplicate ACKs (fast retransmit)"
    echo "  - Total: ~30 duplicate ACKs"
    echo ""
}

# Experiment 3: Bottlenecked Link
experiment_3() {
    log_test "EXPERIMENT 3: BOTTLENECKED LINK (10 Mbit/s limit)"
    echo ""

    # Configure proxy with bottleneck
    if [ "$CONNECTION_MODE" = "proxy" ]; then
        echo -e "${YELLOW}Configuring proxy with 10 Mbit/s bottleneck...${NC}"
        ssh root@"$PROXY_IP" "bash -s" < proxy.sh -m bottleneck -r 10mbit || {
            echo -e "${RED}Failed to configure proxy.${NC}"
            return 1
        }
        echo ""
    else
        echo -e "${YELLOW}Note: For bottleneck experiment without proxy, configure tc locally${NC}"
        echo -e "${RED}Skipping - proxy recommended for this experiment${NC}"
        return 1
    fi

    # TCP Test
    echo -e "${CYAN}Running TCP on 10 Mbit/s link (20 seconds)...${NC}"
    ./client.sh -t 20 -c "$RESULTS_DIR/exp3_bottleneck_tcp" $PROXY_OPTION "$SERVER_IP"

    wait_between_tests

    # UDP Test - Overload at 20 Mbit/s
    echo -e "${CYAN}Running UDP at 20 Mbit/s on 10 Mbit/s link (20 seconds)...${NC}"
    echo -e "${YELLOW}Note: UDP will send at 2x the link capacity${NC}"
    ./client.sh -t 20 -u -b 20M -c "$RESULTS_DIR/exp3_bottleneck_udp" $PROXY_OPTION "$SERVER_IP"

    echo ""
    echo -e "${GREEN}✓ Experiment 3 Complete${NC}"
    echo -e "${YELLOW}Expected observations:${NC}"
    echo "  - TCP: Converges to ~9-10 Mbit/s, self-throttles"
    echo "  - UDP: Sends at 20 Mbit/s, ~50% loss at receiver"
    echo ""
}

# Cleanup function
cleanup_proxy() {
    if [ "$CONNECTION_MODE" = "proxy" ]; then
        echo ""
        echo -e "${YELLOW}Cleaning up proxy configuration...${NC}"
        ssh root@"$PROXY_IP" "bash -s" < proxy.sh -m clean || {
            echo -e "${RED}Warning: Failed to clean proxy. Clean manually:${NC}"
            echo -e "${YELLOW}  ssh root@$PROXY_IP 'tc qdisc del dev eth0 root'${NC}"
        }
    fi
}

# Register cleanup on exit
trap cleanup_proxy EXIT

# Main execution
main() {
    case "$EXPERIMENT" in
        1)
            experiment_1
            ;;
        2)
            experiment_2
            ;;
        3)
            experiment_3
            ;;
        all)
            experiment_1
            wait_between_tests
            experiment_2
            wait_between_tests
            experiment_3
            ;;
    esac

    # Generate summary
    echo ""
    echo -e "${MAGENTA}╔════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║  All Experiments Complete!                ║${NC}"
    echo -e "${MAGENTA}╚════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}Results saved in: $RESULTS_DIR${NC}"
    echo ""
    echo -e "${YELLOW}Analysis Steps:${NC}"
    echo "1. Open captures in Wireshark:"
    echo "   wireshark $RESULTS_DIR/*.pcap"
    echo ""
    echo "2. TCP Analysis:"
    echo "   - Statistics → TCP Stream Graphs → Time-Sequence (Stevens)"
    echo "   - Filter: tcp.analysis.retransmission"
    echo "   - Filter: tcp.analysis.duplicate_ack"
    echo ""
    echo "3. UDP Analysis:"
    echo "   - Statistics → IO Graph"
    echo "   - Compare sent vs received packet counts"
    echo ""
    echo "4. Command-line quick check:"
    echo "   tshark -r $RESULTS_DIR/exp2_loss_tcp_*.pcap -Y 'tcp.analysis.duplicate_ack' | wc -l"
    echo ""

    # Create summary file
    cat > "$RESULTS_DIR/README.txt" << EOF
TCP vs UDP Transport Comparison Lab Results
Generated: $(date)

Configuration:
- Server: $SERVER_IP
- Connection: $CONNECTION_MODE
$([ "$CONNECTION_MODE" = "proxy" ] && echo "- Proxy: $PROXY_IP")

Experiments Run: $EXPERIMENT

Files:
$(ls -1 "$RESULTS_DIR"/*.pcap 2>/dev/null | sed 's/^/- /')

Analysis Guide:
1. Experiment 1 (Baseline): Compare TCP slow start vs UDP constant rate
2. Experiment 2 (Loss): Observe TCP retransmission vs UDP loss tolerance
3. Experiment 3 (Bottleneck): Compare TCP convergence vs UDP overload

Key Metrics:
- TCP: Look for retransmissions, duplicate ACKs, cwnd behavior
- UDP: Calculate loss percentage, measure jitter
EOF

    echo -e "${GREEN}Summary saved: $RESULTS_DIR/README.txt${NC}"
}

# Run main
main