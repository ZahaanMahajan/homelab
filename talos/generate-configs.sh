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

if [[ ! -s "${TEMP_SECRETS}" ]]; then
    echo "ERROR: Decrypted Talos secrets file is empty." >&2
    exit 1
fi

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
