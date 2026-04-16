#!/bin/bash
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
LOGFILE="/var/log/incident-response.log"

echo "[$TIMESTAMP] Incident response triggered: Nginx down" | tee -a $LOGFILE

echo "[$TIMESTAMP] Testing Nginx config..." | tee -a $LOGFILE
sudo nginx -t 2>&1 | tee -a $LOGFILE

echo "[$TIMESTAMP] Attempting Nginx restart..." | tee -a $LOGFILE
sudo systemctl restart nginx

sleep 3
STATUS=$(sudo systemctl is-active nginx)
echo "[$TIMESTAMP] Nginx status after restart: $STATUS" | tee -a $LOGFILE

if [ "$STATUS" = "active" ]; then
    echo "[$TIMESTAMP] RESOLVED: Nginx is back online." | tee -a $LOGFILE
else
    echo "[$TIMESTAMP] ESCALATION NEEDED: Nginx failed to restart." | tee -a $LOGFILE
fi