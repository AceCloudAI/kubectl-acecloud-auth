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
  # Buffer the response before parsing it. Piping curl straight into an
  # early-exiting reader (grep -m1, head -1) closes the pipe while curl still
  # has body left to write, so curl dies with EPIPE (exit 23) and pipefail
  # takes the whole script down before it can print anything useful.
  release_json="$(curl -fsSL --connect-timeout 10 --max-time 30 --retry 2 \
    "https://api.github.com/repos/${REPO}/releases/latest")" \
    || err "could not reach the GitHub releases API (offline, or rate limited?)"
  VERSION="$(printf '%s\n' "$release_json" \
    | awk -F'"' '/"tag_name"/ && !v { v = $4 } END { print v }')"
  [ -n "$VERSION" ] || err "could not determine latest release tag"
fi
info "Installing ${BINARY} ${VERSION} for ${OS}/${ARCH}"

ASSET="${BINARY}-${OS}-${ARCH}"
BASE_URL="https://github.com/${REPO}/releases/download/${VERSION}"

# ---- download into a temp dir ------------------------------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

info "Downloading ${ASSET}..."
# Show progress and give up on a stalled transfer rather than hanging forever.
#   --connect-timeout    cap the TCP/TLS handshake
#   --retry              ride out transient CDN failures
#   --speed-limit/-time  abort if throughput stays under 1 KB/s for 30s, which
#                        is what "stuck at Downloading..." actually looks like
# Note: release assets come from release-assets.githubusercontent.com, a
# different host than api./raw.githubusercontent.com — proxies often allow the
# latter two and silently drop this one.
curl -fL --progress-bar \
  --connect-timeout 15 --retry 3 --retry-delay 2 \
  --speed-limit 1024 --speed-time 30 \
  -o "${TMP}/${BINARY}" "${BASE_URL}/${ASSET}" \
  || err "download failed or stalled: ${BASE_URL}/${ASSET}
       Check that release-assets.githubusercontent.com is reachable (proxy or
       firewall?), or that a build exists for ${OS}/${ARCH} in ${VERSION}."

# ---- verify checksum ---------------------------------------------------------
if curl -fsSL --connect-timeout 10 --max-time 60 --retry 2 \
     -o "${TMP}/checksums.txt" "${BASE_URL}/checksums.txt" 2>/dev/null; then
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
# Prefer a user-writable dir so we never need sudo. Use /usr/local/bin only when
# it's already writable (e.g. Intel Homebrew); otherwise fall back to ~/.local/bin.
if [ -z "${INSTALL_DIR:-}" ]; then
  if [ -w /usr/local/bin ] 2>/dev/null; then
    INSTALL_DIR="/usr/local/bin"
  else
    INSTALL_DIR="${HOME}/.local/bin"
  fi
fi
mkdir -p "$INSTALL_DIR"

info "Installing to ${INSTALL_DIR}/${BINARY}"
mv "${TMP}/${BINARY}" "${INSTALL_DIR}/${BINARY}"

# ---- make the binary reachable ----------------------------------------------
# kubectl resolves the plugin by bare name from PATH, so an install that isn't
# on PATH looks to the user like a broken cluster, not a broken install. Fix
# PATH for them instead of printing instructions and hoping they run them.
PATH_RC=""        # rc file we appended to, if any
NEED_FISH_PATH=0  # fish uses different syntax; ask the user instead

if ! echo ":$PATH:" | grep -q ":${INSTALL_DIR}:"; then
  PATH_LINE="export PATH=\"${INSTALL_DIR}:\$PATH\""
  case "$(basename "${SHELL:-bash}")" in
    zsh)  PATH_RC="${ZDOTDIR:-$HOME}/.zshrc" ;;   # macOS default
    bash) PATH_RC="${HOME}/.bashrc" ;;
    fish) NEED_FISH_PATH=1 ;;
    *)    PATH_RC="${HOME}/.profile" ;;
  esac

  if [ -n "$PATH_RC" ]; then
    # Idempotent: re-running the installer must not stack duplicate lines.
    if [ -f "$PATH_RC" ] && grep -qF "$PATH_LINE" "$PATH_RC"; then
      :
    else
      printf '\n# Added by the AceCloud kubectl auth plugin installer\n%s\n' \
        "$PATH_LINE" >> "$PATH_RC"
    fi
  fi

  # True for the rest of this script, so the check below is meaningful.
  PATH="${INSTALL_DIR}:$PATH"
  export PATH
fi

# ---- prove it works before claiming success ---------------------------------
command -v "$BINARY" >/dev/null 2>&1 \
  || err "installed ${INSTALL_DIR}/${BINARY} but it is not runnable from PATH — please contact AceCloud support"

ok "Installed ${BINARY} ${VERSION} to ${INSTALL_DIR}/${BINARY}"

cat <<'EOF'

Next steps:
  1. Download your kubeconfig from the AceCloud portal.
  2. export KUBECONFIG=/path/to/your-kubeconfig.yaml
  3. kubectl get pods   # the plugin refreshes your token automatically
EOF

# ACTION REQUIRED goes LAST. Whatever prints after a warning is what the user
# actually reads, and a curl|bash user only ever sees the tail of the output.
if [ -n "$PATH_RC" ]; then
  printf '\n\033[1;33m=====================================================================\033[0m\n'
  printf '\033[1;33m  ACTION REQUIRED - kubectl cannot find the plugin until you do this\033[0m\n'
  printf '\033[1;33m=====================================================================\033[0m\n\n'
  printf '  %s was not on your PATH, so we added it to:\n\n' "$INSTALL_DIR"
  printf '      %s\n\n' "$PATH_RC"
  printf '  \033[1mThat only affects NEW terminals. To use kubectl in THIS one, run:\033[0m\n\n'
  printf '      \033[1;32msource %s\033[0m\n\n' "$PATH_RC"
  printf '  Skip this and every kubectl command fails with:\n'
  printf '      exec: executable %s not found\n' "$BINARY"
  printf '  That is an install issue, not a cluster issue.\n'
  printf '\033[1;33m=====================================================================\033[0m\n'
elif [ "$NEED_FISH_PATH" = "1" ]; then
  printf '\n\033[1;33m=====================================================================\033[0m\n'
  printf '\033[1;33m  ACTION REQUIRED - add the plugin to your PATH\033[0m\n'
  printf '\033[1;33m=====================================================================\033[0m\n\n'
  printf '      \033[1;32mfish_add_path %s\033[0m\n\n' "$INSTALL_DIR"
  printf '  Until then kubectl fails with: exec: executable %s not found\n' "$BINARY"
  printf '\033[1;33m=====================================================================\033[0m\n'
fi
