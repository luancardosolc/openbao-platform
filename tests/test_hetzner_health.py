import unittest

from unittest import mock

from ops.hetzner_health import assess, parse_probe, probe_https, ssh_argv


SAMPLE = """host|openbao-platform-prod-openbao
os|Ubuntu 24.04.4 LTS|24.04
uptime|up 228 days, 9 hours
load|0.08,0.02,0.01
cpus|2
memory|3880000|3150000
disk|78600000|4600000|74000000|7%
reboot|required
unit|docker|active
unit|netbird|active
unit|ssh|active
unit|unattended-upgrades|active
unit|cloud-init-hotplugd|failed
failed_units|cloud-init-hotplugd.service
docker_api|permission-denied
openbao_health|200
netbird_dashboard|200
"""


class HealthReportTests(unittest.TestCase):
    def test_parses_resource_and_service_fields(self):
        report = parse_probe(SAMPLE)
        self.assertEqual(report["host"], "openbao-platform-prod-openbao")
        self.assertEqual(report["os"]["version"], "24.04")
        self.assertEqual(report["root_disk_kib"]["use_percent"], 7)
        self.assertEqual(report["cpu_count"], 2)
        self.assertEqual(report["units"]["docker"], "active")
        self.assertEqual(report["failed_units"], ["cloud-init-hotplugd.service"])

    def test_distinguishes_live_health_from_incomplete_inventory(self):
        checks = {item["name"]: item for item in assess(parse_probe(SAMPLE))}
        self.assertEqual(checks["openbao_http"]["status"], "ok")
        self.assertEqual(checks["netbird_dashboard"]["status"], "ok")
        self.assertEqual(checks["docker_inventory"]["status"], "unknown")
        self.assertEqual(checks["reboot"]["status"], "warning")
        self.assertEqual(checks["systemd_failed_units"]["status"], "warning")
        self.assertEqual(checks["memory_available"]["status"], "ok")
        self.assertEqual(checks["load_5m"]["status"], "ok")

    def test_unknown_app_state_is_not_promoted_to_healthy(self):
        checks = {item["name"]: item for item in assess({"units": {}})}
        self.assertEqual(checks["docker_inventory"]["status"], "unknown")
        self.assertEqual(checks["openbao_http"]["status"], "unknown")

    def test_ssh_uses_batch_mode_and_strict_host_key_validation(self):
        argv = ssh_argv("100.102.58.164", "luan", r"C:\Users\luanc\.ssh\key")
        self.assertIn("BatchMode=yes", argv)
        self.assertIn("StrictHostKeyChecking=yes", argv)
        self.assertNotIn("-tt", argv)

    def test_rejects_ssh_option_injection(self):
        with self.assertRaises(ValueError):
            ssh_argv("-oProxyCommand=bad", "luan", "key")
        with self.assertRaises(ValueError):
            ssh_argv("host", "luan;command", "key")

    def test_dashboard_probe_returns_http_code_and_handles_outage(self):
        response = mock.MagicMock()
        response.status = 200
        response.__enter__.return_value = response
        with mock.patch("ops.hetzner_health.urllib.request.urlopen", return_value=response):
            self.assertEqual(probe_https("https://dashboard.example/"), "200")
        with mock.patch("ops.hetzner_health.urllib.request.urlopen", side_effect=TimeoutError):
            self.assertEqual(probe_https("https://dashboard.example/"), "unreachable")

    def test_dashboard_server_error_is_critical(self):
        checks = {item["name"]: item for item in assess({"netbird_dashboard": "503"})}
        self.assertEqual(checks["netbird_dashboard"]["status"], "critical")


if __name__ == "__main__":
    unittest.main()
