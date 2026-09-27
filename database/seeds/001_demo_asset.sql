-- NETRA demo seed
-- Safe to rerun: only the "NETRA Demo" project is replaced.
-- Uses TEST-NET documentation-only IP 203.0.113.10.

BEGIN;

DELETE FROM projects
WHERE name = 'NETRA Demo';

WITH project AS (
    INSERT INTO projects (name, description)
    VALUES (
        'NETRA Demo',
        'Development-only demo data for validating the NETRA asset model'
    )
    RETURNING id
),
domain AS (
    INSERT INTO domains (project_id, name)
    SELECT id, 'example.com'
    FROM project
    RETURNING id, project_id
),
subdomain AS (
    INSERT INTO subdomains (domain_id, fqdn)
    SELECT id, 'test.example.com'
    FROM domain
    RETURNING id, domain_id
),
ip AS (
    INSERT INTO ip_addresses (address)
    VALUES ('203.0.113.10')
    RETURNING id
),
dns AS (
    INSERT INTO dns_records (subdomain_id, record_type, value)
    SELECT id, 'A', '203.0.113.10'
    FROM subdomain
    RETURNING id, subdomain_id
),
resolution AS (
    INSERT INTO dns_ip_resolutions (dns_record_id, ip_address_id)
    SELECT dns.id, ip.id
    FROM dns
    CROSS JOIN ip
    RETURNING dns_record_id, ip_address_id
),
p80 AS (
    INSERT INTO ports (ip_address_id, port, protocol)
    SELECT id, 80, 'tcp' FROM ip
    RETURNING id
),
p443 AS (
    INSERT INTO ports (ip_address_id, port, protocol)
    SELECT id, 443, 'tcp' FROM ip
    RETURNING id
),
p8080 AS (
    INSERT INTO ports (ip_address_id, port, protocol)
    SELECT id, 8080, 'tcp' FROM ip
    RETURNING id
),
p8888 AS (
    INSERT INTO ports (ip_address_id, port, protocol)
    SELECT id, 8888, 'tcp' FROM ip
    RETURNING id
),
services AS (
    INSERT INTO services (port_id, name, product)
    SELECT p80.id, 'HTTP', NULL FROM p80
    UNION ALL
    SELECT p443.id, 'HTTPS', NULL FROM p443
    UNION ALL
    SELECT p8080.id, 'HTTP', NULL FROM p8080
    UNION ALL
    SELECT p8888.id, 'HTTP', NULL FROM p8888
),
web AS (
    INSERT INTO web_states (
        subdomain_id,
        port_id,
        scheme,
        reachable,
        status_code,
        title,
        server,
        response_time_ms,
        content_length
    )
    SELECT s.id, p80.id, 'http', TRUE, 200,
           'Demo Application', 'nginx', 42, 18420
    FROM subdomain s CROSS JOIN p80

    UNION ALL

    SELECT s.id, p443.id, 'https', TRUE, 200,
           'Demo Application', 'nginx', 58, 18510
    FROM subdomain s CROSS JOIN p443

    UNION ALL

    SELECT s.id, p8080.id, 'http', TRUE, 403,
           'Forbidden', NULL, 71, 512
    FROM subdomain s CROSS JOIN p8080

    UNION ALL

    SELECT s.id, p8888.id, 'http', TRUE, 200,
           'Legacy Application', NULL, 93, 22140
    FROM subdomain s CROSS JOIN p8888
),
nginx AS (
    INSERT INTO technologies (name, category)
    VALUES ('nginx', 'web_server')
    RETURNING id
),
php AS (
    INSERT INTO technologies (name, category)
    VALUES ('PHP', 'programming_language')
    RETURNING id
),
nginx_detection AS (
    INSERT INTO technology_detections (subdomain_id, technology_id)
    SELECT s.id, n.id
    FROM subdomain s CROSS JOIN nginx n
    RETURNING id
),
php_detection AS (
    INSERT INTO technology_detections (subdomain_id, technology_id)
    SELECT s.id, p.id
    FROM subdomain s CROSS JOIN php p
    RETURNING id
)
INSERT INTO technology_detection_ports (
    technology_detection_id,
    port_id,
    version,
    confidence
)
SELECT d.id, p.id, '1.24.0', 0.95
FROM nginx_detection d CROSS JOIN p80 p

UNION ALL

SELECT d.id, p.id, '1.24.0', 0.95
FROM nginx_detection d CROSS JOIN p443 p

UNION ALL

SELECT d.id, p.id, '8.3.0', 0.90
FROM php_detection d CROSS JOIN p80 p

UNION ALL

SELECT d.id, p.id, '8.3.0', 0.90
FROM php_detection d CROSS JOIN p8888 p;

COMMIT;
