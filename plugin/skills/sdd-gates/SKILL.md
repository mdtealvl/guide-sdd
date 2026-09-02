---
name: sdd-gates
description: Run the GUIDE SDD gate bank (sdd/gates/run_all) for this OS with output filtered to the summary lines, as the dispatch-frugality rule requires. Use at a stage close or before merge.
argument-hint: "[baseRef] [--pre-fold] [--mechanical] [--strict]"
allowed-tools: Bash, Read
---

# /sdd-gates — run the bank, admit only the verdicts

Arguments: $ARGUMENTS (a resolving base ref first, e.g. `main` or the QA-frozen commit; then flags). Run from the repo root with the spine at `sdd/`.

- Windows: `pwsh sdd/gates/run_all.ps1 $ARGUMENTS 2>&1 | Select-String -Pattern '^(== |PASS|FAIL|WARN|  OVER|  UNCOVERED|  DRIFT)'`
- Linux/macOS: `sh sdd/gates/run_all.sh $ARGUMENTS 2>&1 | grep -E '^(== |PASS|FAIL|WARN|  OVER|  UNCOVERED|  DRIFT)'`

Run it **once**. Report each gate's verdict line and every named failure; do not paste the full output. A gate that errors on paths or regex (not a real PASS/FAIL) means `gates.config.json` needs fixing — never edit a generic gate body.
