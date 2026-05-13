#!/bin/bash
set -uo pipefail

# ──────────────────────────────────────────────
# AKQA Design Studio — Claude Code Setup
# One command. Everything configured.
# ──────────────────────────────────────────────

# Colors
R='\033[0;31m'  G='\033[0;32m'  B='\033[0;34m'
Y='\033[0;33m'  C='\033[0;36m'  W='\033[1;37m'
D='\033[0;90m'  N='\033[0m'

CURRENT_PHASE="startup"

# All interactive reads MUST use /dev/tty — stdin may be a pipe
# (curl ... | bash) or consumed by a subprocess (Homebrew installer)
ask() { read "$@" < /dev/tty; }

die() {
  echo ""
  echo -e "  ${R}━━━ Setup stopped ━━━${N}"
  echo ""
  echo -e "  ${W}Phase:${N} ${CURRENT_PHASE}"
  echo -e "  ${W}Problem:${N} $1"
  echo ""
  echo -e "  ${D}Take a screenshot and send it to your lead.${N}"
  echo ""
  exit 1
}

trap 'die "Unexpected error (line $LINENO)"' ERR

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
phase()   { CURRENT_PHASE="$1"; echo ""; echo -e "  ${C}─── $1 ───${N}"; }

# ──────────────────────────────────────────────
# Pre-flight checks
# ──────────────────────────────────────────────
preflight() {
  CURRENT_PHASE="pre-flight checks"

  if [[ "$(uname -s)" != "Darwin" ]]; then
    die "This script only runs on macOS. Detected: $(uname -s)"
  fi

  info "Checking internet connection..."
  if ! curl -fsS --max-time 8 https://www.google.com &>/dev/null; then
    die "No internet connection. Connect to a network and try again."
  fi
  success "Internet OK"

  if ! xcode-select -p &>/dev/null; then
    echo ""
    warn "Xcode Command Line Tools are not installed."
    echo -e "  ${D}macOS will prompt you to install them now.${N}"
    echo -e "  ${D}Click 'Install' in the dialog, then come back here.${N}"
    echo -e "  ${D}(Takes 5-10 minutes.)${N}"
    echo ""
    xcode-select --install 2>/dev/null || true
    echo -e "  ${D}Press Enter once the install is finished.${N}"
    ask -r -p "  > " _
    if ! xcode-select -p &>/dev/null; then
      die "Xcode Command Line Tools still not detected. Re-run this script after the install finishes."
    fi
  fi
  success "Xcode Command Line Tools OK"
}

# ──────────────────────────────────────────────
# Phase 1: Prerequisites
# ──────────────────────────────────────────────
HAS_BREW=false

detect_homebrew() {
  if ! command -v brew &>/dev/null; then
    if [[ -f /opt/homebrew/bin/brew ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f /usr/local/bin/brew ]]; then
      eval "$(/usr/local/bin/brew shellenv)"
    fi
  fi
  if command -v brew &>/dev/null; then
    HAS_BREW=true
    success "Homebrew detected"
  else
    info "Homebrew not found — using standalone installers (no sudo needed)"
  fi
}

ensure_local_bin() {
  mkdir -p "$HOME/.local/bin"
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
  esac
}

install_node() {
  if command -v node &>/dev/null; then
    local ver
    ver=$(node --version 2>/dev/null || echo "unknown")
    success "Node.js already installed ($ver)"
    return 0
  fi

  if $HAS_BREW; then
    info "Installing Node.js via Homebrew..."
    brew install node
    hash -r 2>/dev/null || true
  else
    info "Installing Node.js via nvm (no sudo needed)..."
    export NVM_DIR="$HOME/.nvm"
    mkdir -p "$NVM_DIR"
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | PROFILE=/dev/null bash
    # Load nvm for this session
    # shellcheck source=/dev/null
    source "$NVM_DIR/nvm.sh"
    nvm install --lts
  fi

  if ! command -v node &>/dev/null; then
    die "Node.js installation failed."
  fi
  success "Node.js installed ($(node --version))"
}

install_gcloud() {
  # gcloud may be installed but not on PATH in this bash context
  if ! command -v gcloud &>/dev/null; then
    for p in "$HOME/google-cloud-sdk/bin" /opt/homebrew/share/google-cloud-sdk/bin /usr/local/share/google-cloud-sdk/bin /opt/homebrew/bin /usr/local/bin; do
      if [[ -x "$p/gcloud" ]]; then
        export PATH="$p:$PATH"
        break
      fi
    done
  fi
  if command -v gcloud &>/dev/null; then
    success "Google Cloud CLI already installed"
    return 0
  fi

  if $HAS_BREW; then
    info "Installing Google Cloud CLI via Homebrew..."
    brew install --cask google-cloud-sdk
    local sdk_dir
    sdk_dir="$(brew --prefix 2>/dev/null || echo "/opt/homebrew")/share/google-cloud-sdk"
    if [[ -f "$sdk_dir/path.bash.inc" ]]; then
      source "$sdk_dir/path.bash.inc"
    fi
    if ! command -v gcloud &>/dev/null && [[ -d "$sdk_dir/bin" ]]; then
      export PATH="$sdk_dir/bin:$PATH"
    fi
  else
    info "Installing Google Cloud CLI (no sudo needed)..."
    local arch
    arch=$(uname -m)
    local url
    if [[ "$arch" == "arm64" ]]; then
      url="https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-darwin-arm.tar.gz"
    else
      url="https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-darwin-x86_64.tar.gz"
    fi
    local tmp_tar
    tmp_tar=$(mktemp)
    curl -fsSL "$url" -o "$tmp_tar"
    # Remove existing partial install if present
    rm -rf "$HOME/google-cloud-sdk"
    tar -xzf "$tmp_tar" -C "$HOME"
    rm -f "$tmp_tar"
    "$HOME/google-cloud-sdk/install.sh" --quiet --path-update=false
    export PATH="$HOME/google-cloud-sdk/bin:$PATH"
  fi

  if ! command -v gcloud &>/dev/null; then
    die "gcloud was installed but can't be found. Try opening a new terminal and re-running this script."
  fi
  success "Google Cloud CLI installed"
}

install_jq() {
  if command -v jq &>/dev/null; then
    return 0
  fi

  if $HAS_BREW; then
    info "Installing jq via Homebrew..."
    brew install jq
  else
    info "Installing jq (no sudo needed)..."
    local arch
    arch=$(uname -m)
    local url
    if [[ "$arch" == "arm64" ]]; then
      url="https://github.com/jqlang/jq/releases/latest/download/jq-macos-arm64"
    else
      url="https://github.com/jqlang/jq/releases/latest/download/jq-macos-amd64"
    fi
    curl -fsSL "$url" -o "$HOME/.local/bin/jq"
    chmod +x "$HOME/.local/bin/jq"
  fi

  if ! command -v jq &>/dev/null; then
    die "jq installation failed."
  fi
  success "jq installed"
}

# ──────────────────────────────────────────────
# Phase 2: GCP Authentication
# ──────────────────────────────────────────────
authenticate_gcp() {
  info "Setting default project to ${W}${GCP_PROJECT}${N}"
  if ! gcloud config set project "$GCP_PROJECT"; then
    die "Could not set GCP project to '$GCP_PROJECT'. Check your internet connection and try again."
  fi

  # Check if already authenticated
  local account
  account=$(gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>/dev/null || true)

  if [[ -n "$account" ]]; then
    success "Signed in as ${W}${account}${N}"
    echo ""
    echo -e "  ${D}Press Enter to continue, or type 'n' to switch accounts.${N}"
    ask -r -p "  > " reauth
    if [[ "$reauth" == "n" || "$reauth" == "N" ]]; then
      echo ""
      info "Opening your browser for Google sign-in..."
      echo -e "  ${D}Sign in with your AKQA account, then come back here.${N}"
      gcloud auth login --update-adc
    fi
  else
    echo ""
    info "Opening your browser for Google sign-in..."
    echo -e "  ${D}Sign in with your AKQA account, then come back here.${N}"
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
  # Check npm won't hit permission errors
  local npm_prefix
  npm_prefix=$(npm config get prefix 2>/dev/null || echo "")
  if [[ "$npm_prefix" == "/usr/local" || "$npm_prefix" == "/" ]]; then
    die "npm's global folder ($npm_prefix) requires admin access. Try re-running this script to install Node via nvm."
  fi

  info "Installing Claude Code CLI (about 30 seconds)..."
  if ! npm install -g @anthropic-ai/claude-code; then
    die "npm install failed. See the error above."
  fi
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

# Tool paths (nvm, gcloud, local binaries)
[[ -s "$HOME/.nvm/nvm.sh" ]] && source "$HOME/.nvm/nvm.sh"
[[ -d "$HOME/google-cloud-sdk/bin" ]] && export PATH="$HOME/google-cloud-sdk/bin:$PATH"
[[ -d "$HOME/.local/bin" ]] && export PATH="$HOME/.local/bin:$PATH"
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
    existing_token=$(jq -r '.mcpServers["figma-console"].env.FIGMA_ACCESS_TOKEN // empty' "$mcp_path" 2>/dev/null || true)
  fi

  if [[ -n "$existing_token" ]]; then
    local masked="${existing_token:0:8}...${existing_token: -4}"
    success "Figma token already configured (${masked})"
    echo ""
    echo -e "  ${D}Press Enter to keep it, or type 'n' to replace it.${N}"
    ask -r -p "  > " keep
    if [[ "$keep" != "n" && "$keep" != "N" ]]; then
      FIGMA_TOKEN="$existing_token"
      return 0
    fi
  fi

  echo ""
  echo -e "  ${W}You need a Figma Personal Access Token.${N}"
  echo ""
  echo -e "  ${D}1. Go to ${W}figma.com${D} and sign in${N}"
  echo -e "  ${D}2. Click your avatar (top-right) → ${W}Settings${N}"
  echo -e "  ${D}3. Scroll to ${W}Personal access tokens${N}"
  echo -e "  ${D}4. Click ${W}Generate new token${N}"
  echo -e "  ${D}5. Name it anything (e.g. 'Claude Code')${N}"
  echo -e "  ${D}6. Copy the token it shows you${N}"
  echo ""
  echo -e "  ${D}Paste it below and press Enter.${N}"
  echo -e "  ${D}(Press Enter without pasting to skip — you can add it later.)${N}"
  echo ""
  ask -r -s -p "  Token: " token
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
# Phase 6: AKQA MCP Bridge
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
    git clone https://github.com/mikehickmanakqa/akqa-mcp.git "$repo_dir"
    success "Cloned to $repo_dir"
  fi

  # Install and build — show output only on failure
  info "Installing dependencies and building (about 30 seconds)..."
  local build_log
  build_log=$(mktemp)
  if (cd "$repo_dir" && npm install 2>&1 && npm run build:local 2>&1) > "$build_log" 2>&1; then
    rm -f "$build_log"
    success "akqa-mcp built"
  else
    echo ""
    fail "Build failed:"
    tail -30 "$build_log" | sed 's/^/    /'
    rm -f "$build_log"
    die "AKQA MCP Bridge failed to build."
  fi

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
# Verification
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

  # Detect piped invocation (curl ... | bash) — interactive prompts
  # won't work without a terminal. /dev/tty is the fallback, but
  # warn clearly so users know the right invocation.
  if [[ ! -t 0 ]]; then
    if [[ ! -e /dev/tty ]]; then
      echo -e "  ${R}This script needs interactive input but no terminal is available.${N}"
      echo ""
      echo -e "  ${W}Run it like this instead:${N}"
      echo -e "  ${D}  bash <(curl -fsSL https://raw.githubusercontent.com/mikehickmanakqa/akqa-onboarding/main/setup-claude.sh)${N}"
      echo ""
      exit 1
    fi
    warn "stdin is not a terminal — using /dev/tty for prompts"
  fi

  # Ensure Homebrew is on PATH regardless of how the script was invoked
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -f /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi

  preflight

  echo -e "  ${D}This script will install and configure:${N}"
  echo -e "  ${D}  Node.js, Google Cloud CLI, Claude Code,${N}"
  echo -e "  ${D}  Vertex AI, AKQA MCP Bridge, and${N}"
  echo -e "  ${D}  design plugins. No sudo required.${N}"
  echo ""
  echo -e "  ${D}Already-installed tools will be skipped.${N}"
  echo ""
  echo -e "  ${W}Prerequisite:${N} Your AKQA Google account"
  echo -e "  ${D}must have access to the${N} ${W}${GCP_PROJECT}${N} ${D}project.${N}"
  echo -e "  ${D}Ask your lead if you're not sure.${N}"
  echo ""
  echo -e "  ${W}Press Enter to begin${N} ${D}(or Ctrl-C to cancel)${N}"
  ask -r -p "  > "

  phase "1/7  Prerequisites"
  detect_homebrew
  ensure_local_bin
  install_jq
  install_node
  install_gcloud

  phase "2/7  GCP Authentication"
  authenticate_gcp

  phase "3/7  Claude Code"
  install_claude

  phase "4/7  Shell Configuration"
  configure_shell

  phase "5/7  Figma Access"
  collect_figma_token

  phase "6/7  AKQA MCP Bridge"
  install_akqa_mcp

  phase "7/7  Plugins"
  configure_plugins

  phase "Verification"
  verify
}

main "$@"
