#!/bin/bash
# proxy.sh - Network proxy with configurable impairments
# Usage: ./proxy.sh [OPTIONS]
#   -m MODE        Impairment mode: clean, loss, bottleneck (default: clean)
#   -l LOSS        Loss percentage for loss mode (default: 1)
#   -r RATE        Rate limit for bottleneck mode (default: 10mbit)
#   -i INTERFACE   Interface to apply rules (default: auto-detect)
#   -d             Dry run - show commands without executing
#   -h             Show help

set -e

# Default values
MODE="clean"
LOSS_PERCENT="1"
RATE_LIMIT="10mbit"
INTERFACE=""
DRY_RUN=false

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Help function
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -m MODE        Impairment mode: clean, loss, bottleneck (default: clean)"
    echo "  -l LOSS        Loss percentage for loss mode, e.g., 1, 5 (default: 1)"
    echo "  -r RATE        Rate limit for bottleneck mode, e.g., 10mbit, 5mbit (default: 10mbit)"
    echo "  -i INTERFACE   Interface to apply rules (auto-detect if not specified)"
    echo "  -d             Dry run - show commands without executing"
    echo "  -h             Show this help message"
    echo ""
    echo "Modes:"
    echo "  clean          Remove all impairments (baseline)"
    echo "  loss           Add random packet loss"
    echo "  bottleneck     Add bandwidth limit"
    echo ""
    echo "Examples:"
    echo "  $0 -m clean                        # Remove all impairments"
    echo "  $0 -m loss -l 1                    # Add 1% packet loss"
    echo "  $0 -m loss -l 5 -i eth0            # Add 5% loss on eth0"
    echo "  $0 -m bottleneck -r 10mbit         # Limit to 10 Mbit/s"
    echo "  $0 -m bottleneck -r 5mbit -i eth1  # Limit eth1 to 5 Mbit/s"
    echo "  $0 -d -m loss -l 2                 # Dry run to preview commands"
    echo ""
    echo "IMPORTANT:"
    echo "  - Run with sudo or as root"
    echo "  - Always run 'clean' mode after experiments to remove rules"
    echo "  - Proxy timeout should be longer than client/server timeouts"
}

# Parse arguments
while getopts "m:l:r:i:dh" opt; do
    case $opt in
        m) MODE="$OPTARG" ;;
        l) LOSS_PERCENT="$OPTARG" ;;
        r) RATE_LIMIT="$OPTARG" ;;
        i) INTERFACE="$OPTARG" ;;
        d) DRY_RUN=true ;;
        h) show_help; exit 0 ;;
        *) show_help; exit 1 ;;
    esac
done

# Validate mode
if [[ ! "$MODE" =~ ^(clean|loss|bottleneck)$ ]]; then
    echo -e "${RED}Error: Invalid mode '$MODE'${NC}"
    echo "Valid modes: clean, loss, bottleneck"
    exit 1
fi

# Check if running as root
if [ "$EUID" -ne 0 ] && [ "$DRY_RUN" = false ]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    echo "Run with: sudo $0 $@"
    exit 1
fi

# Auto-detect interface if not specified
if [ -z "$INTERFACE" ]; then
    echo -e "${YELLOW}Auto-detecting network interface...${NC}"
    INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n 1)
    if [ -z "$INTERFACE" ]; then
        echo -e "${RED}Error: Could not auto-detect interface. Use -i to specify.${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}=== Proxy Configuration ===${NC}"
echo "Mode: $MODE"
echo "Interface: $INTERFACE"
if [ "$MODE" = "loss" ]; then
    echo "Loss percentage: ${LOSS_PERCENT}%"
elif [ "$MODE" = "bottleneck" ]; then
    echo "Rate limit: $RATE_LIMIT"
fi
if [ "$DRY_RUN" = true ]; then
    echo -e "${CYAN}DRY RUN MODE - No changes will be made${NC}"
fi
echo ""

# Execute or print command
run_cmd() {
    local cmd="$1"
    if [ "$DRY_RUN" = true ]; then
        echo -e "${CYAN}[DRY RUN] $cmd${NC}"
    else
        echo -e "${YELLOW}Executing: $cmd${NC}"
        eval "$cmd" || true
    fi
}

# Configure system settings for proxy operation
configure_proxy() {
    echo -e "${BLUE}=== Configuring Proxy System Settings ===${NC}"

    # Enable IP forwarding
    run_cmd "sysctl -w net.ipv4.ip_forward=1"

    # Set longer TCP retry timeout (proxy should wait longer than clients)
    echo -e "${YELLOW}Setting proxy TCP timeout longer than client/server...${NC}"
    run_cmd "sysctl -w net.ipv4.tcp_retries2=15"

    echo -e "${GREEN}✓ Proxy system settings configured${NC}"
    echo ""
}

# Clean all tc rules
clean_rules() {
    echo -e "${BLUE}=== Cleaning tc Rules ===${NC}"
    run_cmd "tc qdisc del dev $INTERFACE root 2>/dev/null"

    echo ""
    echo -e "${GREEN}Current state:${NC}"
    if [ "$DRY_RUN" = false ]; then
        tc qdisc show dev "$INTERFACE"
    else
        echo -e "${CYAN}[Would show: tc qdisc show dev $INTERFACE]${NC}"
    fi
}

# Apply loss impairment
apply_loss() {
    echo -e "${BLUE}=== Applying ${LOSS_PERCENT}% Packet Loss ===${NC}"

    # Clean first
    run_cmd "tc qdisc del dev $INTERFACE root 2>/dev/null"

    # Add netem with loss
    run_cmd "tc qdisc add dev $INTERFACE root netem loss ${LOSS_PERCENT}%"

    echo ""
    echo -e "${GREEN}Current state:${NC}"
    if [ "$DRY_RUN" = false ]; then
        tc qdisc show dev "$INTERFACE"
        tc -s qdisc show dev "$INTERFACE"
    else
        echo -e "${CYAN}[Would show: tc qdisc/stats]${NC}"
    fi

    echo ""
    echo -e "${YELLOW}Expected behavior:${NC}"
    echo "  - ${LOSS_PERCENT}% of packets will be randomly dropped"
    echo "  - TCP will show retransmissions and cwnd reductions"
    echo "  - UDP will maintain send rate but show loss at receiver"
}

# Apply bottleneck impairment
apply_bottleneck() {
    echo -e "${BLUE}=== Applying Bandwidth Limit: $RATE_LIMIT ===${NC}"

    # Clean first
    run_cmd "tc qdisc del dev $INTERFACE root 2>/dev/null"

    # Add TBF (Token Bucket Filter)
    # burst = rate / Hz, with min 1600 bytes
    # For 10mbit, burst = 10000000 / 250 / 8 = 5000 bytes, use 32kbit (4096 bytes)
    run_cmd "tc qdisc add dev $INTERFACE root tbf rate $RATE_LIMIT burst 32kbit latency 400ms"

    echo ""
    echo -e "${GREEN}Current state:${NC}"
    if [ "$DRY_RUN" = false ]; then
        tc qdisc show dev "$INTERFACE"
        tc -s qdisc show dev "$INTERFACE"
    else
        echo -e "${CYAN}[Would show: tc qdisc/stats]${NC}"
    fi

    echo ""
    echo -e "${YELLOW}Expected behavior:${NC}"
    echo "  - Traffic limited to $RATE_LIMIT"
    echo "  - TCP will converge near this rate"
    echo "  - UDP above this rate will experience significant loss"
}

# Main execution
main() {
    case "$MODE" in
        clean)
            clean_rules
            echo ""
            echo -e "${GREEN}All impairments removed. Path is clean.${NC}"
            ;;
        loss)
            configure_proxy
            apply_loss
            echo ""
            echo -e "${GREEN}Loss impairment applied.${NC}"
            echo -e "${YELLOW}Remember to run '$0 -m clean' after testing!${NC}"
            ;;
        bottleneck)
            configure_proxy
            apply_bottleneck
            echo ""
            echo -e "${GREEN}Bottleneck applied.${NC}"
            echo -e "${YELLOW}Remember to run '$0 -m clean' after testing!${NC}"
            ;;
    esac
}

# Verification function
verify_setup() {
    if [ "$DRY_RUN" = false ] && [ "$MODE" != "clean" ]; then
        echo ""
        echo -e "${BLUE}=== Verifying Setup ===${NC}"

        # Check IP forwarding
        if [ "$(cat /proc/sys/net/ipv4/ip_forward)" = "1" ]; then
            echo -e "${GREEN}✓ IP forwarding enabled${NC}"
        else
            echo -e "${RED}✗ IP forwarding disabled${NC}"
        fi

        # Check tc rules
        if tc qdisc show dev "$INTERFACE" | grep -q "netem\|tbf"; then
            echo -e "${GREEN}✓ Traffic control rules active${NC}"
        else
            echo -e "${YELLOW}! No traffic control rules found${NC}"
        fi

        # Show statistics
        echo ""
        echo -e "${BLUE}Statistics:${NC}"
        tc -s qdisc show dev "$INTERFACE"
    fi
}

# Run main function
main

# Verify after applying
verify_setup

echo ""
echo -e "${GREEN}Done!${NC}"

if [ "$MODE" != "clean" ]; then
    echo ""
    echo -e "${RED}REMINDER: Run the following when done testing:${NC}"
    echo -e "${YELLOW}  sudo $0 -m clean${NC}"
fi