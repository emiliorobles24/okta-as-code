###############################################################################
# Okta as Code: identity lifecycle (JML) starter
#
# This file is the "JML + RBAC engine" as code. Read top to bottom; it follows
# the same flow as the reference architecture: source-of-truth attributes ->
# groups (roles) -> group rules (the automation) -> app assignments (birthright
# provisioning) -> contractor population (tighter lifecycle).
#
# STARTER: adapt to your org; verify args against the okta/okta provider docs.
###############################################################################

terraform {
  required_version = ">= 1.5"
  required_providers {
    okta = {
      source  = "okta/okta"
      version = "~> 4.0"
    }
  }
}

# Credentials come from environment / a vault. NEVER hardcode them.
#   OKTA_ORG_NAME, OKTA_BASE_URL, OKTA_API_CLIENT_ID, OKTA_API_PRIVATE_KEY, OKTA_API_SCOPES
provider "okta" {
  org_name = var.okta_org_name
  base_url = var.okta_base_url # "okta.com" (prod) or "oktapreview.com" (preview)
}

variable "okta_org_name" { type = string }
variable "okta_base_url" {
  type    = string
  default = "okta.com"
}

###############################################################################
# 1. UNIVERSAL DIRECTORY: custom attributes
#    These are the org-specific attributes the HRIS masters (profile sourcing)
#    and that the group rules below read. master=PROFILE_MASTER means the HRIS
#    is authoritative; IT does not hand-edit these.
###############################################################################

resource "okta_user_schema_property" "employee_type" {
  index       = "employmentType"
  title       = "Employment Type"
  type        = "string"
  description = "FTE / Contractor / Intern, mastered from the HRIS"
  master      = "PROFILE_MASTER"
  permissions = "READ_ONLY"
  enum        = ["FTE", "Contractor", "Intern"]

  one_of {
    const = "FTE"
    title = "Full-time Employee"
  }
  one_of {
    const = "Contractor"
    title = "Contractor"
  }
  one_of {
    const = "Intern"
    title = "Intern"
  }
}

# Regulated-industry example: a licensure attribute gates clinical access
# (minimum-necessary: only licensed clinicians see PHI-adjacent tools).
resource "okta_user_schema_property" "licensure_state" {
  index       = "licensureState"
  title       = "Licensure State"
  type        = "string"
  description = "Clinician licensure state, mastered from the credentialing system"
  master      = "PROFILE_MASTER"
  permissions = "READ_ONLY"
}

# Drives contractor auto-deactivation (enforced by the leaver Workflow).
resource "okta_user_schema_property" "contract_end_date" {
  index       = "contractEndDate"
  title       = "Contract End Date"
  type        = "string" # ISO-8601 date; the scheduled Workflow compares to today
  description = "Contractor engagement end date; triggers auto-deactivate"
  master      = "OKTA"
  permissions = "READ_WRITE"
}

###############################################################################
# 2. GROUPS = ROLES
#    "BIRTHRIGHT-*" groups deliver baseline access; "POPULATION-*" groups
#    segment identity types. Keep roles COARSE (avoid role explosion; push
#    context like location/time/device into rules + auth policy, not new groups).
###############################################################################

resource "okta_group" "all_employees" {
  name        = "BIRTHRIGHT-All-Employees"
  description = "Baseline access for every FTE: email, Slack, Zoom"
}

resource "okta_group" "engineering" {
  name        = "BIRTHRIGHT-Engineering"
  description = "Engineering baseline: GitHub, eng wiki"
}

resource "okta_group" "clinical_ops" {
  name        = "BIRTHRIGHT-Clinical-Operations"
  description = "Clinical ops baseline (PHI-adjacent; gated to licensed clinicians)"
}

resource "okta_group" "contractors" {
  name        = "POPULATION-Contractors"
  description = "Contractors: tighter defaults, shorter sessions, mandatory expiry"
}

###############################################################################
# 3. GROUP RULES = THE AUTOMATION (attribute -> group, i.e. ABAC)
#    The heart of JML. A rule continuously evaluates HRIS-mastered attributes:
#    match -> add to group (JOINER/MOVER grant); no longer match -> REMOVE from
#    group (MOVER revoke / LEAVER deprovision). The removal half is what makes
#    this least-privilege instead of access-accretion.
###############################################################################

resource "okta_group_rule" "birthright_all_ftes" {
  name              = "Birthright - All FTEs"
  status            = "ACTIVE"
  group_assignments = [okta_group.all_employees.id]
  expression_type   = "urn:okta:expression:1.0"
  expression_value  = "user.employmentType == \"FTE\""
}

resource "okta_group_rule" "birthright_engineering" {
  name              = "Birthright - Engineering FTEs"
  status            = "ACTIVE"
  group_assignments = [okta_group.engineering.id]
  expression_type   = "urn:okta:expression:1.0"
  # Okta Expression Language: coarse role keyed to HRIS department + type
  expression_value  = "user.department == \"Engineering\" and user.employmentType == \"FTE\""
}

resource "okta_group_rule" "birthright_clinical" {
  name              = "Birthright - Clinical Ops (licensed only)"
  status            = "ACTIVE"
  group_assignments = [okta_group.clinical_ops.id]
  expression_type   = "urn:okta:expression:1.0"
  # ABAC in action: department AND a non-empty licensure state. A clinician who
  # loses licensure (attribute cleared) is auto-removed -> PHI access revoked.
  expression_value  = "user.department == \"Clinical Operations\" and String.len(user.licensureState) > 0"
}

resource "okta_group_rule" "contractor_population" {
  name              = "Population - Contractors"
  status            = "ACTIVE"
  group_assignments = [okta_group.contractors.id]
  expression_type   = "urn:okta:expression:1.0"
  expression_value  = "user.employmentType == \"Contractor\""
}

###############################################################################
# 4. APP ASSIGNMENTS = BIRTHRIGHT PROVISIONING
#    Apps (already created / in the OIN) get assigned to groups. Membership
#    drives SCIM provisioning: join the group -> account auto-created in the
#    app; leave the group -> account deactivated. Birthright = no approval.
###############################################################################

# Reference existing apps by label (don't recreate them in this module).
data "okta_app" "slack" { label = "Slack" }
data "okta_app" "zoom" { label = "Zoom" }
data "okta_app" "github" { label = "GitHub" }

resource "okta_app_group_assignment" "slack_all_employees" {
  app_id   = data.okta_app.slack.id
  group_id = okta_group.all_employees.id
}

resource "okta_app_group_assignment" "zoom_all_employees" {
  app_id   = data.okta_app.zoom.id
  group_id = okta_group.all_employees.id
}

resource "okta_app_group_assignment" "github_engineering" {
  app_id   = data.okta_app.github.id
  group_id = okta_group.engineering.id
}

###############################################################################
# 5. WHAT LIVES ELSEWHERE (deliberately)
#
#   - REQUESTABLE access (the sensitive/long-tail apps): NOT here. That's Okta
#     Identity Governance Access Requests: request + approval + time-box. Only
#     the baseline should be birthright; the rest is requested.
#
#   - SoD rules, access certifications, entitlement bundles: OIG governance
#     resources (manageable via the Okta Terraform provider's OIG support).
#
#   - Auth/MFA policy: okta_app_signon_policy + rules. Bind sensitive apps to
#     phishing-resistant factors + Device Assurance (Jamf/Kandji/Intune
#     posture). Contractors get shorter session lifetimes.
#
#   - The LEAVER kill-switch + contractor expiry + file transfer: Okta
#     Workflows, not Terraform (orchestration SCIM can't express).
#     See ../workflows/leaver-flow.md
###############################################################################
