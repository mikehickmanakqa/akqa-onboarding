## AKQA Design Studio — Claude Code Setup

One command. Everything configured.

### What it does

Installs and configures a Mac for Claude Code with
Vertex AI billing, Figma MCP, the AKQA MCP Bridge,
and design skill plugins.

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
| 5 | Figma personal access token |
| 6 | AKQA MCP Bridge (pre-built download) |
| 7 | Superpowers + Designer Skills plugins |

No admin/sudo access required. If Homebrew is
available it will be used; otherwise tools are
installed to user-writable locations.

### Prerequisites

- macOS
- An AKQA Google account with access to the
  `akqa-us-ai-playground` GCP project
- A Figma personal access token (the script will
  prompt you to paste it)

### One manual step

After the script finishes, import the Figma plugin:

1. Open **Figma Desktop**
2. **Plugins → Development → Import plugin from manifest**
3. Select `~/projects/akqa-mcp/figma-desktop-bridge/manifest.json`
4. Click **Open**

This is a one-time import. The plugin persists across
Figma restarts.

### After setup

Open a new terminal and run:

```bash
claude
```

First launch downloads plugins (~1 minute).

### Publishing a new MCP release

When akqa-mcp is updated, publish a new pre-built
release so the setup script picks it up:

```bash
./scripts/release-mcp.sh
```

This builds akqa-mcp from `~/projects/akqa-mcp`,
packages `dist/` and `figma-desktop-bridge/`, and
uploads to a GitHub Release on this repo. The setup
script always downloads the latest `mcp-v*` release.
