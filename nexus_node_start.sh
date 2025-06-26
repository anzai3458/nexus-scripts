#!/bin/bash

# Nexus Network Node Manager Script
# This script manages multiple Nexus network nodes with different node IDs
# Usage: ./nexus_node_start.sh [start|stop|status|log] [node_id]

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to check if the nexus-network command is installed
check_nexus_network_installed() {
    if ! command -v nexus-network &> /dev/null; then
        print_color $RED "Error: nexus-network command not found"
        print_color $BLUE "Please install the Nexus Network CLI by running:"
        print_color $YELLOW "curl https://cli.nexus.xyz/ | sh"
        print_color $BLUE "After installation, restart or refresh your terminal:"
        print_color $YELLOW "source ~/.bashrc  # For Bash"
        print_color $YELLOW "source ~/.zshrc   # For Zsh"
        print_color $BLUE "Or open a new terminal window"
        print_color $BLUE "Then try running this script again"
        exit 1
    fi
}

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="$SCRIPT_DIR/run"
CONFIG_FILE="$SCRIPT_DIR/nexus_config.conf"
PID_FILE="$RUN_DIR/nexus_nodes.pids"
MONITOR_PID_FILE="$RUN_DIR/nexus_monitor.pid"
RESTART_LOG_FILE="$RUN_DIR/nexus_restart.log"
MONITOR_LOG_FILE="$RUN_DIR/nexus_monitor.log"
MONITORED_NODES_FILE="$RUN_DIR/monitored_nodes.list"
LOG_DIR="$SCRIPT_DIR/logs"

# Load configuration from file
load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        print_color $RED "Error: Configuration file not found: $CONFIG_FILE"
        print_color $BLUE "Please create the configuration file or run with --create-config"
        exit 1
    fi
    
    # Source the configuration file
    source "$CONFIG_FILE"
    
    # Set defaults if not specified in config
    MAX_LOG_SIZE_MB=${MAX_LOG_SIZE_MB:-25}
    MAX_LOG_FILES=${MAX_LOG_FILES:-2}
    MONITOR_ENABLED=${MONITOR_ENABLED:-false}
    MONITOR_INTERVAL=${MONITOR_INTERVAL:-30}
    SUCCESS_RATE_THRESHOLD=${SUCCESS_RATE_THRESHOLD:-60}
    MIN_LOG_ENTRIES=${MIN_LOG_ENTRIES:-20}
    RESTART_COOLDOWN=${RESTART_COOLDOWN:-300}
    ENABLE_NOTIFICATIONS=${ENABLE_NOTIFICATIONS:-true}
    LOG_RESTART_ACTIONS=${LOG_RESTART_ACTIONS:-true}
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  start [node_id]       Start all nodes or specific node"
    echo "  stop [node_id]        Stop all nodes or specific node"
    echo "  status [node_id]      Show status of all nodes or specific node"
    echo "  log [node_id]         Show logs for all nodes or specific node"
    echo "  rates [node_id]       Show error/success rates for last 5 minutes"
    echo "  restart [node_id]     Restart all nodes or specific node"
    echo ""
    echo "Monitor Commands:"
    echo "  monitor start         Start monitoring daemon"
    echo "  monitor start --force Start monitor even if no nodes are running"
    echo "  monitor stop          Stop monitoring daemon"
    echo "  monitor status        Show monitoring daemon status"
    echo "  monitor log           Show monitor daemon logs"
    echo "  monitor add NODE_ID   Add a node to monitoring list"
    echo "  monitor remove NODE_ID Remove a node from monitoring list"
    echo ""
    echo "Examples:"
    echo "  $0 start              # Start all nodes"
    echo "  $0 start 6515746      # Start specific node"
    echo "  $0 status             # Show status of all nodes"
    echo "  $0 stop               # Stop all nodes"
    echo "  $0 log 6515746        # Show logs for specific node"
    echo "  $0 rates              # Show error/success rates for all nodes"
    echo "  $0 rates 6515746      # Show rates for specific node"
    echo "  $0 monitor start      # Start auto-restart monitoring"
    echo "  $0 monitor status     # Check monitoring daemon status"
    echo "  $0 monitor add 6515746 # Add node to monitoring list"
}

# Function to ensure log directory exists
ensure_log_dir() {
    if [ ! -d "$LOG_DIR" ]; then
        mkdir -p "$LOG_DIR"
    fi
}

# Function to ensure run directory exists
ensure_run_dir() {
    if [ ! -d "$RUN_DIR" ]; then
        mkdir -p "$RUN_DIR"
    fi
}

# Function to start a single node
start_node() {
    local node_id=$1
    local log_file="$LOG_DIR/nexus_node_${node_id}.log"
    local auto_monitor=${2:-true}  # Default to adding to monitor if it's running
    
    # Check if node is already running
    if is_node_running "$node_id"; then
        print_color $YELLOW "Node $node_id is already running"
        return 1
    fi
    
    print_color $BLUE "Starting Nexus node with ID: $node_id"
    
    # Ensure log directory exists
    ensure_log_dir
    
    # Ensure run directory exists
    ensure_run_dir
    
    # Rotate log file if it's too large
    rotate_log_if_needed "$log_file"
    
    # Start the node as a detached process with proper logging
    nohup nexus-network start --headless --node-id "$node_id" \
        > "$log_file" 2>&1 &
    
    local pid=$!
    
    # Give the process a moment to start
    sleep 2
    
    # Verify the process is still running
    if kill -0 "$pid" 2>/dev/null; then
        echo "$pid:$node_id" >> "$PID_FILE"
        print_color $GREEN "Node $node_id started successfully with PID: $pid"
        print_color $BLUE "Log file: $log_file"
        
        # Add to monitored nodes list if monitor is running
        if [ "$auto_monitor" = true ] && [ -f "$MONITOR_PID_FILE" ]; then
            local monitor_pid=$(cat "$MONITOR_PID_FILE")
            if kill -0 "$monitor_pid" 2>/dev/null; then
                if add_node_to_monitor "$node_id"; then
                    print_color $BLUE "Added node $node_id to monitored nodes list"
                fi
            fi
        fi
        
        return 0
    else
        print_color $RED "Failed to start node $node_id"
        return 1
    fi
}

# Function to check if a node is running
is_node_running() {
    local node_id=$1
    if [ ! -f "$PID_FILE" ]; then
        return 1
    fi
    
    local pid=$(grep ":$node_id$" "$PID_FILE" 2>/dev/null | cut -d: -f1)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        return 0
    else
        # Clean up stale PID entry
        if [ -f "$PID_FILE" ]; then
            grep -v ":$node_id$" "$PID_FILE" > "$PID_FILE.tmp" 2>/dev/null
            mv "$PID_FILE.tmp" "$PID_FILE" 2>/dev/null
        fi
        return 1
    fi
}

# Function to get node PID
get_node_pid() {
    local node_id=$1
    if [ -f "$PID_FILE" ]; then
        grep ":$node_id$" "$PID_FILE" 2>/dev/null | cut -d: -f1
    fi
}

# Function to stop a single node
stop_node() {
    local node_id=$1
    local pid=$(get_node_pid "$node_id")
    
    # Remove from monitored nodes list if monitor is running
    if [ -f "$MONITOR_PID_FILE" ]; then
        local monitor_pid=$(cat "$MONITOR_PID_FILE")
        if kill -0 "$monitor_pid" 2>/dev/null; then
            if remove_node_from_monitor "$node_id"; then
                print_color $BLUE "Removed node $node_id from monitored nodes list"
            fi
        fi
    fi
    
    if [ -z "$pid" ]; then
        print_color $YELLOW "Node $node_id is not running or not found in PID file"
        return 1
    fi
    
    if kill -0 "$pid" 2>/dev/null; then
        print_color $BLUE "Stopping node $node_id (PID: $pid)..."
        
        # Kill all child processes first
        local child_pids=$(pgrep -P "$pid" 2>/dev/null)
        if [ -n "$child_pids" ]; then
            print_color $BLUE "Stopping child processes: $child_pids"
            kill $child_pids 2>/dev/null
        fi
        
        # Kill the main process
        kill "$pid" 2>/dev/null
        
        # Wait for graceful shutdown
        local count=0
        while kill -0 "$pid" 2>/dev/null && [ $count -lt 10 ]; do
            sleep 1
            count=$((count + 1))
        done
        
        # Force kill if still running
        if kill -0 "$pid" 2>/dev/null; then
            print_color $YELLOW "Force killing node $node_id and all its child processes..."
            
            # Kill any remaining child processes with SIGKILL
            child_pids=$(pgrep -P "$pid" 2>/dev/null)
            if [ -n "$child_pids" ]; then
                kill -9 $child_pids 2>/dev/null
            fi
            
            # Kill the main process with SIGKILL
            kill -9 "$pid" 2>/dev/null
            sleep 1
            
            # Final verification
            if kill -0 "$pid" 2>/dev/null; then
                print_color $RED "Failed to stop node $node_id completely"
            else
                print_color $GREEN "Node $node_id force stopped successfully"
            fi
        else
            print_color $GREEN "Node $node_id stopped successfully"
        fi
    else
        print_color $YELLOW "Node $node_id was not running"
    fi
    
    # Remove from PID file
    if [ -f "$PID_FILE" ]; then
        grep -v ":$node_id$" "$PID_FILE" > "$PID_FILE.tmp" 2>/dev/null
        mv "$PID_FILE.tmp" "$PID_FILE" 2>/dev/null
    fi
    
    # Verify no zombie processes remain for this node
    local remaining_processes=$(ps aux | grep "node-id $node_id" | grep -v "grep" | wc -l)
    if [ "$remaining_processes" -gt 0 ]; then
        print_color $YELLOW "Warning: $remaining_processes processes for node $node_id might still be running"
        print_color $BLUE "You may need to manually check: ps aux | grep \"node-id $node_id\""
    fi
    
    return 0
}

# Function to show status of a single node
show_node_status() {
    local node_id=$1
    local pid=$(get_node_pid "$node_id")
    
    printf "%-10s " "$node_id"
    
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        local cpu_mem=$(ps -o pid,pcpu,pmem,etime -p "$pid" 2>/dev/null | tail -n 1)
        if [ -n "$cpu_mem" ]; then
            print_color $GREEN "RUNNING   PID: $pid   $cpu_mem"
        else
            print_color $GREEN "RUNNING   PID: $pid"
        fi
    else
        print_color $RED "STOPPED"
        # Clean up stale PID if exists
        if [ -n "$pid" ]; then
            grep -v ":$node_id$" "$PID_FILE" > "$PID_FILE.tmp" 2>/dev/null
            mv "$PID_FILE.tmp" "$PID_FILE" 2>/dev/null
        fi
    fi
}

# Function to show logs for a node
show_node_log() {
    local node_id=$1
    local log_file="$LOG_DIR/nexus_node_${node_id}.log"
    
    if [ -f "$log_file" ]; then
        print_color $BLUE "=== Logs for Node $node_id ==="
        tail -f "$log_file"
    else
        print_color $YELLOW "No log file found for node $node_id"
        print_color $BLUE "Expected location: $log_file"
    fi
}

# Function to show error/success rates for last 5 minutes
show_rates() {
    local node_id=$1
    local minutes=${2:-5}  # Default to 5 minutes if not specified
    
    print_color $BLUE "Error/Success Rates Analysis (Last $minutes minutes)"
    echo "================================================================="
    printf "%-10s %-8s %-8s %-8s %-12s %-12s\n" "NODE_ID" "SUCCESS" "ERROR" "REFRESH" "SUCCESS%" "ERROR%"
    echo "-----------------------------------------------------------------"
    
    local total_success=0
    local total_error=0
    local total_refresh=0
    
    for current_node in "${NODE_IDS[@]}"; do
        # Skip if specific node requested and this isn't it
        if [ -n "$node_id" ] && [ "$current_node" != "$node_id" ]; then
            continue
        fi
        
        local log_file="$LOG_DIR/nexus_node_${current_node}.log"
        
        if [ -f "$log_file" ]; then
            # Use simpler approach - just count from recent log entries
            local stats=$(tail -n 200 "$log_file" | awk '
                {
                    # Count first word of each line
                    if (match($0, /^[A-Za-z]+/)) {
                        first_word = substr($0, RSTART, RLENGTH)
                        count[first_word]++
                    }
                }
                END {
                    success = (count["Success"] ? count["Success"] : 0)
                    error = (count["Error"] ? count["Error"] : 0)
                    refresh = (count["Refresh"] ? count["Refresh"] : 0)
                    total = success + error + refresh
                    
                    success_rate = (total > 0 ? (success * 100.0 / total) : 0)
                    error_rate = (total > 0 ? (error * 100.0 / total) : 0)
                    
                    printf "%d %d %d %.1f %.1f", success, error, refresh, success_rate, error_rate
                }')
            
            # Parse the stats
            local success=$(echo $stats | cut -d' ' -f1)
            local error=$(echo $stats | cut -d' ' -f2)
            local refresh=$(echo $stats | cut -d' ' -f3)
            local success_rate=$(echo $stats | cut -d' ' -f4)
            local error_rate=$(echo $stats | cut -d' ' -f5)
            
            # Color coding based on error rate (using shell arithmetic)
            error_int=$(printf "%.0f" "$error_rate")
            if [ "$error_int" -gt 50 ]; then
                color=$RED
            elif [ "$error_int" -gt 25 ]; then
                color=$YELLOW
            else
                color=$GREEN
            fi
            
            printf "%-10s %-8s %-8s %-8s " "$current_node" "$success" "$error" "$refresh"
            printf "${color}%-12s %-12s${NC}\n" "${success_rate}%" "${error_rate}%"
            
            # Add to totals
            total_success=$((total_success + success))
            total_error=$((total_error + error))
            total_refresh=$((total_refresh + refresh))
        else
            printf "%-10s %-8s %-8s %-8s %-12s %-12s\n" "$current_node" "N/A" "N/A" "N/A" "N/A" "N/A"
        fi
    done
    
    # Show totals if analyzing all nodes
    if [ -z "$node_id" ]; then
        echo "-----------------------------------------------------------------"
        local total_all=$((total_success + total_error + total_refresh))
        local overall_success_rate=0
        local overall_error_rate=0
        
        if [ $total_all -gt 0 ]; then
            overall_success_rate=$(awk "BEGIN {printf \"%.1f\", $total_success * 100.0 / $total_all}")
            overall_error_rate=$(awk "BEGIN {printf \"%.1f\", $total_error * 100.0 / $total_all}")
        fi
        
        printf "%-10s %-8s %-8s %-8s " "TOTAL" "$total_success" "$total_error" "$total_refresh"
        printf "${BLUE}%-12s %-12s${NC}\n" "${overall_success_rate}%" "${overall_error_rate}%"
    fi
    
    echo "================================================================="
}

# Function to rotate log file if it's too large
rotate_log_if_needed() {
    local log_file=$1
    
    # Check if log file exists and is larger than MAX_LOG_SIZE_MB
    if [ -f "$log_file" ]; then
        local file_size_mb=$(( $(stat -f%z "$log_file" 2>/dev/null || echo 0) / 1024 / 1024 ))
        
        if [ $file_size_mb -gt $MAX_LOG_SIZE_MB ]; then
            print_color $YELLOW "Rotating log file: $log_file (${file_size_mb}MB)"
            
            # Rotate existing backup files
            for ((i=$MAX_LOG_FILES; i>1; i--)); do
                local old_backup="${log_file}.$((i-1))"
                local new_backup="${log_file}.$i"
                if [ -f "$old_backup" ]; then
                    mv "$old_backup" "$new_backup"
                fi
            done
            
            # Move current log to .1 backup
            mv "$log_file" "${log_file}.1"
            
            # Remove old backups beyond MAX_LOG_FILES
            for ((i=$MAX_LOG_FILES+1; i<=10; i++)); do
                local old_backup="${log_file}.$i"
                if [ -f "$old_backup" ]; then
                    rm "$old_backup"
                fi
            done
            
            print_color $GREEN "Log rotation completed. Created new log file: $log_file"
        fi
    fi
}

# Function to clean up PID file
cleanup_pid_file() {
    if [ -f "$PID_FILE" ]; then
        # Remove entries for processes that are no longer running
        local temp_file="$PID_FILE.tmp"
        > "$temp_file"
        
        while IFS=':' read -r pid node_id; do
            if kill -0 "$pid" 2>/dev/null; then
                echo "$pid:$node_id" >> "$temp_file"
            fi
        done < "$PID_FILE"
        
        mv "$temp_file" "$PID_FILE"
    fi
}

# Function to start all nodes
start_all_nodes() {
    print_color $BLUE "Starting Nexus Network Nodes..."
    echo "================================"
    
    local success_count=0
    local total_count=${#NODE_IDS[@]}
    
    for node_id in "${NODE_IDS[@]}"; do
        if start_node "$node_id"; then
            success_count=$((success_count + 1))
        fi
        sleep 1
    done
    
    echo "================================"
    print_color $GREEN "Started $success_count out of $total_count nodes successfully!"
    
    if [ $success_count -gt 0 ]; then
        print_color $BLUE "Process IDs saved to: $PID_FILE"
        print_color $BLUE "Logs saved to: $LOG_DIR/"
    fi
}

# Function to stop all nodes
stop_all_nodes() {
    print_color $BLUE "Stopping all Nexus Network Nodes..."
    echo "==================================="
    
    if [ ! -f "$PID_FILE" ]; then
        print_color $YELLOW "No PID file found. No nodes to stop."
        return
    fi
    
    local stopped_count=0
    for node_id in "${NODE_IDS[@]}"; do
        if stop_node "$node_id"; then
            stopped_count=$((stopped_count + 1))
        fi
    done
    
    echo "==================================="
    print_color $GREEN "Stopped $stopped_count nodes"
    
    # Clean up empty PID file
    if [ -f "$PID_FILE" ] && [ ! -s "$PID_FILE" ]; then
        rm "$PID_FILE"
    fi
}

# Function to show status of all nodes
show_all_status() {
    print_color $BLUE "Nexus Network Nodes Status"
    echo "==========================="
    printf "%-10s %s\n" "NODE_ID" "STATUS"
    echo "---------------------------"
    
    cleanup_pid_file
    
    for node_id in "${NODE_IDS[@]}"; do
        show_node_status "$node_id"
    done
    
    echo "==========================="
    
    # Show summary
    running_count=0
    for node_id in "${NODE_IDS[@]}"; do
        if is_node_running "$node_id"; then
            running_count=$((running_count + 1))
        fi
    done
    
    print_color $BLUE "Total nodes: ${#NODE_IDS[@]}, Running: $running_count, Stopped: $((${#NODE_IDS[@]} - running_count))"
}

# Function to calculate success rate for a node
get_node_success_rate() {
    local node_id=$1
    local log_file="$LOG_DIR/nexus_node_${node_id}.log"
    
    if [ ! -f "$log_file" ]; then
        echo "0:0"  # success_rate:total_entries
        return
    fi
    
    local stats=$(tail -n $MIN_LOG_ENTRIES "$log_file" | awk '
        {
            if (match($0, /^[A-Za-z]+/)) {
                first_word = substr($0, RSTART, RLENGTH)
                count[first_word]++
            }
        }
        END {
            success = (count["Success"] ? count["Success"] : 0)
            error = (count["Error"] ? count["Error"] : 0)
            refresh = (count["Refresh"] ? count["Refresh"] : 0)
            total = success + error + refresh
            
            success_rate = (total > 0 ? (success * 100.0 / total) : 0)
            printf "%.1f:%d", success_rate, total
        }')
    
    echo "$stats"
}

# Function to log restart actions
log_restart_action() {
    local node_id=$1
    local reason=$2
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    if [ "$LOG_RESTART_ACTIONS" = "true" ]; then
        echo "[$timestamp] RESTART: Node $node_id - $reason" >> "$RESTART_LOG_FILE"
    fi
    
    if [ "$ENABLE_NOTIFICATIONS" = "true" ]; then
        print_color $YELLOW "[MONITOR] Restarting node $node_id: $reason"
    fi
}

# Function to check if restart is allowed (cooldown period)
can_restart_node() {
    local node_id=$1
    local current_time=$(date +%s)
    local cooldown_file="$RUN_DIR/.restart_cooldown_${node_id}"
    
    if [ -f "$cooldown_file" ]; then
        local last_restart=$(cat "$cooldown_file")
        local time_diff=$((current_time - last_restart))
        
        if [ $time_diff -lt $RESTART_COOLDOWN ]; then
            return 1  # Still in cooldown
        fi
    fi
    
    echo "$current_time" > "$cooldown_file"
    return 0  # Can restart
}

# Function to log monitor events
log_monitor_event() {
    local message=$1
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $message" >> "$MONITOR_LOG_FILE"
    
    if [ "$ENABLE_NOTIFICATIONS" = "true" ]; then
        print_color $BLUE "[MONITOR] $message"
    fi
}

# Function to check if node is being monitored
is_node_monitored() {
    local node_id=$1
    
    if [ ! -f "$MONITORED_NODES_FILE" ]; then
        return 1  # No monitored nodes list exists
    fi
    
    grep -q "^$node_id$" "$MONITORED_NODES_FILE" 2>/dev/null
    return $?
}

# Function to add node to monitored list
add_node_to_monitor() {
    local node_id=$1
    
    ensure_run_dir
    
    # Create file if it doesn't exist
    if [ ! -f "$MONITORED_NODES_FILE" ]; then
        touch "$MONITORED_NODES_FILE"
    fi
    
    # Only add if not already there
    if ! is_node_monitored "$node_id"; then
        echo "$node_id" >> "$MONITORED_NODES_FILE"
        if [ -f "$MONITOR_LOG_FILE" ]; then
            log_monitor_event "Added node $node_id to monitoring list"
        fi
        return 0
    fi
    
    return 1  # Already monitored
}

# Function to remove node from monitored list
remove_node_from_monitor() {
    local node_id=$1
    
    if [ ! -f "$MONITORED_NODES_FILE" ]; then
        return 1  # No monitored nodes list exists
    fi
    
    if is_node_monitored "$node_id"; then
        grep -v "^$node_id$" "$MONITORED_NODES_FILE" > "${MONITORED_NODES_FILE}.tmp"
        mv "${MONITORED_NODES_FILE}.tmp" "$MONITORED_NODES_FILE"
        if [ -f "$MONITOR_LOG_FILE" ]; then
            log_monitor_event "Removed node $node_id from monitoring list"
        fi
        return 0
    fi
    
    return 1  # Not monitored
}

# Function to monitor and restart nodes
monitor_nodes() {
    log_monitor_event "Monitor daemon started"
    
    while true; do
        # Read the current list of monitored nodes
        if [ ! -f "$MONITORED_NODES_FILE" ]; then
            # No nodes to monitor
            log_monitor_event "No nodes in monitoring list - waiting for nodes to be added"
            sleep "$MONITOR_INTERVAL"
            continue
        fi
        
        # Read monitored nodes into an array
        local monitored_nodes=()
        while read -r node_id; do
            monitored_nodes+=("$node_id")
        done < "$MONITORED_NODES_FILE"
        
        # Check if we have any nodes to monitor
        if [ ${#monitored_nodes[@]} -eq 0 ]; then
            # Empty monitoring list
            sleep "$MONITOR_INTERVAL"
            continue
        fi
        
        # Process each monitored node
        for node_id in "${monitored_nodes[@]}"; do
            if ! is_node_running "$node_id"; then
                if can_restart_node "$node_id"; then
                    log_monitor_event "Node $node_id is not running - attempting restart"
                    log_restart_action "$node_id" "Node not running"
                    start_node "$node_id" >/dev/null 2>&1
                    if is_node_running "$node_id"; then
                        log_monitor_event "Successfully restarted node $node_id"
                    else
                        log_monitor_event "Failed to restart node $node_id"
                    fi
                else
                    log_monitor_event "Node $node_id is not running but still in cooldown period"
                fi
                continue
            fi
            
            # Get success rate
            local rate_info=$(get_node_success_rate "$node_id")
            local success_rate=$(echo "$rate_info" | cut -d: -f1)
            local total_entries=$(echo "$rate_info" | cut -d: -f2)
            
            # Skip if not enough log entries
            if [ "$total_entries" -lt "$MIN_LOG_ENTRIES" ]; then
                continue
            fi
            
            # Check if success rate is below threshold
            local success_int=$(printf "%.0f" "$success_rate")
            if [ "$success_int" -lt "$SUCCESS_RATE_THRESHOLD" ]; then
                if can_restart_node "$node_id"; then
                    log_monitor_event "Node $node_id has low success rate (${success_rate}%) - attempting restart"
                    log_restart_action "$node_id" "Low success rate: ${success_rate}% (threshold: ${SUCCESS_RATE_THRESHOLD}%)"
                    restart_node "$node_id" >/dev/null 2>&1
                    log_monitor_event "Restarted node $node_id due to low success rate"
                else
                    log_monitor_event "Node $node_id has low success rate but still in cooldown period"
                fi
            fi
        done
        
        # Log a heartbeat every 10 monitoring intervals
        if [ $(( SECONDS % (MONITOR_INTERVAL * 10) )) -lt "$MONITOR_INTERVAL" ]; then
            log_monitor_event "Monitor heartbeat - monitoring ${#monitored_nodes[@]} nodes"
        fi
        
        sleep "$MONITOR_INTERVAL"
    done
}

# Function to start monitoring daemon
start_monitor() {
    if [ "$MONITOR_ENABLED" != "true" ]; then
        print_color $YELLOW "Monitoring is disabled in configuration"
        return 1
    fi
    
    if [ -f "$MONITOR_PID_FILE" ]; then
        local monitor_pid=$(cat "$MONITOR_PID_FILE")
        if kill -0 "$monitor_pid" 2>/dev/null; then
            print_color $YELLOW "Monitor daemon is already running (PID: $monitor_pid)"
            return 1
        else
            rm "$MONITOR_PID_FILE"
        fi
    fi
    
    # Ensure run directory exists
    ensure_run_dir
    
    # Create or rotate monitor log file
    if [ -f "$MONITOR_LOG_FILE" ]; then
        if [ -s "$MONITOR_LOG_FILE" ]; then
            # Rotate existing log file if it has content
            local timestamp=$(date "+%Y%m%d_%H%M%S")
            mv "$MONITOR_LOG_FILE" "${MONITOR_LOG_FILE}.${timestamp}"
            print_color $BLUE "Previous monitor log rotated to ${MONITOR_LOG_FILE}.${timestamp}"
        fi
    fi
    
    # Create a list of currently running nodes to monitor
    > "$MONITORED_NODES_FILE"
    local running_nodes=()
    for node_id in "${NODE_IDS[@]}"; do
        if is_node_running "$node_id"; then
            echo "$node_id" >> "$MONITORED_NODES_FILE"
            running_nodes+=("$node_id")
        fi
    done
    
    # Count how many nodes we're monitoring
    local nodes_count=${#running_nodes[@]}
    
    if [ $nodes_count -eq 0 ]; then
        print_color $YELLOW "Warning: No running nodes found to monitor"
        print_color $BLUE "Start nodes first using '$0 start' before starting the monitor"
        print_color $BLUE "Or use '$0 monitor --all' to monitor all nodes even if not running"
        if [ "$2" != "--force" ]; then
            print_color $YELLOW "Monitor not started. Use '$0 monitor start --force' to start anyway"
            return 1
        fi
        print_color $YELLOW "Starting monitor anyway with --force option"
    fi
    
    # Create a new log file with header
    echo "===== Nexus Network Monitor Log - Started $(date) =====" > "$MONITOR_LOG_FILE"
    echo "Monitor interval: ${MONITOR_INTERVAL}s" >> "$MONITOR_LOG_FILE"
    echo "Success rate threshold: ${SUCCESS_RATE_THRESHOLD}%" >> "$MONITOR_LOG_FILE"
    echo "Restart cooldown: ${RESTART_COOLDOWN}s" >> "$MONITOR_LOG_FILE"
    if [ $nodes_count -gt 0 ]; then
        echo "Monitoring nodes: ${running_nodes[*]}" >> "$MONITOR_LOG_FILE"
    else
        echo "Monitoring nodes: None running at start time" >> "$MONITOR_LOG_FILE"
    fi
    echo "=======================================================" >> "$MONITOR_LOG_FILE"
    echo "" >> "$MONITOR_LOG_FILE"
    
    print_color $BLUE "Starting monitoring daemon..."
    print_color $BLUE "Monitor interval: ${MONITOR_INTERVAL}s"
    print_color $BLUE "Success rate threshold: ${SUCCESS_RATE_THRESHOLD}%"
    print_color $BLUE "Restart cooldown: ${RESTART_COOLDOWN}s"
    
    if [ $nodes_count -gt 0 ]; then
        print_color $BLUE "Monitoring nodes: ${running_nodes[*]}"
    else
        print_color $YELLOW "No running nodes to monitor"
    fi
    
    # Start monitor as background process
    monitor_nodes &
    local monitor_pid=$!
    echo "$monitor_pid" > "$MONITOR_PID_FILE"
    
    print_color $GREEN "Monitor daemon started (PID: $monitor_pid)"
    print_color $BLUE "Monitor log: $MONITOR_LOG_FILE"
    print_color $BLUE "Restart log: $RESTART_LOG_FILE"
}

# Function to stop monitoring daemon
stop_monitor() {
    if [ ! -f "$MONITOR_PID_FILE" ]; then
        print_color $YELLOW "Monitor daemon is not running"
        return 1
    fi
    
    local monitor_pid=$(cat "$MONITOR_PID_FILE")
    if kill -0 "$monitor_pid" 2>/dev/null; then
        print_color $BLUE "Stopping monitor daemon (PID: $monitor_pid)..."
        
        # Log the shutdown if the log file exists
        if [ -f "$MONITOR_LOG_FILE" ]; then
            local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
            echo "[$timestamp] Monitor daemon stopping - requested by user" >> "$MONITOR_LOG_FILE"
        fi
        
        kill "$monitor_pid"
        rm "$MONITOR_PID_FILE"
        print_color $GREEN "Monitor daemon stopped"
    else
        print_color $YELLOW "Monitor daemon was not running"
        rm "$MONITOR_PID_FILE"
    fi
}

# Function to show monitor status
show_monitor_status() {
    print_color $BLUE "Monitor Daemon Status"
    echo "===================="
    
    if [ -f "$MONITOR_PID_FILE" ]; then
        local monitor_pid=$(cat "$MONITOR_PID_FILE")
        if kill -0 "$monitor_pid" 2>/dev/null; then
            print_color $GREEN "RUNNING (PID: $monitor_pid)"
        else
            print_color $RED "STOPPED (stale PID file)"
            rm "$MONITOR_PID_FILE"
        fi
    else
        print_color $RED "STOPPED"
    fi
    
    echo ""
    echo "Configuration:"
    echo "  Enabled: $MONITOR_ENABLED"
    echo "  Interval: ${MONITOR_INTERVAL}s"
    echo "  Success threshold: ${SUCCESS_RATE_THRESHOLD}%"
    echo "  Restart cooldown: ${RESTART_COOLDOWN}s"
    echo "  Min log entries: $MIN_LOG_ENTRIES"
    
    # Show monitored nodes
    echo ""
    echo "Monitored Nodes:"
    if [ -f "$MONITORED_NODES_FILE" ] && [ -s "$MONITORED_NODES_FILE" ]; then
        local monitored=()
        while read -r node_id; do
            if is_node_running "$node_id"; then
                monitored+=("$node_id (RUNNING)")
            else
                monitored+=("$node_id (STOPPED)")
            fi
        done < "$MONITORED_NODES_FILE"
        
        printf "  %s\n" "${monitored[@]}"
    else
        echo "  None"
    fi
    
    if [ -f "$RESTART_LOG_FILE" ]; then
        echo ""
        echo "Recent restart actions:"
        tail -n 5 "$RESTART_LOG_FILE" 2>/dev/null | while read line; do
            echo "  $line"
        done
    fi
    
    if [ -f "$MONITOR_LOG_FILE" ]; then
        echo ""
        echo "Recent monitor events:"
        tail -n 5 "$MONITOR_LOG_FILE" 2>/dev/null | while read line; do
            echo "  $line"
        done
        echo ""
        echo "For more details, use '$(basename $0) monitor log'"
    fi
}

# Function to restart nodes
restart_node() {
    local node_id=$1
    print_color $BLUE "Restarting node $node_id..."
    stop_node "$node_id"
    sleep 2
    start_node "$node_id"
}

restart_all_nodes() {
    print_color $BLUE "Restarting all nodes..."
    stop_all_nodes
    sleep 3
    start_all_nodes
}

# Load configuration before executing commands
load_config

# Main execution logic
COMMAND=${1:-"help"}
NODE_ID=$2

# Check if nexus-network command is installed before executing relevant commands
case "$COMMAND" in
    "start"|"stop"|"restart")
        check_nexus_network_installed
        ;;
esac

case "$COMMAND" in
    "start")
        if [ -n "$NODE_ID" ]; then
            # Check if node_id is valid
            if [[ " ${NODE_IDS[@]} " =~ " ${NODE_ID} " ]]; then
                start_node "$NODE_ID"
            else
                print_color $RED "Error: Invalid node ID '$NODE_ID'"
                print_color $BLUE "Available node IDs: ${NODE_IDS[*]}"
                exit 1
            fi
        else
            start_all_nodes
        fi
        ;;
    "stop")
        if [ -n "$NODE_ID" ]; then
            if [[ " ${NODE_IDS[@]} " =~ " ${NODE_ID} " ]]; then
                stop_node "$NODE_ID"
            else
                print_color $RED "Error: Invalid node ID '$NODE_ID'"
                print_color $BLUE "Available node IDs: ${NODE_IDS[*]}"
                exit 1
            fi
        else
            stop_all_nodes
        fi
        ;;
    "status")
        if [ -n "$NODE_ID" ]; then
            if [[ " ${NODE_IDS[@]} " =~ " ${NODE_ID} " ]]; then
                print_color $BLUE "Status for Node $NODE_ID:"
                printf "%-10s %s\n" "NODE_ID" "STATUS"
                echo "---------------------------"
                show_node_status "$NODE_ID"
            else
                print_color $RED "Error: Invalid node ID '$NODE_ID'"
                print_color $BLUE "Available node IDs: ${NODE_IDS[*]}"
                exit 1
            fi
        else
            show_all_status
        fi
        ;;
    "log")
        if [ -n "$NODE_ID" ]; then
            if [[ " ${NODE_IDS[@]} " =~ " ${NODE_ID} " ]]; then
                show_node_log "$NODE_ID"
            else
                print_color $RED "Error: Invalid node ID '$NODE_ID'"
                print_color $BLUE "Available node IDs: ${NODE_IDS[*]}"
                exit 1
            fi
        else
            print_color $BLUE "Showing logs for all nodes:"
            echo "=============================="
            
            for node_id in "${NODE_IDS[@]}"; do
                log_file="$LOG_DIR/nexus_node_${node_id}.log"
                
                echo ""
                print_color $BLUE "=== Node $node_id Logs ==="
                
                if [ -f "$log_file" ]; then
                    # Show last 20 lines of each log file
                    tail -n 20 "$log_file"
                else
                    print_color $YELLOW "No log file found for node $node_id"
                fi
                
                echo "----------------------------"
            done
            
            echo ""
            print_color $BLUE "Use '$0 log <node_id>' to view specific logs with live updates"
        fi
        ;;
    "rates")
        if [ -n "$NODE_ID" ]; then
            if [[ " ${NODE_IDS[@]} " =~ " ${NODE_ID} " ]]; then
                show_rates "$NODE_ID"
            else
                print_color $RED "Error: Invalid node ID '$NODE_ID'"
                print_color $BLUE "Available node IDs: ${NODE_IDS[*]}"
                exit 1
            fi
        else
            show_rates
        fi
        ;;
    "restart")
        if [ -n "$NODE_ID" ]; then
            if [[ " ${NODE_IDS[@]} " =~ " ${NODE_ID} " ]]; then
                restart_node "$NODE_ID"
            else
                print_color $RED "Error: Invalid node ID '$NODE_ID'"
                print_color $BLUE "Available node IDs: ${NODE_IDS[*]}"
                exit 1
            fi
        else
            restart_all_nodes
        fi
        ;;
    "monitor")
        case "$NODE_ID" in
            "start")
                start_monitor
                ;;
            "stop")
                stop_monitor
                ;;
            "status")
                show_monitor_status
                ;;
            "log")
                if [ -f "$MONITOR_LOG_FILE" ]; then
                    print_color $BLUE "=== Logs for Monitor ==="
                    tail -f "$MONITOR_LOG_FILE"
                else
                    print_color $YELLOW "No log file found for monitor"
                    print_color $BLUE "Expected location: $MONITOR_LOG_FILE"
                fi
                ;;
            "add")
                if [ -n "$NODE_ID" ]; then
                    if [[ " ${NODE_IDS[@]} " =~ " ${NODE_ID} " ]]; then
                        add_node_to_monitor "$NODE_ID"
                    else
                        print_color $RED "Error: Invalid node ID '$NODE_ID'"
                        print_color $BLUE "Available node IDs: ${NODE_IDS[*]}"
                        exit 1
                    fi
                else
                    print_color $RED "Error: Missing node ID for 'monitor add'"
                    exit 1
                fi
                ;;
            "remove")
                if [ -n "$NODE_ID" ]; then
                    if [[ " ${NODE_IDS[@]} " =~ " ${NODE_ID} " ]]; then
                        remove_node_from_monitor "$NODE_ID"
                    else
                        print_color $RED "Error: Invalid node ID '$NODE_ID'"
                        print_color $BLUE "Available node IDs: ${NODE_IDS[*]}"
                        exit 1
                    fi
                else
                    print_color $RED "Error: Missing node ID for 'monitor remove'"
                    exit 1
                fi
                ;;
            *)
                print_color $RED "Error: Invalid monitor command '$NODE_ID'"
                print_color $BLUE "Available monitor commands: start, stop, status, log, add, remove"
                exit 1
                ;;
        esac
        ;;
    "help"|"--help"|"")
        show_usage
        ;;
    *)
        print_color $RED "Error: Unknown command '$COMMAND'"
        echo ""
        show_usage
        exit 1
        ;;
esac
