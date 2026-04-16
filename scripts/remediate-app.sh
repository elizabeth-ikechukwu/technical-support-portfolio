#!/bin/bash

ENDPOINT="https://support.lizzycloudlab.online"
SERVICE="support-lab-app"
LOGFILE="/var/log/app-remediation.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

HTTP_CODE=$(curl -o /dev/null -s -w "%{http_code}" --max-time 10 "$ENDPOINT")

if [ "$HTTP_CODE" != "200" ]; then
    echo "[$TIMESTAMP] WARNING: $ENDPOINT returned HTTP $HTTP_CODE. Restarting $SERVICE." >> "$LOGFILE"
    sudo systemctl restart "$SERVICE"
    sleep 5

    RECHECK=$(curl -o /dev/null -s -w "%{http_code}" --max-time 10 "$ENDPOINT")

    if [ "$RECHECK" == "200" ]; then
        echo "[$TIMESTAMP] RECOVERY: $SERVICE restarted successfully. HTTP $RECHECK confirmed." >> "$LOGFILE"
    else
        echo "[$TIMESTAMP] CRITICAL: Restart attempted but $ENDPOINT still returning HTTP $RECHECK. Manual intervention required." >> "$LOGFILE"
    fi
else
    echo "[$TIMESTAMP] OK: $ENDPOINT returned HTTP $HTTP_CODE." >> "$LOGFILE"
fi