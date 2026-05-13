#!/usr/bin/env bash
# Build akqa-mcp from source and publish as a GitHub Release
# on the akqa-onboarding repo.
#
# Usage:  ./scripts/release-mcp.sh [version]
#   version defaults to the version in akqa-mcp/package.json
#
# Prerequisites:
#   - gh CLI authenticated
#   - akqa-mcp cloned at ~/projects/akqa-mcp (or MCP_REPO env var)
#   - Node.js available

set -euo pipefail

MCP_REPO="${MCP_REPO:-$HOME/projects/akqa-mcp}"
ONBOARDING_REPO="mikehickmanakqa/akqa-onboarding"

if [[ ! -d "$MCP_REPO" ]]; then
  echo "Error: akqa-mcp not found at $MCP_REPO"
  echo "Clone it first, or set MCP_REPO=/path/to/akqa-mcp"
  exit 1
fi

if ! command -v gh &>/dev/null; then
  echo "Error: gh CLI not found. Install: brew install gh"
  exit 1
fi

# Pull latest
echo "==> Pulling latest akqa-mcp..."
(cd "$MCP_REPO" && git pull --ff-only)

# Determine version
VERSION="${1:-$(node -p "require('$MCP_REPO/package.json').version")}"
TAG="mcp-v${VERSION}"
echo "==> Version: $VERSION (tag: $TAG)"

# Build
echo "==> Building..."
(cd "$MCP_REPO" && npm install --silent && npm run build:local --silent)

# Package — only dist/ and figma-desktop-bridge/
STAGING=$(mktemp -d)
TARBALL="$STAGING/akqa-mcp-${VERSION}.tar.gz"

tar -czf "$TARBALL" \
  -C "$MCP_REPO" \
  dist/ \
  figma-desktop-bridge/

SIZE=$(du -h "$TARBALL" | cut -f1)
echo "==> Packaged: $TARBALL ($SIZE)"

# Check if release already exists
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
echo "==> Done. Setup script will download from:"
echo "    https://github.com/$ONBOARDING_REPO/releases/download/$TAG/akqa-mcp-${VERSION}.tar.gz"
