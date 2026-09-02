#!/usr/bin/env pwsh
# constitution_lint (TEMPLATE) — project-specific principle checks.
#
# Project-specific because principles differ per project; the RUNNER is generic and
# ships as-is. Copy this file to gates/constitution_lint.ps1 (no edits) and author the
# "constitutionRules" array in gates/gates.config.json.
#
# A rule is a mechanical predicate over file text. Supported kinds:
#   must_match      : EVERY file in `paths` matches `pattern`                    (else FAIL)
#   must_not_match  : NO file in `paths` matches `pattern`                       (else FAIL)
#   file_exists     : at least one file matches the `paths` glob                 (else FAIL)
#   pair_requires   : every file matching `pattern` ALSO matches `expect`        (else FAIL)
#
# Rule shape (a row in gates.config.json -> constitutionRules[]):
#   { "id": "no-hardcoded-ui", "kind": "must_not_match",
#     "paths": "src/**/*.tsx", "pattern": ">[A-Z][a-z]+ ",
#     "message": "UI strings go through useLabels()" }
#   pair_requires also needs:  "expect": "<regex that must also be present>"
#
# Usage:  pwsh gates/constitution_lint.ps1 [-Config gates/gates.config.json]
#         (seam_conformance reuses the same engine with a different rule key)

[CmdletBinding()]
param(
    [string]$Config = 'gates/gates.config.json'
)
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/_common.ps1"
. "$PSScriptRoot/_rules.ps1"

$RulesKey = 'constitutionRules'
$GateName = 'constitution_lint'

$cfg = Read-Config $Config $GateName
$rules = @()
if ($cfg.PSObject.Properties.Name -contains $RulesKey -and $cfg.$RulesKey) { $rules = @($cfg.$RulesKey) }

if ($rules.Count -eq 0) {
    Write-Output "PASS ${GateName}: no rules in $RulesKey (nothing to check)."
    exit 0
}

exit (Invoke-Rules $rules $GateName)
