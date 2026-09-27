
# NETRA — Canonical Data Model

## 1. Purpose

NETRA uses a scanner-agnostic canonical data model.

Scanner output is evidence. It is parsed, normalized, correlated, and then stored as canonical NETRA state in PostgreSQL.

Core flow:

    Discover → Resolve → Expose → Validate → Enrich → Correlate → Monitor → Assess later

The primary logical web asset is the subdomain.

## 2. Canonical Asset View

A Project is the monitoring scope. A Domain is a root domain inside a Project. A Subdomain is the canonical logical host/web asset.

Example consolidated view:

    test.example.com
    ├── DNS
    │   └── A → 203.0.113.10
    ├── IP
    │   └── 203.0.113.10
    ├── Ports / Services
    │   ├── 80/tcp
    │   ├── 443/tcp
    │   ├── 8080/tcp
    │   └── 8888/tcp
    ├── Web States
    │   ├── :80   → HTTP 200
    │   ├── :443  → HTTPS 200
    │   ├── :8080 → HTTP 403
    │   └── :8888 → HTTP 200
    └── Technologies
        ├── nginx
        │    observed_on → 80, 443
        └── PHP
             observed_on → 80, 8888

This is a consolidated application/frontend view, not one physical table.

## 3. Current Canonical Entities

The existing migration 001 provides:

- projects
- domains
- subdomains
- dns_records
- ip_addresses
- dns_ip_resolutions
- ports
- services
- scans

Migration 002 adds:

- technologies
- web_states
- technology_detections
- technology_detection_ports
- asset_change_events

Vulnerability entities are intentionally deferred.

## 4. Port vs Web State

Port and web state remain separate database entities.

A Port answers: "Is this network port exposed/open?"

A Web State answers: "Did this hostname/scheme/port respond to an HTTP(S) probe, and what did it return?"

Conceptually:

    Subdomain
      ↓
    IP
      ↓
    Port
      ├── Service
      └── Web State

Example:

    8080/tcp
    state = open

    Web State
    scheme = http
    reachable = true
    status_code = 403

The frontend combines these into one exposure row such as:

    8080/tcp | HTTP | 403 Forbidden

This separation is intentional because different scanner engines may provide network and application-layer observations.

## 5. Web State Identity

A Web State belongs to:

- one subdomain
- one port
- one scheme

The subdomain reference is required because the same IP and port can host multiple virtual hosts.

Example:

    203.0.113.10:443
    app.example.com   → 200
    admin.example.com → 403

Initial Web State fields:

- id
- subdomain_id
- port_id
- scheme
- reachable
- status_code
- title
- server
- response_time_ms
- content_length
- first_seen
- last_seen
- created_at
- updated_at

HTTP status is not a validity boolean. 200, 301, 302, 401, 403, 404, and 500 can all represent a reachable web endpoint. Failed probes may use reachable=false and status_code=NULL.

## 6. Technology Model

Technology is canonical at the Subdomain level.

The same technology must not be duplicated just because it is observed on several ports.

Example:

    test.example.com

    nginx
      observed_on → 80
      observed_on → 443

    PHP
      observed_on → 80
      observed_on → 8888

The relationship is:

    Subdomain
      ↓
    Technology Detection
      ↓
    Technology
      ↓
    Technology Detection Ports
      ↓
    Port

The Technology catalog contains canonical names and categories.

Initial categories:

- web_server
- programming_language
- framework
- cms
- javascript
- cdn
- waf
- database
- runtime
- other

A Technology Detection stores the current technology state for a subdomain, including version and confidence where available.

If different versions are genuinely observed on different ports, NETRA may maintain multiple detection states internally while the frontend consolidates the technology name.

## 7. Current State and History

NETRA does not store an identical snapshot for every scan.

Current state is updated whenever an observation is processed.

Example:

    Scan 1 → HTTP 200
    Scan 2 → HTTP 200
    Scan 3 → HTTP 200

Current state remains HTTP 200 and last_seen advances.

Only meaningful changes create history events.

Example:

    HTTP 200 → HTTP 403

creates an HTTP_STATUS_CHANGED event.

This avoids unbounded growth from redundant observations.

## 8. Change Detection Engine

Change Detection is application business logic, not a PostgreSQL trigger.

Location:

    backend/app/services/change_detection_service.py

Pipeline:

    Scanner
      ↓
    Parser
      ↓
    Normalizer
      ↓
    Canonical Observation
      ↓
    Change Detection Engine
      ↓
    Current State + Change Event when meaningful

Initial change categories:

- ASSET_DISCOVERED
- ASSET_REAPPEARED
- ASSET_DISAPPEARED
- DNS_CHANGED
- IP_CHANGED
- PORT_OPENED
- PORT_CLOSED
- SERVICE_CHANGED
- WEB_AVAILABLE
- WEB_UNAVAILABLE
- HTTP_STATUS_CHANGED
- TECHNOLOGY_ADDED
- TECHNOLOGY_REMOVED
- TECHNOLOGY_VERSION_CHANGED

The event taxonomy can expand as implementation progresses.

## 9. Change Events

asset_change_events is an audit/history layer.

Initial fields:

- id
- entity_type
- entity_id
- change_type
- old_value JSONB
- new_value JSONB
- scan_id
- detected_at
- metadata JSONB

The generic event table intentionally uses entity_type + entity_id. Canonical asset tables continue to use normal PostgreSQL foreign keys.

## 10. Scanner Normalization

NETRA must not create scanner-specific copies of the same asset.

Example:

    Amass     → app.example.com
    Subfinder → app.example.com
    CT        → app.example.com

Result:

    One canonical subdomain → app.example.com

Likewise:

    Naabu → 443/tcp
    Other scanner → 443/tcp

Result:

    One canonical port → 443/tcp

Scanner/source metadata may be preserved internally later for troubleshooting, but it must not create duplicate canonical assets or dominate the dashboard.

## 11. Scanner Roles

| Tool | Initial role |
|---|---|
| Amass | Broad subdomain/discovery enrichment |
| Subfinder | Passive subdomain discovery |
| dnsx | DNS resolution and DNS record enrichment |
| Naabu | Port discovery |
| httpx | HTTP/HTTPS probing and web enrichment |
| Katana | Web crawling and endpoint discovery, later |
| Nuclei | Vulnerability assessment, later |

Technology detection initially uses web enrichment results. Additional fingerprinting engines can be added later without redesigning the canonical model.

## 12. Retention

NETRA must avoid unbounded data growth.

Data classes:

- Current state: retained while the asset is relevant/active.
- Change events: configurable retention.
- Raw scanner output: shorter retention because it is evidence rather than canonical state.
- Inactive assets: configurable grace period before archival/purge.

Exact retention values are intentionally not fixed yet. They should be chosen after real scan-volume measurements.

Example future configuration only:

    raw_scanner_output: 30d
    change_events: 365d
    inactive_assets: 90d

These are examples, not current defaults.

## 13. Identity and Deduplication

Initial identities:

| Entity | Identity |
|---|---|
| Project | UUID |
| Domain | normalized name + project |
| Subdomain | normalized FQDN + domain |
| DNS Record | subdomain + record type + normalized value |
| IP | normalized IP |
| DNS/IP relationship | DNS record + IP |
| Port | IP + port + protocol |
| Web State | subdomain + port + scheme |
| Technology | normalized name + category |
| Technology Detection | subdomain + technology |
| Scan | unique scan UUID |

Normalization includes lowercase hostnames, canonical DNS notation, canonical IP representation, and protocol normalization.

## 14. Vulnerability Boundary

The current foundation ends at:

    Project
      ↓
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
    Web State
      ↓
    Technology
      ↓
    Change Detection

Later:

    Validated Web Asset
      ↓
    Katana
      ↓
    Web Paths / Resources
      ↓
    Nuclei
      ↓
    Canonical Findings

Vulnerability tables are not part of migration 002.

## 15. Backend / Database / Frontend Responsibilities

### PostgreSQL

Stores:

- canonical entities
- relationships
- current state
- meaningful change history
- integrity constraints
- temporal fields

### Backend

Handles:

- scanner parsing
- normalization
- correlation
- change detection
- scan orchestration
- retention jobs

### Frontend

Handles:

- consolidated asset presentation
- exposure tables
- technology views
- change visualization
- filtering and navigation

The frontend may combine multiple database entities into one user-facing exposure row.

## 16. Design Decisions

### Decision 1 — Canonical Subdomain Asset

A discovered subdomain is represented once as a canonical logical asset.

### Decision 2 — Current State + Meaningful History

Current state is continuously updated; history is created only for meaningful changes.

### Decision 3 — Port and Web State Separation

Ports and HTTP(S) states remain separate database entities because they represent different layers and may originate from different scanners.

### Decision 4 — Unified Frontend Exposure

The frontend presents port + service + web state as one exposure view.

### Decision 5 — Technology Canonicalization

Technology is canonical at the subdomain level; observed ports are represented through a relationship.

### Decision 6 — Application-Level Change Detection

Change detection lives in backend services rather than database triggers.

### Decision 7 — Scanner-Agnostic Storage

Scanner output is normalized before becoming canonical state.

### Decision 8 — Vulnerability Separation

Vulnerability findings are deferred until the discovery/exposure foundation is stable.

## 17. Phase 2 Boundary

Phase 2 covers:

    Project
      ↓
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
    Web State
      ↓
    Technology
      ↓
    Change Detection

Phase 3 will cover web path/endpoint discovery and vulnerability assessment.

PostgreSQL remains the source of truth for canonical current state and meaningful historical changes.
