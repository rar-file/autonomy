#!/bin/bash
# Email Notification System for Autonomy
# Sends email notifications for task completions and important events

AUTONOMY_DIR="${AUTONOMY_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CONFIG_FILE="$AUTONOMY_DIR/config.json"

# Load email config from autonomy config
load_email_config() {
    ENABLED=$(jq -r '.integrations.email.enabled // false' "$CONFIG_FILE" 2>/dev/null)
    SMTP_HOST=$(jq -r '.integrations.email.smtp_host // ""' "$CONFIG_FILE" 2>/dev/null)
    SMTP_PORT=$(jq -r '.integrations.email.smtp_port // 587' "$CONFIG_FILE" 2>/dev/null)
    USERNAME=$(jq -r '.integrations.email.username // ""' "$CONFIG_FILE" 2>/dev/null)
    PASSWORD=$(jq -r '.integrations.email.password // ""' "$CONFIG_FILE" 2>/dev/null)
    FROM=$(jq -r '.integrations.email.from // ""' "$CONFIG_FILE" 2>/dev/null)
    TO=$(jq -r '.integrations.email.to // ""' "$CONFIG_FILE" 2>/dev/null)
}

# Send email notification
send_email() {
    local subject="$1"
    local body="$2"
    
    load_email_config
    
    # Check if enabled
    if [[ "$ENABLED" != "true" ]]; then
        echo "Email notifications disabled"
        return 1
    fi
    
    # Validate config
    if [[ -z "$SMTP_HOST" || -z "$USERNAME" || -z "$PASSWORD" || -z "$TO" ]]; then
        echo "Email not configured properly"
        return 1
    fi
    
    # Use sendmail or curl for SMTP
    if command -v sendmail >/dev/null 2>&1; then
        # Using sendmail
        {
            echo "To: $TO"
            echo "From: $FROM"
            echo "Subject: $subject"
            echo "Content-Type: text/plain; charset=UTF-8"
            echo ""
            echo "$body"
        } | sendmail "$TO"
    elif command -v curl >/dev/null 2>&1; then
        # Using curl with SMTP
        # Note: This is a simplified version - may need adjustment for specific SMTP servers
        echo "Email sending via curl not yet implemented"
        return 1
    else
        echo "No mail sending tool available (sendmail or curl required)"
        return 1
    fi
}

# Notify task completion
notify_task_complete() {
    local task_name="$1"
    local verification="$2"
    
    local subject="[Autonomy] Task Completed: $task_name"
    local body="Task completed at $(date)

Task: $task_name
Verification: $verification

--
Autonomy Agent
"
    
    send_email "$subject" "$body"
}

# Notify task failure
notify_task_failed() {
    local task_name="$1"
    local reason="$2"
    
    local subject="[Autonomy] Task Failed: $task_name"
    local body="Task failed at $(date)

Task: $task_name
Reason: $reason

--
Autonomy Agent
"
    
    send_email "$subject" "$body"
}

# Test email configuration
test_email() {
    load_email_config
    
    echo "Email Configuration:"
    echo "  Enabled: $ENABLED"
    echo "  SMTP Host: $SMTP_HOST"
    echo "  SMTP Port: $SMTP_PORT"
    echo "  Username: $USERNAME"
    echo "  From: $FROM"
    echo "  To: $TO"
    echo ""
    
    if [[ "$ENABLED" == "true" ]]; then
        echo "Sending test email..."
        send_email "[Autonomy] Test Email" "This is a test email from your Autonomy agent.\n\nIf you received this, email notifications are working!"
    else
        echo "Email is disabled. Enable it in config.json to send notifications."
    fi
}

# Setup wizard for email configuration
setup_email() {
    echo "═══════════════════════════════════════════════════════"
    echo "  Email Notification Setup"
    echo "═══════════════════════════════════════════════════════"
    echo ""
    echo "This will configure email notifications for task completions."
    echo ""
    
    read -p "Enable email notifications? (y/n): " enable
    if [[ "$enable" == "y" ]]; then
        read -p "SMTP Host (e.g., smtp.gmail.com): " smtp_host
        read -p "SMTP Port (default: 587): " smtp_port
        smtp_port=${smtp_port:-587}
        read -p "Username: " username
        read -s -p "Password: " password
        echo ""
        read -p "From address: " from
        read -p "To address: " to
        
        # Update config
        tmp_file="${CONFIG_FILE}.tmp"
        jq --arg host "$smtp_host" \
           --arg port "$smtp_port" \
           --arg user "$username" \
           --arg pass "$password" \
           --arg from "$from" \
           --arg to "$to" \
           '.integrations.email = {
             "enabled": true,
             "smtp_host": $host,
             "smtp_port": ($port | tonumber),
             "username": $user,
             "password": $pass,
             "from": $from,
             "to": $to
           }' "$CONFIG_FILE" > "$tmp_file" && mv "$tmp_file" "$CONFIG_FILE"
        
        echo ""
        echo "✅ Email configuration saved"
        echo "Run 'autonomy notify test' to test"
    else
        echo "Email notifications disabled"
    fi
}

# Command dispatch
case "${1:-status}" in
    test)
        test_email
        ;;
    setup)
        setup_email
        ;;
    task-complete)
        notify_task_complete "$2" "$3"
        ;;
    task-failed)
        notify_task_failed "$2" "$3"
        ;;
    status)
        load_email_config
        if [[ "$ENABLED" == "true" ]]; then
            echo "✅ Email notifications enabled"
            echo "  To: $TO"
            echo "  SMTP: $SMTP_HOST:$SMTP_PORT"
        else
            echo "❌ Email notifications disabled"
            echo "Run 'autonomy notify setup' to configure"
        fi
        ;;
    *)
        echo "Usage: $0 {test|setup|status|task-complete <name> <verification>|task-failed <name> <reason>}"
        ;;
esac
