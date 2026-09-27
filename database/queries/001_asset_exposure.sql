-- NETRA query 001
-- Asset-oriented exposure projection.
-- This is a read-only projection over the canonical asset model.
-- It does not create or duplicate data.

SELECT
    s.id AS subdomain_id,
    s.fqdn AS subdomain,
    ia.address::text AS ip_address,
    p.port,
    p.protocol,
    svc.name AS service,
    ws.scheme,
    ws.reachable,
    ws.status_code,
    ws.title,
    ws.server,
    COALESCE(
        string_agg(
            DISTINCT t.name,
            ', ' ORDER BY t.name
        ) FILTER (WHERE t.id IS NOT NULL),
        '—'
    ) AS technologies
FROM subdomains s
JOIN domains d
    ON d.id = s.domain_id
JOIN projects prj
    ON prj.id = d.project_id
JOIN dns_records dr
    ON dr.subdomain_id = s.id
JOIN dns_ip_resolutions dir
    ON dir.dns_record_id = dr.id
JOIN ip_addresses ia
    ON ia.id = dir.ip_address_id
JOIN ports p
    ON p.ip_address_id = ia.id
LEFT JOIN services svc
    ON svc.port_id = p.id
LEFT JOIN web_states ws
    ON ws.subdomain_id = s.id
   AND ws.port_id = p.id
LEFT JOIN technology_detection_ports tdp
    ON tdp.port_id = p.id
   AND tdp.active = TRUE
LEFT JOIN technology_detections td
    ON td.id = tdp.technology_detection_id
   AND td.subdomain_id = s.id
   AND td.active = TRUE
LEFT JOIN technologies t
    ON t.id = td.technology_id
WHERE prj.name = 'NETRA Demo'
GROUP BY
    s.id,
    s.fqdn,
    ia.address,
    p.port,
    p.protocol,
    svc.name,
    ws.scheme,
    ws.reachable,
    ws.status_code,
    ws.title,
    ws.server
ORDER BY
    s.fqdn,
    p.port;
