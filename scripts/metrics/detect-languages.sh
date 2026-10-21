#!/usr/bin/env bash
# Detect languages/stacks present in the PR (and repo markers) for metrics scanners.
# Works for single-stack and monorepos (frontend + backend + infra).
# Prefer Pass 1 ai-commands.json when prepare artifacts are available.
set -euo pipefail
# shellcheck source=../common.sh
source "$(cd "$(dirname "$0")/.." && pwd)/common.sh"

OUT="${AGENTIC_TMP}/metrics-languages.json"
CHANGED="${AGENTIC_TMP}/pr-changed-files.txt"
AI_CMD="${AGENTIC_TMP}/ai-commands.json"

mkdir -p "$AGENTIC_TMP"
[[ -f "$CHANGED" ]] || : > "$CHANGED"

python3 - "$CHANGED" "$AI_CMD" "$OUT" <<'PY'
import json, os, sys
from pathlib import Path

changed_path, ai_path, out_path = sys.argv[1:4]

def strip_repo_rel(p: str) -> str:
    """Strip leading ./ only — never lstrip('./') which corrupts .github/ paths."""
    p = p.strip().replace("\\", "/")
    while p.startswith("./"):
        p = p[2:]
    return p

changed = []
if os.path.isfile(changed_path):
    changed = [strip_repo_rel(ln) for ln in open(changed_path) if ln.strip()]

# Extension → language key (Semgrep config family) — top enterprise stacks
EXT = {
    ".js": "javascript", ".jsx": "javascript", ".mjs": "javascript", ".cjs": "javascript",
    ".ts": "typescript", ".tsx": "typescript",
    ".vue": "vue", ".svelte": "javascript",
    ".py": "python", ".pyi": "python",
    ".go": "go",
    ".java": "java",
    ".kt": "kotlin", ".kts": "kotlin",
    ".rb": "ruby", ".erb": "ruby",
    ".php": "php",
    ".cs": "csharp", ".fs": "csharp",
    ".rs": "rust",
    ".scala": "scala", ".sc": "scala",
    ".swift": "swift",
    ".c": "c", ".h": "c",
    ".cpp": "cpp", ".cc": "cpp", ".cxx": "cpp", ".hpp": "cpp",
    ".dart": "dart",
    ".ex": "elixir", ".exs": "elixir",
    ".hs": "haskell",
    ".pl": "perl", ".pm": "perl",
    ".r": "r", ".R": "r",
    ".ps1": "powershell", ".psm1": "powershell",
    ".groovy": "groovy", ".gradle": "groovy",
    ".sql": "sql",
    ".tf": "terraform", ".hcl": "terraform", ".tfvars": "terraform",
    ".bicep": "bicep",
    ".yaml": "yaml", ".yml": "yaml",
    ".json": "json",
    ".sh": "bash", ".bash": "bash", ".zsh": "bash",
    ".dockerfile": "docker",
}

SKIP_PREFIXES = (
    "node_modules/", "vendor/", ".git/", "dist/", "build/", ".terraform/",
    "coverage/", ".next/", "target/", "bin/", "obj/",
)

def is_skippable(p: str) -> bool:
    pl = p.replace("\\", "/")
    if any(pl.startswith(s) or f"/{s}" in f"/{pl}" for s in SKIP_PREFIXES):
        return True
    base = Path(pl).name.lower()
    if base in {"package-lock.json", "pnpm-lock.yaml", "yarn.lock", "go.sum", "poetry.lock"}:
        return True
    return False

langs = set()
code_files = []
for p in changed:
    if is_skippable(p):
        continue
    path = Path(p)
    name = path.name.lower()
    pl = p.replace("\\", "/")
    if name == "dockerfile" or name.startswith("dockerfile."):
        langs.add("docker")
        code_files.append(p)
        continue
    if name in {"chart.yaml", "chart.yml"} or "/templates/" in f"/{pl}" and name.endswith((".yaml", ".yml")):
        langs.add("helm")
        langs.add("kubernetes")
        code_files.append(p)
        continue
    if name in {"deployment.yaml", "deployment.yml", "statefulset.yaml", "daemonset.yaml",
                "cronjob.yaml", "ingress.yaml", "service.yaml"} or pl.endswith(
        (".k8s.yaml", ".k8s.yml")
    ):
        langs.add("kubernetes")
        code_files.append(p)
        continue
    if name in {"playbook.yml", "playbook.yaml", "site.yml", "site.yaml"} or "/roles/" in f"/{pl}":
        if name.endswith((".yml", ".yaml")):
            langs.add("ansible")
            code_files.append(p)
            continue
    if name.endswith((".template", ".template.json")) or "cloudformation" in pl.lower():
        langs.add("cloudformation")
        code_files.append(p)
        continue
    if name == "nginx.conf" or name.endswith(".nginx"):
        langs.add("nginx")
        code_files.append(p)
        continue
    ext = path.suffix.lower()
    if ext in EXT:
        langs.add(EXT[ext])
        code_files.append(p)

# Repo markers (monorepo roots) — supplement when PR is tiny or docs-only
root = Path(".")
markers = [
    ("package.json", "javascript"),
    ("pnpm-workspace.yaml", "javascript"),
    ("tsconfig.json", "typescript"),
    ("pyproject.toml", "python"),
    ("requirements.txt", "python"),
    ("go.mod", "go"),
    ("pom.xml", "java"),
    ("build.gradle", "java"),
    ("build.gradle.kts", "kotlin"),
    ("Cargo.toml", "rust"),
    ("Gemfile", "ruby"),
    ("composer.json", "php"),
    ("*.csproj", "csharp"),
    ("Package.swift", "swift"),
    ("mix.exs", "elixir"),
    ("pubspec.yaml", "dart"),
    ("main.tf", "terraform"),
    ("terragrunt.hcl", "terraform"),
]

repo_langs = set()
for pattern, lang in markers:
    for hit in root.rglob(pattern):
        s = str(hit).replace("\\", "/")
        if is_skippable(s):
            continue
        # depth limit
        if s.count("/") > 6:
            continue
        repo_langs.add(lang)

# Pass 1 stack hint when present
pass1_langs = set()
if os.path.isfile(ai_path):
    try:
        data = json.load(open(ai_path))
        stack = data.get("stack") or {}
        lang = (stack.get("language") or "").lower()
        mapping = {
            "javascript": "javascript", "typescript": "typescript", "node": "javascript",
            "python": "python", "go": "go", "golang": "go",
            "java": "java", "kotlin": "kotlin", "ruby": "ruby",
            "php": "php", "csharp": "csharp", "c#": "csharp",
            "rust": "rust", "terraform": "terraform", "hcl": "terraform",
        }
        if lang in mapping:
            pass1_langs.add(mapping[lang])
        # Extra stacks from check command paths (monorepo signals)
        for cmd in (data.get("check_commands") or []) + (data.get("setup_commands") or []):
            c = (cmd.get("cmd") if isinstance(cmd, dict) else str(cmd)) or ""
            cl = c.lower()
            if "terraform" in cl:
                pass1_langs.add("terraform")
            if "pytest" in cl or "ruff" in cl or "python" in cl:
                pass1_langs.add("python")
            if "eslint" in cl or "pnpm" in cl or "npm " in cl or "tsc" in cl:
                pass1_langs.add("javascript")
    except Exception:
        pass

# Prefer PR languages; if none, use pass1 then repo markers
if langs:
    selected = sorted(langs)
    source = "pr_changed_files"
elif pass1_langs:
    selected = sorted(pass1_langs)
    source = "pass1_stack"
elif repo_langs:
    selected = sorted(repo_langs)
    source = "repo_markers"
else:
    selected = []
    source = "none"

payload = {
    "languages": selected,
    "source": source,
    "pr_code_files": code_files[:500],
    "pr_code_file_count": len(code_files),
    "repo_languages_detected": sorted(repo_langs),
    "pass1_languages": sorted(pass1_langs),
    "scan_mode": "changed_files" if code_files else ("full_repo" if selected else "skip"),
}
with open(out_path, "w") as f:
    json.dump(payload, f, indent=2)
print(f"  Languages: {', '.join(selected) or '(none)'} (source={source}, mode={payload['scan_mode']})")
PY
