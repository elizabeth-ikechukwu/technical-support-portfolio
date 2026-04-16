#!/bin/bash
echo "=== CPU Remediation Script ==="
echo "Timestamp: $(date)"
echo ""
echo "Top CPU processes before action:"
ps aux --sort=-%cpu | head -5

# Find processes above 80% CPU owned by ubuntu user
HIGH_CPU_PIDS=$(ps aux | awk 'NR>1 && $3>80.0 && $1=="ubuntu" {print $2}')

if [ -z "$HIGH_CPU_PIDS" ]; then
    echo "No high CPU processes found."
else
    echo "High CPU processes found. Terminating..."
    for PID in $HIGH_CPU_PIDS; do
        echo "Killing PID: $PID"
        kill $PID
    done
fi

echo ""
echo "CPU status after action:"
top -b -n1 | head -5
echo "=== Done ==="