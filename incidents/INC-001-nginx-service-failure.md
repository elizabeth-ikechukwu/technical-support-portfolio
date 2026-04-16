# INC-001 -- Nginx Service Failure

**Classification:** P1 - Critical  
**Status:** Resolved  
**Date:** April 12, 2026  
**Reported by:** Ikechukwu Elizabeth  
**Environment:** support-simulation-server / https://support.lizzycloudlab.online

---

## Summary

A complete service outage was detected and resolved proactively before any customer escalation, demonstrating end-to-end incident ownership from automated detection through root cause analysis and permanent prevention. The Nginx web server on support-simulation-server became unavailable, taking down the customer-facing application at https://support.lizzycloudlab.online. Proactive monitoring via Datadog detected the outage within 2 minutes and automatically paged the on-call engineer via Slack. The incident was investigated, resolved using an automated response script, and closed within 13 minutes -- within the P1 SLA target of 15 minutes.

---

## Timeline

| Time (WAT) | Event |
|---|---|
| 13:10 | Nginx service stopped -- outage begins |
| 13:12 | Datadog monitor triggered -- Slack alert fired to #incidents |
| 13:12 | On-call engineer acknowledged alert |
| 13:15 | Investigation started -- systemctl, journalctl, nginx -t, ss commands executed |
| 13:22 | Incident response script executed |
| 13:22 | Nginx config validated -- OK |
| 13:22 | Nginx restarted successfully |
| 13:23 | Datadog recovery notification received in Slack |
| 13:23 | Incident closed |

---

## SLA Performance

| Metric | Target | Actual |
|---|---|---|
| Time to Detect (TTD) | < 5 minutes | 2 minutes |
| Time to Resolve (TTR) | < 15 minutes | 13 minutes |
| SLA Status | Met | Met |

---

## Root Cause

Nginx was manually stopped via `sudo systemctl stop nginx`. Investigation confirmed a clean shutdown with no configuration errors, no port conflicts, and no system resource issues. Root cause: human error -- accidental service stop during a simulated maintenance window.

In a production environment this class of incident would typically result from a failed deployment, an automated process with elevated privileges, or an operator error during maintenance. The investigation process and automated response script documented here apply equally to all root cause variants.

---

## Impact

- https://support.lizzycloudlab.online was unreachable for 13 minutes
- Nginx connections dropped to zero as confirmed on Datadog dashboard
- No data loss occurred
- Estimated customer impact: all users unable to access the application during the outage window
- Customer communication: In a production scenario a status page update would be published within 5 minutes of detection and a post-incident summary distributed within 24 hours of resolution

---

## Investigation

1. **Confirmed service status** -- `sudo systemctl status nginx` returned `inactive (dead)`
2. **Reviewed service logs** -- `sudo journalctl -u nginx --since "30 minutes ago"` confirmed clean manual stop at 13:10
3. **Validated Nginx config** -- `sudo nginx -t` returned `configuration test successful`
4. **Checked port availability** -- `sudo ss -tlnp | grep -E '80|443'` returned no conflicts

---

## Resolution

Executed automated incident response script `~/incident-response-nginx.sh` which tested the Nginx configuration, restarted the service, verified recovery, and logged all actions with timestamps to `/var/log/incident-response.log`.

---

## Prevention Recommendations

1. Add config-failure error handling to the response script to abort restart if configuration is broken -- prevents cascading failures during automated recovery
2. Restrict sudo access on production servers to prevent accidental service stops during maintenance windows
3. Implement deployment checklists to verify service status after any maintenance activity
4. In high-traffic production environments replace the threshold-based monitor with a direct `nginx.can_connect` service check to eliminate NO DATA false positive risk
5. Schedule quarterly fire drills to validate incident response procedures remain current and effective

---

## Evidence

| File | Description |
|---|---|
| 01-server-healthy-before-incident | Datadog monitor showing OK status before injection |
| 02-nginx-welcome-page | Browser showing application accessible before incident |
| 03-browser-failure | Browser showing connection failure after Nginx stopped |
| 04-systemctl-status-inactive | systemctl status showing inactive (dead) |
| 05-journalctl-logs | Journal logs confirming clean stop at 13:10 |
| 06-slack-alert-fired | Slack #incidents alert fired at 13:12 WAT |
| 07-incident-response-script | Script output showing config validated, Nginx restarted |
| 08-monitor-recovery-ok | Datadog monitor showing OK restored at 13:23 WAT |
