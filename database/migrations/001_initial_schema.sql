-- NETRA initial canonical schema
-- Migration: 001_initial_schema
-- PostgreSQL 16+

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE projects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    status TEXT NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'inactive', 'archived')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE domains (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'inactive', 'archived')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_domains_project_name UNIQUE (project_id, name)
);

CREATE TABLE subdomains (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    domain_id UUID NOT NULL REFERENCES domains(id) ON DELETE CASCADE,
    fqdn TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'inactive')),
    first_seen TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_subdomains_domain_fqdn UNIQUE (domain_id, fqdn)
);

CREATE TABLE dns_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subdomain_id UUID NOT NULL REFERENCES subdomains(id) ON DELETE CASCADE,
    record_type TEXT NOT NULL,
    value TEXT NOT NULL,
    ttl INTEGER CHECK (ttl IS NULL OR ttl >= 0),
    first_seen TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_dns_records_identity
        UNIQUE (subdomain_id, record_type, value)
);

CREATE TABLE ip_addresses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    address INET NOT NULL,
    version SMALLINT NOT NULL
        CHECK (version IN (4, 6)),
    first_seen TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_ip_addresses_address UNIQUE (address)
);

CREATE TABLE dns_ip_resolutions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    dns_record_id UUID NOT NULL REFERENCES dns_records(id) ON DELETE CASCADE,
    ip_address_id UUID NOT NULL REFERENCES ip_addresses(id) ON DELETE CASCADE,
    first_seen TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_dns_ip_resolutions_identity
        UNIQUE (dns_record_id, ip_address_id)
);

CREATE TABLE ports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ip_address_id UUID NOT NULL REFERENCES ip_addresses(id) ON DELETE CASCADE,
    port INTEGER NOT NULL CHECK (port BETWEEN 1 AND 65535),
    protocol TEXT NOT NULL
        CHECK (protocol IN ('tcp', 'udp')),
    state TEXT NOT NULL DEFAULT 'open'
        CHECK (state IN ('open', 'closed', 'filtered', 'unknown')),
    first_seen TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_ports_identity
        UNIQUE (ip_address_id, port, protocol)
);

CREATE TABLE services (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    port_id UUID NOT NULL REFERENCES ports(id) ON DELETE CASCADE,
    name TEXT,
    product TEXT,
    version TEXT,
    banner TEXT,
    confidence NUMERIC(5, 2)
        CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 100)),
    first_seen TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE scans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    scan_type TEXT NOT NULL
        CHECK (scan_type IN (
            'DISCOVERY',
            'DNS',
            'PORT_SCAN',
            'WEB',
            'VULNERABILITY',
            'FULL'
        )),
    status TEXT NOT NULL DEFAULT 'queued'
        CHECK (status IN (
            'queued',
            'running',
            'completed',
            'failed',
            'cancelled'
        )),
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_scans_time_order
        CHECK (
            completed_at IS NULL
            OR started_at IS NULL
            OR completed_at >= started_at
        )
);

CREATE INDEX idx_domains_project_id
    ON domains(project_id);

CREATE INDEX idx_subdomains_domain_id
    ON subdomains(domain_id);

CREATE INDEX idx_subdomains_status
    ON subdomains(status);

CREATE INDEX idx_subdomains_last_seen
    ON subdomains(last_seen);

CREATE INDEX idx_dns_records_subdomain_id
    ON dns_records(subdomain_id);

CREATE INDEX idx_dns_records_type
    ON dns_records(record_type);

CREATE INDEX idx_dns_ip_resolutions_dns_record_id
    ON dns_ip_resolutions(dns_record_id);

CREATE INDEX idx_dns_ip_resolutions_ip_address_id
    ON dns_ip_resolutions(ip_address_id);

CREATE INDEX idx_ip_addresses_last_seen
    ON ip_addresses(last_seen);

CREATE INDEX idx_ports_ip_address_id
    ON ports(ip_address_id);

CREATE INDEX idx_ports_state
    ON ports(state);

CREATE INDEX idx_services_port_id
    ON services(port_id);

CREATE INDEX idx_scans_project_id
    ON scans(project_id);

CREATE INDEX idx_scans_status
    ON scans(status);

CREATE INDEX idx_scans_created_at
    ON scans(created_at);

COMMIT;
