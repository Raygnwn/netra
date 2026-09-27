# NETRA — Data Model

## 1. Purpose

This document defines the canonical data model for NETRA.

The model is intentionally **scanner-agnostic**. Scanner output is treated as evidence and is normalized into canonical NETRA entities before being stored as the platform's source of truth.

Core principle:

> **Scanner output is evidence; PostgreSQL is the canonical source of truth.**

This design allows NETRA to add, replace, or combine discovery and assessment engines without redesigning the core data model.

---

## 2. Design Principles

### 2.1 Scanner Agnostic

The database must not depend on the schema of a particular scanner.

For example:

- Amass may discover subdomains.
- Subfinder may discover the same subdomains.
- Certificate Transparency may discover additional names.
- Nuclei may produce vulnerability findings.
- Future integrations may include Nessus or OpenVAS.

All of these sources should feed the same canonical model.

### 2.2 Normalize Before Persistence

The intended pipeline is:

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

### 2.3 Historical Visibility

NETRA must preserve the history of external exposure.

Important temporal fields include:

- first_seen
- last_seen
- created_at
- updated_at
- scan_id

The objective is to identify:

- newly discovered assets
- disappeared assets
- new ports
- closed ports
- DNS changes
- technology changes
- newly discovered endpoints
- newly discovered findings
- findings that reappear after being resolved

### 2.4 Correlation Over Raw Output

The database models relationships between assets rather than simply storing scanner result files.

Target relationship:

```text
Project
  ↓
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

Not every relationship must exist for every asset.

For example, a discovered IP may have no associated website, while a web application may have many endpoints.

---

## 3. Initial Entity Model

The initial Phase 2 model consists of:

1. projects
2. domains
3. subdomains
4. dns_records
5. ip_addresses
6. dns_ip_resolutions
7. ports
8. services
9. scans

Later phases are expected to introduce:

10. websites
11. technologies
12. endpoints
13. findings
14. finding_sources
15. asset history / change events

---

## 4. Entity Relationships

High-level relationship:

```text
Project
  |
  +-- Domain
        |
        +-- Subdomain
              |
              +-- DNS Record
                    |
                    +-- IP Address
                          |
                          +-- Port
                                |
                                +-- Service

Project
  |
  +-- Scan
```

Future extension:

```text
IP / Service
  |
  +-- Website
        |
        +-- Technology
        |
        +-- Endpoint
              |
              +-- Finding
                    |
                    +-- Finding Source
```

---

## 5. projects

Represents a logical NETRA monitoring scope.

### Fields

| Field | Purpose |
|---|---|
| id | Primary key |
| name | Project name |
| description | Optional project description |
| status | Project lifecycle status |
| created_at | Creation timestamp |
| updated_at | Last update timestamp |

### Example

```text
Project
ID: 1
Name: Example External Attack Surface
Status: active
```

A project is the top-level grouping for domains and scans.

---

## 6. domains

Represents root domains registered within a project.

### Fields

| Field | Purpose |
|---|---|
| id | Primary key |
| project_id | Parent project |
| name | Root domain |
| status | Domain monitoring status |
| created_at | Creation timestamp |
| updated_at | Last update timestamp |

### Relationship

```text
Project 1
   |
   +-- example.com
   +-- example.net
```

A domain belongs to one project.

---

## 7. subdomains

Represents discovered hostnames associated with a root domain.

### Fields

| Field | Purpose |
|---|---|
| id | Primary key |
| domain_id | Parent domain |
| fqdn | Fully qualified domain name |
| status | Current asset status |
| first_seen | First observation |
| last_seen | Most recent observation |
| created_at | Creation timestamp |
| updated_at | Last update timestamp |

### Example

```text
example.com
   |
   +-- www.example.com
   +-- api.example.com
   +-- dev.example.com
```

A subdomain should be unique within the appropriate domain/project scope.

---

## 8. dns_records

Represents DNS records associated with a discovered hostname.

### Fields

| Field | Purpose |
|---|---|
| id | Primary key |
| subdomain_id | Parent hostname |
| record_type | DNS record type |
| value | Record value |
| ttl | DNS TTL when available |
| first_seen | First observation |
| last_seen | Most recent observation |

### Supported Initial Record Types

Potential initial types:

- A
- AAAA
- CNAME
- MX
- NS
- TXT
- SOA

The model should not require all types to have identical semantics.

### Example

```text
api.example.com
   |
   +-- CNAME -> api.provider.example
```

---

## 9. ip_addresses

Represents observed IP addresses.

### Fields

| Field | Purpose |
|---|---|
| id | Primary key |
| address | IP address |
| version | IPv4 / IPv6 |
| first_seen | First observation |
| last_seen | Most recent observation |

### Example

```text
203.0.113.10
IPv4
```

An IP may be associated with multiple DNS records and multiple historical observations.

---

## 10. dns_ip_resolutions

Represents the relationship between DNS records and resolved IP addresses.

This is modeled separately because DNS relationships are many-to-many over time.

### Fields

| Field | Purpose |
|---|---|
| id | Primary key |
| dns_record_id | DNS record |
| ip_address_id | Resolved IP |
| first_seen | First observation |
| last_seen | Most recent observation |

### Example

```text
api.example.com
      |
      +-- A -> 203.0.113.10
      +-- A -> 203.0.113.11
```

This structure also allows historical DNS-to-IP changes to be tracked.

---

## 11. ports

Represents network ports observed on IP addresses.

### Fields

| Field | Purpose |
|---|---|
| id | Primary key |
| ip_address_id | Parent IP |
| port | Port number |
| protocol | Network protocol |
| state | Observed state |
| first_seen | First observation |
| last_seen | Most recent observation |

### Example

```text
203.0.113.10
   |
   +-- 80/tcp
   +-- 443/tcp
   +-- 8443/tcp
```

Initial protocol support is expected to focus on TCP and UDP.

---

## 12. services

Represents the service identified on a network port.

### Fields

| Field | Purpose |
|---|---|
| id | Primary key |
| port_id | Parent port |
| name | Service name |
| product | Product name when identified |
| version | Product/service version when identified |
| banner | Observed banner when available |
| confidence | Identification confidence |
| first_seen | First observation |
| last_seen | Most recent observation |

### Example

```text
443/tcp
   |
   +-- HTTPS
       Product: nginx
       Version: 1.x
```

Service identification may be incomplete or uncertain, so confidence should be represented explicitly.

---

## 13. scans

Represents an execution of a NETRA scan or scan workflow.

### Fields

| Field | Purpose |
|---|---|
| id | Primary key |
| project_id | Project being scanned |
| scan_type | Type of scan |
| status | Execution status |
| started_at | Start time |
| completed_at | Completion time |
| created_at | Record creation time |

### Initial Scan Types

- DISCOVERY
- DNS
- PORT_SCAN
- WEB
- VULNERABILITY
- FULL

### Initial Status Examples

- queued
- running
- completed
- failed
- cancelled

A scan provides execution context for observations and enables historical correlation.

---

## 14. Future Entity — websites

A website represents an HTTP/HTTPS application associated with an exposed service or hostname.

Potential fields:

- id
- hostname / asset reference
- URL
- scheme
- port
- HTTP status
- title
- server
- TLS information
- first_seen
- last_seen

This entity will be designed when the HTTP enrichment phase begins.

---

## 15. Future Entity — technologies

Represents technologies detected on websites or services.

Potential examples:

- nginx
- Apache
- IIS
- React
- Next.js
- WordPress
- PHP
- Node.js

Potential fields:

- id
- name
- category
- version
- first_seen
- last_seen

The model should allow multiple technologies to be associated with one website.

---

## 16. Future Entity — endpoints

Represents discovered web application endpoints.

Examples:

```text
/api/login
/api/users
/admin
/upload
/graphql
```

Potential fields:

- id
- website_id
- URL / path
- method
- status_code
- content_type
- first_seen
- last_seen

Endpoint discovery is expected to be implemented during the Katana/web crawling phase.

---

## 17. Future Entity — findings

Findings represent canonical security issues identified by assessment engines.

The finding model must remain scanner-agnostic.

Potential canonical fields:

| Field | Purpose |
|---|---|
| id | Primary key |
| asset reference | Affected asset |
| title | Finding title |
| description | Finding description |
| severity | Severity |
| status | Current finding status |
| first_seen | First observation |
| last_seen | Most recent observation |
| resolved_at | Resolution timestamp |

A finding should describe the security issue itself, not the proprietary structure of a specific scanner.

---

## 18. Future Entity — finding_sources

Finding sources preserve the evidence and identity provided by a scanner.

Potential fields:

| Field | Purpose |
|---|---|
| id | Primary key |
| finding_id | Canonical NETRA finding |
| scanner | Source scanner |
| scanner_finding_id | Scanner-specific identifier |
| raw_reference | Reference to source result |
| raw_data | Original/normalized evidence |

### Example

```text
NETRA Finding
      |
      +-- Nuclei source
      |
      +-- Nessus source
      |
      +-- OpenVAS source
```

This prevents scanner-specific data from leaking into the canonical finding model.

---

## 19. Scanner-Agnostic Correlation Example

Suppose three sources discover the same hostname:

```text
Amass
  → api.example.com

Subfinder
  → api.example.com

Certificate Transparency
  → api.example.com
```

NETRA should create one canonical entity:

```text
Subdomain
api.example.com
```

with multiple discovery sources associated with that observation.

Likewise, if Nuclei and another vulnerability scanner identify the same underlying issue, the platform should be able to represent:

```text
Canonical Finding
      |
      +-- Nuclei evidence
      +-- Other scanner evidence
```

The correlation layer is responsible for determining whether observations represent the same canonical entity.

---

## 20. Identity & Deduplication

NETRA requires stable identity rules.

Initial conceptual identity:

| Entity | Candidate Identity |
|---|---|
| Project | project name / UUID |
| Domain | normalized domain + project |
| Subdomain | normalized FQDN + domain |
| DNS Record | hostname + record type + normalized value |
| IP | normalized IP address |
| DNS/IP Relationship | DNS record + IP |
| Port | IP + port + protocol |
| Service | port + normalized service identity |
| Scan | unique scan ID |

Normalization should account for:
- lowercase hostnames
- normalized DNS names
- IPv4/IPv6 canonical representation
- protocol normalization
- trailing-dot DNS notation where applicable

Exact uniqueness constraints will be finalized during PostgreSQL schema implementation.

---

## 21. Temporal Model

NETRA should distinguish between:

### Identity

What the entity is.

### Observation

When and where the entity was observed.

### State

Whether the entity is currently active, inactive, resolved, or otherwise classified.

Conceptually:

```text
Entity
  |
  +-- Identity
  |
  +-- Current State
  |
  +-- Historical Observations
```

This allows the platform to answer questions such as:

- When was this asset first seen?
- When was it last seen?
- Which scan discovered it?
- When did its IP change?
- When did port 8443 appear?
- When did a finding first appear?
- Was the finding later resolved?
- Did the finding reappear?

---

## 22. Source & Evidence Strategy

Scanner-specific raw output should not become the primary database model.

Instead:

```text
Raw Scanner Output
       ↓
Parser
       ↓
Normalized Observation
       ↓
Canonical Entity
       ↓
Evidence / Source Reference
```

This preserves the ability to:
- debug parsing
- trace findings back to source
- compare scanners
- add new scanners
- reprocess historical results

Raw output storage strategy will be finalized when scanner ingestion is implemented.

---

## 23. Phase 2 Implementation Order

The initial PostgreSQL implementation should proceed in this order:

### Step 1

Create database migration structure.

### Step 2

Create:

- projects
- domains
- subdomains

### Step 3

Create:

- dns_records
- ip_addresses
- dns_ip_resolutions

### Step 4

Create:

- ports
- services

### Step 5

Create:

- scans

### Step 6

Add:
- primary keys
- foreign keys
- indexes
- uniqueness constraints
- timestamps

### Step 7

Add seed/test data.

### Step 8

Validate relationships with representative queries.

---

## 24. Example End-to-End Record

Example conceptual data:

```text
Project
  "Example External Attack Surface"
        |
        +-- Domain
              "example.com"
                    |
                    +-- Subdomain
                          "api.example.com"
                                |
                                +-- DNS Record
                                |     CNAME
                                |     "api.provider.example"
                                |
                                +-- DNS/IP Resolution
                                      |
                                      +-- IP
                                            "203.0.113.10"
                                                  |
                                                  +-- Port
                                                        443/tcp
                                                          |
                                                          +-- Service
                                                                HTTPS
                                                                nginx
```

Future extension:

```text
HTTPS
  |
  +-- Website
        |
        +-- Technology
        |
        +-- Endpoint
              |
              +-- Finding
                    |
                    +-- Finding Source
                          Nuclei
```

---

## 25. Database as Source of Truth

The database should represent the current and historical state of the attack surface.

Scanner execution should therefore follow this conceptual model:

```text
Scanner
  ↓
Observation
  ↓
Normalization
  ↓
Correlation
  ↓
Database
  ↓
Change Detection
  ↓
Dashboard / Alert / Report
```

Scanner output itself is not the application's final state.

This distinction is important because scanners can:
- change versions
- change output formats
- overlap in coverage
- be replaced
- fail partially
- return duplicate observations

NETRA must remain stable even when its underlying scanner engines change.

---

## 26. Design Decisions

### Decision 1 — Canonical Data Model

**Decision:** Use NETRA-owned canonical entities instead of scanner-specific database tables.

**Reason:** Prevent tight coupling to individual scanners.

### Decision 2 — Source Evidence Separation

**Decision:** Keep scanner/source information separate from canonical entities.

**Reason:** Allow multiple sources to contribute evidence to one entity.

### Decision 3 — Historical Tracking

**Decision:** Store first_seen and last_seen on observable entities.

**Reason:** Enable attack-surface change monitoring.

### Decision 4 — Scanner Modularity

**Decision:** Treat scanners as pluggable engines behind parser/normalizer adapters.

**Reason:** New scanners should not require a database redesign.

### Decision 5 — PostgreSQL as Source of Truth

**Decision:** PostgreSQL stores canonical state and historical information.

**Reason:** The dashboard, correlation engine, reporting, and change detection should operate on one consistent data source.

---

## 27. Open Design Questions

The following should be resolved as implementation progresses rather than prematurely locked:

1. UUID vs BIGINT primary keys.
2. Exact status enum values.
3. Whether `assets` should eventually become a generic parent entity.
4. Whether DNS records should be generalized beyond subdomains.
5. Exact website-to-service relationship.
6. Technology relationship model.
7. Finding deduplication logic.
8. Raw scanner evidence storage.
9. Scan-to-observation relationship.
10. Event/change-history architecture.
11. Risk scoring model.
12. Asset ownership confidence.

These are intentionally left open until the corresponding implementation phase provides enough context.

---

## 28. Phase 2 Success Criteria

Phase 2 is considered complete when:

- the initial canonical entities are implemented
- relationships are enforced with foreign keys
- important identity constraints are defined
- historical fields exist where required
- indexes support expected lookup patterns
- representative seed data can be inserted
- relationships can be queried end-to-end
- the schema remains independent from any specific scanner
- the migration can be reproduced on a clean PostgreSQL instance

---

## 29. Reference Architecture

```text
                    PROJECT
                       |
                    DOMAIN
                       |
                   SUBDOMAIN
                       |
                  DNS RECORD
                       |
                 DNS / IP LINK
                       |
                      IP
                       |
                     PORT
                       |
                    SERVICE
                       |
              +--------+--------+
              |                 |
           WEBSITE           OTHER SERVICE
              |
        +-----+------+
        |            |
   TECHNOLOGY     ENDPOINT
                       |
                    FINDING
                       |
                FINDING SOURCE
```

This structure is the canonical direction for NETRA's data model and will evolve through explicit documented design decisions as later phases are implemented.
