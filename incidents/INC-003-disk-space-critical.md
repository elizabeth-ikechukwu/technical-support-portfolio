# INC-003 -- Disk Space Critical: Runaway Log File

**Classification:** P2 - High  
**Status:** Resolved  
**Date:** April 13, 2026  
**Reported by:** Ikechukwu Elizabeth  
**Environment:** support-simulation-server / https://support.lizzycloudlab.online

---

## Summary

A disk space critical incident was detected proactively by Datadog monitoring before application failure occurred. Root partition usage reached 96%, caused by a runaway log file consuming 1.6G in /tmp with no size limit or rotation policy. The incident was resolved using a reusable cleanup script and two permanent prevention measures were implemented -- automated daily cleanup via cron and log rotation via logrotate. A secondary monitoring misconfiguration was identified and corrected during the investigation, improving future detection reliability.

---

## Timeline

| Time (WAT) | Event |
|---|---|
| ~16:10 | Log file injection began |
| 16:21:53 | Disk crossed 80% -- Datadog alert threshold breached |
| 16:23 | Slack alert fired to #incidents channel |
| 16:23 | On-call engineer acknowledged alert |
| ~16:41 | Cleanup script executed -- large file removed |
| 17:04:05 | Datadog monitor returned to OK status |

---

## SLA Performance

| Metric | Time (WAT) | Details |
|---|---|---|
| Incident Start | ~16:10 | Log file injection began |
| Warning Threshold Breached | 16:43:53 | Disk crossed 70% |
| Alert Threshold Breached | 16:21:53 | Disk crossed 80% |
| Slack Notification | 16:23 | #incidents channel notified |
| Cleanup Script Executed | ~16:41 | Large file removed |
| Monitor OK Restored | 17:04:05 | Disk confirmed below 70% |
| MTTD | ~11 minutes | Injection to alert fired |
| MTTR | ~43 minutes | Alert fired to monitor OK |
| Total Duration | ~54 minutes | Full incident lifecycle |

**Note on MTTR:** Total elapsed time was longer than the P2 target due to a Datadog monitor misconfiguration discovered during investigation -- the monitor was watching loop devices instead of the root partition. Diagnosing and correcting this misconfiguration was completed as part of the resolution process. This added real-world troubleshooting value and strengthened future monitoring reliability. Excluding the monitor correction, active remediation time was under 20 minutes.

---

## Root Cause

A runaway application process writing continuously to `/tmp/app-runaway.log` without any size limit or rotation policy. In a production environment this pattern would be caused by an application stuck in an error loop, a verbose debug logging mode left enabled in production, or a batch job writing output without cleanup. The investigation sequence -- confirm partition usage, identify largest directories, drill down to specific files -- applies regardless of the underlying cause.

---

## Impact

- Root partition disk usage reached 96% -- 6.5G used of 6.8G total, leaving only 281M free
- At this level the server was at risk of complete disk exhaustion which would have caused application crashes, failed writes, and potential data loss
- The Node.js status page and Nginx reverse proxy remained operational during the incident but would have failed if disk reached 100%
- Customer communication: In a production scenario a status page update would be published if any customer-visible degradation occurred, with a post-incident summary distributed within 24 hours of resolution

---

## Additional Finding: Monitor Misconfiguration

During this incident a secondary issue was discovered: the Datadog disk monitor was not filtered by device and was evaluating an average across all mount points including loop devices. This caused delayed alerting when disk first hit 96% earlier in the session.

**Corrective action:** The monitor was updated by adding `device_label:cloudimg-rootfs` as a filter, scoping it specifically to the root partition. This is documented as a separate finding and must be noted in future monitoring setup runbooks as a required configuration step.

This finding demonstrates the value of thorough incident investigation -- the monitoring gap would have remained undetected without the hands-on triage process.

---

## Investigation

Upon receiving the Slack alert, triage was performed in the following sequence:

1. **Confirmed the symptom** -- `df -h` showed root partition at 96%, only 281M available
2. **Identified the culprit** -- `du -sh /tmp/* | sort -rh | head -10` revealed a single file consuming 1.6G:
```
1.6G    /tmp/app-runaway.log
```
3. **Confirmed root cause** -- all other files in /tmp were under 12K. Root cause was immediately clear: a runaway application process writing continuously to `/tmp/app-runaway.log` without any size limit or rotation policy

---

## Resolution

Rather than manually deleting the file, a reusable Bash cleanup script was created and executed:

**Script location:** `/home/ubuntu/cleanup-disk.sh`

```bash
#!/bin/bash
echo "=== Disk Cleanup Script ==="
echo "Before cleanup:"
df -h /

echo "Removing large files in /tmp..."
find /tmp -type f -size +100M -delete

echo "Clearing journal logs older than 2 days..."
sudo journalctl --vacuum-time=2d

echo "After cleanup:"
df -h /

echo "=== Cleanup Complete ==="
```

**Results:**
- Removed 1.6G `/tmp/app-runaway.log`
- Freed 26.9M of archived journal logs
- Disk dropped from 96% to 72%
- Monitor returned to OK at 17:04:05 WAT

---

## Prevention Implemented

**1. Cron job -- automated daily cleanup:**

```bash
0 2 * * * /home/ubuntu/cleanup-disk.sh >> /var/log/cleanup.log 2>&1
```

Runs every day at 02:00 WAT. Output logged to `/var/log/cleanup.log` for audit trail.

**2. Logrotate -- automatic log rotation:**

Config file: `/etc/logrotate.d/app-cleanup`

```
/tmp/*.log {
    daily
    rotate 3
    compress
    missingok
    notifempty
    size 100M
}
```

Any log file in /tmp exceeding 100M will be automatically rotated, keeping only 3 compressed copies.

---

## Prevention Recommendations

1. **Monitor device scoping** -- always verify Datadog disk monitors are scoped to the correct device using `device_label` or `device_name` tags during initial setup -- prevents monitoring blind spots
2. **Application-level log limits** -- configure log rotation at the application level, not just the OS level -- defense in depth against runaway log growth
3. **Disk capacity** -- 6.8G root partition is undersized for production; recommend expanding EBS volume to 20G minimum to provide adequate headroom
4. **Warning threshold action** -- warning threshold is set at 70%; establish a clear procedure requiring on-call engineer action at warning level before alert threshold is breached
5. **Pre-deployment checklist** -- add disk space verification to deployment runbooks to confirm adequate headroom before any release

---

## Evidence

| File | Description |
|---|---|
| 01-server-healthy-before-incident | Datadog monitor showing OK status, disk at ~58% |
| 02-monitor-alert-firing | Datadog monitor showing ALERT, disk at 95%+ |
| 03-slack-alert-fired | Slack #incidents showing DISK SPACE ALERT at 16:23 WAT |
| 04-investigation-df-h | df -h showing root partition at 96% |
| 05-investigation-du-sh | du -sh showing 1.6G app-runaway.log as culprit |
| 06-cleanup-script-resolution | Cleanup script output, disk recovered from 96% to 72% |
| 07-cron-job-configured | crontab -l confirming daily automated cleanup |
| 08-monitor-recovery-ok | Datadog monitor OK at 17:04:05 WAT, full incident graph visible |
