# Runbook: High CPU Usage

**Runbook ID:** RB-CPU-002  
**Version:** 2.0  
**Last Updated:** April 15, 2026  
**Owner:** Technical Support / On-Call Engineer  
**Approved By:** Elizabeth Ikechukwu  
**Impacted Service:** LizzyCloudLab Support Portal (Production)  
**Severity:** P2 - High  
**Related Incident:** INC-002  

---

## Overview

This runbook is used when CPU usage on `support-simulation-server` exceeds the alert threshold of 85%.

Sustained high CPU causes application slowness and eventual unresponsiveness. In INC-002, two runaway stress worker processes consumed 95-98% CPU across both vCPUs for approximately 8 minutes before being terminated. Early identification and fast process termination prevents customer-visible impact.

**Goal:** Identify and terminate the offending process within 15 minutes.

**Do not skip steps. Follow sequentially.**

---

## Alert Trigger

You will receive this alert in **#LizzyCloudLab-incidents** Slack channel:

```
🚨 HIGH CPU ALERT
CPU usage exceeded 85% on support-simulation-server
Current value: [value]%
Time: [timestamp]
```

---

## SLA Targets

| Metric | Target |
|---|---|
| Time to Acknowledge | < 5 minutes |
| Time to Resolve | < 15 minutes |
| Time to Escalate | > 10 minutes without resolution |

---

## Immediate Triage (First 3 Minutes)

SSH into `support-simulation-server` and run these commands in order:

**1. Confirm current CPU usage and load:**
```bash
top -b -n1 | head -20
```
Look for: overall CPU percentage, load average, number of running tasks

**2. Identify the offending process:**
```bash
ps aux --sort=-%cpu | head -10
```
Look for: any process consuming over 80% CPU, who owns it (`ubuntu` or `root`), when it started

**3. Note the PID, process name, and owner before taking any action.**

In INC-002 this revealed:
```
ubuntu  1598769  95.0  ...  stress
ubuntu  1598770  95.0  ...  stress
```

---

## Decision Tree

```
Is CPU above 85%?
    │
    ├── YES → Identify the process (ps aux --sort=-%cpu | head -10)
    │             │
    │             ├── Unknown process owned by ubuntu?
    │             │       └── Go to Resolution: Run Remediation Script
    │             │
    │             ├── Known application process (node, nginx)?
    │             │       └── Check application logs before killing
    │             │           sudo journalctl -u support-lab-app -n 50
    │             │
    │             └── System process owned by root?
    │                     └── DO NOT KILL -- Escalate immediately
    │
    └── NO → Alert may have been transient
              Monitor for 5 minutes
              If CPU drops below 70% → close as auto-resolved
              If CPU stays elevated → continue investigation
```

---

## Resolution

### Option A: Automated Remediation Script (Recommended)

```bash
sudo /home/ubuntu/cpu-remediation.sh
```

**What the script does:**
1. Shows top CPU processes before action
2. Finds all processes above 80% CPU owned by the `ubuntu` user
3. Kills each offending process
4. Shows CPU status after action

**Expected successful output:**
```
=== CPU Remediation Script ===
Timestamp: Mon Apr 13 10:14:00 WAT 2026

Top CPU processes before action:
ubuntu  1598769  95.0  ...  stress
ubuntu  1598770  95.0  ...  stress

High CPU processes found. Terminating...
Killing PID: 1598769
Killing PID: 1598770

CPU status after action:
%Cpu(s):  0.0 us,  0.3 sy,  0.0 ni, 99.7 id
=== Done ===
```

**Important scope limitation:** The script only targets processes owned by the `ubuntu` user. It will NOT kill system processes or root-owned processes. If the offending process is root-owned -- escalate immediately.

**Check the cron log to see if automated remediation already fired:**
```bash
tail -30 /var/log/cpu-remediation.log
```

---

### Option B: Manual Termination

**Step 1: Identify the PID:**
```bash
ps aux --sort=-%cpu | head -10
```

**Step 2: Kill the offending process:**
```bash
kill [PID]
```

If the process does not respond:
```bash
kill -9 [PID]
```

**Step 3: Verify CPU returned to normal:**
```bash
top -b -n1 | head -5
```

CPU idle should be above 80%.

---

## Verification Checklist

- [ ] `top -b -n1 | head -5` shows CPU idle above 80%
- [ ] `ps aux --sort=-%cpu | head -5` shows no process above 80% CPU
- [ ] https://support.lizzycloudlab.online loads and responds normally
- [ ] Datadog CPU monitor returns to OK status in Slack
- [ ] `/var/log/cpu-remediation.log` shows termination entry

---

## Common Gotchas

- **Script scope** -- The remediation script only kills `ubuntu` user processes. If a root process is consuming CPU the script will report "No high CPU processes found" even though CPU is high. Check `ps aux` manually and escalate.
- **Process respawns** -- If the process restarts immediately after being killed, a parent process is relaunching it. Killing the child won't help -- you need to identify and stop the parent process.
- **CPU spike is the application itself** -- If `node` is the high CPU process, do not kill it blindly. Check application logs first -- there may be an infinite loop or heavy query causing it.
- **Multiple offenders** -- If many processes are each consuming moderate CPU (e.g., 20% each), the script may not catch them. Review `ps aux --sort=-%cpu` carefully and kill manually.
- **Load average vs CPU** -- High load average with low CPU % indicates I/O wait, not a CPU problem. Check disk I/O separately.

---

## Escalation Criteria

Escalate to senior engineer if:

- The offending process is root-owned or a system process
- The process restarts immediately after being killed
- CPU stays high after terminating the process -- indicates multiple offenders or deeper issue
- The Node.js application itself is consuming high CPU -- may indicate a code-level issue requiring a developer
- Load average stays above 2.0 after CPU appears normal

**Escalation message:**
```
Following RB-CPU-002. High CPU on support-simulation-server.
Remediation script ran -- process killed but CPU remains elevated.
ps aux output and logs attached.
Need immediate assistance.
```

---

## Post-Incident Activities

1. Note the process name, PID, owner, and what caused it to run
2. Check `/var/log/cpu-remediation.log` for full automated remediation history
3. File incident report using INC-002 template
4. If same process type recurs -- consider adding resource limits via `ulimit` or `cgroups`
5. Update this runbook if a new gotcha was discovered

---

## Cron Automation

A cron job runs the remediation script automatically every 5 minutes:

```bash
*/5 * * * * /home/ubuntu/cpu-remediation.sh >> /var/log/cpu-remediation.log 2>&1
```

Always check this log first -- automated remediation may have already resolved the issue before you received the alert.

---

## Prevention Recommendations

1. CPU remediation cron job runs every 5 minutes -- configured and active
2. Datadog CPU monitor alerts at > 85% average over 5 minutes -- configured
3. Consider implementing `ulimit` to cap CPU per process in production
4. Review CPU baseline quarterly to detect gradual drift

---

## Related Resources

- Incident Report: [INC-002-high-cpu-runaway-process.md](../incidents/INC-002-high-cpu-runaway-process.md)
- Remediation Script: [cpu-remediation.sh](../scripts/cpu-remediation.sh)
- Datadog Monitor: `[PROD] High CPU Usage - support-simulation-server`
- Cron Log: `/var/log/cpu-remediation.log`

---

## Runbook Version History

| Version | Date | Changes |
|---|---|---|
| v2.0 | April 15, 2026 | Added gotchas, escalation message, expected script output, scope limitation note, version history |
| v1.0 | April 13, 2026 | Initial version created after INC-002 |
