# Runbook: Disk Space Critical

**Runbook ID:** RB-DISK-003  
**Version:** 2.0  
**Last Updated:** April 15, 2026  
**Owner:** Technical Support / On-Call Engineer  
**Approved By:** Elizabeth Ikechukwu  
**Impacted Service:** LizzyCloudLab Support Portal (Production)  
**Severity:** P2 - High  
**Related Incident:** INC-003  

---

## Overview

This runbook is used when disk usage on `support-simulation-server` exceeds the alert threshold of 80% on the root partition (`device_label:cloudimg-rootfs`).

At 96% disk usage the server risks complete disk exhaustion which causes application crashes, failed writes, and potential data loss. In INC-003, a runaway log file consumed 1.6G in `/tmp`, pushing the root partition to 96% before being detected and resolved.

**Goal:** Identify the culprit and free disk space before the partition reaches 100%.

**Do not skip steps. Follow sequentially.**

---

## Alert Trigger

You will receive this alert in **#LizzyCloudLab-incidents** Slack channel:

```
🚨 DISK SPACE ALERT
Disk usage has exceeded 80% on support-simulation-server
Current value: [value]
Time: [timestamp]
```

---

## SLA Targets

| Metric | Target |
|---|---|
| Time to Acknowledge | < 5 minutes |
| Time to Resolve | < 30 minutes |
| Time to Escalate | > 20 minutes without resolution |

---

## Immediate Triage (First 3 Minutes)

SSH into `support-simulation-server` and run these commands in order:

**1. Confirm current disk usage:**
```bash
df -h
```
Focus on the `/dev/root` line -- note the percentage and available space.

**2. Identify the largest top-level directories:**
```bash
du -sh /* 2>/dev/null | sort -rh | head -10
```
In INC-003 this immediately showed `/tmp` at 4.1G as the largest directory.

**3. Drill down into the culprit directory:**

If `/tmp` is the largest:
```bash
du -sh /tmp/* 2>/dev/null | sort -rh | head -10
```

If `/var` is the largest:
```bash
sudo du -sh /var/log/* 2>/dev/null | sort -rh | head -10
```

In INC-003 this revealed:
```
1.6G    /tmp/app-runaway.log
```

---

## Decision Tree

```
What is consuming the disk?
    │
    ├── Large file in /tmp?
    │       └── Go to Resolution: Run Cleanup Script
    │
    ├── Large log files in /var/log?
    │       └── Go to Resolution: Run Cleanup Script
    │           (script handles journal logs automatically)
    │
    ├── Application data files?
    │       └── Confirm with team before deleting
    │           Consider moving to S3 before removing
    │
    └── Unknown large files?
            └── DO NOT delete without identifying what they are
                Escalate if unsure
```

---

## Resolution

### Option A: Automated Cleanup Script (Recommended)

```bash
sudo /home/ubuntu/cleanup-disk.sh
```

**What the script does:**
1. Shows disk usage before cleanup
2. Removes all files over 100M in `/tmp`
3. Clears journal logs older than 2 days
4. Shows disk usage after cleanup

**Expected successful output:**
```
=== Disk Cleanup Script ===
Before cleanup:
Filesystem      Size  Used Avail Use% Mounted on
/dev/root       6.8G  6.5G  281M  96% /

Removing large files in /tmp...
Clearing journal logs older than 2 days...
Vacuuming done, freed 26.9M of archived journals

After cleanup:
Filesystem      Size  Used Avail Use% Mounted on
/dev/root       6.8G  4.9G  1.9G  72% /

=== Cleanup Complete ===
```

**Check disk after running:**
```bash
df -h
```
Disk should be below 70% after cleanup.

---

### Option B: Manual Cleanup

**Step 1: Identify and confirm the file:**
```bash
ls -lh /tmp/[filename]
```

**Step 2: Remove the large file:**
```bash
rm /tmp/[filename]
```

**Step 3: Clear old journal logs:**
```bash
sudo journalctl --vacuum-time=2d
```

**Step 4: Verify disk usage:**
```bash
df -h
```

---

## Verification Checklist

- [ ] `df -h` shows root partition below 70%
- [ ] `sudo systemctl status support-lab-app` shows `active (running)`
- [ ] `sudo systemctl status nginx` shows `active (running)`
- [ ] https://support.lizzycloudlab.online loads normally
- [ ] Datadog disk monitor returns to OK status in Slack

---

## Common Gotchas

- **Monitor device scope** -- In INC-003 the Datadog disk monitor was initially watching loop devices instead of the root partition. This caused delayed alerting. Always verify the monitor is filtering by `device_label:cloudimg-rootfs`. If the alert fires for an unexpected device, check the monitor configuration in Datadog before investigating the wrong partition.
- **Disk fills up again immediately** -- If disk refills within minutes of cleanup, an active process is writing continuously. Find and stop that process -- just cleaning is not enough.
- **Nginx fails to restart** -- If Nginx was stopped during the disk full period, it may fail to restart even after disk is freed. Run the Nginx runbook (RB-NGINX-001) after resolving disk.
- **Journal logs** -- `/var/log/journal` can grow very large silently. The cleanup script handles this but check manually if disk usage in `/var` is unexpectedly high.
- **Small root partition** -- The root partition on this server is only 6.8G. This is undersized for production. A 20G EBS volume is recommended to provide adequate headroom.

---

## Escalation Criteria

Escalate to senior engineer if:

- Disk fills up again immediately after cleanup -- active runaway process needs to be identified
- Large files belong to the application or database -- do not delete without developer confirmation
- Root partition needs to be expanded -- requires AWS EBS volume resize
- Disk is at 100% and the application has already crashed -- recovery may require additional steps

**Escalation message:**
```
Following RB-DISK-003. Disk critical on support-simulation-server.
Cleanup script ran -- disk freed but filling again immediately.
df -h and du output attached.
Need immediate assistance.
```

---

## Post-Incident Activities

1. Note what was consuming the disk and why the file grew without rotation
2. Verify logrotate is working: `sudo logrotate -v /etc/logrotate.d/app-cleanup`
3. Verify cron job is active: `crontab -l`
4. File incident report using INC-003 template
5. If disk fills up repeatedly -- raise EBS volume expansion request to infrastructure team
6. Update this runbook if a new gotcha was discovered

---

## Cron Automation

A cron job runs the cleanup script automatically every day at 02:00 WAT:

```bash
0 2 * * * /home/ubuntu/cleanup-disk.sh >> /var/log/cleanup.log 2>&1
```

Check the log to see recent automated cleanup history:

```bash
tail -30 /var/log/cleanup.log
```

---

## Important Note on Datadog Monitor Configuration

The disk monitor on this server is scoped to `device_label:cloudimg-rootfs` -- the root partition only. This filter was added during INC-003 after discovering the monitor was previously evaluating loop devices instead of the root partition.

If you suspect the monitor is misconfigured, verify in Datadog:
- Monitor: `[PROD] Disk Space Critical - support-simulation-server`
- Filter should show: `device_label:cloudimg-rootfs`

---

## Prevention Recommendations

1. Cron cleanup runs daily at 02:00 WAT -- configured and active
2. Logrotate configured at `/etc/logrotate.d/app-cleanup` -- rotates files over 100M
3. Datadog disk monitor scoped to root partition -- corrected during INC-003
4. Recommend expanding EBS root volume from 6.8G to 20G minimum

---

## Related Resources

- Incident Report: [INC-003-disk-space-critical.md](../incidents/INC-003-disk-space-critical.md)
- Cleanup Script: [cleanup-disk.sh](../scripts/cleanup-disk.sh)
- Datadog Monitor: `[PROD] Disk Space Critical - support-simulation-server`
- Cron Log: `/var/log/cleanup.log`
- Logrotate Config: `/etc/logrotate.d/app-cleanup`

---

## Runbook Version History

| Version | Date | Changes |
|---|---|---|
| v2.0 | April 15, 2026 | Added gotchas including monitor misconfiguration finding from INC-003, escalation message, expected script output, version history |
| v1.0 | April 13, 2026 | Initial version created after INC-003 |
