---
name: sdd-gates
description: Run the GUIDE SDD gate bank (sdd/gates/run_all) for this OS with output filtered to the summary lines, as the dispatch-frugality rule requires. Use at a stage close or before merge.
argument-hint: "[baseRef] [--pre-fold] [--mechanical] [--strict]"
allowed-tools: Bash, Read
---

# /sdd-gates — run the bank, admit only the verdicts

Arguments: $ARGUMENTS (the QA-frozen SHA first — the item's `frozen:` line; omit it to use `sdd/gates/.frozen`; then flags). `run_all` resolves the project root itself. At Stage 5 exit, freeze first: `pwsh sdd/gates/freeze.ps1 -Unit <ITEM-ID>` / `sh sdd/gates/freeze.sh --unit <ITEM-ID>`, then record the printed `frozen:` line on the item and commit the marker.

- Windows: `pwsh sdd/gates/run_all.ps1 $ARGUMENTS 2>&1 | Select-String -Pattern '^(== |PASS|FAIL|WARN|  OVER|  UNCOVERED|  DRIFT)'`
- Linux/macOS: `sh sdd/gates/run_all.sh $ARGUMENTS 2>&1 | grep -E '^(== |PASS|FAIL|WARN|  OVER|  UNCOVERED|  DRIFT)'`

Run it **once**. Report each gate's verdict line and every named failure; do not paste the full output. A gate that errors on paths or regex (not a real PASS/FAIL) means `gates.config.json` needs fixing — never edit a generic gate body.
