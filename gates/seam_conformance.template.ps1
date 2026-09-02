#!/usr/bin/env pwsh
# seam_conformance (TEMPLATE) — project-specific architecture-seam checks.
#
# Same generic rule engine as constitution_lint (a seam violation is just a mechanical
# predicate over the tree), kept as its own gate so principles and architecture
# boundaries stay separately ownable and wired. Rules live in gates.config.json under
# "seamRules", and EACH seam rule's `id` MUST key to an Project Details SEAM-N so the registry
# (Project Details §1) and the gate stay in lockstep.
#
# Copy this file to gates/seam_conformance.ps1 (no edits) and author "seamRules" in
# gates/gates.config.json. Same four kinds as constitution_lint:
#   must_match | must_not_match | file_exists | pair_requires
#
# Seam-flavoured examples (author as seamRules[] rows):
#   * audit invariant   id=SEAM-2-audit  kind=pair_requires
#                       paths="src/**/Handlers/**/*.cs" pattern="ICommandHandler" expect="IAuditSink"
#   * dispatch registry id=SEAM-1-dispatch kind=pair_requires
#                       paths="src/**/Handlers/**/*.cs" pattern="ICommandHandler" expect="\[Command\("
#   * no manual DI      id=SEAM-1-no-di  kind=must_not_match
#                       paths="src/**/Program.cs" pattern="services\.AddScoped<"
#
# Usage:  pwsh gates/seam_conformance.ps1 [-Config gates/gates.config.json]
#
# Implementation: shares the rule engine (_rules.ps1) with constitution_lint, exactly as
# the .py original imported constitution_lint's runner. Copy both gates at init.

[CmdletBinding()]
param(
    [string]$Config = 'gates/gates.config.json'
)
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/_common.ps1"
. "$PSScriptRoot/_rules.ps1"

$RulesKey = 'seamRules'
$GateName = 'seam_conformance'

$cfg = Read-Config $Config $GateName
$rules = @()
if ($cfg.PSObject.Properties.Name -contains $RulesKey -and $cfg.$RulesKey) { $rules = @($cfg.$RulesKey) }

if ($rules.Count -eq 0) {
    Write-Output "PASS ${GateName}: no rules in $RulesKey (nothing to check)."
    exit 0
}

exit (Invoke-Rules $rules $GateName)
