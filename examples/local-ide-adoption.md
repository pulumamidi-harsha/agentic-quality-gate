# App adoption — one command

## Setup (one paste — then `run-qg` works in that same terminal)

**macOS / Linux**

```bash
cd /path/to/your-app && bash ../agentic-quality-gate/scripts/install-app.sh && export PATH="$HOME/.local/bin:$PATH" && hash -r
```

**Windows (PowerShell)** — needs Git for Windows + Python 3:

```powershell
cd C:\path\to\your-app; & ..\agentic-quality-gate\scripts\install-app.ps1
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
