# NETRA — Project Architecture & Goals

> **Network Exposure & Threat Reconnaissance Architecture (NETRA)**  
> Self-hosted External Attack Surface Management (EASM) platform.

## 1. Project Overview

NETRA is designed to discover, monitor, correlate, and assess Internet-facing assets in an authorized scope.

The platform is scanner-agnostic. Open-source security tools act as discovery and assessment engines, while NETRA provides the orchestration, normalization, correlation, historical tracking, change detection, and visualization layer.

Core philosophy:

> **Tools = Engine | Database = Source of Truth | Dashboard = Intelligence Layer**

Target asset relationship:

```text
Domain
 → Subdomain
 → DNS
 → IP
 → ASN / Provider
 → Port
 → Service
 → Web
 → Technology
 → Endpoint
 → Vulnerability
```

---

## 2. Goals

### Primary Goals

1. Discover Internet-facing assets within an authorized scope.
2. Identify newly discovered, changed, and inactive assets.
3. Map DNS relationships and potential direct-origin exposure.
4. Identify Internet-exposed ports and services.
5. Identify web technologies and application attack surface.
6. Discover web endpoints.
7. Perform vulnerability and misconfiguration assessment.
8. Maintain historical data for attack-surface comparison over time.
9. Provide a centralized dashboard for security analysis.
10. Produce information useful for investigation, remediation, and reporting.

### Long-Term Goal

Build a self-hosted EASM platform that can serve as a:

> **Single Source of Truth for the External Attack Surface.**

The platform should accept data from multiple discovery and security engines without being tightly coupled to a single vendor or scanner.

---

## 3. Scope

### Initial Scope

- Internet-facing domains
- Subdomains
- DNS records
- Public IP addresses
- ASN / hosting provider information
- Open ports
- HTTP/HTTPS services
- Web technologies
- Web endpoints
- Vulnerabilities
- Security misconfigurations
- Asset changes

### Initial Out of Scope

- Internal network discovery
- Credentialed vulnerability scanning
- Endpoint/EDR monitoring
- SIEM replacement
- Full penetration testing
- Automated exploitation

NETRA is an attack-surface visibility and assessment platform, not an automated exploitation framework.

---

## 4. High-Level Architecture

```text
                              INTERNET
                                  |
                                  v
                     +-------------------------+
                     |      DISCOVERY LAYER    |
                     |                         |
                     | Amass                   |
                     | Subfinder               |
                     | CT / OSINT              |
                     +------------+------------+
                                  |
                                  v
                     +-------------------------+
                     |     SCOPE VALIDATION    |
                     |                         |
                     | Allowed Domains         |
                     | Allowed IP/CIDR         |
                     | Exclusions              |
                     +------------+------------+
                                  |
                                  v
                     +-------------------------+
                     |    ENRICHMENT LAYER     |
                     |                         |
                     | dnsx                    |
                     | httpx                   |
                     | Naabu                   |
                     | Katana                  |
                     +------------+------------+
                                  |
                                  v
                     +-------------------------+
                     |   ASSESSMENT LAYER      |
                     |                         |
                     | Nuclei                  |
                     | TLS Checks              |
                     | Exposure Checks         |
                     | Misconfiguration        |
                     +------------+------------+
                                  |
                                  v
                     +-------------------------+
                     |      DATA ENGINE        |
                     |                         |
                     | Normalization            |
                     | Deduplication            |
                     | Correlation              |
                     | Asset Resolution         |
                     | Change Detection         |
                     +------------+------------+
                                  |
                                  v
                     +-------------------------+
                     |       DATABASE          |
                     |                         |
                     | PostgreSQL               |
                     +------------+------------+
                                  |
                                  v
                     +-------------------------+
                     |       API / BACKEND     |
                     |                         |
                     | FastAPI                 |
                     | Job Management           |
                     | Authentication           |
                     | Reporting API            |
                     +------------+------------+
                                  |
                                  v
                     +-------------------------+
                     |       DASHBOARD         |
                     |                         |
                     | Overview                |
                     | Assets                  |
                     | DNS                     |
                     | Services                |
                     | Web                     |
                     | Vulnerabilities         |
                     | Changes                 |
                     | Attack Graph            |
                     | Reports                 |
                     +-------------------------+
```

---

## 5. Core Technology Stack

### Discovery & Security Engines

| Tool | Primary Function |
|---|---|
| OWASP Amass | Attack-surface mapping / passive discovery |
| Subfinder | Passive subdomain discovery |
| dnsx | DNS resolution and record enrichment |
| httpx | HTTP probing and web metadata |
| Naabu | Port discovery |
| Katana | Web crawling and endpoint discovery |
| Nuclei | Vulnerability and misconfiguration assessment |

The scanner layer is intentionally modular so engines can be added or replaced without redesigning the core platform.

### Application Stack

**Backend**
- Python
- FastAPI

**Database**
- PostgreSQL

**Job / Queue**
- Redis
- Worker framework such as Celery or RQ

**Frontend**
- React
- Next.js or equivalent React framework
- Tailwind CSS

**Deployment**
- Docker
- Docker Compose
- Linux VM

Kubernetes is not a requirement for the initial deployment.

---

## 6. Data Flow

```text
ROOT DOMAIN
     |
     v
Amass / Subfinder
     |
     v
Raw Discovery Data
     |
     v
Scope Validation
     |
     v
Normalized Asset
     |
     +------------------+
     |                  |
     v                  v
    DNS                HTTP
   dnsx                httpx
     |                  |
     +--------+---------+
              |
              v
        Asset Correlation
              |
              v
            Naabu
              |
              v
        Service / Port Data
              |
              v
           Katana
              |
              v
        Endpoint Discovery
              |
              v
           Nuclei
              |
              v
       Vulnerability Data
              |
              v
          PostgreSQL
              |
              v
          Dashboard
```

## 7. Scanner Execution & Worker Architecture

NETRA treats scanner binaries as execution engines, not as part of the canonical data model.

The production deployment will package scanner tooling inside a dedicated **Worker Docker image** rather than installing scanner binaries directly on the NETRA host.

### 7.1 Production topology

```text
                         NETRA Docker Compose
                                  |
        +-------------------------+-------------------------+
        |                         |                         |
        v                         v                         v
   +---------+              +-----------+              +---------+
   |Frontend | -----------> |  Backend  |              | Redis   |
   +---------+              +-----+-----+              +----+----+
                                  |                         |
                                  +------------+------------+
                                               |
                                               v
                                        +-------------+
                                        |    Worker   |
                                        | Docker Image|
                                        +------+------+
                                               |
                 +-----------------------------+-----------------------------+
                 |              |              |              |              |
                 v              v              v              v              v
               Amass         Subfinder        dnsx          httpx          Naabu
                                                                              |
                                                                         +----+
                                                                         |
                                                                       Katana
                                                                         |
                                                                       Nuclei
                                               |
                                               v
                                        Scanner Adapters
                                               |
                                               v
                                     Canonical Observation
                                               |
                                               v
                                    Correlation / Deduplication
                                               |
                                               v
                                       Change Detection
                                               |
                                               v
                                          PostgreSQL
```

The exact process/queue framework remains an implementation detail. The architectural requirement is that scanner execution is isolated in the Worker layer.

### 7.2 Scanner binaries inside the Worker

The Worker image will contain pinned scanner versions.

```text
Worker Image
├── Amass
├── Subfinder
├── dnsx
├── Naabu
├── httpx
├── Katana
└── Nuclei
```

Scanner versions will be pinned so that development, testing, and deployment use reproducible scanner environments.

### 7.3 Development/research environment

During scanner research, individual binaries may temporarily be installed directly on the Ubuntu VM. This is a research/development environment, not the intended final deployment model.

The purpose is to execute the real scanner binaries, inspect their actual JSON/JSONL output, capture sanitized fixtures, define scanner-specific adapter contracts, and test normalization against real output.

Once scanner contracts are established, the same pinned versions will be packaged into the Worker Docker image.

### 7.4 Scanner adapter boundary

The boundary is:

```text
Real Scanner
     |
     v
Raw JSON / JSONL
     |
     v
Scanner-specific Adapter
     |
     v
Canonical NETRA Observation
     |
     v
Correlation / Deduplication
     |
     v
Change Detection
     |
     +--------------------+
     |                    |
     v                    v
Current State       Change Events
     |                    |
     +---------+----------+
               v
           PostgreSQL
```

Each scanner gets its own adapter because output schemas, optional fields, semantics, and versions differ.

The normalization contract must be based on real output from the pinned scanner version, not assumed fields or hand-written examples.

### 7.5 Version and fixture policy

For every scanner adapter, NETRA should retain a sanitized fixture representing actual scanner output.

```text
scanners/
├── amass/
│   └── fixtures/
│       └── enumeration.jsonl
├── dnsx/
│   └── fixtures/
│       └── resolution.jsonl
└── httpx/
    └── fixtures/
        └── probe.jsonl
```

Each fixture should be associated with scanner name, scanner version, command/flags used, output format, relevant target type, and known optional fields.

Sensitive or company-specific scan results must not be committed to the public repository.

---

## 8. Discovery Layer

### OWASP Amass

Amass is one of the primary discovery engines.

Objectives:
- subdomain discovery
- passive asset discovery
- DNS intelligence
- relationship mapping
- external attack-surface mapping

Initial discovery should favor passive methods.

Example:

```bash
amass enum -passive -d example.com
```

Raw results should be retained as evidence for historical comparison.

### Subfinder

Subfinder provides an additional passive discovery source.

Using multiple discovery sources helps:
- improve coverage
- compare source results
- reduce dependency on one source
- identify assets missed by a particular source

Amass and Subfinder results are normalized and deduplicated before becoming canonical NETRA entities.

---

## 8. Scope Validation

Scope validation is a critical security control.

Every discovery result should pass scope validation before active enrichment.

Example:

```text
*.example.com              ALLOW
example.com                ALLOW

thirdparty.example.net     REVIEW / REJECT
```

The scope engine should support:
- allowed domains
- allowed subdomains
- allowed IP/CIDR
- exclusions
- third-party exclusions

Principle:

> **Discovery may be broad, but active scanning must remain controlled.**

---

## 9. DNS Intelligence

Primary engine:

**dnsx**

Potential data:
- A
- AAAA
- CNAME
- MX
- NS
- TXT
- SOA
- DNS resolution status

Relationship:

```text
Hostname
    |
    +--> CNAME
    |
    +--> IP
          |
          +--> ASN
          |
          +--> Provider
          |
          +--> Geographic information
```

Future detection opportunities:
- direct-origin exposure
- unexpected DNS changes
- suspicious CNAME relationships
- dangling DNS indicators
- unexpected hosting providers
- IP changes

---

## 10. HTTP Intelligence

Primary engine:

**httpx**

Potential data:
- HTTP/HTTPS status
- title
- server
- technology
- TLS metadata
- response headers
- redirect chain
- content length
- web service availability

Example:

```text
https://api.example.com
Status: 200
Server: nginx
Technology: Node.js
TLS: valid
```

---

## 11. Port & Service Discovery

Primary engine:

**Naabu**

Purpose:
- identify exposed ports
- detect unexpected services
- track port changes

Example:

```text
api.example.com

80/tcp
443/tcp
8443/tcp
```

Port data is correlated with IP addresses and services rather than stored as scanner-specific output.

---

## 12. Web Crawling

Primary engine:

**Katana**

Purpose:
- endpoint discovery
- URL discovery
- JavaScript endpoint discovery
- parameter discovery
- application attack-surface mapping

Example:

```text
https://api.example.com
|
+-- /login
+-- /api/users
+-- /api/auth
+-- /admin
+-- /upload
```

---

## 13. Vulnerability Assessment

Primary initial engine:

**Nuclei**

Assessment categories:
- CVEs
- exposed panels
- misconfigurations
- default configurations
- known vulnerable technologies
- security headers
- TLS issues
- exposure indicators

Canonical NETRA findings should remain scanner-agnostic.

Concept:

```text
NETRA Finding
  ├── Nuclei source
  ├── Future Nessus source
  └── Future OpenVAS source
```

This allows additional assessment engines without redesigning the core finding model.

---

## 14. Data Correlation

Core relationship:

```text
Domain
  ↓
Subdomain
  ↓
DNS Record
  ↓
IP
  ↓
Port
  ↓
Service
  ↓
Website
  ↓
Technology
  ↓
Endpoint
  ↓
Finding
```

Example:

```text
example.com
    |
api.example.com
    |
CNAME → cloud.example.net
    |
203.0.113.10
    |
443/tcp
    |
nginx
    |
https://api.example.com
    |
/api/login
    |
Finding: example issue
```

The database is the canonical source of truth; scanner output is treated as evidence.

---

## 15. Normalization & Deduplication

Different scanners may discover the same asset.

Example:

```text
Amass      → api.example.com
Subfinder  → api.example.com
CT source  → api.example.com
```

NETRA should create one canonical subdomain entity with multiple discovery sources.

Pipeline:

```text
Scanner
  ↓
Parser
  ↓
Normalizer
  ↓
Correlation
  ↓
Canonical NETRA Entity
  ↓
PostgreSQL
```

This keeps the core model independent from scanner output formats.

---

## 16. Historical Tracking

Each asset should maintain historical visibility.

Important fields include:
- first_seen
- last_seen
- scan_id
- source
- timestamps

Examples:

### New Asset

```text
api2.example.com
First Seen: 2026-09-17
```

### Removed Asset

```text
old.example.com
Last Seen: 2026-08-30
Status: inactive
```

### Port Change

```text
NEW PORT

api.example.com
8443/tcp
```

### DNS Change

```text
CNAME CHANGE

OLD → Provider A
NEW → Provider B
```

### Technology Change

```text
TECHNOLOGY CHANGE

OLD: IIS
NEW: nginx
```

### New Finding

```text
NEW FINDING

api.example.com
Finding: example issue
Severity: High
```

---

## 17. Dashboard Features

### Overview

Potential metrics:
- total assets
- active assets
- inactive assets
- public IPs
- open ports
- live web services
- technologies
- vulnerabilities
- new assets
- changed assets
- recent findings
- scan status

### Asset Inventory

Example fields:

```text
Hostname
IP
Status
Ports
Technology
Provider
First Seen
Last Seen
Findings
```

Features:
- search
- filtering
- sorting
- tagging
- asset detail

### Asset Detail

Example:

```text
api.example.com

Overview
DNS
IPs
Ports
HTTP
Technologies
Endpoints
Vulnerabilities
Changes
History
```

### DNS Intelligence

Visual relationship:

```text
Hostname
   |
 CNAME
   |
Provider
   |
 IP
   |
 ASN
```

### Service Exposure

Display:
- port
- protocol
- service
- exposure status
- first seen
- last seen

### Web Attack Surface

Display:
- URL
- endpoint
- HTTP status
- technology
- endpoint type
- discovery date

### Vulnerability Management

Display:
- severity
- CVE or finding identifier
- asset
- template/source
- evidence
- first seen
- last seen
- remediation status

### Change Monitoring

Timeline example:

```text
09:00  NEW ASSET
10:15  NEW PORT
11:02  DNS CHANGE
13:10  NEW ENDPOINT
15:40  NEW VULNERABILITY
```

### Attack Surface Graph

```text
DOMAIN
  |
SUBDOMAIN
  |
DNS
  |
IP
  |
PORT
  |
SERVICE
  |
TECHNOLOGY
  |
ENDPOINT
  |
FINDING
```

### Reports

Potential outputs:
- HTML
- CSV
- PDF
- JSON

Use cases:
- security review
- management reporting
- remediation tracking
- audit evidence
- periodic security reporting

---

## 18. Scan Management

Scans should be policy-driven.

Example:

```text
Daily Scan
-----------
Passive Discovery
DNS
HTTP
Exposure

Weekly Scan
-----------
Discovery
DNS
HTTP
Port
Crawling
Assessment

Manual / Approved
------------------
Higher-impact assessment
```

Each scan should record:

```text
Scan ID
Start Time
End Time
Status
Tool Version
Target
Result Count
Error Count
```

---

## 19. Notification

Future integrations may include:
- Email
- Microsoft Teams
- Slack
- Webhook
- SIEM/SOC integration

Example alert:

```text
NEW EXTERNAL ASSET

Hostname:
dev-api.example.com

IP:
203.0.113.10

Port:
443

Technology:
nginx

First Seen:
2026-09-17
```

---

## 20. Risk & Prioritization

NETRA should provide context rather than simply count vulnerabilities.

Potential context:

```text
Asset Exposure
+
Finding Severity
+
Internet Accessibility
+
Service Exposure
+
Technology
+
Asset Criticality
+
Change Recency
```

Example:

```text
Internet-facing
+
High-severity finding
+
Known vulnerable technology
=
High-priority investigation
```

Risk scoring should be configurable and should not replace analyst validation.

---

## 21. Security & Safety Controls

### Scope Control

- allowed domains
- allowed CIDR
- exclusions
- third-party protection

### Rate Limiting

Prevent overly aggressive scanning.

### Scan Policy

Separate discovery from active assessment.

### Audit Log

Record:
- who started the scan
- when
- target
- policy
- tool
- result

### Credential Separation

Discovery-source credentials and API keys should be securely stored and never exposed in dashboard output.

### Least Privilege

Scanner workers should receive only the permissions they require.

### Authorization

NETRA is intended for assets that the operator is authorized to assess.

---

## 22. Deployment Architecture

Initial deployment uses Docker Compose:

```text
+------------------------------------------------+
|                  NETRA SERVER                  |
|                                                |
|  +----------+     +-----------+                |
|  | Frontend | --> |  FastAPI  |                |
|  +----------+     +-----+-----+                |
|                         |                      |
|                    +----+----+                 |
|                    |  Redis  |                 |
|                    +----+----+                 |
|                         |                      |
|                    +----+----+                 |
|                    |  Worker |                 |
|                    +----+----+                 |
|                         |                      |
|          +--------------+--------------+       |
|          |              |              |       |
|        Amass         dnsx/httpx      Nuclei    |
|        Naabu          Katana                   |
|                                                |
|                    +-----------+               |
|                    | PostgreSQL|               |
|                    +-----------+               |
+------------------------------------------------+
```

---

## 23. Repository Structure

Current repository structure is evolving from the initial foundation:

```text
netra/
├── backend/
├── config/
├── database/
├── docs/
├── frontend/
├── scanners/
├── scripts/
├── .env.example
├── .gitignore
└── docker-compose.yml
```

The structure will expand as the backend, data model, scanner adapters, and frontend are implemented.

---

## 24. Development Roadmap

### Phase 0 — Project Definition

- project goals
- architecture
- scope
- safety principles
- technology direction

**Status: Complete**

### Phase 1 — Infrastructure Foundation

- Ubuntu VM
- Docker
- Docker Compose
- PostgreSQL
- Redis
- FastAPI skeleton
- container networking
- health checks

**Status: Complete**

### Phase 2 — Data Model

Initial canonical entities:
- projects
- domains
- subdomains
- DNS records
- IP addresses
- DNS/IP resolutions
- ports
- services
- scans

Planned later:
- websites
- technologies
- endpoints
- findings
- finding sources
- asset history/change events

**Status: In Progress**

### Phase 3 — Discovery Engine

Initial engines:
- Amass
- Subfinder

Goal:

> Validate discovery coverage and ingestion.

### Phase 4 — DNS Engine

Tool:
- dnsx

Goal:

> Hostname → DNS → IP relationship.

### Phase 5 — HTTP Engine

Tool:
- httpx

Goal:

> Identify live web services and technology metadata.

### Phase 6 — Port Exposure

Tool:
- Naabu

Goal:

> Map Internet-exposed ports.

### Phase 7 — Web Crawling

Tool:
- Katana

Goal:

> Discover web endpoints and application attack surface.

### Phase 8 — Vulnerability Assessment

Tool:
- Nuclei

Goal:

> Add vulnerability and misconfiguration visibility.

### Phase 9 — Database & Correlation

Goals:
- normalized data
- asset correlation
- historical tracking
- change detection
- scanner-source evidence

### Phase 10 — Dashboard MVP

Initial pages:
1. Overview
2. Assets
3. Asset Detail
4. DNS
5. Services
6. Web
7. Vulnerabilities
8. Changes
9. Scan Management

### Future — Intelligence & Integration

Potential additions:
- attack graph
- configurable risk prioritization
- provider/ASN intelligence
- threat-intelligence correlation
- asset ownership confidence
- suspicious asset detection
- SIEM
- SOAR
- ticketing
- Teams/Slack
- CMDB
- management reporting

---

## 25. Final Vision

NETRA should answer five questions quickly.

### 1. What do we expose?

```text
Assets
IPs
Ports
Services
Websites
Endpoints
```

### 2. What changed?

```text
New Asset
New IP
New Port
DNS Change
Technology Change
New Endpoint
New Finding
```

### 3. What requires investigation?

```text
Vulnerability
Misconfiguration
Unexpected Exposure
Unexpected Service
Suspicious Change
```

### 4. What is connected?

```text
Domain
 ↓
Subdomain
 ↓
DNS
 ↓
IP
 ↓
Port
 ↓
Service
 ↓
Technology
 ↓
Endpoint
 ↓
Finding
```

### 5. What should the analyst investigate first?

The platform should surface contextual signals such as:
- newly exposed Internet services
- unexpected assets
- high-severity findings
- suspicious DNS changes
- unexpected technology changes

The final prioritization remains an analyst decision supported by evidence and context.

---

## 26. Project Philosophy

> **Discover broadly, validate carefully, correlate intelligently, assess safely, and monitor continuously.**

NETRA is not intended to be just another scanner.

It is a platform that turns the output of multiple open-source security engines into a correlated, historical, and understandable view of an external attack surface for security analysts and management.

---

## 27. Success Criteria

The project is considered successful when:

- discovery engines can be integrated through adapters
- assets can be normalized and deduplicated
- assets maintain historical records
- DNS, IP, port, web, endpoint, and finding relationships can be correlated
- scans can be scheduled
- attack-surface changes can be detected
- findings from multiple assessment engines can be represented consistently
- analysts can investigate from a centralized dashboard
- scope and scanning safety controls are enforced
- data can be exported for reporting
- new security engines can be added without major redesign of the canonical data model

---

## 28. End State

```text
                    EASM PLATFORM
                         |
       +-----------------+------------------+
       |                 |                  |
   DISCOVERY          EXPOSURE          ASSESSMENT
       |                 |                  |
   Subdomain            Port              Findings
   DNS                   Web               CVE
   IP                    API               Misconfig
   OSINT                 TLS
       |                 |
       +-----------------+------------------+
                         |
                    CORRELATION
                         |
                  CHANGE DETECTION
                         |
                  RISK INTELLIGENCE
                         |
                    DASHBOARD
                         |
              +----------+----------+
              |                     |
          SECURITY              MANAGEMENT
          ANALYST                REPORTING
```

**Project objective:** build a modular, open-source-based, self-hosted, controlled, and extensible EASM platform for external attack-surface intelligence.
