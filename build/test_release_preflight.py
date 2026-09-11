#!/usr/bin/env python3
"""Exercise release refusal rules without credentials or external writes."""
import unittest
from release_preflight import verify_entry, verify_result


class ReleasePreflightTests(unittest.TestCase):
    def test_allows_an_unpublished_version(self):
        verify_entry({"versions": [{"version": "0.1.0"}]}, "0.2.0")

    def test_refuses_existing_binary_even_with_different_build_metadata(self):
        with self.assertRaises(ValueError):
            verify_entry({"versions": [{"version": "0.1.0+1"}]}, "0.1.0+2")

    def test_refuses_missing_or_invalid_inventory(self):
        for value in ([], None, {}, {"versions": "unknown"}, {"versions": [{}]}):
            with self.assertRaises(ValueError):
                verify_entry(value, "0.1.0")

    def test_refuses_malformed_success_output(self):
        with self.assertRaises(ValueError):
            verify_result(0, "Service temporarily unavailable", "0.1.0")

    def test_allows_explicit_missing_entry_response(self):
        verify_result(1, "The entry slug sent is invalid or does not exist", "0.1.0")

    def test_refuses_other_cli_failures(self):
        for message in ("Authentication failed", "Timed out", "Service unavailable", ""):
            with self.assertRaises(ValueError):
                verify_result(1, message, "0.1.0")


if __name__ == "__main__":
    unittest.main()
