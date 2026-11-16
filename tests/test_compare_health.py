import unittest

from ops.compare_health import compare


def snapshot(*, load="0.08,0.02,0.01", available=300, disk=7, service="ok"):
    return {
        "host": {
            "load_average": load,
            "memory_kib": {"total": 1000, "available": available},
            "root_disk_kib": {"use_percent": disk},
        },
        "checks": [{"name": "openbao_http", "status": service}],
    }


class CompareHealthTests(unittest.TestCase):
    def test_reports_no_regression_for_steady_health(self):
        result = compare(snapshot(), snapshot(load="0.09,0.03,0.01", available=290, disk=8))
        self.assertEqual(result["result"], "no_regression_detected")

    def test_flags_new_critical_check(self):
        result = compare(snapshot(), snapshot(service="critical"))
        self.assertEqual(result["result"], "review")
        self.assertIn("check openbao_http: ok -> critical", result["regressions"])

    def test_flags_resource_regressions_against_thresholds(self):
        before = snapshot(load="0.08,0.1,0.1", available=500, disk=10)
        after = snapshot(load="0.08,1.5,1.0", available=300, disk=22)
        result = compare(before, after)
        self.assertEqual(result["result"], "review")
        self.assertEqual(len(result["regressions"]), 3)

    def test_existing_warning_is_not_misreported_as_new_regression(self):
        self.assertEqual(compare(snapshot(service="warning"), snapshot(service="warning"))["regressions"], [])

    def test_missing_check_after_was_healthy_requires_review(self):
        before = snapshot(service="ok")
        after = snapshot(service="unknown")
        self.assertIn("check openbao_http: ok -> unknown", compare(before, after)["regressions"])


if __name__ == "__main__":
    unittest.main()
