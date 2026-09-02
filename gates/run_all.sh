#!/usr/bin/env bash
# run_all — the full gate bank, mechanical-first, fail-fast. Exits nonzero on the first
# failing gate, so it drops into CI and pre-merge hooks unchanged.
#
# Order (Stage 7 ship):
#   link_check -> prose_check -> coverage_check -> test_edit_ban -> suite_green
#     -> constitution_lint* -> seam_conformance* -> qa_import_ban* -> fold_check
#     -> suite_green (re-run)
# (*) project gates run only if their concrete (non-template) .sh script exists — a fresh
#     repo is green before you author them.
#
# This .sh runner invokes the .sh siblings (the Linux/macOS path; needs git + jq).
#
# Usage:  sh gates/run_all.sh [baseRef] [--pre-fold] [--mechanical] [--strict]
#   baseRef       optional merge base for diffs (defaults to config baseRef).
#   --pre-fold    skip fold_check (and its post-fold suite re-run): the pins it checks
#                 do not exist until the fold happens. Use for the Stage-7 pre-fold pass.
#   --mechanical  skip test_edit_ban: the mechanical route has no QA/Engineer split, so a
#                 single author legitimately writes tests + code together.
#   --strict      forward --strict to fold_check: a configured resolver that errors/returns
#                 non-zero FAILS instead of degrading. CI should run with --strict.
#                 Also forwarded to prose_check (spec-form violations FAIL instead of WARN).

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
# Run from the repo root (parent of gates/) so every path the gates resolve — spec
# shards, test globs, the config — is repo-relative and portable across shells/CI.
cd "$HERE/.."
GD="$(basename "$HERE")"          # gate dir name, normally "gates"
CFG="$GD/gates.config.json"

. "$HERE/_common.sh"
require_jq run_all

BASE=""; PREFOLD=0; MECH=0; STRICT=0
for a in "$@"; do
  case "$a" in
    --pre-fold)   PREFOLD=1 ;;
    --mechanical) MECH=1 ;;
    --strict)     STRICT=1 ;;
    *)            BASE="$a" ;;
  esac
done

fail() { echo ">>> GATE FAILED: $1"; exit 1; }

run_suite() {
  SUITE=$(read_cfg "$CFG" '.suiteCmd' '')
  case "$SUITE" in
    ""|"<from project-details"*)
      echo "== suite_green == (skipped: set suiteCmd in gates.config.json)";;
    *)
      echo "== suite_green =="
      sh -c "$SUITE" || fail suite_green;;
  esac
}

echo "== link_check =="
bash "$HERE/link_check.sh" --config "$CFG" || fail link_check

echo "== prose_check =="
PC_STRICT=""; [ "$STRICT" = 1 ] && PC_STRICT="--strict"
# shellcheck disable=SC2086
bash "$HERE/prose_check.sh" --config "$CFG" --base "$BASE" $PC_STRICT || fail prose_check

echo "== coverage_check =="
bash "$HERE/coverage_check.sh" --config "$CFG" || fail coverage_check

if [ "$MECH" = 1 ]; then
  echo "== test_edit_ban == (skipped: mechanical route, no QA/Engineer split)"
else
  echo "== test_edit_ban =="
  bash "$HERE/test_edit_ban.sh" "$BASE" --config "$CFG" || fail test_edit_ban
fi

run_suite

# --- project-specific gates: only if copied from template ---
if [ -f "$HERE/constitution_lint.sh" ]; then
  echo "== constitution_lint =="
  bash "$HERE/constitution_lint.sh" --config "$CFG" || fail constitution_lint
else
  echo "== constitution_lint == (skipped: cp constitution_lint.template.sh constitution_lint.sh)"
fi

if [ -f "$HERE/seam_conformance.sh" ]; then
  echo "== seam_conformance =="
  bash "$HERE/seam_conformance.sh" --config "$CFG" || fail seam_conformance
else
  echo "== seam_conformance == (skipped: cp seam_conformance.template.sh seam_conformance.sh)"
fi

if [ -f "$HERE/qa_import_ban.sh" ]; then
  echo "== qa_import_ban =="
  bash "$HERE/qa_import_ban.sh" --config "$CFG" || fail qa_import_ban
else
  echo "== qa_import_ban == (skipped: cp qa_import_ban.template.sh qa_import_ban.sh)"
fi

if [ "$PREFOLD" = 1 ]; then
  echo "== fold_check == (skipped: --pre-fold pass; runs in the authoritative post-fold pass)"
else
  echo "== fold_check =="
  FC_STRICT=""; [ "$STRICT" = 1 ] && FC_STRICT="--strict"
  # shellcheck disable=SC2086
  bash "$HERE/fold_check.sh" --config "$CFG" --base "$BASE" $FC_STRICT || fail fold_check
  run_suite   # re-run after fold recompiles the spec index
fi

echo ">>> ALL GATES PASSED"
