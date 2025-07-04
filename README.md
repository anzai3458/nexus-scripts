# 🚀 Nexus Network Node Manager

A bash script to manage multiple Nexus network nodes with different node IDs.

## ✨ Features

- Start, stop, and monitor multiple Nexus nodes
- View real-time logs and status
- Auto-restart nodes on failure
- Time-based success/error rate calculation (5-minute window)
- Process hang detection with automatic recovery
- Log rotation to prevent disk space issues
- Detailed monitoring with configurable parameters
- Automatic dependency check for Nexus Network CLI
- Optimized performance for large log files

## 🏗️ System Architecture

```mermaid
graph TD
    subgraph "Nexus Node Manager"
        A[nexus_node_start.sh] --> B[Start Nodes]
        A --> C[Stop Nodes]
        A --> D[Check Status]
        A --> E[View Logs]
        A --> F[Monitor System]
    end

    subgraph "Nodes"
        N1[Node 1] 
        N2[Node 2]
        N3[Node 3]
    end

    subgraph "Monitoring System"
        M1[Monitor Daemon]
        M2[Success Rate Analysis]
        M3[Auto-Restart]
        M4[Hang Detection]
    end

    subgraph "Log Files"
        L1[Node Logs]
        L2[Monitor Log]
        L3[Restart Log]
    end

    B --> N1
    B --> N2
    B --> N3
    
    F --> M1
    M1 --> M2
    M1 --> M4
    M2 --> M3
    M4 --> M3
    
    N1 --> L1
    N2 --> L1
    N3 --> L1
    
    M1 --> L2
    M3 --> L3
    
    M3 -.Restarts.-> N1
    M3 -.Restarts.-> N2
    M3 -.Restarts.-> N3
```

## 🏁 Quick Start

1. Clone this repository: `git clone https://github.com/anzai3458/nexus-scripts.git`
2. Copy the config template: `cp nexus_config.conf.template nexus_config.conf`
3. Edit the config file and update your node IDs: `nano nexus_config.conf` 
4. Install Nexus Network CLI: `curl https://cli.nexus.xyz/ | sh`
5. Start your nodes: `./nexus_node_start.sh start`
6. Check status: `./nexus_node_start.sh status`
7. Start monitoring: `./nexus_node_start.sh monitor start`

## 📦 Installation

1. Download the script:
   ```bash
   git clone https://github.com/anzai3458/nexus-scripts.git
   cd nexus-scripts
   chmod +x nexus_node_start.sh
   ```

2. Install the Nexus Network CLI:
   ```bash
   curl https://cli.nexus.xyz/ | sh
   ```
   
   After installation, restart or refresh your terminal:
   ```bash
   # For Bash
   source ~/.bashrc
   
   # For Zsh
   source ~/.zshrc
   
   # Or simply open a new terminal window
   ```
   
   Note: The script will automatically check if the CLI is installed and prompt you to install it if it's not.

3. Create your configuration file from the template:
   ```bash
   # Copy the template 
   cp nexus_config.conf.template nexus_config.conf
   
   # Edit the configuration file and update your node IDs
   nano nexus_config.conf
   ```
   
   Make sure to update the NODE_IDS array with your actual node IDs:
   ```bash
   # List of node IDs to manage - REPLACE THESE with your actual node IDs
   NODE_IDS=(6515746 6515747 6515748)
   ```

4. Make sure you have the `nexus-network` command in your PATH

## ⚙️ Configuration

Edit the `nexus_config.conf` file to customize your settings:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `NODE_IDS` | Array of node IDs to manage | (required) |
| `MAX_LOG_SIZE_MB` | Maximum log file size before rotation | 25 |
| `MAX_LOG_FILES` | Number of log backups to keep | 2 |
| `MONITOR_ENABLED` | Enable/disable monitoring | false |
| `MONITOR_INTERVAL` | Seconds between monitoring checks | 30 |
| `SUCCESS_RATE_THRESHOLD` | Minimum success rate percentage | 60 |
| `MIN_LOG_ENTRIES` | Minimum log entries for rate calculation | 20 |
| `RESTART_COOLDOWN` | Seconds to wait before restarting same node | 300 |
| `RATE_CALCULATION_MINUTES` | Time window in minutes for rate calculation | 5 |
| `INACTIVITY_THRESHOLD` | Seconds of inactivity before considering a node as hanging | 300 |
| `ENABLE_NOTIFICATIONS` | Show notifications when monitor takes action | true |
| `LOG_RESTART_ACTIONS` | Log all restart actions | true |

## 📋 Example Workflow

Here's a typical workflow for managing your Nexus nodes:

### 🚀 Initial Setup

```bash
# Create required directories
mkdir -p logs run

# Start all nodes
./nexus_node_start.sh start
# Output will show the PIDs of the started nodes

# Check status to ensure nodes are running
./nexus_node_start.sh status

# Start monitoring (only running nodes will be monitored)
./nexus_node_start.sh monitor start

# Or start monitoring and auto-start all nodes even if not running
./nexus_node_start.sh monitor start --force

# Check monitor status to see which nodes are being monitored
./nexus_node_start.sh monitor status
```

### 📊 Daily Operations

```bash
# Check node status each morning
./nexus_node_start.sh status

# Check error/success rates
./nexus_node_start.sh rates

# Check if any nodes were restarted overnight
cat run/nexus_restart.log

# View recent monitor events
./nexus_node_start.sh monitor status
```

### 🧰 Maintenance

```bash
# To restart a specific node for maintenance
./nexus_node_start.sh restart 6515746

# To temporarily remove a node from monitoring
./nexus_node_start.sh monitor remove 6515746

# Perform maintenance, then re-add to monitoring
./nexus_node_start.sh monitor add 6515746

# To restart the entire cluster
./nexus_node_start.sh stop
./nexus_node_start.sh start
```

## 🛠️ Usage

### 📟 Basic Commands

```bash
# Start all nodes
./nexus_node_start.sh start

# Start a specific node
./nexus_node_start.sh start 6515746

# Check status of all nodes
./nexus_node_start.sh status

# Check status of a specific node
./nexus_node_start.sh status 6515746

# Stop all nodes
./nexus_node_start.sh stop

# Stop a specific node
./nexus_node_start.sh stop 6515746

# View logs (tail -f) for a specific node
./nexus_node_start.sh log 6515746

# View error/success rates for all nodes
./nexus_node_start.sh rates

# Restart all nodes
./nexus_node_start.sh restart
```

### 📊 Monitoring Commands

```bash
# Start monitoring daemon
./nexus_node_start.sh monitor start

# Force start monitoring even if no nodes are running
# This will also auto-start all configured nodes
./nexus_node_start.sh monitor start --force

# Check monitoring status
./nexus_node_start.sh monitor status

# View monitoring logs
./nexus_node_start.sh monitor log

# Stop monitoring
./nexus_node_start.sh monitor stop

# Add a node to monitoring
./nexus_node_start.sh monitor add 6515746

# Remove a node from monitoring
./nexus_node_start.sh monitor remove 6515746
```

## 🔍 Monitoring System

The monitoring system tracks node health and can automatically restart nodes if:

1. A node process stops running
2. A node's success rate falls below the configured threshold
3. A node appears to be hanging (no log output for 5 minutes)

### 🤖 How Monitoring Works

1. Only monitors nodes that are running when the monitor starts (or manually added)
2. Calculates success/error rates from log entries within the last 5 minutes
3. Detects hanging processes by monitoring the timestamp of the last log entry
4. Restarts nodes that fail, hang, or have low success rates
5. Applies a cooldown period to prevent excessive restarts
6. Maintains separate logs for monitor events and restart actions

### 📊 Rate Calculation

The success/error rates are calculated based on:
- Log entries from the past 5 minutes only (time-based window)
- Entries with timestamps outside this window are ignored
- Each entry is categorized as Success, Error, or Refresh
- Success rate = (Success entries / Total entries) × 100%
- Optimized for large log files with efficient pre-filtering and in-memory timestamp parsing

### 🕒 Process Hang Detection

A node is considered "hanging" when:
- No new log entries have been generated in the past 5 minutes
- The node process is still running but not producing output
- The monitor will automatically restart hanging nodes to recover them

### 📁 Log Files

- Node logs: `logs/nexus_node_<node_id>.log`
- Monitor log: `run/nexus_monitor.log`
- Restart log: `run/nexus_restart.log`

## 🔧 Troubleshooting

### 🚫 Node won't start

Check the node's log file for errors:
```bash
cat logs/nexus_node_<node_id>.log
```

### 🚨 Monitor not restarting failed nodes

1. Check if the node is in the monitored nodes list:
   ```bash
   ./nexus_node_start.sh monitor status
   ```

2. Check the monitor log for events:
   ```bash
   ./nexus_node_start.sh monitor log
   ```

3. Verify monitor is running:
   ```bash
   ./nexus_node_start.sh monitor status
   ```

### 👻 Managing Stale PIDs

If the script reports a node is running but it's not:
```bash
# Stop the node to clean up the PID file
./nexus_node_start.sh stop <node_id>

# Then start it again
./nexus_node_start.sh start <node_id>
```

## 📜 License

MIT License

## 🎯 Conclusion

The Nexus Network Node Manager is designed to simplify the operation and maintenance of multiple Nexus network nodes. With its automated monitoring and restart capabilities, you can ensure maximum uptime for your nodes while minimizing manual intervention.

Key benefits:
- 🚀 Simplifies managing multiple nodes from a single interface
- 📈 Provides detailed error and success rate analytics
- 🛠️ Automatically recovers from failures and hanging processes
- 📊 Maintains comprehensive logs for troubleshooting
- ⚙️ Flexible configuration to meet your specific needs
- 🔋 Optimized performance even with large log files

For questions, issues, or contributions, please open a GitHub issue or submit a pull request. Happy node running! 😄 