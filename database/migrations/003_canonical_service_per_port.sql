-- NETRA migration 003
-- Enforce one current canonical service record per port.

BEGIN;

CREATE UNIQUE INDEX uq_services_port_id
    ON services(port_id);

COMMIT;
