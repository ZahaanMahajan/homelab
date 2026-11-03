# NAS Setup

## Overview

A dedicated Debian 13 server provides centralized NFS storage for the Kubernetes homelab.

The NAS runs independently of the Kubernetes cluster and provides persistent storage for application workloads.

## Infrastructure

| Component | Configuration |
|---|---|
| Operating System | Debian 13 (Trixie) |
| Hostname | `nas` |
| IP Address | `192.168.29.100` |
| Storage Protocol | NFS |
| Export Path | `/kubernetes` |
| NFS Version | 4.1 |

## Architecture

```text
       Kubernetes Cluster
               |
               v
          NFS CSI Driver
               |
               v
         NFS Server
        192.168.29.100
               |
               v
        /kubernetes
               |
         Persistent Data
```

## NFS Configuration

The NAS exports the following directory:

```text
/kubernetes
```

The NFS export is configured to allow Kubernetes worker nodes to access persistent storage.

Export configuration is maintained in:

```bash
/etc/exports
```

NFS service management:

```bash
# Check NFS service
sudo systemctl status nfs-server

# Restart NFS service
sudo systemctl restart nfs-server

# Display active exports
sudo exportfs -v

# List available exports
showmount -e 192.168.29.100
```

## Storage Integration

Kubernetes accesses the NAS through the NFS CSI driver.

Dynamic provisioning allows PersistentVolumeClaims to request storage without manually creating individual NFS directories and PersistentVolumes.

See [NFS CSI Integration](Kubernetes-NFS-CSI-Integration.md) for Kubernetes configuration.

---

The NAS operates as an independent storage server, keeping persistent application data separate from Kubernetes workloads.
