# App adoption — one command

## Setup

```bash
cd /path/to/your-app
curl -fsSL https://raw.githubusercontent.com/pulumamidi-harsha/agentic-quality-gate/main/scripts/install-app.sh | bash
```

## Run (pick one)

**Terminal — live logs (best for watching progress):**

```bash
run-qg
```

**VS Code:** Terminal → Run Task… → `run-qg`

**Agent chat:** type `run-qg` (good for explain/fix; may look idle until a chunk returns)

## Automatic

- **push** → pre-push hook (`run-qg --strict`)
- **PR** → GitHub Quality Gate workflow
