"""Tests for okta_cli. Run: python3 -m unittest discover cli
All tests use --mock (fixtures) — no tenant, no credential, no network."""

import io
import os
import sys
import unittest
from contextlib import redirect_stdout

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import okta_cli


def run_cli(argv):
    buf = io.StringIO()
    with redirect_stdout(buf):
        okta_cli.main(argv)
    return buf.getvalue()


class MockModeTests(unittest.TestCase):
    def test_users_lists_all_fixture_users(self):
        out = run_cli(["--mock", "users"])
        self.assertIn("avery.chen@example.com", out)
        self.assertIn("-- 3 user(s)", out)

    def test_users_search_filters(self):
        out = run_cli(["--mock", "users", "--search", "jordan"])
        self.assertIn("jordan.smith@example.com", out)
        self.assertNotIn("avery.chen", out)
        self.assertIn("-- 1 user(s)", out)

    def test_user_by_login(self):
        out = run_cli(["--mock", "user", "c-riley.vendor@example.com"])
        self.assertIn('"employmentType": "CONTRACTOR"', out)

    def test_user_not_found_exits(self):
        with self.assertRaises(SystemExit):
            run_cli(["--mock", "user", "nobody@example.com"])

    def test_groups_lists_killswitch(self):
        out = run_cli(["--mock", "groups"])
        self.assertIn("vendor-acme-killswitch", out)
        self.assertIn("-- 3 group(s)", out)


class CredentialPatternTests(unittest.TestCase):
    def test_env_token_fallback(self):
        os.environ["OKTA_OP_REF"] = "op://nonexistent/vault/item"
        os.environ["OKTA_API_TOKEN"] = "test-token-abc"
        try:
            self.assertEqual(okta_cli.get_token(), "test-token-abc")
        finally:
            del os.environ["OKTA_API_TOKEN"]
            del os.environ["OKTA_OP_REF"]

    def test_no_credential_exits_without_leaking(self):
        os.environ["OKTA_OP_REF"] = "op://nonexistent/vault/item"
        os.environ.pop("OKTA_API_TOKEN", None)
        try:
            with self.assertRaises(SystemExit) as ctx:
                okta_cli.get_token()
            self.assertIn("never read a token from a file", str(ctx.exception))
        finally:
            del os.environ["OKTA_OP_REF"]


if __name__ == "__main__":
    unittest.main()
