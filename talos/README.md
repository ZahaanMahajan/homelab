
homelab on  main [!?] on  (ap-south-1)
❯ sed -n '1,260p' talos/generate-configs.sh
#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

# -----------------------------------------------------------------------------
# Talos configuration generation
#
# Generates reproducible Talos configuration artifacts from:
#   - SOPS-encrypted cluster secrets
#   - version/install parameters defined below
#   - tracked Talos patches
#
# Generated files:
#   talos/controlplane.yaml
#   talos/worker.yaml
#   talos/talosconfig
#
# Worker-specific node configuration is produced by combining worker.yaml with
# the appropriate worker-specific patches when provisioning each worker.
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

CLUSTER_NAME="homelab"
CLUSTER_ENDPOINT="https://192.168.29.20:6443"

TALOS_VERSION="v1.13.8"
KUBERNETES_VERSION="1.36.2"

INSTALL_DISK="/dev/sda"
INSTALL_IMAGE="ghcr.io/siderolabs/installer:v1.13.8"

SECRETS_FILE="${SCRIPT_DIR}/secrets/secrets.yaml"
PATCH_DIR="${SCRIPT_DIR}/patches"

OUTPUT_DIR="${SCRIPT_DIR}"

TEMP_SECRETS="$(mktemp)"
trap 'rm -f "${TEMP_SECRETS}"' EXIT

cd "${REPO_ROOT}"

echo "==> Checking prerequisites"

command -v talosctl >/dev/null 2>&1 || {
    echo "ERROR: talosctl is not installed or not in PATH." >&2
    exit 1
}

command -v sops >/dev/null 2>&1 || {
    echo "ERROR: sops is not installed or not in PATH." >&2
    exit 1
}

if [[ -z "${SOPS_AGE_KEY_FILE:-}" ]]; then
    echo "ERROR: SOPS_AGE_KEY_FILE is not set." >&2
    exit 1
fi

if [[ ! -f "${SOPS_AGE_KEY_FILE}" ]]; then
    echo "ERROR: SOPS age key file does not exist:" >&2
    echo "       ${SOPS_AGE_KEY_FILE}" >&2
    exit 1
fi

if [[ ! -f "${SECRETS_FILE}" ]]; then
    echo "ERROR: Talos secrets file does not exist:" >&2
    echo "       ${SECRETS_FILE}" >&2
    exit 1
fi

echo "==> Checking required Talos patches"

required_patches=(
    "endpoint-patch.yaml"
    "controlplane-static-ip.yaml"
    "hostname-controlplane.yaml"
    "apiserver-certsan.yaml"
    "worker1-static-ip.yaml"
    "hostname-worker1.yaml"
    "worker2-static-ip.yaml"
    "hostname-worker2.yaml"
)

for patch in "${required_patches[@]}"; do
    if [[ ! -f "${PATCH_DIR}/${patch}" ]]; then
        echo "ERROR: Required patch is missing:" >&2
        echo "       ${PATCH_DIR}/${patch}" >&2
        exit 1
    fi
done

echo "==> Decrypting Talos secrets temporarily"

sops --decrypt "${SECRETS_FILE}" > "${TEMP_SECRETS}"
chmod 600 "${TEMP_SECRETS}"

echo "==> Removing previous generated configuration"

rm -f \
    "${OUTPUT_DIR}/controlplane.yaml" \
    "${OUTPUT_DIR}/worker.yaml" \
    "${OUTPUT_DIR}/talosconfig"

echo "==> Generating Talos configuration"

talosctl gen config "${CLUSTER_NAME}" "${CLUSTER_ENDPOINT}" \
    --talos-version "${TALOS_VERSION}" \
    --kubernetes-version "${KUBERNETES_VERSION}" \
    --install-disk "${INSTALL_DISK}" \
    --install-image "${INSTALL_IMAGE}" \
    --with-secrets "${TEMP_SECRETS}" \
    --config-patch "@${PATCH_DIR}/endpoint-patch.yaml" \
    --config-patch-control-plane "@${PATCH_DIR}/controlplane-static-ip.yaml" \
    --config-patch-control-plane "@${PATCH_DIR}/hostname-controlplane.yaml" \
    --config-patch-control-plane "@${PATCH_DIR}/apiserver-certsan.yaml" \
    --output "${OUTPUT_DIR}"

echo
echo "==> Generated configuration successfully"
echo
echo "Generated files:"
echo "  ${OUTPUT_DIR}/controlplane.yaml"
echo "  ${OUTPUT_DIR}/worker.yaml"
echo "  ${OUTPUT_DIR}/talosconfig"
echo
echo "Cluster:"
echo "  Name:     ${CLUSTER_NAME}"
echo "  Endpoint: ${CLUSTER_ENDPOINT}"
echo
echo "Versions:"
echo "  Talos:       ${TALOS_VERSION}"
echo "  Kubernetes:  ${KUBERNETES_VERSION}"
echo
echo "Install:"
echo "  Disk:  ${INSTALL_DISK}"
echo "  Image: ${INSTALL_IMAGE}"
echo
echo "Worker-specific patches remain separate:"
echo "  Worker 01:"
echo "    ${PATCH_DIR}/worker1-static-ip.yaml"
echo "    ${PATCH_DIR}/hostname-worker1.yaml"
echo
echo "  Worker 02:"
echo "    ${PATCH_DIR}/worker2-static-ip.yaml"
echo "    ${PATCH_DIR}/hostname-worker2.yaml"
echo
echo "The decrypted Talos secrets have been removed."

homelab on  main [!?] on  (ap-south-1)
❯ sed -n '1,320p' talos/README.md
# Talos Linux Configuration

This directory contains the declarative configuration required to reproduce the Talos Linux Kubernetes cluster used by the Homelab project.

The configuration separates:

* reusable Talos patches
* encrypted cluster secrets
* generated machine configurations
* cluster deployment procedures

Generated Talos configurations contain credential-bearing material and are intentionally excluded from Git.

---

## Cluster

| Property           | Value                        |
| ------------------ | ---------------------------- |
| Cluster name       | `homelab`                    |
| Talos Linux        | `v1.13.8`                    |
| Kubernetes         | `v1.36.2`                    |
| Control plane      | `192.168.29.20`              |
| Worker 01          | `192.168.29.21`              |
| Worker 02          | `192.168.29.22`              |
| Kubernetes API     | `https://192.168.29.20:6443` |
| Pod CIDR           | `10.244.0.0/16`              |
| Service CIDR       | `10.96.0.0/12`               |
| Cluster DNS domain | `cluster.local`              |
| Network interface  | `ens18`                      |
| Default gateway    | `192.168.29.1`               |
| Install disk       | `/dev/sda`                   |

---

## Directory Structure

```text
talos/
├── README.md
├── generate-configs.sh
│
├── patches/
│   ├── apiserver-certsan.yaml
│   ├── controlplane-static-ip.yaml
│   ├── endpoint-patch.yaml
│   ├── hostname-controlplane.yaml
│   ├── hostname-worker1.yaml
│   ├── hostname-worker2.yaml
│   ├── worker1-static-ip.yaml
│   └── worker2-static-ip.yaml
│
├── secrets/
│   └── secrets.yaml
│
├── controlplane.yaml
├── worker.yaml
└── talosconfig
```

### Tracked

The following are safe and intended to be committed:

```text
talos/README.md
talos/generate-configs.sh
talos/patches/*
talos/secrets/secrets.yaml
```

`talos/secrets/secrets.yaml` is encrypted using SOPS and age.

### Ignored

The following files are generated locally and must not be committed:

```text
talos/controlplane.yaml
talos/worker.yaml
talos/talosconfig
```

---

# Secrets Management

The cluster's Talos secret bundle is stored as:

```text
talos/secrets/secrets.yaml
```

The file is encrypted using:

* SOPS
* age

The age private key is stored outside the repository:

```text
~/.config/sops/age/keys.txt
```

The private key must never be committed.

The repository only contains the encrypted secret bundle and the public age recipient in:

```text
.sops.yaml
```

---

# Prerequisites

The following tools must be available:

```bash
talosctl
sops
age
```

The SOPS age key must be available locally:

```bash
export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
```

Verify:

```bash
talosctl version
sops --version
age --version
```

---

# Generate Talos Configurations

The complete generation process is handled by:

```bash
./talos/generate-configs.sh
```

The script:

1. validates required tools and files
2. decrypts the SOPS secret bundle into a temporary file
3. generates the Talos control-plane configuration
4. generates the reusable worker configuration
5. generates `talosconfig`
6. removes the temporary plaintext secret bundle

The decrypted secret bundle is never written into the repository.

After generation:

```text
talos/controlplane.yaml
talos/worker.yaml
talos/talosconfig
```

are available locally.

---

# Configuration Patches

## Control Plane

The control-plane configuration uses:

```text
controlplane-static-ip.yaml
hostname-controlplane.yaml
endpoint-patch.yaml
apiserver-certsan.yaml
```

This produces:

```text
IP:       192.168.29.20/24
Hostname: talos-controlplane-01
Gateway:  192.168.29.1
Endpoint: https://192.168.29.20:6443
API SAN:  192.168.29.20
```

---

## Worker 01

Worker 01 uses:

```text
endpoint-patch.yaml
worker1-static-ip.yaml
hostname-worker1.yaml
```

Result:

```text
IP:       192.168.29.21/24
Hostname: talos-worker-01
Gateway:  192.168.29.1
Endpoint: https://192.168.29.20:6443
```

---

## Worker 02

Worker 02 uses:

```text
endpoint-patch.yaml
worker2-static-ip.yaml
hostname-worker2.yaml
```

Result:

```text
IP:       192.168.29.22/24
Hostname: talos-worker-02
Gateway:  192.168.29.1
Endpoint: https://192.168.29.20:6443
```

The generic:

```text
talos/worker.yaml
```

is the reusable worker configuration.

Worker-specific configuration is produced by applying the appropriate worker patches to that base configuration.

---

# Generated Talos Features

The generated configuration currently reproduces the following live Talos settings.

## Kubelet

```text
Kubernetes version: v1.36.2
Default runtime Seccomp profile: enabled
Manifests directory: disabled
```

## KubePrism

```text
Enabled: true
Port:    7445
```

## Host DNS

```text
Enabled:               true
Forward Kubernetes DNS: true
```

## Disk Quota

```text
diskQuotaSupport: true
```

## Control Plane Node Label

The control plane includes:

```text
node.kubernetes.io/exclude-from-external-load-balancers: ""
```

These settings are already reproduced by the Talos configuration generation process and therefore do not require additional custom patches.

---

# Fresh Talos Node Installation

The following procedure applies when provisioning a new Talos node.

The Proxmox layer must already have created the VM.

The Talos configuration layer then provides the machine configuration.

## Control Plane

For a fresh control-plane node, apply:

```bash
talosctl apply-config \
  --insecure \
  --nodes 192.168.29.20 \
  --file talos/controlplane.yaml
```

The exact node IP used with `--insecure` depends on the temporary network address available during initial Talos provisioning.

After the node has the intended configuration, verify:

```bash
talosctl get machineconfig -n 192.168.29.20
```

---

homelab on  main [!?] on  (ap-south-1)
❯

