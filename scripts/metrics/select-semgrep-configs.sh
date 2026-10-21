#!/usr/bin/env bash
# Build Semgrep config list from quality-gate package + detected languages.
# Designed for org-scale (~10k repos): broad registry packs + local hotspot rules.
# Unknown/404 packs are skipped per-pack in scan-semgrep.sh (fail-open on registry).
set -euo pipefail
# shellcheck source=../common.sh
source "$(cd "$(dirname "$0")/.." && pwd)/common.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PIPELINE_DIR="${PIPELINE_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
LANG_FILE="${AGENTIC_TMP}/metrics-languages.json"
PKG_FILE="${AGENTIC_TMP}/quality-package.json"
OUT="${AGENTIC_TMP}/semgrep-configs.json"

mkdir -p "$AGENTIC_TMP"
if [[ ! -f "$LANG_FILE" ]]; then
  echo '{"configs":["p/ci"],"reason":"no_language_file"}' > "$OUT"
  exit 0
fi
if [[ ! -f "$PKG_FILE" ]]; then
  echo '{"configs":["p/ci"],"reason":"no_package_file"}' > "$OUT"
  exit 0
fi

python3 - "$LANG_FILE" "$PKG_FILE" "$PIPELINE_DIR" "$OUT" <<'PY'
import json, sys
from pathlib import Path

lang_path, pkg_path, pipeline, out_path = sys.argv[1:5]
data = json.load(open(lang_path))
pkg = json.load(open(pkg_path))
langs = set(data.get("languages") or [])
root = Path(pipeline)

# Top stacks for enterprise multi-repo rollout. Registry 404s are skipped at scan time.
PACKS = {
    # Web / Node
    "javascript": ["p/javascript", "p/typescript", "p/nodejs", "p/react"],
    "typescript": ["p/typescript", "p/javascript", "p/nodejs", "p/react"],
    "vue": ["p/javascript", "p/nodejs"],
    # Backend languages
    "python": ["p/python", "p/django", "p/flask"],
    "go": ["p/golang"],
    "java": ["p/java", "p/spring"],
    "kotlin": ["p/kotlin", "p/java"],
    "csharp": ["p/csharp", "p/dotnet"],
    "ruby": ["p/ruby", "p/rails"],
    "php": ["p/php"],
    "rust": ["p/rust"],
    "scala": ["p/scala", "p/java"],
    "swift": ["p/swift"],
    "c": ["p/c", "p/cpp"],
    "cpp": ["p/cpp", "p/c"],
    "dart": ["p/dart"],
    "elixir": ["p/elixir"],
    "haskell": ["p/haskell"],
    "perl": ["p/perl"],
    "r": ["p/r"],
    "powershell": ["p/powershell"],
    "groovy": ["p/java"],
    # Data / query
    "sql": ["p/sql"],
    # Infra / cloud / config
    "terraform": ["p/terraform"],
    "docker": ["p/docker"],
    "kubernetes": ["p/kubernetes"],
    "helm": ["p/kubernetes"],
    "ansible": ["p/ansible"],
    "cloudformation": ["p/cloudformation"],
    "bicep": ["p/csharp"],
    "nginx": ["p/nginx"],
    "bash": ["p/bash"],
    # YAML: Actions via always_packs; k8s when detected separately
    "yaml": [],
    "json": [],
}

configs = []
seen = set()

def add(c: str) -> None:
    if c and c not in seen:
        seen.add(c)
        configs.append(c)

if pkg.get("language_packs", True):
    for lang in sorted(langs):
        for pack in PACKS.get(lang, []):
            add(pack)

for pack in pkg.get("always_packs") or []:
    add(pack)

# Local Semgrep rules from the quality package (hotspot parity across stacks)
local_configs = []
for rel in pkg.get("local_rules") or []:
    p = root / rel
    if p.is_dir() or p.is_file():
        local_configs.append(str(p))
        add(str(p))

if not configs:
    add("p/ci")

payload = {
    "configs": configs,
    "local_rules": local_configs,
    "languages": sorted(langs),
    "package": pkg.get("name", "default"),
    "reason": "quality_package",
    "packs_by_language": {
        lang: PACKS.get(lang, []) for lang in sorted(langs)
    },
}
Path(out_path).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
print("  Semgrep configs: " + ", ".join(configs))
PY
