#!/usr/bin/env bash
# Install a pinned Semgrep into an isolated venv under AGENTIC_TMP.
#
# IMPORTANT:
# - Semgrep ≥1.38 rejects `python3 -m semgrep` (exit 2, no JSON) — use the binary.
# - setuptools ≥81 drops pkg_resources; Semgrep/OpenTelemetry still need it.
#   Pin setuptools<81 inside the venv.
set -euo pipefail
# shellcheck source=../common.sh
source "$(cd "$(dirname "$0")/.." && pwd)/common.sh"

SEMGREP_VERSION="${SEMGREP_VERSION:-1.97.0}"
SEMGREP_PREFIX="${AGENTIC_TMP}/semgrep-prefix"
SEMGREP_VENV="${SEMGREP_PREFIX}/venv"
SEMGREP_ENV="${AGENTIC_TMP}/semgrep.env"

write_env() {
  {
    echo "export PATH=\"${SEMGREP_VENV}/bin\${PATH:+:\$PATH}\""
    echo "export VIRTUAL_ENV=\"${SEMGREP_VENV}\""
  } > "$SEMGREP_ENV"
}

semgrep_ok() {
  set +e
  # shellcheck disable=SC1090
  [[ -f "$SEMGREP_ENV" ]] && source "$SEMGREP_ENV"
  if ! command -v semgrep >/dev/null 2>&1; then
    set -e
    return 1
  fi
  local out
  out="$(semgrep --version 2>/dev/null | head -1)"
  local rc=$?
  set -e
  [[ $rc -eq 0 && -n "$out" ]]
}

if semgrep_ok; then
  # shellcheck disable=SC1090
  source "$SEMGREP_ENV"
  agentic_log "  Semgrep present: $(semgrep --version 2>/dev/null | head -1)"
  exit 0
fi

agentic_log "  Installing semgrep==${SEMGREP_VERSION} into ${SEMGREP_VENV}"
rm -rf "$SEMGREP_PREFIX"
mkdir -p "$SEMGREP_PREFIX"

python3 -m venv "$SEMGREP_VENV"
# shellcheck disable=SC1091
source "${SEMGREP_VENV}/bin/activate"

set +e
pip install --upgrade --quiet pip
pip install --quiet \
  "setuptools>=75,<81" wheel "semgrep==${SEMGREP_VERSION}"
PIP_RC=$?
set -e
if [[ $PIP_RC -ne 0 ]]; then
  agentic_log "  quiet pip failed — retrying with logs"
  pip install \
    "setuptools>=75,<81" wheel "semgrep==${SEMGREP_VERSION}"
fi

deactivate 2>/dev/null || true
write_env
# shellcheck disable=SC1090
source "$SEMGREP_ENV"

if ! semgrep_ok; then
  agentic_log "  ⚠ Semgrep still not runnable after isolated install:"
  set +e
  ls -la "${SEMGREP_VENV}/bin" 2>&1 | while IFS= read -r line; do
    agentic_log "    $line"
  done
  "${SEMGREP_VENV}/bin/semgrep" --version 2>&1 | tail -n 25 | while IFS= read -r line; do
    agentic_log "    $line"
  done
  set -e
  # Do not leave a broken semgrep on PATH for scan-semgrep.sh
  rm -f "$SEMGREP_ENV"
  exit 0
fi
agentic_log "  Installed: $(semgrep --version 2>/dev/null | head -1)"
