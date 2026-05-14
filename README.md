## AKQA Design Studio — Claude Code Setup

One command. Everything configured.

### What it does

Installs and configures a Mac for Claude Code with
Vertex AI billing and design skill plugins.

Already-installed tools are detected and skipped.

### Quick start

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/mikehickmanakqa/akqa-onboarding/main/setup-claude.sh)
```

### What gets installed

| Phase | What |
|-------|------|
| 1 | jq, Node.js, Google Cloud CLI (no sudo) |
| 2 | GCP authentication (browser sign-in) |
| 3 | Claude Code CLI |
| 4 | Vertex AI environment variables |
| 5 | Superpowers + Designer Skills plugins |

No admin/sudo access required. If Homebrew is
available it will be used; otherwise tools are
installed to user-writable locations.

### Prerequisites

- macOS
- An AKQA Google account with access to the
  `akqa-us-ai-playground` GCP project

### After setup

Open a new terminal and run:

```bash
claude
```

First launch downloads plugins (~1 minute).
