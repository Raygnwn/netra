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

## 2. Important Lifecycle Rule

ASSET_DISAPPEARED must only be generated from an authoritative scan scope where the asset was expected to be observed.

A missing result from a partial scanner must not be interpreted as disappearance.

Lifecycle:

- first known observation → ASSET_DISCOVERED
- known asset absent from an authoritative full-scope observation → ASSET_DISAPPEARED
- previously disappeared asset observed again → ASSET_REAPPEARED

## 3. Initial Event Rules

| Change | Rule |
|---|---|
| ASSET_DISCOVERED | No previous canonical observation exists |
| ASSET_REAPPEARED | Previous observation was not present, current observation is present |
| ASSET_DISAPPEARED | Previous observation was present, current authoritative observation is not present |
| DNS_CHANGED | Normalized DNS value set changed |
| IP_CHANGED | Normalized IP value set changed |
| PORT_OPENED | Port transitioned into open state |
| PORT_CLOSED | Port transitioned out of open state |
| SERVICE_CHANGED | Canonical service fields changed for the same port |
| WEB_AVAILABLE | Web state transitioned to reachable |
| WEB_UNAVAILABLE | Web state transitioned from reachable to unavailable |
| HTTP_STATUS_CHANGED | Both observations have HTTP status codes and the status changed |
| TECHNOLOGY_ADDED | Technology name exists only in current observation |
| TECHNOLOGY_REMOVED | Technology name exists only in previous observation |
| TECHNOLOGY_VERSION_CHANGED | Same technology exists but its observed version changed |

## 4. Current Implementation Boundary

This first implementation is a pure Python comparison layer.

It does not:

- connect to PostgreSQL;
- execute scanner commands;
- modify current-state tables;
- insert into asset_change_events;
- expose a FastAPI endpoint.

Persistence belongs to the later ingestion/repository layer.

## 5. Why Pure Comparison First

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

## 6. Test Coverage

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
