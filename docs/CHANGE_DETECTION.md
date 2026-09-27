# NETRA — Change Detection Engine

## 1. Purpose

The Change Detection Engine compares two normalized canonical observations of the same logical asset and emits only meaningful changes.

It is application business logic. It does not use PostgreSQL triggers and it does not persist data by itself.

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
    Current State + asset_change_events

## 2. Canonical Asset and Identity Rules

NETRA separates **asset identity** from the **state observed inside an asset**.

### 2.1 Canonical hierarchy

The logical hierarchy is:

    Project
      └── Domain
            └── Subdomain
                  ├── DNS
                  ├── IP
                  ├── Ports / Services
                  ├── Web States
                  └── Technologies

The **Subdomain is the primary canonical logical asset** used by the attack-surface model.

A Domain is a parent/container entity within the project hierarchy. A newly discovered root domain can therefore create a new Domain entity, but it is distinct from the dashboard concept of a Subdomain asset.

### 2.2 What creates a new asset?

A new Subdomain identity creates a new canonical asset.

Examples:

    api.example.com     → new asset
    admin.example.com   → new asset

If the Subdomain already exists, changes to its observed state do **not** create another asset.

Examples:

    api.example.com
      IP changed              → internal asset change
      DNS changed             → internal asset change
      443/tcp opened          → internal asset change
      HTTP 200 → 403          → internal asset change
      nginx version changed   → internal asset change

The identity remains:

    api.example.com

Therefore NETRA must never create a second Subdomain asset merely because its IP, port, service, web state, or technology changed.

### 2.3 Scanner duplication must not create duplicate assets

Different discovery sources can report the same logical Subdomain:

    Amass
       └── api.example.com

    Subfinder
       └── api.example.com

    Certificate Transparency
       └── api.example.com

These observations must be normalized and correlated into:

    ONE CANONICAL ASSET
    api.example.com

Scanner-specific observations are evidence used to enrich or validate the canonical asset; they are not separate asset identities.

## 3. Core Change Detection Rules

The engine follows these rules in order:

### Rule 1 — Determine asset identity first

Before comparing state, NETRA determines whether the canonical Subdomain already exists.

    Does canonical asset identity exist?
             │
        ┌────┴────┐
       NO        YES
        │          │
        ▼          ▼
  Create asset   Compare state

### Rule 2 — New Subdomain = asset discovery

If no previous canonical observation exists for the Subdomain:

    ASSET_DISCOVERED

is emitted.

The DNS, IP, ports, services, web states, and technologies observed during that initial discovery become the **baseline state of the new asset**.

They are not treated as internal changes from a nonexistent baseline.

Therefore an initial discovery such as:

    test.example.com
      A → 203.0.113.10
      80/tcp   HTTP 200
      443/tcp  HTTPS 200
      nginx
      PHP

results in one asset-discovery event, with those values stored as the asset's initial state.

The engine does not need to emit:

    IP_CHANGED
    PORT_OPENED
    WEB_AVAILABLE
    TECHNOLOGY_ADDED

for every property of a brand-new asset.

### Rule 3 — Existing Subdomain = compare internal state

If the Subdomain already exists, NETRA compares the current observation with the previous known state.

Only the changed component generates an event.

    Existing asset
          │
          ▼
      Compare state
          │
     ┌────┴────┐
   Changed   No change
     │          │
     ▼          ▼
 Record event  Do nothing

### Rule 4 — Internal changes never create a new asset

The following are state changes of the existing Subdomain:

- DNS changes
- IP changes
- Port opens
- Port closes
- Service changes
- Web availability changes
- HTTP status changes
- Technology additions
- Technology removals
- Technology version changes

They must update the existing asset state and create the corresponding change event when applicable.

### Rule 5 — No meaningful change = no event

If the canonical identity and all tracked state remain unchanged:

    No asset creation
    No change event

The engine must not create history entries merely because another scan occurred.

### Rule 6 — Asset disappearance is different from an internal change

If an existing Subdomain is no longer observed, this is an asset lifecycle event:

    ASSET_DISAPPEARED

It is not equivalent to:

    PORT_CLOSED
    WEB_UNAVAILABLE
    TECHNOLOGY_REMOVED

Those internal events describe changes to an asset that still exists in the authoritative observation.

## 4. Asset Lifecycle

The canonical lifecycle is:

    First observed
         │
         ▼
    ASSET_DISCOVERED
         │
         ▼
    Active asset
         │
       Scan
         │
    ┌────┴───────────────┐
    │                    │
 No state change     State changed
    │                    │
    ▼                    ▼
 Do nothing         Record event
    │                    │
    └─────────┬──────────┘
              ▼
         Active asset
              │
      Authoritative scan
              │
       Asset not observed
              ▼
      ASSET_DISAPPEARED
              │
       Observed again
              ▼
       ASSET_REAPPEARED

The distinction is important:

- **Discovery** creates the canonical asset.
- **Change** modifies the state of an existing asset.
- **Disappearance** changes the lifecycle state of an existing asset.
- **Reappearance** returns a previously disappeared asset to the active state.
- **No change** produces no event.

## 5. Important Lifecycle Rule

ASSET_DISAPPEARED must only be generated from an authoritative scan scope where the asset was expected to be observed.

A missing result from a partial scanner must not be interpreted as disappearance.

For example, if Subfinder runs only one passive source and does not return an existing Subdomain, NETRA must not conclude that the Subdomain disappeared.

Disappearance requires an observation that is authoritative for the relevant scope.

Lifecycle:

- first known observation → ASSET_DISCOVERED
- known asset absent from an authoritative full-scope observation → ASSET_DISAPPEARED
- previously disappeared asset observed again → ASSET_REAPPEARED

## 6. Event Rules

| Event | Trigger | Creates a new Subdomain asset? |
|---|---|---|
| ASSET_DISCOVERED | No previous canonical Subdomain observation exists | Yes |
| ASSET_REAPPEARED | Previously disappeared Subdomain is observed again | No |
| ASSET_DISAPPEARED | Existing Subdomain is absent from an authoritative observation | No |
| DNS_CHANGED | Normalized DNS value set changed | No |
| IP_CHANGED | Normalized IP value set changed | No |
| PORT_OPENED | Port transitioned into open state | No |
| PORT_CLOSED | Port transitioned out of open state | No |
| SERVICE_CHANGED | Canonical service fields changed for the same port | No |
| WEB_AVAILABLE | Web state transitioned to reachable | No |
| WEB_UNAVAILABLE | Web state transitioned from reachable to unavailable | No |
| HTTP_STATUS_CHANGED | Both observations have HTTP status codes and the status changed | No |
| TECHNOLOGY_ADDED | Technology name exists only in current observation | No |
| TECHNOLOGY_REMOVED | Technology name exists only in previous observation | No |
| TECHNOLOGY_VERSION_CHANGED | Same technology exists but its observed version changed | No |

The only event in this table that creates a new **Subdomain asset** is ASSET_DISCOVERED.

A newly discovered Domain is a separate hierarchy-level creation and is not represented by ASSET_DISCOVERED in the current event model.

## 7. Initial Discovery vs Subsequent Changes

This distinction is a core NETRA rule.

### Initial discovery

    No canonical asset
           +
    test.example.com discovered
           ↓
    ASSET_DISCOVERED
           ↓
    Store initial baseline:
      DNS
      IP
      Ports
      Services
      Web States
      Technologies

### Subsequent observation

    Existing test.example.com
           +
    443/tcp already existed
           +
    HTTP 200 → HTTP 403
           ↓
    HTTP_STATUS_CHANGED

No second asset is created.

### Example

Scan #1:

    test.example.com
      80/tcp  HTTP 200
      443/tcp HTTPS 200

Result:

    ASSET_DISCOVERED

Scan #2:

    test.example.com
      80/tcp  HTTP 200
      443/tcp HTTPS 403

Result:

    HTTP_STATUS_CHANGED
    old_value = {"status_code": 200}
    new_value = {"status_code": 403}

Asset count remains unchanged.

## 8. Current Implementation Boundary

This first implementation is a pure Python comparison layer.

It does not:

- connect to PostgreSQL;
- execute scanner commands;
- modify current-state tables;
- insert into asset_change_events;
- expose a FastAPI endpoint.

Persistence belongs to the later ingestion/repository layer.

## 9. Why Pure Comparison First

Keeping comparison independent from persistence gives NETRA a deterministic unit that can be tested with small synthetic observations.

Example:

    Scan #1
    test.example.com
      80/tcp  HTTP 200

    Scan #2
    test.example.com
      80/tcp  HTTP 403

Expected event:

    HTTP_STATUS_CHANGED
    old_value = {"status_code": 200}
    new_value = {"status_code": 403}

No duplicate asset is created.

## 10. Test Coverage

The standard-library test suite covers:

- first discovery;
- port opening;
- HTTP status change;
- technology addition;
- technology version change;
- disappearance and reappearance;
- no-change behavior.

Run from the backend directory:

    python -m unittest discover -s tests -v

The tests intentionally avoid an external test dependency for this initial phase.
