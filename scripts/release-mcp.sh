#!/usr/bin/env bash
# Build akqa-mcp from source and publish as a GitHub Release
# on the akqa-onboarding repo.
#
# One-liner:
#   bash <(curl -fsSL https://raw.githubusercontent.com/mikehickmanakqa/akqa-onboarding/main/scripts/release-mcp.sh)
#
# Uses ~/projects/akqa-mcp if it exists, otherwise clones
# to a temp directory and cleans up after.
#
# Prerequisites:
#   - gh CLI authenticated (brew install gh && gh auth login)
#   - Node.js available

set -euo pipefail

ONBOARDING_REPO="mikehickmanakqa/akqa-onboarding"
MCP_REMOTE="https://github.com/mikehickmanakqa/akqa-mcp.git"
CLEANUP_REPO=false

# ── Preflight ──

if ! command -v gh &>/dev/null; then
  echo "Error: gh CLI not found."
  echo "  brew install gh && gh auth login"
  exit 1
fi

if ! command -v node &>/dev/null; then
  echo "Error: Node.js not found."
  exit 1
fi

# ── Get the source ──

MCP_REPO="${MCP_REPO:-$HOME/projects/akqa-mcp}"

if [[ -d "$MCP_REPO/.git" ]]; then
  echo "==> Using local clone at $MCP_REPO"
  (cd "$MCP_REPO" && git pull --ff-only)
else
  MCP_REPO=$(mktemp -d)
  CLEANUP_REPO=true
  echo "==> Cloning akqa-mcp to temp directory..."
  git clone --depth 1 "$MCP_REMOTE" "$MCP_REPO"
fi

cleanup() { $CLEANUP_REPO && rm -rf "$MCP_REPO"; }
trap cleanup EXIT

# ── Build ──

VERSION=$(node -p "require('$MCP_REPO/package.json').version")
TAG="mcp-v${VERSION}"
echo "==> Version: $VERSION (tag: $TAG)"

echo "==> Installing dependencies..."
(cd "$MCP_REPO" && npm install --silent)

echo "==> Building..."
(cd "$MCP_REPO" && npm run build:local --silent)

# ── Package ──

STAGING=$(mktemp -d)
TARBALL="$STAGING/akqa-mcp-${VERSION}.tar.gz"

tar -czf "$TARBALL" \
  -C "$MCP_REPO" \
  dist/ \
  figma-desktop-bridge/

SIZE=$(du -h "$TARBALL" | cut -f1)
echo "==> Packaged: $TARBALL ($SIZE)"

# ── Publish ──

if gh release view "$TAG" --repo "$ONBOARDING_REPO" &>/dev/null; then
  echo "==> Release $TAG already exists — updating asset..."
  gh release delete-asset "$TAG" "akqa-mcp-${VERSION}.tar.gz" \
    --repo "$ONBOARDING_REPO" --yes 2>/dev/null || true
  gh release upload "$TAG" "$TARBALL" \
    --repo "$ONBOARDING_REPO"
else
  echo "==> Creating release $TAG..."
  gh release create "$TAG" "$TARBALL" \
    --repo "$ONBOARDING_REPO" \
    --title "AKQA MCP $VERSION" \
    --notes "Pre-built AKQA MCP Bridge (dist + Figma Desktop Bridge plugin)."
fi

rm -rf "$STAGING"
echo ""
echo "==> Done. New team members will get this version automatically."
