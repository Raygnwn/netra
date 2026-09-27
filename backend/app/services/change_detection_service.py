from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any
from uuid import UUID


@dataclass(frozen=True)
class PortObservation:
    entity_id: UUID
    port: int
    protocol: str
    state: str = "open"
    service: dict[str, Any] | None = None


@dataclass(frozen=True)
class WebObservation:
    entity_id: UUID
    port_id: UUID
    scheme: str
    reachable: bool
    status_code: int | None = None


@dataclass(frozen=True)
class TechnologyObservation:
    entity_id: UUID
    name: str
    version: str | None = None


@dataclass
class AssetObservation:
    """Canonical observation for one logical subdomain asset."""
    entity_id: UUID
    present: bool = True
    dns_values: set[str] = field(default_factory=set)
    ip_values: set[str] = field(default_factory=set)
    ports: dict[tuple[int, str], PortObservation] = field(default_factory=dict)
    web_states: dict[tuple[UUID, str], WebObservation] = field(default_factory=dict)
    technologies: dict[str, TechnologyObservation] = field(default_factory=dict)


@dataclass(frozen=True)
class ChangeEvent:
    entity_type: str
    entity_id: UUID
    change_type: str
    old_value: Any = None
    new_value: Any = None
    metadata: dict[str, Any] = field(default_factory=dict)


def _sorted_values(values: set[str]) -> list[str]:
    return sorted(values)


def _service_signature(service: dict[str, Any] | None) -> dict[str, Any] | None:
    if service is None:
        return None
    return {
        "name": service.get("name"),
        "product": service.get("product"),
        "version": service.get("version"),
    }


def detect_asset_changes(
    previous: AssetObservation | None,
    current: AssetObservation,
) -> list[ChangeEvent]:
    """Compare two canonical observations and return meaningful changes."""
    if previous is None:
        return [
            ChangeEvent(
                entity_type="subdomain",
                entity_id=current.entity_id,
                change_type="ASSET_DISCOVERED",
                new_value={"present": current.present},
            )
        ]

    events: list[ChangeEvent] = []

    if not previous.present and current.present:
        events.append(ChangeEvent(
            entity_type="subdomain",
            entity_id=current.entity_id,
            change_type="ASSET_REAPPEARED",
            old_value={"present": False},
            new_value={"present": True},
        ))
    elif previous.present and not current.present:
        events.append(ChangeEvent(
            entity_type="subdomain",
            entity_id=current.entity_id,
            change_type="ASSET_DISAPPEARED",
            old_value={"present": True},
            new_value={"present": False},
        ))

    if previous.dns_values != current.dns_values:
        events.append(ChangeEvent(
            entity_type="subdomain",
            entity_id=current.entity_id,
            change_type="DNS_CHANGED",
            old_value={"values": _sorted_values(previous.dns_values)},
            new_value={"values": _sorted_values(current.dns_values)},
        ))

    if previous.ip_values != current.ip_values:
        events.append(ChangeEvent(
            entity_type="subdomain",
            entity_id=current.entity_id,
            change_type="IP_CHANGED",
            old_value={"values": _sorted_values(previous.ip_values)},
            new_value={"values": _sorted_values(current.ip_values)},
        ))

    for key in sorted(set(previous.ports) | set(current.ports)):
        old = previous.ports.get(key)
        new = current.ports.get(key)

        old_open = old is not None and old.state == "open"
        new_open = new is not None and new.state == "open"

        if not old_open and new_open:
            events.append(ChangeEvent(
                entity_type="port",
                entity_id=new.entity_id,
                change_type="PORT_OPENED",
                old_value=None if old is None else {"state": old.state},
                new_value={
                    "port": new.port,
                    "protocol": new.protocol,
                    "state": new.state,
                },
            ))
        elif old_open and not new_open:
            events.append(ChangeEvent(
                entity_type="port",
                entity_id=old.entity_id,
                change_type="PORT_CLOSED",
                old_value={
                    "port": old.port,
                    "protocol": old.protocol,
                    "state": old.state,
                },
                new_value=None if new is None else {"state": new.state},
            ))

        if old is not None and new is not None:
            old_service = _service_signature(old.service)
            new_service = _service_signature(new.service)
            if old_service != new_service:
                service_id = (
                    new.service.get("id")
                    if new.service and new.service.get("id")
                    else new.entity_id
                )
                events.append(ChangeEvent(
                    entity_type="service",
                    entity_id=service_id,
                    change_type="SERVICE_CHANGED",
                    old_value=old_service,
                    new_value=new_service,
                    metadata={
                        "port": new.port,
                        "protocol": new.protocol,
                        "port_id": str(new.entity_id),
                    },
                ))

    for key in sorted(
        set(previous.web_states) | set(current.web_states),
        key=lambda item: (str(item[0]), item[1]),
    ):
        old = previous.web_states.get(key)
        new = current.web_states.get(key)

        old_reachable = old is not None and old.reachable
        new_reachable = new is not None and new.reachable

        if not old_reachable and new_reachable:
            events.append(ChangeEvent(
                entity_type="web_state",
                entity_id=new.entity_id,
                change_type="WEB_AVAILABLE",
                old_value=None if old is None else {"reachable": old.reachable},
                new_value={"reachable": True, "scheme": new.scheme},
            ))
        elif old_reachable and not new_reachable:
            events.append(ChangeEvent(
                entity_type="web_state",
                entity_id=old.entity_id,
                change_type="WEB_UNAVAILABLE",
                old_value={"reachable": True, "scheme": old.scheme},
                new_value=None if new is None else {"reachable": False},
            ))

        if (
            old is not None
            and new is not None
            and old.status_code is not None
            and new.status_code is not None
            and old.status_code != new.status_code
        ):
            events.append(ChangeEvent(
                entity_type="web_state",
                entity_id=new.entity_id,
                change_type="HTTP_STATUS_CHANGED",
                old_value={"status_code": old.status_code},
                new_value={"status_code": new.status_code},
                metadata={
                    "scheme": new.scheme,
                    "port_id": str(new.port_id),
                },
            ))

    for name in sorted(set(previous.technologies) | set(current.technologies)):
        old = previous.technologies.get(name)
        new = current.technologies.get(name)

        if old is None and new is not None:
            events.append(ChangeEvent(
                entity_type="technology_detection",
                entity_id=new.entity_id,
                change_type="TECHNOLOGY_ADDED",
                new_value={"name": new.name, "version": new.version},
            ))
        elif old is not None and new is None:
            events.append(ChangeEvent(
                entity_type="technology_detection",
                entity_id=old.entity_id,
                change_type="TECHNOLOGY_REMOVED",
                old_value={"name": old.name, "version": old.version},
            ))
        elif old is not None and new is not None and old.version != new.version:
            events.append(ChangeEvent(
                entity_type="technology_detection",
                entity_id=new.entity_id,
                change_type="TECHNOLOGY_VERSION_CHANGED",
                old_value={"name": old.name, "version": old.version},
                new_value={"name": new.name, "version": new.version},
            ))

    return events
