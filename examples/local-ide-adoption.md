# App adoption — one command

## Setup (from the app repo)

```bash
cd /path/to/your-app          # e.g. dso-os-frontend
curl -fsSL https://raw.githubusercontent.com/pulumamidi-harsha/agentic-quality-gate/main/scripts/install-app.sh | bash
```

Restart VS Code or Cursor on that folder.

## Daily

Ask Agent: `Run the quality gate on my changes`

## Automatic

- **push** → git pre-push hook runs the gate (`--strict`)
- **PR** → GitHub Quality Gate workflow (commit `.github/workflows/quality-gate.yml` if the installer added it)

## Pilot checklist

- [ ] Ran `install-app.sh` from the app root
- [ ] Restarted IDE → Agent quality gate works
- [ ] `git push` runs the gate (or fails with findings)
- [ ] PR workflow present and pinned to a hub SHA
