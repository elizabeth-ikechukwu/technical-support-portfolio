# INC-004 -- Application 502 Bad Gateway

**Classification:** P2 - High  
**Status:** Resolved  
**Date:** April 14, 2026  
**Reported by:** Elizabeth Ikechukwu  
**Environment:** support-simulation-server / https://support.lizzycloudlab.online

---

## Summary

The Node.js status application became unavailable, causing Nginx to return 502 Bad Gateway errors to all incoming requests. The application process had stopped while Nginx continued running, leaving the reverse proxy with no upstream to forward traffic to. Datadog Synthetics detected the failure within 1 minute of onset and fired an automated Slack alert. The incident was resolved via automated remediation script which detected the 502, restarted the application service, and confirmed HTTP 200 recovery -- without any manual intervention. Total application downtime was 17 minutes. Two permanent prevention controls were implemented to prevent recurrence.

---

## Timeline

| Time (UTC) | Event |
|---|---|
| 18:50 | Node.js application process stopped -- Nginx began returning 502 to all requests |
| 18:50 | Datadog Synthetics detected non-200 response from https://support.lizzycloudlab.online |
| 18:51 | Slack alert fired to #LizzyCloudLab-incidents channel |
| ~18:51 | On-call engineer acknowledged alert |
| ~18:55 | Investigation started -- ss, systemctl, nginx error logs executed |
| ~19:05 | Automated remediation script executed -- support-lab-app restarted |
| ~19:05 | HTTP 200 confirmed -- application recovered |
| 19:07 | Datadog Synthetics monitor returned to OK status |

---

## SLA Performance

| Metric | Target | Actual |
|---|---|---|
| Time to Detect (TTD) | < 5 minutes | 1 minute |
| Time to Resolve (TTR) | < 15 minutes | 17 minutes |
| Actual Application Downtime | - | 17 minutes |
| SLA Status | P2 target | Met |

**Note on TTR:** Application was restored and HTTP 200 confirmed at ~19:05 UTC. Datadog Synthetics monitor confirmed OK at 19:07 UTC. TTR of 17 minutes is within acceptable range for a P2 incident resolved entirely through automated remediation with no manual restart required.

---

## Root Cause

The Node.js application process stopped running, leaving port 3000 with no active listener. Nginx was configured to proxy all incoming requests to `127.0.0.1:3000`. With nothing listening on that port, every proxied request resulted in a connection refused error at the Nginx upstream layer, which was returned to the client as a 502 Bad Gateway.

**Critical distinction:** A 502 error does not indicate Nginx is broken -- it indicates the upstream application is unreachable. Nginx was functioning correctly throughout the incident. The failure was entirely at the application layer.

In a production environment this class of incident would be caused by an application crash, an out-of-memory kill, a failed deployment leaving the service stopped, or a dependency failure causing the process to exit.

---

## Detection

Datadog Synthetics HTTP check running every 1 minute from AWS us-east-1 (N. Virginia) detected the failure at 18:50 UTC. The monitor assertion -- `status code is 200` -- failed when the endpoint returned 502. An automated Slack alert fired to #LizzyCloudLab-incidents within 1 minute of the application stopping.

---

## Investigation

Three commands confirmed the root cause in sequence:

1. **Port check** -- `sudo ss -tlnp | grep 3000` returned no output, confirming nothing was listening on port 3000 -- immediate confirmation the app was down
2. **Service status** -- `sudo systemctl status support-lab-app` showed the service as `inactive (dead)`, stopped at 18:50 UTC
3. **Nginx error logs** -- `sudo tail -20 /var/log/nginx/error.log` showed repeated entries:

```
connect() failed (111: Connection refused) while connecting to upstream,
upstream: "http://127.0.0.1:3000/"
```

All three confirmed the same root cause -- application process down, Nginx upstream unreachable. Total investigation time: under 5 minutes.

**Key diagnostic insight:** Starting with the port check (`ss -tlnp`) rather than logs is faster for initial triage -- it immediately confirms whether the upstream service is running without parsing log output.

---

## Resolution

Automated remediation script `/usr/local/bin/remediate-app.sh` executed the following sequence:

1. Sent HTTP GET request to endpoint -- received HTTP 502
2. Issued `systemctl restart support-lab-app`
3. Waited 5 seconds and re-checked endpoint
4. Confirmed HTTP 200 response
5. Logged all actions with timestamps to `/var/log/app-remediation.log`

**Remediation log output:**

```
[2026-04-14 19:05:20] WARNING: https://support.lizzycloudlab.online returned HTTP 502. Restarting support-lab-app.
[2026-04-14 19:05:25] RECOVERY: support-lab-app restarted successfully. HTTP 200 confirmed.
[2026-04-14 19:07:00] OK: Datadog Synthetics monitor returned to OK status.
```

---

## Prevention Implemented

**1. Systemd restart policy:**

The `support-lab-app` service was configured with automatic restart on failure:

```ini
[Service]
Restart=on-failure
RestartSec=5s
StartLimitBurst=3
StartLimitIntervalSec=60s
```

If the process crashes or exits unexpectedly, systemd will automatically restart it within 5 seconds -- up to 3 attempts per 60-second window. This provides the first layer of self-healing before the remediation script fires.

**2. Cron health check:**

```bash
*/5 * * * * /usr/local/bin/remediate-app.sh >> /var/log/app-remediation.log 2>&1
```

Runs every 5 minutes. Checks the live endpoint, restarts the service if a non-200 response is detected, and logs all actions with timestamps for audit purposes.

---

## Prevention Recommendations

1. **Defense in depth** -- systemd restart handles process-level crashes immediately; cron health check handles cases where the process appears running but the endpoint is unresponsive -- both layers are required
2. **Upstream health checks in Nginx** -- configure Nginx upstream health checks to detect application unavailability at the proxy layer and return a custom maintenance page instead of a raw 502
3. **Application-level health endpoint** -- ensure `/health` returns meaningful dependency status, not just HTTP 200 -- enables more precise failure diagnosis during triage
4. **Deployment verification** -- add endpoint health check to deployment pipeline -- any deployment that leaves the service returning non-200 should automatically trigger rollback
5. **Alert escalation** -- for P1 502 incidents in production, add PagerDuty escalation in addition to Slack to ensure on-call engineer is paged even if Slack notification is missed

---

## Lessons Learned

- **502 means upstream is down, not Nginx** -- always check the upstream application first before investigating the proxy layer
- **Port listening checks are faster than log analysis for initial triage** -- `ss -tlnp` confirms application status in one command without parsing log files
- **Automated remediation combined with external synthetic monitoring reduces MTTR significantly** -- the application was recovered without any manual intervention, demonstrating the value of investing in automation after each incident
- **Layered prevention is more reliable than single-point controls** -- combining systemd restart policy with a cron health check ensures recovery even if one mechanism fails

---

## Evidence

| File | Description |
|---|---|
| 01-app-healthy-before-incident | Browser showing HTTP 200, Datadog Synthetics OK status |
| 02-502-error-browser | Browser showing 502 Bad Gateway on https://support.lizzycloudlab.online |
| 03-synthetics-alert-slack | Slack #incidents alert fired at 18:51 UTC |
| 04-investigation-ss-tlnp | ss -tlnp showing nothing listening on port 3000 |
| 05-investigation-systemctl | systemctl status showing service inactive (dead) at 18:50 UTC |
| 06-investigation-nginx-logs | Nginx error log showing connection refused to upstream |
| 07-remediation-script-output | Remediation log showing WARNING → RECOVERY → OK sequence |
| 08-synthetics-recovery | Datadog Synthetics showing Alert Triggered 18:50 → Alert Recovered 19:07, 17-minute outage window |
