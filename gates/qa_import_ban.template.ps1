#!/usr/bin/env pwsh
# qa_import_ban (TEMPLATE) - a partial structural proof of QA ⊥ implementation.
#
# QA test files must NOT import/reference production internals beyond the contracted
# surface. This is the structural half of the QA-blind independence guarantee: without it,
# "QA never read the implementation" is honor-system. A rule typically scopes the QA test
# glob and `must_not_match` an import of a production-internal namespace/path.
#
# Project-specific (the production-internal surface differs per project), so it ships as a
# template like constitution_lint / seam_conformance and reuses the SAME rule engine.
# Copy this file to gates/qa_import_ban.ps1 (no edits) and author the "qaImportRules" array
# in gates/gates.config.json. Same four kinds as the other rule gates:
#   must_match | must_not_match | file_exists | pair_requires
#
# Rule shape (a row in gates.config.json -> qaImportRules[]):
#   { "id": "qa-no-impl-import", "kind": "must_not_match",
#     "paths": "tests/**/*.cs", "pattern": "using\\s+MyApp\\.Internal",
#     "message": "QA tests may not import production internals (test the contracted surface)" }
#
# Usage:  pwsh gates/qa_import_ban.ps1 [-Config gates/gates.config.json]
#         (shares the rule engine _rules.ps1 with constitution_lint / seam_conformance)

[CmdletBinding()]
param(
    [string]$Config = 'gates/gates.config.json'
)
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/_common.ps1"
. "$PSScriptRoot/_rules.ps1"

$RulesKey = 'qaImportRules'
$GateName = 'qa_import_ban'

$cfg = Read-Config $Config $GateName
$rules = @()
if ($cfg.PSObject.Properties.Name -contains $RulesKey -and $cfg.$RulesKey) { $rules = @($cfg.$RulesKey) }

if ($rules.Count -eq 0) {
    # Fail closed: a copied-in gate with no rules would certify QA-blindness it never checked.
    Write-Output "FAIL ${GateName}: no rules in $RulesKey - author at least one must_not_match over the production-internal surface (gates/README.md), or remove this gate."
    exit 2
}

exit (Invoke-Rules $rules $GateName)
