import unittest
from uuid import uuid4

from app.services.change_detection_service import (
    AssetObservation,
    PortObservation,
    TechnologyObservation,
    WebObservation,
    detect_asset_changes,
)


class ChangeDetectionServiceTests(unittest.TestCase):
    def setUp(self):
        self.asset_id = uuid4()
        self.port_80_id = uuid4()
        self.port_443_id = uuid4()
        self.web_80_id = uuid4()
        self.tech_nginx_id = uuid4()

    def test_first_observation_is_discovered(self):
        events = detect_asset_changes(
            None,
            AssetObservation(entity_id=self.asset_id),
        )
        self.assertEqual(
            [event.change_type for event in events],
            ["ASSET_DISCOVERED"],
        )

    def test_port_opened(self):
        previous = AssetObservation(entity_id=self.asset_id)
        current = AssetObservation(
            entity_id=self.asset_id,
            ports={
                (443, "tcp"): PortObservation(
                    entity_id=self.port_443_id,
                    port=443,
                    protocol="tcp",
                    state="open",
                )
            },
        )
        events = detect_asset_changes(previous, current)
        self.assertEqual(
            [event.change_type for event in events],
            ["PORT_OPENED"],
        )

    def test_http_status_change(self):
        previous = AssetObservation(
            entity_id=self.asset_id,
            web_states={
                (self.port_80_id, "http"): WebObservation(
                    entity_id=self.web_80_id,
                    port_id=self.port_80_id,
                    scheme="http",
                    reachable=True,
                    status_code=200,
                )
            },
        )
        current = AssetObservation(
            entity_id=self.asset_id,
            web_states={
                (self.port_80_id, "http"): WebObservation(
                    entity_id=self.web_80_id,
                    port_id=self.port_80_id,
                    scheme="http",
                    reachable=True,
                    status_code=403,
                )
            },
        )
        events = detect_asset_changes(previous, current)
        self.assertEqual(
            [event.change_type for event in events],
            ["HTTP_STATUS_CHANGED"],
        )

    def test_technology_added_and_version_changed(self):
        previous = AssetObservation(
            entity_id=self.asset_id,
            technologies={
                "nginx": TechnologyObservation(
                    entity_id=self.tech_nginx_id,
                    name="nginx",
                    version="1.24.0",
                )
            },
        )
        current = AssetObservation(
            entity_id=self.asset_id,
            technologies={
                "nginx": TechnologyObservation(
                    entity_id=self.tech_nginx_id,
                    name="nginx",
                    version="1.26.0",
                ),
                "PHP": TechnologyObservation(
                    entity_id=uuid4(),
                    name="PHP",
                    version="8.3.0",
                ),
            },
        )
        events = detect_asset_changes(previous, current)
        self.assertEqual(
            sorted(event.change_type for event in events),
            ["TECHNOLOGY_ADDED", "TECHNOLOGY_VERSION_CHANGED"],
        )

    def test_asset_disappeared_and_reappeared(self):
        missing = AssetObservation(
            entity_id=self.asset_id,
            present=False,
        )
        disappear_events = detect_asset_changes(
            AssetObservation(entity_id=self.asset_id, present=True),
            missing,
        )
        reappear_events = detect_asset_changes(
            missing,
            AssetObservation(entity_id=self.asset_id, present=True),
        )
        self.assertEqual(
            [event.change_type for event in disappear_events],
            ["ASSET_DISAPPEARED"],
        )
        self.assertEqual(
            [event.change_type for event in reappear_events],
            ["ASSET_REAPPEARED"],
        )

    def test_no_change_produces_no_events(self):
        previous = AssetObservation(
            entity_id=self.asset_id,
            dns_values={"203.0.113.10"},
            ip_values={"203.0.113.10"},
        )
        current = AssetObservation(
            entity_id=self.asset_id,
            dns_values={"203.0.113.10"},
            ip_values={"203.0.113.10"},
        )
        self.assertEqual(
            detect_asset_changes(previous, current),
            [],
        )


if __name__ == "__main__":
    unittest.main()
