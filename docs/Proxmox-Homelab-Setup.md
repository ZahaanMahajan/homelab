# Proxmox Homelab Setup

## Overview

Proxmox VE provides the virtualization layer for the homelab, hosting the Talos Linux virtual machines that form the Kubernetes cluster.

The infrastructure runs across two physical Proxmox hosts.

## Architecture

```text
             Proxmox VE
                 |
        +--------+--------+
        |                 |
      Host 01           Host 02
        |                 |
   Control Plane      Worker 01
                      Worker 02
```

## Infrastructure

| Component | Purpose |
|---|---|
| Proxmox VE | Virtualization platform |
| Talos Linux | Kubernetes node operating system |
| Virtual Machines | Kubernetes control plane and workers |
| Terraform | Infrastructure as Code |

## Kubernetes Virtual Machines

| VM | Role | IP Address |
|---|---|---|
| `talos-controlplane-01` | Control Plane | `192.168.29.20` |
| `talos-worker-01` | Worker | `192.168.29.21` |
| `talos-worker-02` | Worker | `192.168.29.22` |

## Terraform

Proxmox infrastructure configuration is maintained under:

```text
proxmox/
```

Terraform manages infrastructure definitions such as:

- Provider configuration
- Virtual machines
- Networking
- Storage
- Variables and outputs

## Management

Proxmox web interface:

```text
https://<proxmox-host-ip>:8006
```

Useful commands:

```bash
# Check Proxmox version
pveversion

# List virtual machines
qm list

# Show VM configuration
qm config <vm-id>

# Check VM status
qm status <vm-id>
```

## Security

- Keep Terraform state and sensitive variable files private.
- Protect Proxmox credentials and API tokens.
- Avoid committing passwords or infrastructure secrets.

---

Proxmox provides the virtualization foundation, while Talos Linux manages the Kubernetes node operating system.
