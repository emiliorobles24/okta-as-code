###############################################################################
# Contractor JML: the tighter lifecycle, as code
#
# identity.tf establishes the contractor POPULATION (employmentType ->
# POPULATION-Contractors) and the contractEndDate attribute. This file is the
# layer that makes contractor access defensible in an audit, built on four
# rules learned the hard way in production identity work:
#
#   1. ACCOUNTABILITY: every contractor has a named internal sponsor. Access
#      without an accountable owner is access nobody will ever remove.
#   2. TIME-BOUND BY DEFAULT: contractor access expires unless renewed. The
#      expiry is enforced by automation (leaver-flow.md Flow B), not memory.
#   3. VENDOR BLAST RADIUS: contractors are grouped by vendor, so ending a
#      vendor relationship is one kill-switch, not an account-by-account hunt.
#   4. LESS BIRTHRIGHT, TIGHTER AUTH: contractors get a smaller baseline app
#      set and a stricter sign-on posture than FTEs. Everything else is
#      requested, approved, and time-boxed.
#
# STARTER: adapt to your org; verify args against the okta/okta provider docs.
###############################################################################

###############################################################################
# 1. ACCOUNTABILITY ATTRIBUTES
#    Mastered from the vendor-management/HRIS source, same as identity.tf:
#    IT does not hand-edit these, which is what makes them audit evidence.
###############################################################################

# The internal FTE accountable for this contractor's access. Recertification
# (quarterly) goes to the sponsor: "still needed? Y/N", and a departed sponsor
# with no replacement is itself an offboarding trigger.
resource "okta_user_schema_property" "contractor_sponsor" {
  index       = "contractorSponsor"
  title       = "Contractor Sponsor"
  type        = "string"
  description = "Email of the internal FTE accountable for this contractor's access"
  master      = "PROFILE_MASTER"
  permissions = "READ_ONLY"
}

# The staffing vendor or agency. Drives the vendor groups below.
resource "okta_user_schema_property" "contractor_vendor" {
  index       = "contractorVendor"
  title       = "Contractor Vendor"
  type        = "string"
  description = "Staffing vendor / agency, mastered from the vendor-management system"
  master      = "PROFILE_MASTER"
  permissions = "READ_ONLY"
}

###############################################################################
# 2. VENDOR GROUPS = BLAST-RADIUS CONTROL
#    One group per active vendor, populated by rule. When a vendor contract
#    ends, suspending this group's members is a single reviewed change, and
#    the group's membership list IS the audit answer to "who did that vendor
#    have in our systems?"
###############################################################################

resource "okta_group" "vendor_acme_staffing" {
  name        = "VENDOR-Acme-Staffing"
  description = "All active contractors from Acme Staffing; kill-switch scope for the vendor relationship"
}

resource "okta_group_rule" "vendor_acme_staffing" {
  name              = "Vendor - Acme Staffing"
  status            = "ACTIVE"
  group_assignments = [okta_group.vendor_acme_staffing.id]
  expression_type   = "urn:okta:expression:1.0"
  expression_value  = "user.employmentType == \"Contractor\" and user.contractorVendor == \"Acme Staffing\""
}

###############################################################################
# 3. CONTRACTOR BIRTHRIGHT = DELIBERATELY SMALLER
#    Contractors get collaboration basics only (reusing the app data sources
#    from identity.tf). No engineering tools, no clinical tools, nothing
#    PHI-adjacent by default: those are requestable, approved by the sponsor,
#    and time-boxed. The absence of assignments here is the design.
###############################################################################

resource "okta_app_group_assignment" "slack_contractors" {
  app_id   = data.okta_app.slack.id
  group_id = okta_group.contractors.id
}

resource "okta_app_group_assignment" "zoom_contractors" {
  app_id   = data.okta_app.zoom.id
  group_id = okta_group.contractors.id
}

###############################################################################
# 4. SIGN-ON POSTURE: SHORTER SESSIONS, MFA ALWAYS
#    Contractors work on devices we often don't manage, on networks we never
#    see. The compensating control is the session: shorter lifetime, no
#    persistent sessions, MFA on every sign-on. FTE convenience trade-offs
#    stop at the population boundary.
###############################################################################

resource "okta_policy_signon" "contractor_signon" {
  name            = "Contractors - Sign-On Policy"
  status          = "ACTIVE"
  description     = "Tighter session posture for the contractor population"
  priority        = 1
  groups_included = [okta_group.contractors.id]
}

resource "okta_policy_rule_signon" "contractor_signon_rule" {
  policy_id          = okta_policy_signon.contractor_signon.id
  name               = "Contractors - MFA every sign-on, 8h session"
  status             = "ACTIVE"
  access             = "ALLOW"
  authtype           = "ANY"
  mfa_required       = true
  mfa_prompt         = "ALWAYS"
  session_idle       = 60
  session_lifetime   = 480
  session_persistent = false
}

###############################################################################
# 5. WHAT LIVES ELSEWHERE (deliberately)
#
#   - EXPIRY ENFORCEMENT: contractEndDate is enforced by the scheduled leaver
#     Workflow (../workflows/leaver-flow.md, Flow B): list contractors past
#     end date -> suspend -> notify sponsor -> deactivate after grace window.
#     Orchestration with side effects belongs in Workflows, not Terraform.
#
#   - RECERTIFICATION: quarterly sponsor attestation of every contractor's
#     continued need. Run it through OIG access certifications, or the
#     access-review orchestration pattern in my n8n-support-ops repo.
#
#   - DEVICE POSTURE: unmanaged-device limits (no downloads, browser-only
#     sessions) belong in app sign-on policies with Device Assurance, bound
#     per-app, not in this population policy.
###############################################################################
