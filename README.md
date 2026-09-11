## AKQA Claude Code Bootstrap

One command to get Claude Code + Vertex AI running on a fresh
Mac. No AKQA-internal content lives here — just Node, gcloud,
the Claude Code CLI, and shell config.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/mikehickmanakqa/akqa-onboarding/main/setup-claude.sh)
```

**Prerequisite:** your AKQA Google account needs access to the
`akqa-us-ai-playground` GCP project. Ask your lead if you're
not sure.

After this finishes, get the AKQA Intelligence plugin
(role-specific skills + shared knowledge — private repo,
needs GitHub access):

```bash
git clone https://github.com/mikehickmanakqa/akqa-intelligence.git
cd akqa-intelligence
bash setup-claude.sh
```

Open a new terminal, run `claude`, then `/first-session`.

### Why two scripts

This repo is public (curl one-liners need a public raw URL) and
deliberately contains nothing AKQA-specific. `akqa-intelligence`
is private and owns the plugin, skills, and knowledge base — it
still uses a git-clone flow, not curl, since it's kept private.
