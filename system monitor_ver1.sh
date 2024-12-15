#!/bin/bash

# Configuration
LOG_FILE="var/log/system_resource.log"
ALERT_EMAIL="fjustine920@gmail.com"
CPU_THRESHOLD=80
MEMORY_THRESHOLD=80
DISK_THRESHOLD=80
LOG_INTERVAL=2  # Log every 2 seconds
SEND_ALERTS=true
REPORT_DIR="var/log/system_reports"
GRAPH_SCRIPT="tmp/system_monitor_plot.gnuplot"

# Ensure necessary directories exist
mkdir -p $REPORT_DIR

# Function to log system resource usage
log_usage() {
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}')
    memory_usage=$(free | grep Mem | awk '{print $3/$2 * 100.0}')
    disk_usage=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')

    # Fallback to 0 if parsing fails
    cpu_usage=${cpu_usage:-0}
    memory_usage=${memory_usage:-0}
    disk_usage=${disk_usage:-0}

    # Log usage to file
    echo "$timestamp,CPU,$cpu_usage" >> $LOG_FILE
    echo "$timestamp,MEMORY,$memory_usage" >> $LOG_FILE
    echo "$timestamp,DISK,$disk_usage" >> $LOG_FILE
}

# Function to preprocess the log file and separate data into CPU, MEMORY, and DISK files
preprocess_data() {
    # Extract CPU, MEMORY, and DISK data into separate files
    awk -F, '$2 == "CPU" {print $1, $3}' $LOG_FILE > "$REPORT_DIR/cpu_data.log"
    awk -F, '$2 == "MEMORY" {print $1, $3}' $LOG_FILE > "$REPORT_DIR/memory_data.log"
    awk -F, '$2 == "DISK" {print $1, $3}' $LOG_FILE > "$REPORT_DIR/disk_data.log"
}

# Function to generate graphical reports
generate_reports() {
    local report_file="$REPORT_DIR/resource_usage_$(date '+%Y%m%d%H%M%S').png"

    # Check if log file is empty
    if [ ! -s "$LOG_FILE" ]; then
        echo "Log file is empty. Skipping report generation."
        return
    fi

    # Preprocess data to separate resource types
    preprocess_data

    # Gnuplot script to plot the pre-processed data
    cat <<EOF > $GRAPH_SCRIPT
set terminal png size 800,600
set output "$report_file"
set title "System Resource Usage"
set xlabel "Time"
set ylabel "Usage (%)"
set xdata time
set timefmt "%Y-%m-%d %H:%M:%S"
set format x "%H:%M"
set grid

# Plot CPU, Memory, and Disk usage from pre-processed files
plot "$REPORT_DIR/cpu_data.log" using 1:2 with lines title "CPU Usage", \
     "$REPORT_DIR/memory_data.log" using 1:2 with lines title "Memory Usage", \
     "$REPORT_DIR/disk_data.log" using 1:2 with lines title "Disk Usage"
EOF

    # Run the Gnuplot script to generate the report
    gnuplot $GRAPH_SCRIPT && echo "Graphical report generated: $report_file"
}

# Function to send alerts
send_alert() {
    local recipient="$ALERT_EMAIL"
    local sender="$ALERT_EMAIL"
    local subject="System Monitor Report"
    local body="Greetings,\n\nWe, Justine Francisco, Jethro Malabar, Lester Dagansina, Joshua Magdagasang, and John Paul Colita, would like to inf>

    if [ $(echo "$cpu_usage > $CPU_THRESHOLD" | bc) -eq 1 ]; then
        body+="CPU Usage: $cpu_usage% (Threshold: $CPU_THRESHOLD%)\n"
    fi
    if [ $(echo "$memory_usage > $MEMORY_THRESHOLD" | bc) -eq 1 ]; then
       body+="Disk Usage: $disk_usage% (Threshold: $DISK_THRESHOLD%)\n"
    fi

    body+="\nThis usage exceeds the threshold of 80%. Please check your system to take necessary actions.\n"

    # Generate the report
    local report_file="$REPORT_DIR/resource_usage_$(date '+%Y%m%d%H%M%S').png"
    generate_reports

    # Create the email content with attachment
    {
        echo "To: $recipient"
        echo "From: $sender"
        echo "Subject: $subject"
        echo "MIME-Version: 1.0"
        echo "Content-Type: multipart/mixed; boundary=\"boundary42\""
        echo
        echo "--boundary42"
        echo "Content-Type: text/plain; charset=UTF-8"
        echo
        echo -e "$body"
        echo "--boundary42"
        echo "Content-Type: image/png; name=\"$(basename $report_file)\""
        echo "Content-Transfer-Encoding: base64"
        echo "Content-Disposition: attachment; filename=\"$(basename $report_file)\""
        echo
        base64 "$report_file"
        echo "--boundary42--"
    } | ssmtp -t

    echo "System Monitor Report sent successfully via email."
}


# Function to check thresholds and trigger alerts
check_thresholds() {
    exceeded=false

    # Ensure numeric comparisons
    if [ $(echo "$cpu_usage > $CPU_THRESHOLD" | bc) -eq 1 ]; then
        exceeded=true
        echo "CPU Usage exceeds threshold sending report via email..."
    fi
    if [ $(echo "$memory_usage > $MEMORY_THRESHOLD" | bc) -eq 1 ]; then
        exceeded=true
        echo "Memory Usage exceeds threshold sending report via email..."
    fi
    if [ "$disk_usage" -gt "$DISK_THRESHOLD" ]; then
        exceeded=true
        echo "Disk Usage exceeds threshold sending report via email..."
    fi

    if [ "$exceeded" = true ] && [ "$SEND_ALERTS" = true ]; then
        send_alert
    fi
}

# Main monitoring loop
while true; do
    log_usage
    check_thresholds
    sleep $LOG_INTERVAL
done