# Runbook: Application 502 Bad Gateway

**Runbook ID:** RB-502-004  
**Version:** 2.0  
**Last Updated:** April 15, 2026  
**Owner:** Technical Support / On-Call Engineer  
**Approved By:** Elizabeth Ikechukwu  
**Impacted Service:** LizzyCloudLab Support Portal (Production)  
**Severity:** P2 - High  
**Related Incident:** INC-004  

---

## Overview

This runbook is used when the application at **https://support.lizzycloudlab.online** returns 502 Bad Gateway errors.

A 502 error means Nginx is running but cannot reach the Node.js application on port 3000. In INC-004, the Node.js application process stopped while Nginx continued running -- causing all requests to return 502. Datadog Synthetics detected the failure within 1 minute and the automated remediation script restored service without manual intervention.

> **Critical reminder: A 502 error does NOT mean Nginx is broken. It means the upstream Node.js application on port 3000 is unreachable. Always check the application first.**

**Goal:** Restore HTTP 200 response within 15 minutes.

**Do not skip steps. Follow sequentially.**

---

## Alert Trigger

You will receive this alert in **#LizzyCloudLab-incidents** Slack channel via Datadog Synthetics:

```
🚨 Synthetics Alert
support.lizzycloudlab.online - HTTP Check
Status: Alert
Assertion failed: status code is 200
```

Or a 502 error may be reported directly by a user in a support ticket.

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

**1. Check if anything is listening on port 3000 -- this is your fastest diagnostic:**
```bash
sudo ss -tlnp | grep 3000
```
- **No output** → Application is down. Go to Resolution immediately.
- **Output showing node** → Application process is running but may be unresponsive.

**2. Check application service status:**
```bash
sudo systemctl status support-lab-app
```
- **`inactive (dead)`** → Application crashed or was stopped. Go to Resolution.
- **`active (running)`** → Service is up. Check application logs for errors.

**3. Confirm Nginx upstream failure in error logs:**
```bash
sudo tail -20 /var/log/nginx/error.log
```

In INC-004 this showed:
```
connect() failed (111: Connection refused) while connecting to upstream,
upstream: "http://127.0.0.1:3000/"
```

This confirms Nginx cannot reach port 3000 -- the application is the problem, not Nginx.

---

## Decision Tree

```
Is anything listening on port 3000?
    │
    ├── NO → Application is down
    │           └── Go to Resolution: Run Remediation Script
    │
    └── YES → Application process is running
                  │
                  ├── Check application logs for errors
                  │   sudo journalctl -u support-lab-app -n 50
                  │
                  ├── Application throwing errors?
                  │       └── Restart the service
                  │           sudo systemctl restart support-lab-app
                  │
                  └── Application logs look normal?
                          └── Check Nginx config is pointing to correct port
                              sudo cat /etc/nginx/sites-available/support-lab
                              proxy_pass should be http://localhost:3000
```

---

## Resolution

### Option A: Automated Remediation Script (Recommended)

```bash
sudo /usr/local/bin/remediate-app.sh
```

**What the script does:**
1. Sends HTTP GET to https://support.lizzycloudlab.online
2. If response is not 200 -- restarts `support-lab-app` service
3. Waits 5 seconds and rechecks the endpoint
4. If HTTP 200 confirmed -- logs RECOVERY
5. If still not 200 after restart -- logs CRITICAL and requires manual intervention
6. All actions logged with timestamps to `/var/log/app-remediation.log`

**Expected successful output in log:**
```
[2026-04-14 19:05:20] WARNING: https://support.lizzycloudlab.online returned HTTP 502. Restarting support-lab-app.
[2026-04-14 19:05:25] RECOVERY: support-lab-app restarted successfully. HTTP 200 confirmed.
```

If you see `CRITICAL` in the log -- the automated restart failed. Proceed to manual steps immediately.

**Check the full log:**
```bash
tail -20 /var/log/app-remediation.log
```

**Check if the cron job already fired before your alert:**
```bash
tail -30 /var/log/app-remediation.log
```

---

### Option B: Manual Recovery

**Step 1: Restart the application service:**
```bash
sudo systemctl restart support-lab-app
```

**Step 2: Verify the service is running:**
```bash
sudo systemctl status support-lab-app
```
Should show `active (running)`

**Step 3: Verify port 3000 is now listening:**
```bash
sudo ss -tlnp | grep 3000
```
Should show node listening on port 3000

**Step 4: Verify in browser:**

Visit https://support.lizzycloudlab.online -- status page should load with HTTP 200.

---

## Verification Checklist

- [ ] `sudo ss -tlnp | grep 3000` shows node listening on port 3000
- [ ] `sudo systemctl status support-lab-app` shows `active (running)`
- [ ] https://support.lizzycloudlab.online loads and returns HTTP 200
- [ ] Datadog Synthetics monitor returns to OK status in Slack
- [ ] `/var/log/app-remediation.log` shows RECOVERY entry

---

## Common Gotchas

- **502 is not an Nginx problem** -- The most common mistake is investigating Nginx when the application is the issue. Always check port 3000 first with `ss -tlnp`. In INC-004 Nginx was healthy throughout -- the Node.js process had simply stopped.
- **Systemd restart may have already fired** -- The `support-lab-app` service has `Restart=on-failure` configured. By the time you SSH in, systemd may have already restarted the app. Check `systemctl status support-lab-app` -- if it shows the service restarted recently, verify the endpoint is returning 200 before taking further action.
- **Cron remediation may have already fired** -- The remediation script runs every 5 minutes via cron. Check `/var/log/app-remediation.log` to see if it already resolved the issue.
- **App restarts but crashes again** -- If the application keeps crashing after restart, there is an underlying code or dependency issue. Check `journalctl -u support-lab-app -n 100` for the crash reason and escalate to the development team.
- **Disk full causing app crash** -- If disk is at 100%, the Node.js application cannot write logs and may crash. Check `df -h` first and resolve disk issue using RB-DISK-003 before restarting the app.

---

## Escalation Criteria

Escalate to senior engineer if:

- Application restarts but immediately crashes again -- attach journal logs
- Remediation script logs CRITICAL after restart attempt
- Port 3000 is occupied by a different process -- `ss -tlnp | grep 3000` shows non-node process
- Disk is full -- application cannot start if disk is at 100%
- Application logs show repeated errors that suggest a code-level issue

**Escalation message:**
```
Following RB-502-004. App returning 502 on support-simulation-server.
Remediation script ran -- service restarted but still returning 502.
ss -tlnp, systemctl status, and app logs attached.
Need immediate assistance.
```

---

## Post-Incident Activities

1. Check `/var/log/app-remediation.log` for the full remediation timeline
2. Check application logs to understand why the process stopped: `sudo journalctl -u support-lab-app -n 100`
3. Note whether systemd auto-restart fired before the cron script ran
4. File incident report using INC-004 template
5. If application crashes repeatedly -- escalate to development team with journal logs
6. Update this runbook if a new gotcha was discovered

---

## Automation in Place

**Systemd auto-restart:**
```ini
Restart=on-failure
RestartSec=5s
StartLimitBurst=3
StartLimitIntervalSec=60s
```
Restarts the app within 5 seconds of a crash -- up to 3 attempts per 60-second window.

**Cron health check:**
```bash
*/5 * * * * /usr/local/bin/remediate-app.sh >> /var/log/app-remediation.log 2>&1
```
Checks the live endpoint every 5 minutes and restarts the service if non-200 is detected.

Both layers working together means the application often recovers automatically before any manual intervention is needed.

---

## Prevention Recommendations

1. Systemd restart policy configured -- `Restart=on-failure` active
2. Cron health check runs every 5 minutes -- configured and active
3. Datadog Synthetics HTTP check running every 1 minute from AWS us-east-1
4. Add Nginx upstream health checks to return a custom maintenance page instead of raw 502
5. Add endpoint health check to deployment pipeline to catch failed deployments before customers do

---

## Related Resources

- Incident Report: [INC-004-502-bad-gateway.md](../incidents/INC-004-502-bad-gateway.md)
- Remediation Script: [remediate-app.sh](../scripts/remediate-app.sh)
- Datadog Monitor: Synthetics HTTP Check -- support.lizzycloudlab.online
- App Remediation Log: `/var/log/app-remediation.log`
- Application Service: `support-lab-app`

---

## Runbook Version History

| Version | Date | Changes |
|---|---|---|
| v2.0 | April 15, 2026 | Added gotchas, escalation message, expected log output, automation summary, version history |
| v1.0 | April 14, 2026 | Initial version created after INC-004 |
