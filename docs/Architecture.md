# Homelab Architecture

## Overview

A self-hosted Kubernetes platform built on Proxmox VE and Talos Linux, with GitOps-based management through Argo CD.

The infrastructure is organized into four layers:

1. **Infrastructure:** Proxmox VE, Talos Linux and NAS.
2. **Kubernetes:** Cluster networking, load balancing and storage.
3. **Platform:** Argo CD, monitoring and shared services.
4. **Applications:** Self-hosted workloads managed through Helm.

## Architecture Diagram

```text
                         Internet
                            |
                      Cloudflare DNS
                            |
               +------------+------------+
               |                         |
        Cloudflare Tunnel          MetalLB / Gateway
               |                         |
               +------------+------------+
                            |
                   Talos Kubernetes
                       v1.36.2
                            |
          +-----------------+-----------------+
          |                 |                 |
     Control Plane       Worker 01         Worker 02
     192.168.29.20      192.168.29.21     192.168.29.22
          |                 |                 |
          +-----------------+-----------------+
                            |
                +-----------+-----------+
                |                       |
              Argo CD              Platform Services
                |                       |
          +-----+------+          +-----+------+
          |            |          |            |
    Infrastructure Applications Homepage   Monitoring
          |
     +----+------------------+
     |           |           |
   MetalLB   cert-manager   NFS CSI
                            |
                            NAS
```

## Infrastructure

| Component | Technology |
|---|---|
| Virtualization | Proxmox VE |
| Operating System | Talos Linux |
| Container Runtime | containerd |
| Kubernetes | v1.36.2 |
| CNI | Flannel |
| Storage | NFS CSI |

## Cluster Configuration

| Node | Role | IP Address |
|---|---|---|
| `talos-controlplane-01` | Control Plane | `192.168.29.20` |
| `talos-worker-01` | Worker | `192.168.29.21` |
| `talos-worker-02` | Worker | `192.168.29.22` |

The cluster uses a single control plane and is designed for homelab workloads and Kubernetes learning.

## Networking

| Component | Configuration |
|---|---|
| LAN | `192.168.29.0/24` |
| Gateway | `192.168.29.1` |
| Internal DNS | `192.168.29.10` |
| Pod CIDR | `10.244.0.0/16` |
| Service CIDR | `10.96.0.0/12` |
| Kubernetes API | `192.168.29.20:6443` |

### Traffic Flow

- **MetalLB:** Provides external IP allocation for Kubernetes LoadBalancer services.
- **Gateway API:** Handles application traffic routing.
- **cert-manager:** Automates TLS certificate issuance and renewal.
- **Cloudflare:** Provides DNS and external edge services.
- **cloudflared:** Enables tunnel-based access to internal applications.

## GitOps Workflow

Argo CD manages declarative Kubernetes resources stored in Git.

```text
Git Repository
      |
      v
   Argo CD
      |
      v
Kubernetes Resources
      |
      v
Desired Cluster State
```

Changes committed to Git are reconciled by Argo CD.

## Storage Architecture

Persistent application data is stored on an external NAS and accessed through the Kubernetes NFS CSI driver.

```text
Application
     |
     v
PVC
     |
     v
StorageClass
     |
     v
NFS CSI Driver
     |
     v
NAS / NFS Server
```

## Documentation

| Component | Documentation |
|---|---|
| Proxmox VE | [Proxmox Setup](Proxmox-Homelab-Setup.md) |
| NAS | [NAS Setup](NAS-Setup.md) |
| NFS CSI | [NFS CSI Integration](Kubernetes-NFS-CSI-Integration.md) |
| MetalLB | [MetalLB Setup](MetalLB-Setup.md) |
| TLS | [Kubernetes TLS](Kubernetes-TLS.md) |
| Internal DNS | [ Internal DNS](Internal-DNS.md) |

---

*This architecture evolves as new infrastructure and platform services are introduced.*
