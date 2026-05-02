#!/bin/bash
set -euo pipefail

# ──────────────────────────────────────────────
# AKQA Design Studio — Claude Code Setup
# One command. Everything configured.
# ──────────────────────────────────────────────

# Colors
R='\033[0;31m'  G='\033[0;32m'  B='\033[0;34m'
Y='\033[0;33m'  C='\033[0;36m'  W='\033[1;37m'
D='\033[0;90m'  N='\033[0m'

GCP_PROJECT="akqa-us-ai-playground"
DEFAULT_MODEL="claude-sonnet-4-6"

banner() {
  echo ""
  echo -e "${B}  ╔══════════════════════════════════════╗${N}"
  echo -e "${B}  ║${W}   AKQA Design Studio                 ${B}║${N}"
  echo -e "${B}  ║${D}   Claude Code + Vertex AI + Figma    ${B}║${N}"
  echo -e "${B}  ╚══════════════════════════════════════╝${N}"
  echo ""
}

info()    { echo -e "  ${D}▸${N} $1"; }
success() { echo -e "  ${G}✓${N} $1"; }
warn()    { echo -e "  ${Y}!${N} $1"; }
fail()    { echo -e "  ${R}✗${N} $1"; }
phase()   { echo ""; echo -e "  ${C}─── $1 ───${N}"; }

# ──────────────────────────────────────────────
# Phase 1: Prerequisites
# ──────────────────────────────────────────────
install_homebrew() {
  if command -v brew &>/dev/null; then
    success "Homebrew already installed"
    return 0
  fi
  info "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Add Homebrew to PATH for this session (Apple Silicon)
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
  success "Homebrew installed"
}

install_node() {
  if command -v node &>/dev/null; then
    local ver
    ver=$(node --version)
    success "Node.js already installed ($ver)"
    return 0
  fi
  info "Installing Node.js..."
  brew install node
  success "Node.js installed ($(node --version))"
}

install_gcloud() {
  if command -v gcloud &>/dev/null; then
    success "Google Cloud CLI already installed"
    return 0
  fi
  info "Installing Google Cloud CLI..."
  brew install --cask google-cloud-sdk
  # Source completions for this session
  if [[ -f "$(brew --prefix)/share/google-cloud-sdk/path.zsh.inc" ]]; then
    source "$(brew --prefix)/share/google-cloud-sdk/path.zsh.inc"
  fi
  success "Google Cloud CLI installed"
}

install_jq() {
  if command -v jq &>/dev/null; then
    return 0
  fi
  info "Installing jq (for config management)..."
  brew install jq
  success "jq installed"
}

# ──────────────────────────────────────────────
# Phase 2: GCP Authentication
# ──────────────────────────────────────────────
authenticate_gcp() {
  info "Setting default project to ${W}${GCP_PROJECT}${N}"
  gcloud config set project "$GCP_PROJECT" 2>/dev/null

  # Check if already authenticated
  local account
  account=$(gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>/dev/null || true)

  if [[ -n "$account" ]]; then
    success "Already authenticated as ${W}${account}${N}"
    echo ""
    echo -e "  ${D}Is this the right account? (y/n)${N}"
    read -r -p "  > " reauth
    if [[ "$reauth" == "n" || "$reauth" == "N" ]]; then
      info "Opening browser for Google sign-in..."
      gcloud auth login --update-adc
    fi
  else
    info "Opening browser for Google sign-in..."
    gcloud auth login --update-adc
  fi

  # Ensure application default credentials exist
  local adc_path="$HOME/.config/gcloud/application_default_credentials.json"
  if [[ ! -f "$adc_path" ]]; then
    info "Setting up application default credentials..."
    gcloud auth application-default login
  fi
  success "GCP authentication complete"
}

# ──────────────────────────────────────────────
# Phase 3: Claude Code CLI
# ──────────────────────────────────────────────
install_claude() {
  if command -v claude &>/dev/null; then
    local ver
    ver=$(claude --version 2>/dev/null || echo "unknown")
    success "Claude Code already installed ($ver)"
    return 0
  fi
  info "Installing Claude Code CLI..."
  npm install -g @anthropic-ai/claude-code
  success "Claude Code installed ($(claude --version 2>/dev/null))"
}

# ──────────────────────────────────────────────
# Phase 4: Shell Configuration
# ──────────────────────────────────────────────
configure_shell() {
  local shell_rc="$HOME/.zshrc"
  local marker="# AKQA Claude Code — managed by setup-claude.sh"

  if grep -q "$marker" "$shell_rc" 2>/dev/null; then
    success "Shell already configured (skipping)"
    return 0
  fi

  info "Adding Vertex AI configuration to ~/.zshrc"

  # Backup
  cp "$shell_rc" "${shell_rc}.backup.$(date +%s)" 2>/dev/null || true

  cat >> "$shell_rc" << 'SHELL_BLOCK'

# AKQA Claude Code — managed by setup-claude.sh
export CLAUDE_CODE_USE_VERTEX=1
export ANTHROPIC_VERTEX_PROJECT_ID=akqa-us-ai-playground
export GCLOUD_PROJECT="$ANTHROPIC_VERTEX_PROJECT_ID"
export GOOGLE_CLOUD_PROJECT="$ANTHROPIC_VERTEX_PROJECT_ID"
export GOOGLE_APPLICATION_CREDENTIALS="$HOME/.config/gcloud/application_default_credentials.json"
SHELL_BLOCK

  # Source for this session
  export CLAUDE_CODE_USE_VERTEX=1
  export ANTHROPIC_VERTEX_PROJECT_ID="$GCP_PROJECT"
  export GCLOUD_PROJECT="$GCP_PROJECT"
  export GOOGLE_CLOUD_PROJECT="$GCP_PROJECT"
  export GOOGLE_APPLICATION_CREDENTIALS="$HOME/.config/gcloud/application_default_credentials.json"

  success "Shell configured"
}

# ──────────────────────────────────────────────
# Phase 5: Figma Token
# ──────────────────────────────────────────────
collect_figma_token() {
  local mcp_path="$HOME/.claude/mcp.json"
  local existing_token=""

  # Check if already configured
  if [[ -f "$mcp_path" ]]; then
    existing_token=$(jq -r '.mcpServers.figma.env.FIGMA_API_KEY // empty' "$mcp_path" 2>/dev/null || true)
  fi

  if [[ -n "$existing_token" ]]; then
    local masked="${existing_token:0:8}...${existing_token: -4}"
    success "Figma token already configured (${masked})"
    echo ""
    echo -e "  ${D}Keep this token? (y/n)${N}"
    read -r -p "  > " keep
    if [[ "$keep" == "y" || "$keep" == "Y" || -z "$keep" ]]; then
      FIGMA_TOKEN="$existing_token"
      return 0
    fi
  fi

  echo ""
  echo -e "  ${W}Figma Personal Access Token${N}"
  echo -e "  ${D}Create one at: figma.com > Settings > Security${N}"
  echo -e "  ${D}> Personal access tokens > Generate new token${N}"
  echo ""
  read -r -s -p "  Paste token: " token
  echo ""

  if [[ -z "$token" ]]; then
    fail "No token provided — Figma MCP won't be configured"
    FIGMA_TOKEN=""
    return 0
  fi

  FIGMA_TOKEN="$token"
  success "Token captured"
}

# ──────────────────────────────────────────────
# Phase 6: MCP Configuration
# ──────────────────────────────────────────────
configure_mcp() {
  local mcp_path="$HOME/.claude/mcp.json"

  mkdir -p "$HOME/.claude"

  if [[ -z "${FIGMA_TOKEN:-}" ]]; then
    warn "Skipping MCP setup (no Figma token)"
    return 0
  fi

  # Build mcp.json — preserve any existing servers
  local existing="{}"
  if [[ -f "$mcp_path" ]]; then
    existing=$(cat "$mcp_path")
  fi

  local new_config
  new_config=$(echo "$existing" | jq --arg token "$FIGMA_TOKEN" '
    .mcpServers.figma = {
      "command": "npx",
      "args": ["-y", "figma-mcp"],
      "env": {
        "FIGMA_API_KEY": $token
      }
    }
  ')

  echo "$new_config" | jq '.' > "$mcp_path"
  success "Figma MCP configured"
}

# ──────────────────────────────────────────────
# Phase 7: AKQA MCP Bridge
# ──────────────────────────────────────────────
install_akqa_mcp() {
  local repo_dir="$HOME/projects/akqa-mcp"
  local mcp_path="$HOME/.claude/mcp.json"

  # Clone if not present
  if [[ -d "$repo_dir" ]]; then
    success "akqa-mcp already cloned at $repo_dir"
  else
    info "Cloning akqa-mcp..."
    mkdir -p "$HOME/projects"
    git clone https://github.com/mikehickman/akqa-mcp.git "$repo_dir"
    success "Cloned to $repo_dir"
  fi

  # Install and build
  info "Installing dependencies and building..."
  (cd "$repo_dir" && npm install --silent 2>/dev/null && npm run build:local --silent 2>/dev/null)
  success "akqa-mcp built"

  # Add figma-console to mcp.json (reuses Figma token)
  if [[ -z "${FIGMA_TOKEN:-}" ]]; then
    warn "Skipping figma-console MCP (no Figma token)"
    return 0
  fi

  local existing="{}"
  if [[ -f "$mcp_path" ]]; then
    existing=$(cat "$mcp_path")
  fi

  local updated
  updated=$(echo "$existing" | jq \
    --arg token "$FIGMA_TOKEN" \
    --arg script "$repo_dir/dist/local.js" '
    .mcpServers["figma-console"] = {
      "command": "node",
      "args": [$script],
      "env": {
        "FIGMA_ACCESS_TOKEN": $token,
        "ENABLE_MCP_APPS": "true"
      }
    }
  ')

  echo "$updated" | jq '.' > "$mcp_path"
  success "figma-console MCP configured"

  # Print the one manual step
  echo ""
  echo -e "  ${Y}── Manual step ──${N}"
  echo -e "  ${D}Import the Figma plugin (one-time):${N}"
  echo -e "  ${D}  1. Open Figma Desktop${N}"
  echo -e "  ${D}  2. Plugins → Development → Import plugin from manifest${N}"
  echo -e "  ${D}  3. Select: ${W}~/projects/akqa-mcp/figma-desktop-bridge/manifest.json${N}"
  echo -e "  ${D}  4. Click Open${N}"
  echo ""
}

# ──────────────────────────────────────────────
# Phase 8: Plugins
# ──────────────────────────────────────────────
configure_plugins() {
  local settings_path="$HOME/.claude/settings.json"

  mkdir -p "$HOME/.claude"

  local existing="{}"
  if [[ -f "$settings_path" ]]; then
    existing=$(cat "$settings_path")
  fi

  # Merge plugin config into existing settings
  local updated
  updated=$(echo "$existing" | jq '
    .enabledPlugins["superpowers@claude-plugins-official"] = true |
    .enabledPlugins["design-research@designer-skills"] = true |
    .enabledPlugins["design-systems@designer-skills"] = true |
    .enabledPlugins["designer-toolkit@designer-skills"] = true |
    .enabledPlugins["interaction-design@designer-skills"] = true |
    .enabledPlugins["prototyping-testing@designer-skills"] = true |
    .enabledPlugins["ui-design@designer-skills"] = true |
    .enabledPlugins["ux-strategy@designer-skills"] = true |
    .extraKnownMarketplaces["designer-skills"] = {
      "source": {
        "source": "git",
        "url": "https://github.com/Owl-Listener/designer-skills.git"
      },
      "autoUpdate": true
    }
  ')

  echo "$updated" | jq '.' > "$settings_path"
  success "Superpowers plugin enabled"
  success "Designer Skills plugin enabled"
}

# ──────────────────────────────────────────────
# Phase 8: Verify
# ──────────────────────────────────────────────
verify() {
  local all_good=true

  info "Running checks..."

  if command -v claude &>/dev/null; then
    success "Claude Code CLI: $(claude --version 2>/dev/null)"
  else
    fail "Claude Code CLI not found"; all_good=false
  fi

  if command -v gcloud &>/dev/null; then
    local project
    project=$(gcloud config get project 2>/dev/null || true)
    if [[ "$project" == "$GCP_PROJECT" ]]; then
      success "GCP project: $project"
    else
      warn "GCP project is '$project' (expected $GCP_PROJECT)"
    fi
  else
    fail "gcloud CLI not found"; all_good=false
  fi

  if [[ -f "$HOME/.config/gcloud/application_default_credentials.json" ]]; then
    success "Application default credentials exist"
  else
    fail "No application default credentials"; all_good=false
  fi

  if [[ "${CLAUDE_CODE_USE_VERTEX:-}" == "1" ]]; then
    success "Vertex AI enabled"
  else
    warn "Vertex AI env vars not in current session (restart terminal)"
  fi

  if [[ -f "$HOME/.claude/mcp.json" ]]; then
    local servers
    servers=$(jq -r '.mcpServers | keys[]' "$HOME/.claude/mcp.json" 2>/dev/null || true)
    success "MCP servers: $servers"
  else
    warn "No MCP configuration found"
  fi

  if [[ -f "$HOME/.claude/settings.json" ]]; then
    local plugins
    plugins=$(jq -r '.enabledPlugins | keys | length' "$HOME/.claude/settings.json" 2>/dev/null || echo "0")
    success "Plugins configured: $plugins"
  fi

  echo ""
  if $all_good; then
    echo -e "  ${G}══════════════════════════════════════${N}"
    echo -e "  ${G}  Ready to go.${N}"
    echo -e "  ${G}══════════════════════════════════════${N}"
    echo ""
    echo -e "  ${D}Open a new terminal, then:${N}"
    echo -e "  ${W}  claude${N}"
    echo ""
    echo -e "  ${D}First launch will download plugins.${N}"
    echo -e "  ${D}Takes about a minute.${N}"
  else
    echo -e "  ${Y}══════════════════════════════════════${N}"
    echo -e "  ${Y}  Partially configured — see above.${N}"
    echo -e "  ${Y}══════════════════════════════════════${N}"
  fi
  echo ""
}

# ──────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────
main() {
  banner

  echo -e "  ${D}This script will install and configure:${N}"
  echo -e "  ${D}  Homebrew, Node.js, Google Cloud CLI,${N}"
  echo -e "  ${D}  Claude Code, Vertex AI, Figma MCP,${N}"
  echo -e "  ${D}  AKQA MCP Bridge, and design plugins.${N}"
  echo ""
  echo -e "  ${D}Already-installed tools will be skipped.${N}"
  echo ""
  echo -e "  ${W}Prerequisite:${N} Your AKQA Google account"
  echo -e "  ${D}must have access to the${N} ${W}${GCP_PROJECT}${N} ${D}project.${N}"
  echo -e "  ${D}Ask your lead if you're not sure.${N}"
  echo ""
  read -r -p "  Ready? (y/n) > " go
  if [[ "$go" != "y" && "$go" != "Y" ]]; then
    echo ""; info "No worries. Run again when ready."; echo ""
    exit 0
  fi

  phase "1/8  Prerequisites"
  install_homebrew
  install_jq
  install_node
  install_gcloud

  phase "2/8  GCP Authentication"
  authenticate_gcp

  phase "3/8  Claude Code"
  install_claude

  phase "4/8  Shell Configuration"
  configure_shell

  phase "5/8  Figma Access"
  collect_figma_token

  phase "6/8  MCP Servers"
  configure_mcp

  phase "7/8  AKQA MCP Bridge"
  install_akqa_mcp

  phase "8/8  Plugins"
  configure_plugins

  phase "Verification"
  verify
}

main "$@"
