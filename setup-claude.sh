#!/bin/bash
set -uo pipefail

# ──────────────────────────────────────────────
# AKQA Claude Code Bootstrap
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

banner() {
  echo ""
  echo -e "${B}  ╔══════════════════════════════════════╗${N}"
  echo -e "${B}  ║${W}   AKQA Claude Code Bootstrap          ${B}║${N}"
  echo -e "${B}  ║${D}   Claude Code + Vertex AI             ${B}║${N}"
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

  if ! command -v git &>/dev/null; then
    die "git is not available. It should come with Xcode Command Line Tools — try: xcode-select --install"
  fi
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
    local brew_prefix
    brew_prefix="$(brew --prefix 2>/dev/null)"
    if [[ -n "$brew_prefix" ]] && [[ -w "$brew_prefix" ]]; then
      HAS_BREW=true
      success "Homebrew detected"
    else
      info "Homebrew found but permissions are broken — using standalone installers"
    fi
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
    local npm_prefix
    npm_prefix=$(npm config get prefix 2>/dev/null || echo "")
    if [[ -n "$npm_prefix" ]] && [[ -w "$npm_prefix" ]]; then
      success "Node.js already installed ($(node --version 2>/dev/null))"
      return 0
    fi
    warn "Node.js found but npm can't write to $npm_prefix — installing via nvm..."
  fi

  if $HAS_BREW && ! command -v node &>/dev/null; then
    info "Installing Node.js via Homebrew..."
    brew install node
    hash -r 2>/dev/null || true
  else
    info "Installing Node.js via nvm (no sudo needed)..."
    export NVM_DIR="$HOME/.nvm"
    mkdir -p "$NVM_DIR"
    local nvm_script
    nvm_script=$(mktemp)
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh -o "$nvm_script"
    PROFILE=/dev/null bash "$nvm_script"
    rm -f "$nvm_script"
    # shellcheck source=/dev/null
    source "$NVM_DIR/nvm.sh"
    nvm install --lts
  fi

  if ! command -v node &>/dev/null; then
    die "Node.js installation failed."
  fi
  success "Node.js installed ($(node --version))"
}

install_python() {
  if ! command -v python3 &>/dev/null; then
    if $HAS_BREW; then
      info "Installing Python 3 via Homebrew..."
      brew install python
      hash -r 2>/dev/null || true
    elif [[ -x /usr/bin/python3 ]]; then
      export PATH="/usr/bin:$PATH"
    else
      die "Python 3 is required but not found. It should come with Xcode Command Line Tools — try: xcode-select --install"
    fi
  fi

  if ! command -v python3 &>/dev/null; then
    die "Python 3 installation failed."
  fi

  # gcloud requires Python 3.10+
  local py_ver
  py_ver=$(python3 -c 'import sys; print(f"{sys.version_info.minor}")' 2>/dev/null || echo "0")
  if (( py_ver < 10 )); then
    info "Python 3.${py_ver} is too old for gcloud (needs 3.10+) — installing standalone Python..."
    local arch url py_dir="$HOME/.local/python3"
    arch=$(uname -m)
    if [[ "$arch" == "arm64" ]]; then
      url="https://github.com/astral-sh/python-build-standalone/releases/download/20260510/cpython-3.10.20+20260510-aarch64-apple-darwin-install_only.tar.gz"
    else
      url="https://github.com/astral-sh/python-build-standalone/releases/download/20260510/cpython-3.10.20+20260510-x86_64-apple-darwin-install_only.tar.gz"
    fi
    local tmp_tar
    tmp_tar=$(mktemp)
    info "Downloading Python 3.10..."
    curl -fL --progress-bar "$url" -o "$tmp_tar" || die "Could not download Python. Check your internet connection."
    rm -rf "$py_dir"
    mkdir -p "$py_dir"
    tar -xzf "$tmp_tar" -C "$py_dir" --strip-components=1
    rm -f "$tmp_tar"
    export PATH="$py_dir/bin:$PATH"
    py_ver=$(python3 -c 'import sys; print(f"{sys.version_info.minor}")' 2>/dev/null || echo "0")
  fi

  # Force gcloud to use this Python, not whatever it was bundled with
  export CLOUDSDK_PYTHON="$(command -v python3)"
  success "Python 3.${py_ver} installed"
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
    if gcloud version &>/dev/null; then
      success "Google Cloud CLI already installed"
      return 0
    fi
    warn "gcloud found but broken (Python issue) — installing standalone copy..."
  fi

  if command -v gcloud &>/dev/null && ! gcloud version &>/dev/null; then
    # Broken install (e.g. Homebrew with bad Python) — skip Brew, go straight to standalone
    :
  elif $HAS_BREW; then
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
    if command -v gcloud &>/dev/null && gcloud version &>/dev/null; then
      success "Google Cloud CLI installed"
      return 0
    fi
    warn "Homebrew gcloud not working — falling back to standalone install..."
  fi

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
  info "Downloading (~500 MB — this takes a few minutes)..."
  curl -fL --progress-bar "$url" -o "$tmp_tar"
  rm -rf "$HOME/google-cloud-sdk"
  tar -xzf "$tmp_tar" -C "$HOME"
  rm -f "$tmp_tar"
  CLOUDSDK_PYTHON="$(command -v python3)" \
    "$HOME/google-cloud-sdk/install.sh" --quiet --path-update=false --install-python=false
  export PATH="$HOME/google-cloud-sdk/bin:$PATH"

  if ! command -v gcloud &>/dev/null; then
    die "gcloud was installed but can't be found. Try opening a new terminal and re-running this script."
  fi
  if ! gcloud version &>/dev/null; then
    die "gcloud installed but still not working. Try opening a new terminal and re-running this script."
  fi
  success "Google Cloud CLI installed"
}

# ──────────────────────────────────────────────
# Phase 2: GCP Authentication
# ──────────────────────────────────────────────
authenticate_gcp() {
  # Authenticate FIRST — new users can't validate the project until
  # they've signed in with an account that has access to it.
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
      if ! gcloud auth login --update-adc; then
        die "Google sign-in failed. Re-run the script to try again."
      fi
    fi
  else
    echo ""
    info "Opening your browser for Google sign-in..."
    echo -e "  ${D}Sign in with your AKQA account, then come back here.${N}"
    if ! gcloud auth login --update-adc; then
      die "Google sign-in failed. Re-run the script to try again."
    fi
  fi

  # Now set the project — requires an authenticated account with access
  info "Setting default project to ${W}${GCP_PROJECT}${N}"
  if ! gcloud config set project "$GCP_PROJECT" 2>/dev/null; then
    echo ""
    fail "Could not set project to '${GCP_PROJECT}'."
    echo -e "  ${D}This usually means your account doesn't have access yet.${N}"
    echo -e "  ${D}Ask your lead to add your Google account to the${N}"
    echo -e "  ${D}${W}akqa-us-ai-playground${N}${D} GCP project, then re-run this script.${N}"
    die "GCP project access denied — see above."
  fi

  # Ensure application default credentials exist
  local adc_path="$HOME/.config/gcloud/application_default_credentials.json"
  if [[ ! -f "$adc_path" ]]; then
    info "Setting up application default credentials..."
    gcloud auth application-default login
  fi

  # Bind quota project so Claude Code bills to the right place
  info "Setting ADC quota project..."
  gcloud auth application-default set-quota-project "$GCP_PROJECT" 2>/dev/null || true
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
  local npm_prefix
  npm_prefix=$(npm config get prefix 2>/dev/null || echo "")
  if [[ -n "$npm_prefix" ]] && [[ ! -w "$npm_prefix" ]]; then
    die "npm's global folder ($npm_prefix) isn't writable. Try deleting the existing Node.js and re-running this script."
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
    # Older versions may lack nvm/gcloud PATH lines or CLOUD_ML_REGION — update if so
    if ! grep -q 'nvm.sh' "$shell_rc" 2>/dev/null || ! grep -q 'CLOUD_ML_REGION' "$shell_rc" 2>/dev/null || ! grep -q 'CLOUDSDK_PYTHON' "$shell_rc" 2>/dev/null; then
      info "Updating shell config (new settings available)..."
      cp "$shell_rc" "${shell_rc}.backup.$(date +%s)" 2>/dev/null || true
      # Remove old block and re-add below
      sed -i '' "/$marker/,/^$/d" "$shell_rc"
    else
      success "Shell already configured (skipping)"
      # Still export for this session
      export CLAUDE_CODE_USE_VERTEX=1
      export ANTHROPIC_VERTEX_PROJECT_ID="$GCP_PROJECT"
      export CLOUD_ML_REGION="us-east5"
      export GCLOUD_PROJECT="$GCP_PROJECT"
      export GOOGLE_CLOUD_PROJECT="$GCP_PROJECT"
      export GOOGLE_APPLICATION_CREDENTIALS="$HOME/.config/gcloud/application_default_credentials.json"
      return 0
    fi
  fi

  info "Adding Vertex AI configuration to ~/.zshrc"

  # Backup
  cp "$shell_rc" "${shell_rc}.backup.$(date +%s)" 2>/dev/null || true

  cat >> "$shell_rc" << 'SHELL_BLOCK'

# AKQA Claude Code — managed by setup-claude.sh
export CLAUDE_CODE_USE_VERTEX=1
export ANTHROPIC_VERTEX_PROJECT_ID=akqa-us-ai-playground
export CLOUD_ML_REGION=us-east5
export GCLOUD_PROJECT="$ANTHROPIC_VERTEX_PROJECT_ID"
export GOOGLE_CLOUD_PROJECT="$ANTHROPIC_VERTEX_PROJECT_ID"
export GOOGLE_APPLICATION_CREDENTIALS="$HOME/.config/gcloud/application_default_credentials.json"

# Force gcloud to use a modern Python (not its bundled version)
command -v python3 &>/dev/null && export CLOUDSDK_PYTHON="$(command -v python3)"

# Tool paths (nvm, gcloud, standalone python, local binaries)
[[ -d "$HOME/.local/python3/bin" ]] && export PATH="$HOME/.local/python3/bin:$PATH"
[[ -s "$HOME/.nvm/nvm.sh" ]] && source "$HOME/.nvm/nvm.sh"
[[ -d "$HOME/google-cloud-sdk/bin" ]] && export PATH="$HOME/google-cloud-sdk/bin:$PATH"
[[ -d "$HOME/.local/bin" ]] && export PATH="$HOME/.local/bin:$PATH"
SHELL_BLOCK

  # Source for this session
  export CLAUDE_CODE_USE_VERTEX=1
  export ANTHROPIC_VERTEX_PROJECT_ID="$GCP_PROJECT"
  export CLOUD_ML_REGION="us-east5"
  export GCLOUD_PROJECT="$GCP_PROJECT"
  export GOOGLE_CLOUD_PROJECT="$GCP_PROJECT"
  export GOOGLE_APPLICATION_CREDENTIALS="$HOME/.config/gcloud/application_default_credentials.json"

  success "Shell configured"
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

  echo ""
  if $all_good; then
    echo -e "  ${G}══════════════════════════════════════${N}"
    echo -e "  ${G}  Ready to go.${N}"
    echo -e "  ${G}══════════════════════════════════════${N}"
    echo ""
    echo -e "  ${D}Open a new terminal, then:${N}"
    echo -e "  ${W}  claude${N}"
    echo ""
    echo -e "  ${W}Next:${N} ${D}get the AKQA Intelligence plugin${N}"
    echo -e "  ${D}(role-specific skills + shared knowledge):${N}"
    echo -e "  ${D}  git clone https://github.com/mikehickmanakqa/akqa-intelligence.git${N}"
    echo -e "  ${D}  cd akqa-intelligence && bash setup-claude.sh${N}"
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
  echo -e "  ${D}  and Vertex AI.${N}"
  echo -e "  ${D}  No sudo required.${N}"
  echo ""
  echo -e "  ${D}Already-installed tools will be skipped.${N}"
  echo ""
  echo -e "  ${W}Prerequisite:${N} Your AKQA Google account"
  echo -e "  ${D}must have access to the${N} ${W}${GCP_PROJECT}${N} ${D}project.${N}"
  echo -e "  ${D}Ask your lead if you're not sure.${N}"
  echo ""
  echo -e "  ${W}Press Enter to begin${N} ${D}(or Ctrl-C to cancel)${N}"
  ask -r -p "  > "

  phase "1/4  Prerequisites"
  detect_homebrew
  ensure_local_bin
  install_node
  install_python
  install_gcloud

  phase "2/4  GCP Authentication"
  authenticate_gcp

  phase "3/4  Claude Code"
  install_claude

  phase "4/4  Shell Configuration"
  configure_shell

  phase "Verification"
  verify
}

main "$@"
