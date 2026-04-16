# INC-002 -- High CPU Usage: Runaway Process

**Classification:** P2 - High  
**Status:** Resolved  
**Date:** April 13, 2026  
**Reported by:** Ikechukwu Elizabeth  
**Environment:** support-simulation-server / https://support.lizzycloudlab.online

---

## Summary

A runaway process incident consuming 95-98% CPU across both vCPUs was detected proactively by Datadog monitoring before any customer-facing degradation occurred. The on-call engineer identified and terminated two offending stress worker processes within 3 minutes of alert notification. Following resolution, an automated CPU remediation script was developed, tested, and deployed via cron to prevent recurrence -- eliminating the need for manual intervention in future incidents of this class.

---

## Timeline

| Time (WAT) | Event |
|---|---|
| 10:06:00 | Stress processes launched -- CPU begins climbing |
| 10:11:30 | Datadog CPU monitor triggered -- average CPU 90.859% |
| 10:12:00 | Slack alert fired to #incidents channel |
| 10:12:00 | On-call engineer acknowledged alert |
| 10:14:25 | PIDs 1598769 and 1598770 terminated -- CPU returned to 0% |
| 10:15:30 | Datadog monitor returned to OK status |

---

## SLA Performance

| Metric | Time (WAT) | Details |
|---|---|---|
| Incident Start | 10:06:00 | Stress processes launched |
| Alert Fired | 10:11:30 | Datadog detected CPU > 85% |
| Slack Notification | 10:12:00 | #incidents channel notified |
| Process Killed | 10:14:25 | PIDs 1598769 and 1598770 terminated |
| Monitor OK Restored | 10:15:30 | Datadog confirmed full recovery |
| MTTD | ~5.5 minutes | Inject to alert fired |
| MTTR | ~3 minutes | Alert fired to process killed |
| Total Incident Duration | ~9.5 minutes | Inject to full recovery |

SLA assessment: Both detection and resolution were within acceptable thresholds for a P2 incident. Automated alerting via Datadog performed as expected with no manual intervention required for detection.

---

## Root Cause

Two runaway stress worker processes consuming 100% of available CPU across both vCPUs. In a production environment this pattern would indicate a runaway application process, a poorly optimized batch job, or a compute-intensive script triggered without resource limits. The investigation sequence -- confirm symptom, identify process, establish ownership, verify root cause -- applies regardless of the underlying cause.

---

## Impact

- Server CPU sustained at 95-98% across both vCPUs for approximately 8 minutes
- No application outage occurred -- the status page remained accessible throughout
- Sustained high CPU would have caused service degradation and eventual unresponsiveness for any running workloads
- Customer communication: In a production scenario, a proactive status update would be published if degradation was customer-visible, with a post-incident summary distributed within 24 hours

---

## Investigation

Upon receiving the Slack alert, triage was performed in the following sequence:

1. **Confirmed the symptom** -- `top -b -n1 | head -20` at 10:07:49 WAT showed 95.5% CPU in use, load average 1.37, with 3 running tasks
2. **Identified the offending processes** -- `ps aux --sort=-%cpu | head -10` revealed two stress worker processes (PID 1598769 and PID 1598770) each consuming approximately 95% CPU, both started at 10:06 WAT
3. **Confirmed root cause** -- two runaway stress worker processes consuming 100% of available CPU across both vCPUs

---

## Resolution

Both offending processes were terminated using:

```bash
kill 1598769 1598770
```

CPU immediately returned to 0.0% utilization confirmed by `top -b -n1 | head -5` at 10:14:25 WAT. Datadog monitor status returned to OK at 10:15:30 WAT.

---

## Post-Incident: Automated Remediation Implemented

Following manual resolution, a CPU remediation script was written and tested on April 14, 2026 to automate detection and termination of runaway processes in future incidents.

**Script location:** `/home/ubuntu/cpu-remediation.sh`

```bash
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
```

**Test results (April 14, 06:00 WAT):** Script successfully detected stress processes at 95.8% CPU and terminated them automatically. CPU returned to 100% idle immediately after execution.

**Cron job configured:**

```bash
*/5 * * * * /home/ubuntu/cpu-remediation.sh >> /var/log/cpu-remediation.log 2>&1
```

All remediation actions logged to `/var/log/cpu-remediation.log` for audit trail.

---

## Prevention Recommendations

1. **Automated remediation** -- CPU remediation script deployed and scheduled via cron every 5 minutes -- immediate recurrence prevention in place
2. **Resource limits** -- implement `ulimit` or cgroups to cap CPU usage per process in production, preventing any single process from consuming all available compute
3. **Process-level monitoring** -- implement alerting on unknown high-CPU processes by name, not just aggregate CPU percentage -- enables faster identification without manual `ps aux` investigation
4. **Runbook** -- document the triage sequence (confirm → identify → isolate → terminate → verify) as a formal runbook for all on-call engineers
5. **Capacity review** -- schedule quarterly review of CPU baseline metrics to identify gradual drift before it becomes an incident

---

## Evidence

| File | Description |
|---|---|
| 01-server-healthy-before-incident | Datadog monitor showing OK status before injection |
| 02-stress-test-running | Terminal showing stress process launched at 10:06 WAT |
| 03-dashboard-cpu-spike | Datadog dashboard showing CPU at 98.4% |
| 04-slack-alert-fired | Slack #incidents alert at 10:12 WAT, CPU 90.859% |
| 05-investigation-top | top showing 95.5% CPU at 10:07:49 WAT |
| 06-investigation-ps-aux | ps aux showing PIDs at ~95% CPU |
| 07-kill-process-resolved | kill command executed, CPU returned to 0% idle |
| 08-monitor-recovery-ok | Datadog monitor showing OK restored at 10:15:30 WAT |
| 09-cpu-remediation-script | Script output showing automated detection and termination |
| 10-cron-job-configured | crontab -l showing remediation cron jobs active |
