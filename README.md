# technical-support-portfolio

**Production-Grade Incident Response and Monitoring Simulation**

A hands-on technical support engineering portfolio project demonstrating end-to-end incident ownership -- from proactive detection through automated remediation, root cause analysis, and permanent prevention -- on a live AWS production environment.

> All incidents were detected automatically by Datadog before any customer escalation. All resolutions were executed via automated Bash scripts. All incidents are documented with full timelines, SLA metrics, root cause analysis, and prevention measures.

---

## Live Environment

| Component | Detail |
|---|---|
| Application URL | https://support.lizzycloudlab.online |
| Server | AWS EC2 Ubuntu t3.micro |
| Hostname | support-simulation-server |
| Monitoring Dashboard | Datadog -- Support Simulation - Server Health |

---

## Stack

| Tool | Role |
|---|---|
| AWS EC2 Ubuntu | Production server |
| Node.js | Application runtime |
| Nginx | Reverse proxy with SSL termination |
| Certbot | SSL certificate management |
| Datadog | Monitoring, alerting, log management, Synthetics |
| Slack | Incident notification channel |
| Systemd | Service management and auto-restart |
| Bash | Automated remediation and prevention scripts |
| Cron | Scheduled automation |
| Logrotate | Log rotation and management |

---

## Architecture

```
Internet
    │
    ▼
DNS (support.lizzycloudlab.online)
    │
    ▼
AWS EC2 -- support-simulation-server
    │
    ├── Nginx (port 443/80)
    │       └── Reverse proxy → Node.js app (port 3000)
    │
    ├── Node.js App (systemd managed)
    │       ├── GET /
    │       ├── GET /health
    │       └── GET /api/tasks
    │
    ├── Datadog Agent
    │       ├── Host metrics (CPU, memory, disk, network)
    │       ├── Nginx integration
    │       ├── Log collection
    │       └── Synthetics HTTP check
    │
    └── Bash Scripts
            ├── incident-response-nginx.sh
            ├── cpu-remediation.sh
            ├── cleanup-disk.sh
            └── remediate-app.sh
```

---

## Monitoring Setup

### Datadog Monitors

| Monitor | Metric | Alert Threshold | Warning Threshold |
|---|---|---|---|
| High CPU Usage | system.cpu.user | > 85% | > 70% |
| High Memory Usage | system.mem.pct_usable | < 15% | < 20% |
| Disk Space Critical | system.disk.in_use | > 80% | > 70% |
| Nginx Down | nginx.net.connections | < 1 | < 2 |
| App Health Check | Synthetics HTTP | non-200 response | - |

All monitors route alerts to Slack `#LizzyCloudLab-incidents` channel with structured investigation steps embedded in each alert message.

### Datadog Dashboard

**Support Simulation - Server Health** -- live dashboard showing CPU usage, memory usage, disk usage, Nginx connections, system load, and log stream in a single view.

---

## Incident Simulations

Four production-grade incidents were simulated, investigated, and resolved on this environment. Each incident follows the full lifecycle: detection → investigation → resolution → prevention.

---

### INC-001 -- Nginx Service Failure (P1 - Critical)

| Metric | Detail |
|---|---|
| Date | April 12, 2026 |
| Detection | Datadog Nginx monitor -- 2 minutes |
| Resolution | Automated script -- 13 minutes |
| SLA | Met |

**What happened:** Nginx service stopped, taking down the customer-facing application. Datadog detected the outage within 2 minutes and fired a Slack alert. Automated response script validated config, restarted Nginx, and confirmed recovery.

**Script:** `incident-response-nginx.sh`  
**Full report:** [INC-001-nginx-service-failure.md](./incidents/INC-001-nginx-service-failure.md)

---

### INC-002 -- High CPU Usage: Runaway Process (P2 - High)

| Metric | Detail |
|---|---|
| Date | April 13, 2026 |
| Detection | Datadog CPU monitor -- 5.5 minutes |
| Resolution | Process termination -- 3 minutes |
| SLA | Met |

**What happened:** Two runaway stress worker processes consumed 95-98% CPU across both vCPUs. Datadog fired alert at 90.859% average CPU. Investigation identified offending PIDs via `ps aux`. CPU remediation script deployed and scheduled via cron every 5 minutes for automated recurrence prevention.

**Script:** `cpu-remediation.sh`  
**Full report:** [INC-002-high-cpu-runaway-process.md](./incidents/INC-002-high-cpu-runaway-process.md)

---

### INC-003 -- Disk Space Critical: Runaway Log File (P2 - High)

| Metric | Detail |
|---|---|
| Date | April 13, 2026 |
| Detection | Datadog disk monitor -- 11 minutes |
| Resolution | Cleanup script -- 43 minutes |
| SLA | Met |
| Additional Finding | Datadog monitor misconfiguration identified and corrected |

**What happened:** A runaway log file consumed 1.6G in `/tmp`, pushing root partition to 96%. Datadog fired alert at 95.8% disk usage. Investigation used `df -h` and `du -sh` to identify the culprit file. Cleanup script removed large files and cleared journal logs. Logrotate and cron job configured for permanent automated prevention.

**Notable:** A Datadog monitor misconfiguration was identified during investigation -- the monitor was evaluating loop devices instead of the root partition. Corrected by scoping the monitor to `device_label:cloudimg-rootfs`.

**Script:** `cleanup-disk.sh`  
**Full report:** [INC-003-disk-space-critical.md](./incidents/INC-003-disk-space-critical.md)

---

### INC-004 -- Application 502 Bad Gateway (P2 - High)

| Metric | Detail |
|---|---|
| Date | April 14, 2026 |
| Detection | Datadog Synthetics HTTP check -- 1 minute |
| Resolution | Automated remediation script -- 17 minutes |
| SLA | Met |

**What happened:** Node.js application process stopped while Nginx continued running, causing all requests to return 502 Bad Gateway. Datadog Synthetics detected the non-200 response within 1 minute. Investigation confirmed nothing listening on port 3000 via `ss -tlnp`. Automated remediation script restarted the service and confirmed HTTP 200 recovery without manual intervention.

**Key insight:** A 502 error indicates the upstream application is unreachable -- not that Nginx is broken. Port check (`ss -tlnp`) is faster than log analysis for initial triage.

**Script:** `remediate-app.sh`  
**Full report:** [INC-004-502-bad-gateway.md](./incidents/INC-004-502-bad-gateway.md)

---

## Automation Scripts

| Script | Purpose | Trigger |
|---|---|---|
| `incident-response-nginx.sh` | Validates Nginx config, restarts service, verifies recovery | Manual or on-call response |
| `cpu-remediation.sh` | Identifies and kills processes above 80% CPU | Cron every 5 minutes |
| `cleanup-disk.sh` | Removes large files in /tmp, clears old journal logs | Cron daily at 02:00 WAT |
| `remediate-app.sh` | Checks endpoint health, restarts app if non-200 detected | Cron every 5 minutes |

All scripts log timestamped output to `/var/log/` for audit trail.

---

## Repository Structure

```
technical-support-portfolio/
├── incidents/
│   ├── INC-001-nginx-service-failure.md
│   ├── INC-002-high-cpu-runaway-process.md
│   ├── INC-003-disk-space-critical.md
│   └── INC-004-502-bad-gateway.md
├── scripts/
│   ├── incident-response-nginx.sh
│   ├── cpu-remediation.sh
│   ├── cleanup-disk.sh
│   └── remediate-app.sh
├── screenshots/
│   ├── incident-1-nginx-down/
│   ├── incident-2-high-cpu/
│   ├── incident-3-disk-space/
│   └── incident-4-502-bad-gateway/
└── README.md
```

---

## Key Skills Demonstrated

- Proactive incident detection using Datadog monitors and Synthetics -- no waiting for customer reports
- Structured incident investigation using Linux commands -- `systemctl`, `journalctl`, `ss`, `top`, `ps aux`, `df`, `du`
- Automated remediation using Bash scripts -- no manual fixes in production
- Permanent prevention using cron, logrotate, and systemd restart policies
- Professional incident documentation with SLA metrics, timelines, root cause analysis, and lessons learned
- Monitoring misconfiguration identification and correction during live incident investigation
- Alert routing via Slack with structured investigation steps embedded in alert messages

---

## What's Next

- INC-005: Memory exhaustion simulation -- coming soon
- Runbooks: Internal on-call runbooks for all 4 incident types
- Project 2: Customer-facing troubleshooting runbooks for 5 common SaaS support scenarios

---

*Built and maintained by Elizabeth Ikechukwu -- Technical Support Engineer | DevOps & Cloud Background*  
*LinkedIn: https://www.linkedin.com/in/ikechukwu-elizabeth*
