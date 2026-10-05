# Talos Linux

This directory contains the **Talos Linux machine configuration and
bootstrap artifacts** used to build the Kubernetes nodes in the homelab.

Talos is the operating-system layer between the Proxmox virtual machines
and Kubernetes:

``` text
┌──────────────────────────────────────────────┐
│                  Homelab                     │
├──────────────────────────────────────────────┤
│                                              │
│  OpenTofu / Proxmox                          │
│          │                                   │
│          ▼                                   │
│      Proxmox VMs                             │
│          │                                   │
│          ▼                                   │
│     Talos Linux                              │
│          │                                   │
│          ▼                                   │
│     Kubernetes                               │
│          │                                   │
│    ┌─────┴─────┐                             │
│    │           │                             │
│ Control Plane  Workers                        │
│                                              │
└──────────────────────────────────────────────┘
```

The Talos layer is intentionally kept separate from:

-   Proxmox VM provisioning
-   Kubernetes application manifests
-   Argo CD GitOps configuration
-   Kubernetes infrastructure services

------------------------------------------------------------------------

# 1. Directory Overview

The current directory contains:

``` text
talos/
├── controlplane.yaml
├── generate-configs.sh
├── patches
│   ├── apiserver-certsan.yaml
│   ├── controlplane-static-ip.yaml
│   ├── endpoint-patch.yaml
│   ├── hostname-controlplane.yaml
│   ├── hostname-worker1.yaml
│   ├── hostname-worker2.yaml
│   ├── hostname-worker3.yaml
│   ├── worker1-static-ip.yaml
│   ├── worker2-static-ip.yaml
│   ├── worker3-disk.yaml
│   ├── worker3-network.yaml
│   └── worker3-static-ip.yaml
├── README.md
├── secrets
│   └── secrets.yaml
├── talosconfig
└── worker.yaml
```

The directory can be understood as four major components:

``` text
talos/
│
├── Base machine configuration
│   ├── controlplane.yaml
│   └── worker.yaml
│
├── Configuration generation
│   └── generate-configs.sh
│
├── Machine-specific patches
│   └── patches/
│
└── Cluster/bootstrap credentials
    ├── secrets/
    │   └── secrets.yaml
    └── talosconfig
```

------------------------------------------------------------------------

# 2. Current Talos Cluster

The homelab Kubernetes cluster is built on Talos Linux.

Current cluster information:

  Component           Version
  ------------------- --------------------
  Talos Linux         `v1.13.8`
  Kubernetes          `v1.36.2`
  Container runtime   `containerd 2.2.6`
  CNI                 Flannel
  Pod CIDR            `10.244.0.0/16`
  Service CIDR        `10.96.0.0/12`

The current active node layout is:

  Node                      Role            IP
  ------------------------- --------------- -----------------
  `talos-controlplane-01`   Control plane   `192.168.29.20`
  `talos-worker-01`         Worker          `192.168.29.21`
  `talos-worker-02`         Worker          `192.168.29.22`

The repository also contains configuration patches for a third worker:

``` text
talos-worker-03
```

However, the existence of `worker3-*` patches in the repository should
not be interpreted as proof that worker 03 is currently running.

The repository describes configuration for it, while the live cluster
state must be checked separately.

------------------------------------------------------------------------

# 3. Talos Architecture

Talos is responsible for the operating-system and node-management layer.

``` text
                    Proxmox
                       │
             ┌─────────┼─────────┐
             │         │         │
             ▼         ▼         ▼
        Control      Worker 01  Worker 02
          VM           VM         VM
             │         │         │
             └─────────┼─────────┘
                       │
                  Talos Linux
                       │
                       ▼
                  Kubernetes
```

The responsibilities are separated as follows:

  Layer        Responsibility
  ------------ -------------------------------------------
  OpenTofu     Defines Proxmox VM infrastructure
  Proxmox      Runs the virtual machines
  Talos        Provides the immutable Kubernetes node OS
  Kubernetes   Runs the cluster
  Argo CD      Reconciles Kubernetes workloads
  Helm         Packages applications

------------------------------------------------------------------------

# 4. Why Talos?

Talos is designed specifically for Kubernetes nodes.

The homelab uses Talos to keep the operating-system layer minimal and
Kubernetes-focused.

The important architectural distinction is:

``` text
Traditional Linux VM
    │
    ├── Linux userspace
    ├── SSH
    ├── systemd
    ├── package manager
    ├── manually installed container runtime
    └── Kubernetes
```

versus:

``` text
Talos
    │
    ├── Immutable/minimal OS
    ├── Machine API
    ├── Kubernetes components
    └── Kubernetes
```

Talos nodes are administered through Talos tooling and APIs rather than
through the normal SSH/package-management workflow used by a
general-purpose Linux distribution.

This is especially useful in the homelab because the Kubernetes node
configuration remains declarative and reproducible.

------------------------------------------------------------------------

# 5. Base Machine Configurations

The repository contains two primary base configurations:

``` text
controlplane.yaml
worker.yaml
```

These represent the two Talos machine roles.

## Control Plane

``` text
controlplane.yaml
       │
       ├── Kubernetes control-plane configuration
       ├── Machine configuration
       └── Common Talos settings
```

The control-plane configuration is the base configuration from which the
control-plane node configuration is generated.

## Worker

``` text
worker.yaml
       │
       ├── Kubernetes worker configuration
       ├── Machine configuration
       └── Common Talos settings
```

The worker configuration provides the base for worker nodes.

Machine-specific differences are handled through patches.

------------------------------------------------------------------------

# 6. Configuration Patches

The `patches/` directory contains machine-specific configuration.

``` text
patches/
├── apiserver-certsan.yaml
├── controlplane-static-ip.yaml
├── endpoint-patch.yaml
├── hostname-controlplane.yaml
├── hostname-worker1.yaml
├── hostname-worker2.yaml
├── hostname-worker3.yaml
├── worker1-static-ip.yaml
├── worker2-static-ip.yaml
├── worker3-disk.yaml
├── worker3-network.yaml
└── worker3-static-ip.yaml
```

The patch-based approach avoids maintaining a completely independent
machine configuration file for every node.

Conceptually:

``` text
                 Base configuration
                       │
             ┌─────────┴─────────┐
             │                   │
       controlplane.yaml      worker.yaml
             │                   │
             │             ┌─────┼─────────────┐
             │             │     │             │
             ▼             ▼     ▼             ▼
       Control-plane    Worker1 Worker2     Worker3
             │             │     │             │
             ▼             ▼     ▼             ▼
          patches        patches patches      patches
```

This makes common configuration easier to maintain while still allowing
individual machines to have different:

-   hostnames
-   IP addresses
-   network configuration
-   disks
-   control-plane settings
-   API endpoint configuration

------------------------------------------------------------------------

# 7. Patch Responsibilities

The filenames make the intended purpose of the patches explicit.

## API Server Certificate SAN

``` text
patches/apiserver-certsan.yaml
```

This patch is associated with additional API-server certificate Subject
Alternative Name configuration.

This is important when the Kubernetes API server must be reachable
through addresses or names beyond the default generated values.

------------------------------------------------------------------------

## Control-Plane Static IP

``` text
patches/controlplane-static-ip.yaml
```

This patch provides static network configuration for the control-plane
node.

The current control-plane node uses:

``` text
192.168.29.20
```

------------------------------------------------------------------------

## Worker Static IPs

``` text
patches/worker1-static-ip.yaml
patches/worker2-static-ip.yaml
patches/worker3-static-ip.yaml
```

These provide machine-specific static networking for the workers.

Current active worker addresses are:

``` text
worker-01 → 192.168.29.21
worker-02 → 192.168.29.22
```

The repository also contains configuration for worker 03.

------------------------------------------------------------------------

## Hostname Patches

``` text
patches/hostname-controlplane.yaml
patches/hostname-worker1.yaml
patches/hostname-worker2.yaml
patches/hostname-worker3.yaml
```

These provide machine-specific hostnames.

The current cluster naming convention is:

``` text
talos-controlplane-01
talos-worker-01
talos-worker-02
```

The worker 03 hostname patch is retained for the additional worker
configuration.

------------------------------------------------------------------------

## Kubernetes Endpoint Patch

``` text
patches/endpoint-patch.yaml
```

This patch is associated with the Kubernetes control-plane endpoint
configuration.

The endpoint configuration is important because Kubernetes components
need a stable API-server endpoint during cluster bootstrap and normal
operation.

------------------------------------------------------------------------

## Worker 03 Disk

``` text
patches/worker3-disk.yaml
```

This patch provides worker-03-specific disk configuration.

It exists because disk configuration can differ between Talos machines.

------------------------------------------------------------------------

## Worker 03 Network

``` text
patches/worker3-network.yaml
```

This patch provides worker-03-specific network configuration.

The separate network patch allows worker 03 to have configuration that
differs from the first two workers without modifying the common worker
configuration.

------------------------------------------------------------------------

# 8. Configuration Generation

The repository contains:

``` text
generate-configs.sh
```

This script is the configuration-generation entry point for the Talos
setup.

The intended workflow is:

``` text
Base configs
     │
     ├── controlplane.yaml
     └── worker.yaml
           │
           ▼
      generate-configs.sh
           │
           ├── machine-specific patches
           │
           ▼
      generated Talos configs
           │
           ▼
       Talos machines
```

The exact commands implemented by the script should be treated as the
source of truth for the generation process.

Before modifying the script, inspect its current contents and preserve
the existing patch ordering and command-line arguments.

------------------------------------------------------------------------

# 9. Talos Secrets

The directory contains:

``` text
secrets/
└── secrets.yaml
```

Talos secrets are cluster bootstrap material and must be treated as
sensitive.

They should **not** be considered ordinary configuration.

Conceptually:

``` text
Talos configuration
       +
Talos secrets
       │
       ▼
Machine configuration
       │
       ▼
Talos cluster
```

The secrets file can contain credentials/material required to
authenticate or bootstrap the Talos cluster.

Do not publish its contents.

------------------------------------------------------------------------

# 10. Talosconfig

The repository also contains:

``` text
talosconfig
```

`talosconfig` is used by Talos tooling to authenticate to and
communicate with Talos machines.

It should be treated as sensitive infrastructure configuration.

A useful distinction is:

``` text
talosconfig
    │
    └── Talos API administration

kubeconfig
    │
    └── Kubernetes API administration
```

They serve different management planes.

------------------------------------------------------------------------

# 11. Talos API vs Kubernetes API

There are two separate APIs in the environment.

``` text
                    Administrator
                         │
             ┌───────────┴───────────┐
             │                       │
        Talos tooling             kubectl
             │                       │
             ▼                       ▼
        Talos API              Kubernetes API
             │                       │
             ▼                       ▼
       Talos machine             Kubernetes
       configuration             resources
```

Talos API operations are concerned with the node itself.

Kubernetes API operations are concerned with cluster resources.

Examples:

``` text
Talos:
- machine configuration
- node-level Talos state
- Talos services
- machine health

Kubernetes:
- Pods
- Deployments
- Services
- ConfigMaps
- Secrets
- PVCs
- Nodes
```

This separation is fundamental when troubleshooting the cluster.

------------------------------------------------------------------------

# 12. Cluster Bootstrap

The Talos cluster follows a layered bootstrap process.

``` text
1. Proxmox VM exists
        │
        ▼
2. Talos boots
        │
        ▼
3. Machine configuration applied
        │
        ▼
4. Control plane initialized
        │
        ▼
5. Worker nodes configured
        │
        ▼
6. Kubernetes cluster becomes available
        │
        ▼
7. kubectl access
        │
        ▼
8. Kubernetes infrastructure installed
```

The bootstrap process should not be confused with the later GitOps
deployment process.

Argo CD operates at the Kubernetes layer after the Kubernetes cluster is
available.

------------------------------------------------------------------------

# 13. Node Roles

## Control Plane

The control-plane node hosts the Kubernetes control-plane components.

Current node:

``` text
talos-controlplane-01
192.168.29.20
```

Its Proxmox VM is:

``` text
control-plane
VM ID: 101
```

The Proxmox VM definition is maintained under:

``` text
proxmox/vms.tf
```

------------------------------------------------------------------------

## Workers

Current worker nodes:

``` text
talos-worker-01
192.168.29.21
```

and:

``` text
talos-worker-02
192.168.29.22
```

Their corresponding Proxmox VMs are:

``` text
worker-01
VM ID: 102
```

and:

``` text
worker-02
VM ID: 103
```

The VM layer and Talos layer intentionally use separate
naming/configuration files.

------------------------------------------------------------------------

# 14. Kubernetes Networking

The cluster currently uses Flannel as its CNI.

``` text
CNI:
Flannel
```

The cluster network ranges are:

``` text
Pod CIDR:
10.244.0.0/16

Service CIDR:
10.96.0.0/12
```

Conceptually:

``` text
Kubernetes Cluster
│
├── Node Network
│
├── Pod Network
│      └── 10.244.0.0/16
│
└── Service Network
       └── 10.96.0.0/12
```

These CIDRs are Kubernetes-level configuration and are distinct from the
physical homelab LAN:

``` text
Physical LAN:
192.168.29.0/24
```

------------------------------------------------------------------------

# 15. Physical and Kubernetes Networks

The homelab has multiple network layers.

``` text
                    Home LAN
                 192.168.29.0/24
                         │
                 ┌───────┴───────┐
                 │               │
              Proxmox        Other LAN
                 │
                 ▼
             Talos nodes
                 │
        ┌────────┴────────┐
        │                 │
    Pod network       Service network
    10.244.0.0/16     10.96.0.0/12
```

This distinction matters during troubleshooting.

For example:

-   `192.168.29.x` → physical/LAN node addresses
-   `10.244.x.x` → Pod addresses
-   `10.96.x.x` → Kubernetes Service addresses

------------------------------------------------------------------------

# 16. Talos and Proxmox Relationship

The Proxmox and Talos configurations deliberately have different
responsibilities.

``` text
proxmox/
    │
    └── Defines VM
            │
            ▼
        Proxmox VM
            │
            ▼
        Talos Linux
            │
            ├── Machine configuration
            └── Kubernetes node
```

For example:

``` text
proxmox/vms.tf

resource:
    control-plane
        │
        ▼
Talos:
    controlplane.yaml
        +
    control-plane patches
        │
        ▼
Kubernetes:
    talos-controlplane-01
```

This means changing CPU or RAM belongs to the Proxmox layer, while
changing a Talos hostname or machine configuration belongs to the Talos
layer.

------------------------------------------------------------------------

# 17. Configuration Lifecycle

The intended lifecycle is:

``` text
                    Git
                     │
             ┌───────┴────────┐
             │                │
        Proxmox config     Talos config
             │                │
             ▼                ▼
          OpenTofu       Machine patches
             │                │
             ▼                ▼
         Proxmox VM       Talos machine
             │                │
             └───────┬────────┘
                     ▼
                Kubernetes
                     │
                     ▼
                  Argo CD
                     │
                     ▼
              Applications
```

Each layer should be changed using its own tooling.

------------------------------------------------------------------------

# 18. Common Talos Tooling

The primary tools used with Talos are:

``` bash
talosctl
kubectl
```

`talosctl` communicates with the Talos API.

`kubectl` communicates with Kubernetes.

Examples of the conceptual workflow:

``` bash
talosctl version
talosctl get members
talosctl get machinestatus
```

For Kubernetes:

``` bash
kubectl get nodes
kubectl get pods -A
kubectl cluster-info
```

The exact command and target syntax should follow the installed
Talos/Kubernetes versions and the current `talosconfig`/kubeconfig.

------------------------------------------------------------------------

# 19. Checking the Cluster

A basic Kubernetes health check:

``` bash
kubectl get nodes -o wide
```

Expected active nodes:

``` text
talos-controlplane-01
talos-worker-01
talos-worker-02
```

Check all system workloads:

``` bash
kubectl get pods -A
```

Check cluster information:

``` bash
kubectl cluster-info
```

For Talos-level troubleshooting, use `talosctl` against the affected
machine.

------------------------------------------------------------------------

# 20. Troubleshooting Methodology

When something breaks, determine which layer is failing before changing
configuration.

Use this model:

``` text
Physical network
      │
      ▼
Proxmox
      │
      ▼
VM
      │
      ▼
Talos
      │
      ▼
Kubernetes node
      │
      ▼
Kubernetes control plane
      │
      ▼
CNI / Services / Storage
      │
      ▼
Applications
```

For example:

### VM unavailable

Start at:

``` text
Proxmox
```

### VM is running but Talos is unreachable

Investigate:

``` text
VM network
    ↓
Talos network configuration
    ↓
Talos API
```

### Talos is healthy but Kubernetes node is NotReady

Investigate:

``` text
Talos
    ↓
kubelet / Kubernetes services
    ↓
CNI
    ↓
Kubernetes node conditions
```

### Kubernetes nodes are healthy but applications cannot communicate

Investigate:

``` text
CNI
Services
Gateway / Ingress
NetworkPolicy
Application configuration
```

This layered approach prevents troubleshooting the wrong component.

------------------------------------------------------------------------

# 21. Static IP Design

The repository uses machine-specific static-IP patches.

``` text
Control plane
    └── 192.168.29.20

Worker 01
    └── 192.168.29.21

Worker 02
    └── 192.168.29.22
```

The static IP configuration is part of Talos machine configuration
rather than being inferred from Kubernetes.

This gives the cluster stable node addresses on the homelab LAN.

------------------------------------------------------------------------

# 22. Hostname Design

The Talos hostname patches establish predictable machine names.

``` text
talos-controlplane-01
talos-worker-01
talos-worker-02
talos-worker-03
```

The worker 03 configuration is present in Git even if the node is not
currently part of the active cluster.

Keeping the naming scheme consistent makes:

-   node identification
-   troubleshooting
-   documentation
-   monitoring
-   automation

easier.

------------------------------------------------------------------------

# 23. Security Considerations

The following files should be considered sensitive:

``` text
talos/secrets/secrets.yaml
talos/talosconfig
```

Generated machine configuration may also contain sensitive material
depending on how it was generated and what is embedded in it.

Before publishing the repository, inspect Git tracking:

``` bash
git status
git ls-files talos/secrets/secrets.yaml
git ls-files talos/talosconfig
git ls-files talos/controlplane.yaml
git ls-files talos/worker.yaml
```

Also inspect the Git history if sensitive files were previously
committed.

Do not assume that adding a file to `.gitignore` removes secrets from
existing Git history.

If secrets have already been committed, they may require:

1.  removal from the repository
2.  history rewriting where appropriate
3.  credential/secret rotation
4.  regeneration of affected configuration

------------------------------------------------------------------------

# 24. What Should Be Version Controlled?

The intended repository model is:

``` text
Version control:
    ├── Base Talos configuration
    ├── Machine patches
    ├── Configuration-generation scripts
    └── Documentation

Sensitive / generated material:
    ├── Talos secrets
    ├── Talos administrative configuration
    └── Generated artifacts containing credentials
```

The exact treatment of generated files depends on the workflow used by
this repository.

Before making the repository public, explicitly review every file under:

``` text
talos/
```

rather than relying only on filename conventions.

------------------------------------------------------------------------

# 25. Making a Talos Configuration Change

A safe change workflow is:

``` text
1. Identify the layer
        │
        ▼
2. Determine whether change belongs
   in base config or patch
        │
        ▼
3. Modify configuration
        │
        ▼
4. Generate/re-render machine config
        │
        ▼
5. Review generated configuration
        │
        ▼
6. Apply through Talos tooling
        │
        ▼
7. Verify Talos machine health
        │
        ▼
8. Verify Kubernetes node health
```

Avoid editing generated configuration manually when the source should
instead be changed in the base file or patch.

------------------------------------------------------------------------

# 26. Base Configuration vs Patch

Use the base configuration when a setting should apply to an entire
machine role.

For example:

``` text
worker.yaml
    │
    ├── common worker settings
    └── common Kubernetes worker configuration
```

Use a patch when a setting is machine-specific:

``` text
worker.yaml
    +
worker1-static-ip.yaml
    +
hostname-worker1.yaml
        │
        ▼
    worker-01 config
```

This provides a clean separation between:

``` text
Common configuration
```

and:

``` text
Machine-specific configuration
```

------------------------------------------------------------------------

# 27. Worker 03 Configuration

The repository contains dedicated worker 03 patches:

``` text
hostname-worker3.yaml
worker3-static-ip.yaml
worker3-disk.yaml
worker3-network.yaml
```

This indicates that worker 03 has additional machine-specific
requirements compared with workers 01 and 02.

The configuration should therefore be treated as a prepared/optional
node configuration unless the live cluster confirms that worker 03 has
been provisioned.

Do not infer live cluster membership solely from repository files.

------------------------------------------------------------------------

# 28. Relationship to Kubernetes GitOps

Talos is below Kubernetes in the architecture.

Argo CD operates after Kubernetes is available:

``` text
Proxmox
   │
   ▼
Talos
   │
   ▼
Kubernetes
   │
   ▼
Argo CD
   │
   ├── Infrastructure
   ├── Platform
   └── Applications
```

Talos should therefore not contain Kubernetes application manifests such
as:

``` text
Deployment
Service
Ingress
Gateway
HTTPRoute
ConfigMap
PVC
```

Those belong to:

``` text
kubernetes/
```

The Talos directory should remain focused on machine and cluster
bootstrap configuration.

------------------------------------------------------------------------

# 29. Operational Boundaries

## Proxmox

Responsible for:

``` text
VMs
CPU
RAM
Virtual disks
Network devices
VM placement
Physical disk attachment
```

## Talos

Responsible for:

``` text
Node OS
Machine configuration
Node networking
Kubernetes node bootstrap
Talos API
Machine lifecycle
```

## Kubernetes

Responsible for:

``` text
Pods
Nodes
Deployments
Services
Storage
Networking
RBAC
Workloads
```

## Argo CD

Responsible for:

``` text
GitOps reconciliation
Application synchronization
Desired-state management
```

Keeping these boundaries clear is important for maintainability.

------------------------------------------------------------------------

# 30. Recovery Model

The Talos layer should be recoverable from:

``` text
Git repository
    │
    ├── Base machine configs
    ├── Machine patches
    └── Generation script
```

combined with the required sensitive bootstrap material.

The recovery chain is:

``` text
Proxmox
   │
   ▼
VM
   │
   ▼
Talos configuration
   │
   ▼
Kubernetes bootstrap
   │
   ▼
Kubernetes cluster
   │
   ▼
Argo CD
   │
   ▼
Applications
```

This layered recovery model is one of the major reasons for keeping the
Talos configuration separate from Kubernetes application configuration.

------------------------------------------------------------------------

# 31. Validation Checklist

After provisioning or modifying Talos nodes, validate the following.

## Proxmox

``` bash
# Verify the VM exists and is running
```

The VM should have the expected:

-   CPU
-   memory
-   disk
-   network device
-   node placement

## Talos

Verify:

``` text
Talos API reachable
Machine configuration applied
Expected hostname
Expected IP address
Machine healthy
```

## Kubernetes

Run:

``` bash
kubectl get nodes -o wide
```

Verify that expected nodes are:

``` text
Ready
```

Then:

``` bash
kubectl get pods -A
```

Verify that cluster-system workloads are healthy.

------------------------------------------------------------------------

# 32. Current Talos State

The repository currently represents the following architecture:

``` text
                 Proxmox
                    │
       ┌────────────┼────────────┐
       │            │            │
       ▼            ▼            ▼
   Control       Worker 01    Worker 02
   Plane VM         VM           VM
       │            │            │
       ▼            ▼            ▼
    Talos         Talos        Talos
       │            │            │
       └────────────┼────────────┘
                    ▼
               Kubernetes
                    │
          ┌─────────┼─────────┐
          │         │         │
       Flannel   Storage   Gateway
          │
          ▼
       Workloads
```

Current active node configuration:

``` text
Control plane:
    talos-controlplane-01
    192.168.29.20

Worker:
    talos-worker-01
    192.168.29.21

Worker:
    talos-worker-02
    192.168.29.22
```

Prepared additional configuration:

``` text
Worker:
    talos-worker-03
```

------------------------------------------------------------------------

# 33. Design Principles

The Talos configuration follows these principles:

### 1. Immutable Infrastructure

Talos provides a Kubernetes-focused operating system rather than a
general-purpose Linux environment.

### 2. Declarative Configuration

Machine configuration is represented in Git through base configuration
and patches.

### 3. Role-Based Configuration

Control-plane and worker machines have separate base configurations.

### 4. Machine-Specific Patching

Machine-specific values are isolated into patches instead of duplicating
complete configurations.

### 5. Layer Separation

Talos configuration does not replace Proxmox or Kubernetes
configuration.

### 6. Reproducibility

A node should be reproducible from the documented configuration rather
than depending on undocumented manual changes.

### 7. Explicit Networking

Node addresses and machine networking are represented explicitly through
Talos configuration patches.

------------------------------------------------------------------------

# 34. Related Documentation

  ------------------------------------------------------------------------------------------------------------
  Documentation                                                            Purpose
  ------------------------------------------------------------------------ -----------------------------------
  [`../README.md`](../README.md)                                           Homelab overview

  [`../docs/Architecture.md`](../docs/Architecture.md)                     Overall architecture

  [`../docs/Operations.md`](../docs/Operations.md)                         Operational procedures

  [`../proxmox/README.md`](../proxmox/README.md)                           Proxmox/OpenTofu infrastructure

  [`../kubernetes/README.md`](../kubernetes/README.md)                     Kubernetes layer

  [`../kubernetes/argocd/README.md`](../kubernetes/argocd/README.md)       Argo CD GitOps

  [`../docs/Proxmox-Homelab-Setup.md`](../docs/Proxmox-Homelab-Setup.md)   Proxmox setup
  ------------------------------------------------------------------------------------------------------------

------------------------------------------------------------------------

# 35. Quick Reference

``` text
Talos version:
    v1.13.8

Kubernetes:
    v1.36.2

Container runtime:
    containerd 2.2.6

CNI:
    Flannel

Pod CIDR:
    10.244.0.0/16

Service CIDR:
    10.96.0.0/12

Control plane:
    talos-controlplane-01
    192.168.29.20

Worker 01:
    talos-worker-01
    192.168.29.21

Worker 02:
    talos-worker-02
    192.168.29.22

Additional configured worker:
    talos-worker-03
```

------------------------------------------------------------------------

# 36. Summary

The `talos/` directory is the **operating-system and Kubernetes-node
configuration layer** of the homelab.

Its responsibilities are:

``` text
                    talos/
                       │
        ┌──────────────┼──────────────┐
        │              │              │
        ▼              ▼              ▼
  Base configs       Patches       Bootstrap
        │              │              │
        └──────────────┼──────────────┘
                       ▼
                 Talos machines
                       │
                       ▼
                  Kubernetes
```

The important architectural boundary is:

``` text
OpenTofu / Proxmox
        │
        ▼
   VM infrastructure
        │
        ▼
      Talos
        │
        ▼
 Kubernetes nodes
        │
        ▼
 Kubernetes platform
        │
        ▼
    Applications
```

This separation keeps the homelab reproducible and makes each
infrastructure layer independently understandable, testable, and
maintainable.
