# Autonomy Capability Extensions

This document describes the enhanced capabilities added to the Agentic Autonomy system.

## Overview

The autonomy skill has been extended with 6 major capability modules that provide deep system integration, file watching, diagnostics, enhanced execution, intelligent logging, and plugin support.

---

## 1. VM Integration (`autonomy vm`)

Full system introspection and control capabilities.

### Process Management
```bash
autonomy vm process_list      # List all processes
autonomy vm process_tree      # Show process tree
autonomy vm process_details <pid>  # Get process details
autonomy vm process_kill <pid> [signal]  # Kill process
autonomy vm top_cpu           # Top CPU consumers
autonomy vm top_memory        # Top memory consumers
```

### Service Management (systemd)
```bash
autonomy vm service_list      # List running services
autonomy vm service_status <service>  # Check service status
autonomy vm service_logs <service> [lines]  # View service logs
autonomy vm service_restart <service>  # Restart service
```

### Resource Monitoring
```bash
autonomy vm cpu               # CPU usage percentage
autonomy vm memory            # Memory usage
autonomy vm disk              # Disk usage
autonomy vm load              # Load average
autonomy vm uptime            # System uptime
```

### Network
```bash
autonomy vm network_connections   # Active connections
autonomy vm network_interfaces    # Network interfaces
autonomy vm dns <hostname>        # DNS lookup
autonomy vm ping <host> [count]   # Ping host
```

### Docker Integration
```bash
autonomy vm docker_ps         # List containers
autonomy vm docker_images     # List images
autonomy vm docker_logs <container> [lines]  # Container logs
autonomy vm docker_stats      # Container stats
autonomy vm docker_inspect <container>  # Container details
```

### Storage
```bash
autonomy vm storage_list      # List storage devices
autonomy vm storage_df        # Disk free space
autonomy vm storage_du <path> # Directory size
autonomy vm storage_largest_files <path>  # Largest files
```

### System Information
```bash
autonomy vm kernel_info       # Kernel information
autonomy vm cpu_info          # CPU details
autonomy vm memory_info       # Memory details
autonomy vm packages_list     # Installed packages
autonomy vm users_list        # System users
autonomy vm current_user      # Current user info
```

---

## 2. File Watcher (`autonomy watcher`)

Monitor files and directories for changes, trigger actions automatically.

### Basic Commands
```bash
autonomy watcher add <path> <action> [name]   # Add watcher
autonomy watcher remove <name>                # Remove watcher
autonomy watcher list                         # List watchers
autonomy watcher enable <name>                # Enable watcher
autonomy watcher disable <name>               # Disable watcher
autonomy watcher check [name]                 # Check for changes
```

### Daemon Mode
```bash
autonomy watcher daemon_start [interval]      # Start background watcher
autonomy watcher daemon_stop                  # Stop daemon
autonomy watcher daemon_status                # Check status
```

### Quick Setup
```bash
autonomy watcher setup_git [repo_path]        # Watch git repo
autonomy watcher setup_config [config_path]   # Watch config file
```

### Example
```bash
# Watch workspace and notify on changes
autonomy watcher add /root/.openclaw/workspace \
  "autonomy work 'Changes detected - analyze impact'" \
  workspace-watcher
```

---

## 3. Diagnostics (`autonomy diagnostic`)

Self-diagnosis, health checks, and auto-repair.

### Health Checks
```bash
autonomy diagnostic health              # Run full health check
autonomy diagnostic system              # Show system information
```

### Auto-Repair
```bash
autonomy diagnostic repair              # Auto-repair all issues
autonomy diagnostic repair_permissions  # Fix permissions
autonomy diagnostic repair_dirs         # Create missing dirs
autonomy diagnostic repair_config       # Restore config
autonomy diagnostic repair_logs         # Rotate large logs
```

### Health Check Categories
- Dependencies (bash, jq, python3, git)
- Configuration (valid JSON)
- Directories (required dirs exist)
- Permissions (executable scripts)
- Disk space
- Log size
- Daemon status
- Web UI status
- Git repository

---

## 4. Enhanced Task Execution (`autonomy execute`)

Better error handling, retries, async execution, and parallel processing.

### Retry Logic
```bash
autonomy execute retry "<command>" [max_retries] [delay]
```

### Async Execution
```bash
autonomy execute async "<command>" [task_name]    # Run in background
autonomy execute async_status <task_name>          # Check status
autonomy execute async_wait <task_name>            # Wait for completion
```

### Parallel Execution
```bash
autonomy execute parallel "cmd1" "cmd2" "cmd3"     # Run in parallel
# Or via stdin:
echo -e "cmd1\ncmd2\ncmd3" | autonomy execute parallel
```

### Timeout
```bash
autonomy execute timeout <seconds> "<command>"
```

### Conditional Execution
```bash
autonomy execute if "<condition>" "<then_cmd>" ["<else_cmd>"]
autonomy execute unless "<condition>" "<cmd>"
```

### Pipeline with Error Handling
```bash
autonomy execute pipeline "cmd1" "cmd2" "cmd3"
```

### Progress Tracking
```bash
autonomy execute progress_start <task> <total_steps>
autonomy execute progress_update <task> <step> [message]
autonomy execute progress_complete <task>
```

---

## 5. Intelligent Logging (`autonomy log`)

Structured logging with filtering, analysis, and export.

### Query Logs
```bash
autonomy log query [filters...]
  --level <DEBUG|INFO|WARN|ERROR|FATAL>
  --component <name>
  --since <iso_date>
  --until <iso_date>
  --contains <string>
  --last <n>
```

### View Logs
```bash
autonomy log tail [n]           # Show last N lines
autonomy log follow             # Follow log output (tail -f)
autonomy log errors [n]         # Show last N errors
```

### Analysis
```bash
autonomy log stats              # Log statistics
```

### Maintenance
```bash
autonomy log rotate [max_size]  # Rotate if too large
autonomy log cleanup [days]     # Remove old logs
```

### Export/Import
```bash
autonomy log export <file>      # Export to JSON
autonomy log import <file>      # Import from JSON
```

---

## 6. Plugin System (`autonomy plugin`)

Extensible plugin architecture for custom capabilities.

### Plugin Management
```bash
autonomy plugin list            # List plugins
autonomy plugin load <name>     # Load a plugin
autonomy plugin unload <name>   # Unload a plugin
autonomy plugin reload <name>   # Reload a plugin
autonomy plugin reload_all      # Reload all plugins
autonomy plugin create <name>   # Create plugin template
```

### Capability Discovery
```bash
autonomy plugin discover        # Show all capabilities
```

### Creating a Plugin

Create a plugin file in `plugins/`:

```bash
#!/bin/bash
# Plugin: my_plugin
# Description: My custom plugin
# Version: 0.1.0

my_plugin_init() {
    echo "My plugin initialized"
}

my_plugin_hello() {
    echo "Hello from my plugin!"
}

case "${1:-}" in
    init) my_plugin_init ;;
    hello) my_plugin_hello ;;
    *) echo "Usage: $0 {init|hello}" ;;
esac
```

Load and use:
```bash
autonomy plugin create my_plugin
# Edit plugins/my_plugin.sh
autonomy plugin load my_plugin
autonomy plugin call my_plugin hello
```

---

## Integration with Heartbeat

All capabilities are automatically documented in `HEARTBEAT.md` on each cycle, so the AI knows what tools are available and how to use them.

The heartbeat includes:
- Available VM commands
- Active file watchers
- Diagnostic capabilities
- Execution helpers
- Logging features
- Plugin commands

---

## Security Considerations

1. **VM Integration**: Full system access - use with appropriate user permissions
2. **File Watcher**: Can trigger arbitrary commands - validate watcher actions
3. **Plugin System**: Plugins can execute arbitrary code - review before loading
4. **Diagnostics**: Auto-repair only fixes safe issues (permissions, directories)

---

## Future Enhancements

Potential additions:
- Kubernetes integration (`autonomy k8s`)
- Cloud provider APIs (`autonomy aws`, `autonomy gcp`, `autonomy azure`)
- Database monitoring (`autonomy db monitor`)
- Security scanning (`autonomy security scan`)
- Network discovery (`autonomy network scan`)
- Backup/restore (`autonomy backup`)

---

## Summary

These capability extensions transform the autonomy skill from a simple task manager into a comprehensive system automation platform with:

- **Full VM Access**: Monitor and control processes, services, Docker, resources
- **Reactive Automation**: File watching with automatic triggers
- **Self-Healing**: Built-in diagnostics and auto-repair
- **Robust Execution**: Retries, async, parallel, timeouts
- **Observability**: Structured logging with analysis
- **Extensibility**: Plugin system for custom capabilities

Total new capabilities: 6 modules, ~2500 lines of code, 50+ commands.
