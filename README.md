# Okta as Code: identity lifecycle (JML) starter

A working starter for running an identity program as code: Terraform for the Okta configuration (groups, group rules, custom attributes, app assignments) plus an Okta Workflows design for the offboarding paths that SCIM alone can't express.

Built around the joiner-mover-leaver (JML) lifecycle: access is driven by HR-mastered attributes, granted automatically on day one, adjusted on role change, and revoked cleanly on exit.

## What's in here

- terraform/identity.tf : birthright groups, group rules (the JML/RBAC engine), custom profile attributes, app assignments, contractor population
- workflows/leaver-flow.md : the leaver automation, card by card: kill-switch, contractor expiry, and deprovision-drift reconciliation

## The architecture this implements

1. Source of truth = the HRIS (for example Workday). It masters identity attributes into Okta's Universal Directory; the custom schema properties in identity.tf are the attributes the HRIS fills.
2. Group rules are the JML + RBAC engine. Each rule is "if attribute matches, add to group." When an attribute stops matching (a mover or leaver), Okta auto-removes the user from the group and the associated apps deprovision. Adds AND removes: the removal half is what makes this least-privilege instead of access accretion.
3. Groups are roles. Birthright access (everyone in a department gets a baseline app set) is delivered by assigning apps to groups. No tickets, no manual provisioning. Roles stay coarse to avoid role explosion; context (device posture, location) belongs in authentication policy, not in more groups.
4. Contractors get a separate population and a contractEndDate attribute; the leaver flow enforces auto-deactivation on expiry.
5. Requestable access lives elsewhere on purpose. Only the baseline should be birthright; sensitive and long-tail access goes through request-and-approval (Okta Identity Governance), time-boxed where possible.

Everything lives in Git, goes through PR review, and deploys through CI. The audit trail is itself a compliance control (SOC 2 / HIPAA-style access governance).

## Security notes

- No secrets in this repo, ever. The Terraform provider reads credentials from environment variables or a vault. Code references secrets; it never contains them.
- Regulated-industry example included: the clinical group rule gates access on a licensure attribute, so access follows credential status automatically (minimum-necessary by design).

## Status

This is a starter, not a drop-in module: shapes to adapt, not import blindly. Verify resource names and arguments against the current Okta Terraform provider docs for your provider version before applying to a real tenant.
