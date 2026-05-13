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
| 1 | Homebrew, jq, Node.js, Google Cloud CLI |
| 2 | GCP authentication (browser sign-in) |
| 3 | Claude Code CLI |
| 4 | Vertex AI environment variables |
| 5 | Figma personal access token |
| 6 | AKQA MCP Bridge (clone, build, configure) |
| 7 | Superpowers + Designer Skills plugins |

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
