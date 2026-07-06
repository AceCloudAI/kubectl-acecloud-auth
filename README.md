# kubectl-acecloud-auth

A [`kubectl` credential plugin](https://kubernetes.io/docs/reference/access-authn-authz/authentication/#client-go-credential-plugins)
for authenticating to AceCloud Kubernetes clusters. It automatically refreshes
your access token you never handle credentials directly.

## Install

**Linux / macOS**

```bash
curl -fsSL https://raw.githubusercontent.com/AceCloudAI/kubectl-acecloud-auth/main/install.sh | bash
```

**Windows (PowerShell)**

```powershell
irm https://raw.githubusercontent.com/AceCloudAI/kubectl-acecloud-auth/main/install.ps1 | iex
```

Then verify:

```bash
kubectl acecloud_auth version
```

### Options

| Variable | Effect |
|---|---|
| `VERSION` | Install a specific release, e.g. `VERSION=v1.2.3 curl ... | bash` |
| `INSTALL_DIR` | Override install location (default `/usr/local/bin`, else `~/.local/bin`) |

## Usage

1. Download your **kubeconfig** from the AceCloud portal.
2. Point kubectl at it and use your cluster normally:

```bash
export KUBECONFIG=/path/to/your-kubeconfig.yaml
kubectl get pods
```

The plugin refreshes your token behind the scenes. If your refresh token has
expired, re-download the kubeconfig from the portal.

## Manual download

Grab a binary for your platform from the [Releases](../../releases) page,
rename it to `kubectl-acecloud_auth` (keep the `.exe` on Windows), make it
executable, and place it on your `PATH`. Verify against `checksums.txt`.

## Uninstall

```bash
rm "$(command -v kubectl-acecloud_auth)"
```
