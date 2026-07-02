# Okta Workflows: leaver automation (design spec)

Okta Workflows is a no-code canvas (you drag "cards"), so this is the **flow design**,
card by card. It covers what SCIM alone can't: session/token kill-switch, file
transfer, mailbox handling, notifications, and the audit record. Offboarding is the
highest-risk path in an identity program, so it's designed for speed and completeness.

---

## Flow A: "Leaver: deactivate and clean up" (event-triggered)

**Trigger:** Okta **Event Hook** on `user.lifecycle.deactivate`
*(HRIS termination -> Okta deactivates the user -> this flow fires immediately.
For for-cause terminations, HRIS real-time sync makes the deactivate near-instant.)*

| # | Card | What it does | Why (design note) |
|---|------|--------------|-------------------|
| 1 | **Okta - Read User** | Pull the user's profile (manager, email, department) | Need the manager for transfers and notifications |
| 2 | **Okta - Clear User Sessions** | Revoke all active Okta sessions | **Deactivating an account does not kill live sessions.** This is the kill-switch. |
| 3 | **Okta - Revoke Tokens** (API connector: clear sessions + OAuth grants) | Revoke OAuth/refresh tokens | A stolen refresh token outlives the account otherwise |
| 4 | **Google Workspace - Transfer Drive** | Reassign Drive ownership to the manager | Don't orphan documents; preserve continuity |
| 5 | **Google Workspace - Delegate mailbox, then Suspend** | Delegate mail to the manager, then suspend the account | Keep mail accessible; stop new access |
| 6 | **Slack - Deactivate User** | Deactivate (don't delete) Slack | Reclaim the seat, keep history |
| 7 | **Loop - Reclaim Licenses** | For each provisioned app, deactivate via SCIM active=false | License cost and access removal in one pass |
| 8 | **Slack / Email - Notify** | Message the manager + IT: "X offboarded, files transferred to you" | Human in the loop; closes the ticket |
| 9 | **Append to Audit Table / SIEM** | Write an immutable record: who, what, when, which systems cleared | This record IS the audit evidence (SOC 2 / HIPAA-style controls) |

**Idempotency:** design steps to be safely re-runnable. If one app's SCIM call fails,
the flow retries, and the scheduled reconciliation flow (Flow C) catches the drift,
so a partial failure self-heals instead of leaving a live account.

---

## Flow B: "Contractor expiry" (scheduled)

**Trigger:** **Scheduled Flow**, runs daily.

1. **Okta - List Users** where employmentType == "Contractor".
2. **Loop** each; compare contractEndDate to today.
3. If contractEndDate <= today: **Okta - Deactivate User** (which fires Flow A).
4. If contractEndDate is within 7 days: **notify the sponsor** to re-attest or extend.

*Solves the #1 contractor risk: accounts that outlive the engagement.*

---

## Flow C: "Deprovision drift reconciliation" (scheduled)

**Trigger:** **Scheduled Flow**, nightly.

1. **Okta - List Users** with status DEPROVISIONED / SUSPENDED.
2. For each, check every connected app for a still-active account (SCIM read / API).
3. If found: force-deactivate and **alert IT** ("deactivated in Okta, still active in app X").

*Catches batch-sync apps and the gaps that make offboarding incomplete in the real world.*

---

## Security

No tokens or PHI in the design or the repo. Connections are authorized inside
Okta Workflows; credentials never leave the platform.
