-- NETRA migration 002
-- Web enrichment and meaningful change tracking
-- PostgreSQL 16+
--
-- Migration 001 is already applied and must not be edited.
-- This migration adds the canonical web/technology layer and change-event history.

BEGIN;

CREATE TABLE technologies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    category TEXT NOT NULL
        CHECK (category IN (
            'web_server',
            'programming_language',
            'framework',
            'cms',
            'javascript',
            'cdn',
            'waf',
            'database',
            'runtime',
            'other'
        )),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_technologies_name_category
        UNIQUE (name, category)
);

CREATE TABLE web_states (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subdomain_id UUID NOT NULL REFERENCES subdomains(id) ON DELETE CASCADE,
    port_id UUID NOT NULL REFERENCES ports(id) ON DELETE CASCADE,

    scheme TEXT NOT NULL
        CHECK (scheme IN ('http', 'https')),

    reachable BOOLEAN NOT NULL DEFAULT FALSE,
    status_code INTEGER
        CHECK (
            status_code IS NULL
            OR status_code BETWEEN 100 AND 599
        ),
    title TEXT,
    server TEXT,
    response_time_ms BIGINT
        CHECK (
            response_time_ms IS NULL
            OR response_time_ms >= 0
        ),
    content_length BIGINT
        CHECK (
            content_length IS NULL
            OR content_length >= 0
        ),

    first_seen TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_web_states_identity
        UNIQUE (subdomain_id, port_id, scheme)
);

CREATE TABLE technology_detections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subdomain_id UUID NOT NULL REFERENCES subdomains(id) ON DELETE CASCADE,
    technology_id UUID NOT NULL REFERENCES technologies(id) ON DELETE CASCADE,

    active BOOLEAN NOT NULL DEFAULT TRUE,
    first_seen TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_technology_detections_identity
        UNIQUE (subdomain_id, technology_id)
);

CREATE TABLE technology_detection_ports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    technology_detection_id UUID NOT NULL
        REFERENCES technology_detections(id) ON DELETE CASCADE,
    port_id UUID NOT NULL
        REFERENCES ports(id) ON DELETE CASCADE,

    version TEXT,
    confidence NUMERIC(5, 2)
        CHECK (
            confidence IS NULL
            OR (confidence >= 0 AND confidence <= 100)
        ),

    active BOOLEAN NOT NULL DEFAULT TRUE,
    first_seen TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_technology_detection_ports_identity
        UNIQUE (technology_detection_id, port_id)
);

CREATE TABLE asset_change_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    entity_type TEXT NOT NULL
        CHECK (entity_type IN (
            'project',
            'domain',
            'subdomain',
            'dns_record',
            'ip_address',
            'port',
            'service',
            'web_state',
            'technology_detection',
            'technology_detection_port'
        )),

    entity_id UUID NOT NULL,

    change_type TEXT NOT NULL
        CHECK (change_type IN (
            'ASSET_DISCOVERED',
            'ASSET_REAPPEARED',
            'ASSET_DISAPPEARED',
            'DNS_CHANGED',
            'IP_CHANGED',
            'PORT_OPENED',
            'PORT_CLOSED',
            'SERVICE_CHANGED',
            'WEB_AVAILABLE',
            'WEB_UNAVAILABLE',
            'HTTP_STATUS_CHANGED',
            'TECHNOLOGY_ADDED',
            'TECHNOLOGY_REMOVED',
            'TECHNOLOGY_VERSION_CHANGED'
        )),

    old_value JSONB,
    new_value JSONB,

    scan_id UUID REFERENCES scans(id) ON DELETE SET NULL,

    detected_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB
);

CREATE INDEX idx_web_states_subdomain_id
    ON web_states(subdomain_id);

CREATE INDEX idx_web_states_port_id
    ON web_states(port_id);

CREATE INDEX idx_web_states_reachable
    ON web_states(reachable);

CREATE INDEX idx_web_states_last_seen
    ON web_states(last_seen);

CREATE INDEX idx_technology_detections_subdomain_id
    ON technology_detections(subdomain_id);

CREATE INDEX idx_technology_detections_technology_id
    ON technology_detections(technology_id);

CREATE INDEX idx_technology_detections_active
    ON technology_detections(active);

CREATE INDEX idx_technology_detection_ports_detection_id
    ON technology_detection_ports(technology_detection_id);

CREATE INDEX idx_technology_detection_ports_port_id
    ON technology_detection_ports(port_id);

CREATE INDEX idx_technology_detection_ports_active
    ON technology_detection_ports(active);

CREATE INDEX idx_asset_change_events_entity
    ON asset_change_events(entity_type, entity_id);

CREATE INDEX idx_asset_change_events_change_type
    ON asset_change_events(change_type);

CREATE INDEX idx_asset_change_events_scan_id
    ON asset_change_events(scan_id);

CREATE INDEX idx_asset_change_events_detected_at
    ON asset_change_events(detected_at);

COMMIT;
