#!/usr/bin/env bash
# run_all - the full gate bank, mechanical-first, fail-fast. Exits nonzero on the first
# failing gate, so it drops into CI and pre-merge hooks unchanged.
#
# Order (Stage 7 ship):
#   link_check -> prose_check -> coverage_check -> test_edit_ban -> structure_check -> suite_green
#     -> constitution_lint* -> seam_conformance* -> qa_import_ban* -> fold_check
#     -> suite_green (re-run)
# (*) project gates run only if their concrete (non-template) .sh script exists - a fresh
#     repo is green before you author them.
# structure_check runs its --frozen half (approved diagram unchanged vs the frozen base) only on
# the persona route's --pre-fold pass; the forward trace runs in every pass.
#
# Working directory: the PROJECT ROOT - the git top-level of the tree the gates live in
# (so a spine vendored at sdd/ still resolves `spec/**`, `tests/**` from the repo root).
# Override with `projectRoot` in gates.config.json (relative to the spine directory) for a
# non-git or nested layout. Every config path is root-relative.
#
# suite_green is REQUIRED: an unset suiteCmd is exit 2, never a silent skip - a bank that
# prints ALL GATES PASSED without running the suite proves nothing.
#
# This .sh runner invokes the .sh siblings (the Linux/macOS path; needs git + jq).
#
# Usage:  sh gates/run_all.sh [baseRef] [--pre-fold] [--mechanical] [--strict]
#   baseRef       the QA-frozen SHA for test_edit_ban / prose_check / fold_check diffs.
#                 Omitted: test_edit_ban reads gates/.frozen, else config baseRef (weak).
#   --pre-fold    skip fold_check (and its post-fold suite re-run): the pins it checks
#                 do not exist until the fold happens. Use for the Stage-7 pre-fold pass.
#   --mechanical  skip test_edit_ban: the mechanical route has no QA/Engineer split, so a
#                 single author legitimately writes tests + code together. The route is
#                 recorded on the changelog item; CI passes this flag from that record.
#   --strict      forward --strict to fold_check: a configured resolver that errors/returns
#                 non-zero FAILS instead of degrading. CI should run with --strict.
#                 Also forwarded to prose_check (spec-form violations FAIL instead of WARN).

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/_common.sh"
require_jq run_all

# Resolve the project root: config projectRoot (relative to the spine dir) > git top-level > spine dir.
PR=$(jq -r '.projectRoot // empty' "$HERE/gates.config.json" 2>/dev/null)
if [ -n "$PR" ]; then
  ROOT=$(cd "$HERE/.." && cd "$PR" 2>/dev/null && pwd) || { echo "FAIL run_all: projectRoot '$PR' does not exist"; exit 2; }
else
  TOP=$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null || true)
  if [ -n "$TOP" ]; then ROOT=$(cd "$TOP" && pwd); else ROOT=$(cd "$HERE/.." && pwd); fi
fi
cd "$ROOT" || exit 2
GD=${HERE#"$ROOT"/}; [ "$GD" = "$HERE" ] && GD="."   # gate dir relative to the root, e.g. gates or sdd/gates
CFG="$GD/gates.config.json"
[ -f "$CFG" ] || { echo "FAIL run_all: cannot read config $CFG (cwd $ROOT)"; exit 2; }

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
      echo "FAIL suite_green: suiteCmd is not set in $CFG - the bank cannot pass without the project suite (INIT section 5)."
      exit 2 ;;
    *)
      echo "== suite_green =="
      sh -c "$SUITE" || fail suite_green;;
  esac
}

echo "== run_all == (root: $ROOT)"
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
  if [ -n "$BASE" ]; then
    bash "$HERE/test_edit_ban.sh" "$BASE" --config "$CFG" || fail test_edit_ban
  else
    bash "$HERE/test_edit_ban.sh" --config "$CFG" || fail test_edit_ban
  fi
fi

# structure_check: on the persona route's pre-fold pass the PM-approved diagram must equal the frozen
# base (the fold itself rewrites the canonical shard, so the post-fold pass skips this half); the
# forward trace (every diagram class/member exists under paths.code) runs in every pass.
if [ "$MECH" = 0 ] && [ "$PREFOLD" = 1 ]; then
  echo "== structure_check --frozen =="
  if [ -n "$BASE" ]; then
    bash "$HERE/structure_check.sh" --frozen "$BASE" --config "$CFG" || fail structure_check
  else
    bash "$HERE/structure_check.sh" --frozen --config "$CFG" || fail structure_check
  fi
fi
echo "== structure_check =="
bash "$HERE/structure_check.sh" --config "$CFG" || fail structure_check

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
