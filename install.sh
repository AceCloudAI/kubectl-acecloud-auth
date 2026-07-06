#!/usr/bin/env bash
#
# Installer for the AceCloud kubectl auth plugin.
#
#   curl -fsSL https://raw.githubusercontent.com/AceCloudAI/kubectl-acecloud-auth/main/install.sh | bash
#
# Environment overrides:
#   VERSION      Install a specific tag (e.g. v1.2.3). Default: latest release.
#   INSTALL_DIR  Where to place the binary. Default: /usr/local/bin (falls back
#                to $HOME/.local/bin if not writable).

set -euo pipefail

REPO="AceCloudAI/kubectl-acecloud-auth"   # public releases repo
BINARY="kubectl-acecloud_auth"          # must keep this name for kubectl discovery

# ---- pretty output -----------------------------------------------------------
info()  { printf '\033[0;34m==>\033[0m %s\n' "$1"; }
ok()    { printf '\033[0;32m==>\033[0m %s\n' "$1"; }
err()   { printf '\033[0;31mError:\033[0m %s\n' "$1" >&2; exit 1; }

# ---- detect OS / arch --------------------------------------------------------
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$OS" in
  linux|darwin) ;;
  *) err "unsupported OS: $OS (Windows users: see the README for install.ps1)" ;;
esac

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64)  ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) err "unsupported architecture: $ARCH" ;;
esac

# ---- resolve version ---------------------------------------------------------
if [ -z "${VERSION:-}" ]; then
  info "Looking up latest release..."
  VERSION="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
    | grep -m1 '"tag_name"' | cut -d'"' -f4)"
  [ -n "$VERSION" ] || err "could not determine latest release tag"
fi
info "Installing ${BINARY} ${VERSION} for ${OS}/${ARCH}"

ASSET="${BINARY}-${OS}-${ARCH}"
BASE_URL="https://github.com/${REPO}/releases/download/${VERSION}"

# ---- download into a temp dir ------------------------------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

info "Downloading ${ASSET}..."
curl -fsSL -o "${TMP}/${BINARY}" "${BASE_URL}/${ASSET}" \
  || err "download failed — no build for ${OS}/${ARCH} in ${VERSION}?"

# ---- verify checksum ---------------------------------------------------------
if curl -fsSL -o "${TMP}/checksums.txt" "${BASE_URL}/checksums.txt" 2>/dev/null; then
  info "Verifying checksum..."
  expected="$(grep " ${ASSET}\$" "${TMP}/checksums.txt" | awk '{print $1}')"
  if [ -n "$expected" ]; then
    if command -v sha256sum >/dev/null 2>&1; then
      actual="$(sha256sum "${TMP}/${BINARY}" | awk '{print $1}')"
    else
      actual="$(shasum -a 256 "${TMP}/${BINARY}" | awk '{print $1}')"
    fi
    [ "$expected" = "$actual" ] || err "checksum mismatch — aborting"
    ok "Checksum verified"
  fi
else
  info "No checksums.txt found in release — skipping verification"
fi

chmod +x "${TMP}/${BINARY}"

# ---- choose install dir ------------------------------------------------------
if [ -z "${INSTALL_DIR:-}" ]; then
  if [ -w /usr/local/bin ] 2>/dev/null; then
    INSTALL_DIR="/usr/local/bin"
  elif command -v sudo >/dev/null 2>&1 && [ -d /usr/local/bin ]; then
    INSTALL_DIR="/usr/local/bin"
    USE_SUDO=1
  else
    INSTALL_DIR="${HOME}/.local/bin"
    mkdir -p "$INSTALL_DIR"
  fi
fi

info "Installing to ${INSTALL_DIR}/${BINARY}"
if [ "${USE_SUDO:-0}" = "1" ]; then
  sudo mv "${TMP}/${BINARY}" "${INSTALL_DIR}/${BINARY}"
else
  mv "${TMP}/${BINARY}" "${INSTALL_DIR}/${BINARY}"
fi

# ---- verify + next steps -----------------------------------------------------
if ! echo ":$PATH:" | grep -q ":${INSTALL_DIR}:"; then
  printf '\033[0;33mNote:\033[0m %s is not on your PATH. Add it:\n' "$INSTALL_DIR"
  printf '  echo '\''export PATH="%s:$PATH"'\'' >> ~/.bashrc && source ~/.bashrc\n' "$INSTALL_DIR"
fi

ok "Installed. Verify with: kubectl acecloud_auth version"
cat <<'EOF'

Next steps:
  1. Download your kubeconfig from the AceCloud portal.
  2. export KUBECONFIG=/path/to/your-kubeconfig.yaml
  3. kubectl get pods   # the plugin refreshes your token automatically
EOF
