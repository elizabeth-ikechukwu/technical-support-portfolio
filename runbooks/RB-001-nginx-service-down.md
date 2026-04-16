# Runbook: Nginx Service Down

**Runbook ID:** RB-NGINX-001  
**Version:** 2.0  
**Last Updated:** April 16, 2026  
**Owner:** Technical Support / On-Call Engineer  
**Approved By:** Elizabeth Ikechukwu  
**Impacted Service:** LizzyCloudLab Support Portal (Production)  
**Severity:** P1 - Critical  
**Related Incident:** INC-001  

---

## Overview

This runbook is used when the Nginx web server becomes unresponsive or stops on `support-simulation-server`.

When Nginx is down, the entire application at **https://support.lizzycloudlab.online** becomes unreachable. Unlike a 502 Bad Gateway where Nginx continues running but cannot reach the upstream application, this incident involves Nginx itself as the failed component. No upstream errors are generated because the failure occurs before any request can be proxied.

**Goal:** Restore service in under 15 minutes.

**Do not skip steps. Follow sequentially.**

---

## Alert Trigger

You will receive two simultaneous alerts in **#LizzyCloudLab-incidents** Slack channel:

**Alert 1 -- Process Check:**
```
🚨 [PROD] Nginx Process Down
PROCS CRITICAL: 0 processes found for nginx
Host: support-simulation-server
```

**Alert 2 -- Synthetics HTTP Check:**
```
🚨 Synthetics Alert
support.lizzycloudlab.online - HTTP Check
Status: Alert
Assertion failed: status code is 200
```

Both monitors firing simultaneously is the strongest possible detection signal -- infrastructure layer and user experience layer both confirming the outage. If only one fires, the other may still be recovering data. Treat either alert as a P1 requiring immediate response.

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

**1. Check disk space first -- before anything else:**
```bash
df -h
```
Look for `/` being 95%+ full. A full disk will silently prevent Nginx from restarting even if config is valid.

**2. Check Nginx service status:**
```bash
sudo systemctl status nginx
```
- **Down:** `inactive (dead)` or `failed`
- **Up:** `active (running)`

**3. Confirm port state -- fastest single-command confirmation:**
```bash
sudo ss -tlnp | grep -E '80|443'
```
- **Healthy:** Nginx listening on both ports
- **Down:** No output returned -- nothing listening on 80 or 443

**4. Check recent journal logs:**
```bash
sudo journalctl -u nginx --since "1 hour ago" --no-pager
```
Look for: the exact timestamp the service stopped, any error messages preceding the stop, config errors

---

## Decision Tree

```
Is Nginx inactive (dead) or failed?
    │
    ├── YES → Is disk full? (df -h shows / at 95%+)
    │               │
    │               ├── YES → Resolve disk first using RB-DISK-003
    │               │         Then return here and restart Nginx
    │               │
    │               └── NO → Go to Resolution Section
    │
    └── NO
            └── Is Nginx active but connections = 0?
                    │
                    ├── YES → Check Nginx error logs
                    │         sudo tail -50 /var/log/nginx/error.log
                    │         If upstream errors → check Node.js app (RB-502-004)
                    │
                    └── NO → Run: sudo nginx -t
                                    │
                                    ├── Config OK → False positive, monitor for 5 min
                                    └── Config broken → Fix error → Restart
```

---

## Resolution

### Option A: Automated Recovery Script (Recommended)

```bash
sudo /home/ubuntu/incident-response-nginx.sh
```

**What the script does:**
1. Logs incident response trigger with timestamp to `/var/log/incident-response.log`
2. Tests Nginx configuration with `nginx -t`
3. Restarts Nginx with `systemctl restart nginx`
4. Waits 3 seconds and checks active status via `systemctl is-active nginx`
5. If active -- logs RESOLVED with timestamp
6. If not active -- logs ESCALATION NEEDED

**Expected successful output:**
```
[2026-04-16 04:53:44] Incident response triggered: Nginx down
[2026-04-16 04:53:44] Testing Nginx config...
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
[2026-04-16 04:53:45] Attempting Nginx restart...
[2026-04-16 04:53:48] Nginx status after restart: active
[2026-04-16 04:53:48] RESOLVED: Nginx is back online.
```

If you see `ESCALATION NEEDED` -- proceed to manual steps or escalate immediately.

**Check the full log:**
```bash
tail -20 /var/log/incident-response.log
```

---

### Option B: Manual Recovery

**Step 1: Validate configuration:**
```bash
sudo nginx -t
```
- Success: `configuration test successful` → proceed
- Failure: fix the reported config error before restarting

**Step 2: Restart Nginx:**
```bash
sudo systemctl restart nginx
```

**Step 3: Verify service:**
```bash
sudo systemctl status nginx
sudo ss -tlnp | grep -E '80|443'
```

**Step 4: Verify from browser:**

Visit https://support.lizzycloudlab.online -- status page should load.

---

## Verification Checklist

- [ ] `systemctl status nginx` shows `active (running)`
- [ ] `sudo ss -tlnp | grep -E '80|443'` shows Nginx listening on both ports
- [ ] https://support.lizzycloudlab.online loads successfully in browser
- [ ] Datadog `[PROD] Nginx Process Down` monitor returns to OK in Slack
- [ ] Datadog Synthetics HTTP Check returns to OK in Slack
- [ ] `/var/log/incident-response.log` shows RESOLVED entry with timestamp

---

## Common Gotchas

- **Disk full** -- Nginx cannot write its PID file or logs if disk is at 100%. Always run `df -h` before attempting restart. If disk is full, resolve using RB-DISK-003 first then return here.
- **Process check vs metric monitor** -- The previous `nginx.net.connections` metric monitor was unreliable because connection counts do not consistently drop to zero when Nginx stops. It was replaced with a process check monitor during INC-001. If you see the metric monitor alerting but the process check is OK -- investigate before acting.
- **Port conflict** -- Another process may have taken port 80 or 443. Run `sudo ss -tlnp | grep -E '80|443'` to identify the occupying process before restarting.
- **Config syntax error** -- A recent config change may have broken syntax. Always run `sudo nginx -t` before restarting. The remediation script does this automatically.
- **SSL certificate issue** -- Certbot certificate may have expired. Check `/etc/letsencrypt/live/support.lizzycloudlab.online/` for certificate validity dates if Nginx fails to restart after config test passes.
- **Node.js app still running** -- During INC-001 the Node.js application continued running on port 3000 throughout the Nginx outage. Restarting Nginx is sufficient -- do not restart the application unless separately indicated.

---

## Escalation Criteria

Escalate to senior engineer if:

- Nginx config test fails and you cannot identify the error
- Nginx restarts but immediately crashes again -- check `journalctl -u nginx -n 20`
- Port 80 or 443 is occupied by an unknown process
- Disk is full and cleanup does not free enough space
- SSL certificate has expired
- Both Datadog monitors recover but the browser still shows an error

**Escalation message:**
```
Following RB-NGINX-001. Nginx down on support-simulation-server.
Manual restart attempted -- failed.
Script output and logs attached.
Need immediate assistance.
```

---

## Post-Incident Activities

1. Record exact downtime -- detection time to resolution time
2. Review `/var/log/incident-response.log` for full action timeline
3. File incident report using INC-001 template
4. Confirm both Datadog monitors -- process check and Synthetics -- returned to OK
5. Identify root cause and update prevention measures
6. Update this runbook if a new gotcha was discovered

---

## Monitoring Configuration

**Process Check Monitor:** `[PROD] Nginx Process Down`
- Tracks nginx process count directly on `host:support-simulation-server`
- Fires when process count = 0
- Delivers structured Slack alert with SSH command, action steps, and runbook link

**Synthetics HTTP Check:** `support.lizzycloudlab.online HTTP Check`
- External HTTP GET from AWS us-east-1 every 1 minute
- Fires when status code assertion fails (non-200 response)
- Provides external validation that outage is customer-visible

**Important:** Use process check monitors for detecting stopped services -- not metric-based monitors. Metrics can lag or remain non-zero even when the service is down. This was confirmed during INC-001.

---

## Prevention Recommendations

1. **Dual-layer monitoring** -- process check and Synthetics endpoint check both configured and active -- no single point of detection failure
2. **Systemd restart policy** -- `Restart=on-failure` configured -- Nginx auto-restarts on unexpected process termination
3. **Nginx config validation** -- always run `nginx -t` before any restart -- the remediation script does this automatically
4. **Deployment verification** -- add Nginx service status check to all deployment runbooks

---

## Related Resources

- Incident Report: [INC-001-nginx-service-failure.md](../incidents/INC-001-nginx-service-failure.md)
- Recovery Script: [incident-response-nginx.sh](../scripts/incident-response-nginx.sh)
- Datadog Process Monitor: `[PROD] Nginx Process Down - support-simulation-server`
- Datadog Synthetics: `support.lizzycloudlab.online HTTP Check`
- Nginx Config: `/etc/nginx/sites-available/support-lab`
- Incident Log: `/var/log/incident-response.log`

---

## Runbook Version History

| Version | Date | Changes |
|---|---|---|
| v2.0 | April 16, 2026 | Updated to reflect dual-monitor detection from INC-001 re-simulation. Replaced metric monitor references with process check monitor. Added Synthetics alert trigger. Added Node.js app behaviour note to gotchas. Added monitoring configuration section. |
| v1.0 | April 12, 2026 | Initial version |
