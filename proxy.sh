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
    echo "Error: Invalid mode '$MODE'"
    echo "Valid modes: clean, loss, bottleneck"
    exit 1
fi

# Check if running as root
if [ "$EUID" -ne 0 ] && [ "$DRY_RUN" = false ]; then
    echo "Error: This script must be run as root"
    echo "Run with: sudo $0 $@"
    exit 1
fi

# Auto-detect interface if not specified
if [ -z "$INTERFACE" ]; then
    echo "Auto-detecting network interface..."
    INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n 1)
    if [ -z "$INTERFACE" ]; then
        echo "Error: Could not auto-detect interface. Use -i to specify."
        exit 1
    fi
fi

echo "=== Proxy Configuration ==="
echo "Mode: $MODE"
echo "Interface: $INTERFACE"
if [ "$MODE" = "loss" ]; then
    echo "Loss percentage: ${LOSS_PERCENT}%"
elif [ "$MODE" = "bottleneck" ]; then
    echo "Rate limit: $RATE_LIMIT"
fi
if [ "$DRY_RUN" = true ]; then
    echo "DRY RUN MODE - No changes will be made"
fi
echo ""

# Execute or print command
run_cmd() {
    local cmd="$1"
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] $cmd"
    else
        echo "Executing: $cmd"
        eval "$cmd" || true
    fi
}

# Configure system settings for proxy operation
configure_proxy() {
    echo "=== Configuring Proxy System Settings ==="

    # Enable IP forwarding
    run_cmd "sysctl -w net.ipv4.ip_forward=1"

    # Set longer TCP retry timeout (proxy should wait longer than clients)
    echo "Setting proxy TCP timeout longer than client/server..."
    run_cmd "sysctl -w net.ipv4.tcp_retries2=15"

    echo "Proxy system settings configured"
    echo ""
}

# Clean all tc rules
clean_rules() {
    echo "=== Cleaning tc Rules ==="
    run_cmd "tc qdisc del dev $INTERFACE root 2>/dev/null"

    echo ""
    echo "Current state:"
    if [ "$DRY_RUN" = false ]; then
        tc qdisc show dev "$INTERFACE"
    else
        echo "[Would show: tc qdisc show dev $INTERFACE]"
    fi
}

# Apply loss impairment
apply_loss() {
    echo "=== Applying ${LOSS_PERCENT}% Packet Loss ==="

    # Clean first
    run_cmd "tc qdisc del dev $INTERFACE root 2>/dev/null"

    # Add netem with loss
    run_cmd "tc qdisc add dev $INTERFACE root netem loss ${LOSS_PERCENT}%"

    echo ""
    echo "Current state:"
    if [ "$DRY_RUN" = false ]; then
        tc qdisc show dev "$INTERFACE"
        tc -s qdisc show dev "$INTERFACE"
    else
        echo "[Would show: tc qdisc/stats]"
    fi

    echo ""
    echo "Expected behavior:"
    echo "  - ${LOSS_PERCENT}% of packets will be randomly dropped"
    echo "  - TCP will show retransmissions and cwnd reductions"
    echo "  - UDP will maintain send rate but show loss at receiver"
}

# Apply bottleneck impairment
apply_bottleneck() {
    echo "=== Applying Bandwidth Limit: $RATE_LIMIT ==="

    # Clean first
    run_cmd "tc qdisc del dev $INTERFACE root 2>/dev/null"

    # Add TBF (Token Bucket Filter)
    run_cmd "tc qdisc add dev $INTERFACE root tbf rate $RATE_LIMIT burst 32kbit latency 400ms"

    echo ""
    echo "Current state:"
    if [ "$DRY_RUN" = false ]; then
        tc qdisc show dev "$INTERFACE"
        tc -s qdisc show dev "$INTERFACE"
    else
        echo "[Would show: tc qdisc/stats]"
    fi

    echo ""
    echo "Expected behavior:"
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
            echo "All impairments removed. Path is clean."
            ;;
        loss)
            configure_proxy
            apply_loss
            echo ""
            echo "Loss impairment applied."
            echo "Remember to run '$0 -m clean' after testing!"
            ;;
        bottleneck)
            configure_proxy
            apply_bottleneck
            echo ""
            echo "Bottleneck applied."
            echo "Remember to run '$0 -m clean' after testing!"
            ;;
    esac
}

# Verification function
verify_setup() {
    if [ "$DRY_RUN" = false ] && [ "$MODE" != "clean" ]; then
        echo ""
        echo "=== Verifying Setup ==="

        # Check IP forwarding
        if [ "$(cat /proc/sys/net/ipv4/ip_forward)" = "1" ]; then
            echo "IP forwarding enabled"
        else
            echo "IP forwarding disabled"
        fi

        # Check tc rules
        if tc qdisc show dev "$INTERFACE" | grep -q "netem\|tbf"; then
            echo "Traffic control rules active"
        else
            echo "! No traffic control rules found"
        fi

        # Show statistics
        echo ""
        echo "Statistics:"
        tc -s qdisc show dev "$INTERFACE"
    fi
}

# Run main function
main

# Verify after applying
verify_setup

echo ""
echo "Done!"

if [ "$MODE" != "clean" ]; then
    echo ""
    echo "REMINDER: Run the following when done testing:"
    echo "  sudo $0 -m clean"
fi