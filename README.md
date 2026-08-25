# Okta as Code — identity lifecycle (JML) starter

A working starter for running an identity program **as code**: Terraform for the Okta
configuration (groups, group rules, custom attributes, app assignments) plus an
Okta Workflows design for the offboarding paths that SCIM alone can't express.

Built around the joiner-mover-leaver (JML) lifecycle: access is driven by HR-mastered
attributes, granted automatically on day one, adjusted on role change, and revoked
cleanly on exit.

## What's in here

```
okta-as-code/
├── terraform/
│   ├── identity.tf        # Birthright groups, group rules (the JML/RBAC engine),
│   │                      # custom profile attributes, app assignments, contractor population
│   └── contractors.tf     # The contractor lifecycle layer: sponsor accountability,
│                          # vendor blast-radius groups, reduced birthright, tighter sign-on
└── workflows/
    └── leaver-flow.md     # The leaver automation, card by card: kill-switch,
                           # contractor expiry, and deprovision-drift reconciliation
```

## The architecture this implements

1. **Source of truth = the HRIS** (for example Workday). It masters identity attributes
   into Okta's Universal Directory; the custom schema properties in `identity.tf` are
   the attributes the HRIS fills.
2. **Group rules are the JML + RBAC engine.** Each rule is "if attribute matches, add to
   group." When an attribute stops matching (a mover or leaver), Okta auto-removes the
   user from the group and the associated apps deprovision. Adds AND removes: the removal
   half is what makes this least-privilege instead of access accretion.
3. **Groups are roles.** Birthright access (everyone in a department gets a baseline app
   set) is delivered by assigning apps to groups. No tickets, no manual provisioning.
   Roles stay coarse to avoid role explosion; context (device posture, location) belongs
   in authentication policy, not in more groups.
4. **Contractors** get a separate population and a `contractEndDate` attribute; the
   leaver flow enforces auto-deactivation on expiry.
5. **Requestable access lives elsewhere on purpose.** Only the baseline should be
   birthright; sensitive and long-tail access goes through request-and-approval
   (Okta Identity Governance), time-boxed where possible.

Everything lives in Git, goes through PR review, and deploys through CI. The audit
trail is itself a compliance control (SOC 2 / HIPAA-style access governance).

## The contractor lifecycle, specifically

Contractors are where JML programs go to die quietly: accounts that outlive
engagements, access nobody owns, vendors whose people you can't enumerate.
`terraform/contractors.tf` is the layer that prevents that, built on four rules:

1. **Every contractor has a sponsor.** A `contractorSponsor` attribute names the
   internal FTE accountable for the access; quarterly recertification asks the
   sponsor, not the contractor, and a departed sponsor is itself an offboarding
   trigger.
2. **Time-bound by default.** `contractEndDate` (identity.tf) is enforced by the
   scheduled leaver flow: suspend on expiry, notify the sponsor, deactivate after
   the grace window. Renewal is an explicit act, not the absence of one.
3. **Vendor groups bound the blast radius.** One rule-populated group per vendor,
   so ending a vendor relationship is a single kill-switch and "who did that
   vendor have in our systems" is a membership list, not an investigation.
4. **Smaller birthright, tighter sign-on.** Collaboration basics only; MFA on
   every sign-on, shorter sessions, nothing persistent. Everything else is
   requested, sponsor-approved, and time-boxed.

## Security notes

- **No secrets in this repo, ever.** The Terraform provider reads credentials from
  environment variables or a vault. Code references secrets; it never contains them.
- Regulated-industry example included: the clinical group rule gates access on a
  licensure attribute, so access follows credential status automatically
  (minimum-necessary by design).

## Status

This is a **starter**, not a drop-in module: shapes to adapt, not import blindly.
Verify resource names and arguments against the current
[Okta Terraform provider docs](https://registry.terraform.io/providers/okta/okta/latest/docs)
for your provider version before applying to a real tenant.
