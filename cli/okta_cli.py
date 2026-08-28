#!/usr/bin/env python3
"""okta-cli: a small, deliberately read-only CLI for common Okta lookups.

The point of this tool is the credential pattern, not the lookups:
the API token is retrieved AT RUNTIME from a secrets manager (1Password
via the `op` CLI) and held only in process memory. It is never written
to a file, never committed, never placed in a .env.

Token resolution order:
  1. 1Password CLI:  `op read <ref>` where <ref> defaults to
     op://IT/okta-api-token/credential  (override with OKTA_OP_REF)
  2. Environment variable OKTA_API_TOKEN (intended for CI only)
  3. Fail loudly, with no partial state.

Usage:
  python3 okta_cli.py users                 # list users
  python3 okta_cli.py users --search jsmith # filter by login/name
  python3 okta_cli.py user 00u1abcd         # one user by id or login
  python3 okta_cli.py groups                # list groups
  python3 okta_cli.py --mock users          # run against local fixtures, no tenant

Requires OKTA_ORG_URL (e.g. https://yourorg.okta.com) unless --mock.
Read-only by design: every request is a GET. There is no write path.
"""

import argparse
import json
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

FIXTURES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures")
DEFAULT_OP_REF = "op://IT/okta-api-token/credential"


def get_token():
    """Fetch the API token at runtime. Memory only; never persisted."""
    op_ref = os.environ.get("OKTA_OP_REF", DEFAULT_OP_REF)
    try:
        out = subprocess.run(
            ["op", "read", op_ref],
            capture_output=True, text=True, timeout=30,
        )
        if out.returncode == 0 and out.stdout.strip():
            return out.stdout.strip()
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass  # op CLI not installed or not signed in; fall through

    env_token = os.environ.get("OKTA_API_TOKEN")
    if env_token:
        return env_token

    sys.exit(
        "No credential available. Sign in to 1Password (`op signin`) so the token\n"
        "can be read at runtime, or set OKTA_API_TOKEN (CI only). This tool will\n"
        "never read a token from a file."
    )


def api_get(path, params=None):
    base = os.environ.get("OKTA_ORG_URL")
    if not base:
        sys.exit("Set OKTA_ORG_URL (e.g. https://yourorg.okta.com), or use --mock.")
    url = base.rstrip("/") + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url)
    req.add_header("Authorization", "SSWS " + get_token())
    req.add_header("Accept", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as e:
        sys.exit(f"Okta API error {e.code} on GET {path}: {e.reason}")


def load_fixture(name):
    with open(os.path.join(FIXTURES, name + ".json")) as f:
        return json.load(f)


def cmd_users(args):
    if args.mock:
        users = load_fixture("users")
        if args.search:
            s = args.search.lower()
            users = [u for u in users
                     if s in u["profile"]["login"].lower()
                     or s in (u["profile"]["firstName"] + " " + u["profile"]["lastName"]).lower()]
    else:
        params = {"limit": str(args.limit)}
        if args.search:
            params["q"] = args.search
        users = api_get("/api/v1/users", params)
    for u in users:
        p = u["profile"]
        print(f'{u["id"]}  {u["status"]:<12} {p["login"]:<32} {p["firstName"]} {p["lastName"]}')
    print(f"-- {len(users)} user(s)")


def cmd_user(args):
    if args.mock:
        users = load_fixture("users")
        match = [u for u in users
                 if u["id"] == args.id_or_login or u["profile"]["login"] == args.id_or_login]
        if not match:
            sys.exit(f"No user matching {args.id_or_login}")
        print(json.dumps(match[0], indent=2))
    else:
        print(json.dumps(api_get(f"/api/v1/users/{args.id_or_login}"), indent=2))


def cmd_groups(args):
    groups = load_fixture("groups") if args.mock else api_get("/api/v1/groups", {"limit": str(args.limit)})
    for g in groups:
        p = g["profile"]
        print(f'{g["id"]}  {p["name"]:<40} {p.get("description", "")}')
    print(f"-- {len(groups)} group(s)")


def main(argv=None):
    parser = argparse.ArgumentParser(prog="okta-cli", description=__doc__.splitlines()[0])
    parser.add_argument("--mock", action="store_true",
                        help="run against local fixtures (no tenant, no credential)")
    sub = parser.add_subparsers(dest="command", required=True)

    p_users = sub.add_parser("users", help="list users")
    p_users.add_argument("--search", help="filter by login or name")
    p_users.add_argument("--limit", type=int, default=200)
    p_users.set_defaults(func=cmd_users)

    p_user = sub.add_parser("user", help="one user by id or login")
    p_user.add_argument("id_or_login")
    p_user.set_defaults(func=cmd_user)

    p_groups = sub.add_parser("groups", help="list groups")
    p_groups.add_argument("--limit", type=int, default=200)
    p_groups.set_defaults(func=cmd_groups)

    args = parser.parse_args(argv)
    args.func(args)


if __name__ == "__main__":
    main()
