# Homelab Kubernetes Cluster

A self-hosted Kubernetes homelab built on two Proxmox VE hosts using
Talos Linux.

The cluster is designed as a practical learning and engineering
environment for Kubernetes, CKA preparation, networking, storage,
security, observability, ingress, and platform engineering.

> **Current cluster checkpoint:** 1 control-plane node + 2 worker nodes,
> all running on Proxmox VMs.

------------------------------------------------------------------------

## Table of Contents

-   [Architecture](#architecture)
-   [Infrastructure](#infrastructure)
-   [Proxmox Hosts](#proxmox-hosts)
-   [Kubernetes Cluster](#kubernetes-cluster)
-   [Node Resources](#node-resources)
-   [Network Architecture](#network-architecture)
-   [Talos Linux](#talos-linux)
-   [Kubernetes Networking](#kubernetes-networking)
-   [Cluster Components](#cluster-components)
-   [Current Cluster State](#current-cluster-state)
-   [Repository Structure](#repository-structure)
-   [Configuration Management](#configuration-management)
-   [Security and Secrets](#security-and-secrets)
-   [Verification](#verification)
-   [Useful Commands](#useful-commands)
-   [Next Steps](#next-steps)
-   [Project Goals](#project-goals)

------------------------------------------------------------------------

## Architecture

The current infrastructure is split across two physical Proxmox VE
hosts.

``` text
                              Home Network
                           192.168.29.0/24
                                  │
                         Gateway / Router
                         192.168.29.1
                                  │
              ┌───────────────────┴───────────────────┐
              │                                       │
       Proxmox VE: pve                      Proxmox VE: pve-i3
       192.168.29.2                         192.168.29.3
              │                                       │
              │                                       │
      ┌───────┴────────┐                    ┌─────────┴─────────┐
      │                │                    │                   │
      │ VM 100         │                    │ VM 102            │
      │ Pi-hole        │                    │ Worker 01         │
      │ 192.168.29.10  │                    │ 192.168.29.21     │
      │                │                    │                   │
      ├────────────────┤                    ├───────────────────┤
      │ VM 101         │                    │ VM 103            │
      │ Control Plane  │                    │ Worker 02         │
      │ 192.168.29.20  │                    │ 192.168.29.22     │
      └────────────────┘                    └───────────────────┘
              │                                       │
              └───────────────────┬───────────────────┘
                                  │
                         Kubernetes Cluster
                                  │
                    ┌─────────────┴─────────────┐
                    │                           │
             Control Plane                 Workers
             192.168.29.20         192.168.29.21 / .22
                    │
                    ├── kube-apiserver
                    ├── kube-controller-manager
                    ├── kube-scheduler
                    ├── etcd
                    └── kubelet
```

### Kubernetes topology

``` text
                    Kubernetes Cluster
                    ───────────────────

              ┌──────────────────────────┐
              │  talos-controlplane-01   │
              │  Control Plane           │
              │  192.168.29.20           │
              │                          │
              │  etcd                    │
              │  kube-apiserver          │
              │  controller-manager      │
              │  scheduler               │
              │  kubelet                 │
              └────────────┬─────────────┘
                           │
             ┌─────────────┴─────────────┐
             │                           │
   ┌─────────▼─────────┐       ┌─────────▼─────────┐
   │ talos-worker-01   │       │ talos-worker-02   │
   │ 192.168.29.21     │       │ 192.168.29.22     │
   │                   │       │                   │
   │ kubelet           │       │ kubelet           │
   │ containerd        │       │ containerd        │
   │ kube-proxy        │       │ kube-proxy        │
   │ Flannel           │       │ Flannel           │
   └───────────────────┘       └───────────────────┘
```

------------------------------------------------------------------------

## Infrastructure

  Layer                               Technology
  ----------------------------------- ------------------------------
  Virtualization                      Proxmox VE
  Kubernetes OS                       Talos Linux
  Kubernetes                          v1.36.2
  Talos Linux                         v1.13.8
  Container runtime                   containerd 2.2.6
  Kubernetes CNI                      Flannel
  Cluster network                     `192.168.29.0/24`
  Gateway                             `192.168.29.1`
  Internal DNS                        Pi-hole
  DNS server                          `192.168.29.10`
  Kubernetes control-plane endpoint   `https://192.168.29.20:6443`
  Pod CIDR                            `10.244.0.0/16`
  Service CIDR                        `10.96.0.0/12`
  VM networking                       Proxmox `vmbr0`
  VM NIC                              VirtIO

------------------------------------------------------------------------

# Proxmox Hosts

## `pve`

Management IP:

``` text
192.168.29.2
```

Hardware:

-   12 logical CPUs
-   \~7.1 GiB RAM available to Proxmox
-   \~67 GiB Proxmox root filesystem
-   Local LVM-thin storage available for VMs

Network:

``` text
nic0
  │
  └── vmbr0
        └── 192.168.29.2/24
```

Relevant Proxmox configuration:

``` text
Bridge: vmbr0
Physical NIC: nic0
Gateway: 192.168.29.1
```

### VMs on `pve`

  ------------------------------------------------------------------------------------------------
         VMID Name              Purpose      IP                       vCPU         RAM        Disk
  ----------- ----------------- ------------ ----------------- ----------- ----------- -----------
          100 `pi-hole`         Internal DNS `192.168.29.10`             1       1 GiB      16 GiB

          101 `control-plane`   Kubernetes   `192.168.29.20`             2       2 GiB      32 GiB
                                control                                                
                                plane                                                  
  ------------------------------------------------------------------------------------------------

------------------------------------------------------------------------

## `pve-i3`

Management IP:

``` text
192.168.29.3
```

Hardware:

-   4 logical CPUs
-   \~15 GiB RAM available to Proxmox
-   \~94 GiB Proxmox root filesystem
-   Large LVM-thin storage pool for VMs

Network:

``` text
nic0
  │
  └── vmbr0
        └── 192.168.29.3/24
```

### VMs on `pve-i3`

  --------------------------------------------------------------------------------------------
         VMID Name          Purpose      IP                       vCPU         RAM        Disk
  ----------- ------------- ------------ ----------------- ----------- ----------- -----------
          102 `worker-01`   Kubernetes   `192.168.29.21`             1       4 GiB      32 GiB
                            worker                                                 

          103 `worker-02`   Kubernetes   `192.168.29.22`             1       4 GiB      32 GiB
                            worker                                                 
  --------------------------------------------------------------------------------------------

------------------------------------------------------------------------

# Kubernetes Cluster

## Node topology

  -----------------------------------------------------------------------------------------------
  Kubernetes Node           Role       IP                Proxmox              vCPU            RAM
                                                         Host                      
  ------------------------- ---------- ----------------- ---------- -------------- --------------
  `talos-controlplane-01`   Control    `192.168.29.20`   `pve`                   2          2 GiB
                            Plane                                                  

  `talos-worker-01`         Worker     `192.168.29.21`   `pve-i3`                1          4 GiB

  `talos-worker-02`         Worker     `192.168.29.22`   `pve-i3`                1          4 GiB
  -----------------------------------------------------------------------------------------------

The cluster intentionally uses a single control-plane node at this
stage.

This is suitable for the current homelab and learning objectives, but it
is **not highly available**. A production HA control plane would
normally require multiple control-plane/etcd members.

------------------------------------------------------------------------

## Node naming

The Kubernetes node names are:

``` text
talos-controlplane-01
talos-worker-01
talos-worker-02
```

The node names are explicitly configured through Talos patches rather
than relying on automatically generated Talos hostnames.

------------------------------------------------------------------------

# Node Resources

Current Kubernetes allocatable capacity is approximately:

  Node              CPU Capacity   Memory Capacity
  --------------- -------------- -----------------
  Control Plane            2 CPU         \~1.9 GiB
  Worker 01                1 CPU         \~3.8 GiB
  Worker 02                1 CPU         \~3.8 GiB

The relatively small worker nodes are intentional: this cluster is a
constrained homelab environment and is designed to provide realistic
Kubernetes operational experience rather than maximize application
capacity.

------------------------------------------------------------------------

# Network Architecture

The physical/home network is:

``` text
192.168.29.0/24
```

Gateway:

``` text
192.168.29.1
```

Important addresses:

``` text
192.168.29.2   pve
192.168.29.3   pve-i3
192.168.29.10  Pi-hole
192.168.29.20  Kubernetes control plane
192.168.29.21  Kubernetes worker 01
192.168.29.22  Kubernetes worker 02
```

The Kubernetes nodes use static addresses.

Each Proxmox host provides the VMs with Layer-2 connectivity through
`vmbr0` and VirtIO network adapters.

------------------------------------------------------------------------

## Kubernetes network ranges

### Pod network

Flannel is configured with:

``` text
10.244.0.0/16
```

The cluster currently assigns individual node pod CIDRs such as:

``` text
10.244.0.0/24
```

Flannel uses VXLAN for pod-to-pod networking between nodes.

### Service network

Kubernetes uses:

``` text
10.96.0.0/12
```

The default Kubernetes API service is:

``` text
10.96.0.1
```

The cluster DNS service is:

``` text
10.96.0.10
```

------------------------------------------------------------------------

# Talos Linux

Talos Linux is used as the operating system for all Kubernetes nodes.

Talos provides an immutable, minimal operating system designed
specifically for Kubernetes.

The cluster was created using:

``` text
Talos Linux v1.13.8
```

The Kubernetes nodes currently report:

``` text
Kubernetes:       v1.36.2
Kernel:           6.18.42-talos
Container runtime: containerd 2.2.6
```

------------------------------------------------------------------------

## Talos boot/install model

The Kubernetes VMs boot from the Talos installation ISO and install
Talos onto:

``` text
/dev/sda
```

The VMs use:

``` text
BIOS:    OVMF
Machine: q35
Disk:    VirtIO/SCSI
NIC:     VirtIO
```

The Talos installation disk is the VM's virtual disk, not a physical
disk from the Proxmox host.

------------------------------------------------------------------------

## Talos configuration

The generated Talos machine configurations are intentionally **not
committed to this repository**.

The repository contains the reusable patches under:

``` text
talos/patches/
```

The generated configurations remain local because they contain
credential-bearing material.

Ignored files include:

``` text
talos/controlplane.yaml
talos/worker.yaml
talos/talosconfig
```

This separation allows the repository to document and reproduce the
architecture without publishing cluster credentials.

------------------------------------------------------------------------

# Talos Configuration Patches

The repository currently contains these patches:

``` text
talos/patches/
├── apiserver-certsan.yaml
├── controlplane-static-ip.yaml
├── endpoint-patch.yaml
├── hostname-controlplane.yaml
├── hostname-worker1.yaml
├── hostname-worker2.yaml
├── worker1-static-ip.yaml
└── worker2-static-ip.yaml
```

Their responsibilities are:

  -----------------------------------------------------------------------
  Patch                               Purpose
  ----------------------------------- -----------------------------------
  `controlplane-static-ip.yaml`       Static IP and default route for
                                      control plane

  `worker1-static-ip.yaml`            Static IP and default route for
                                      worker 01

  `worker2-static-ip.yaml`            Static IP and default route for
                                      worker 02

  `hostname-controlplane.yaml`        Control-plane hostname

  `hostname-worker1.yaml`             Worker 01 hostname

  `hostname-worker2.yaml`             Worker 02 hostname

  `endpoint-patch.yaml`               Kubernetes control-plane endpoint

  `apiserver-certsan.yaml`            API server certificate SAN
  -----------------------------------------------------------------------

The patches use the VM's VirtIO interface:

``` text
ens18
```

------------------------------------------------------------------------

# Kubernetes Networking

The cluster currently uses **Flannel** as its CNI.

Flannel is deployed as a DaemonSet and runs on all three Kubernetes
nodes.

Current topology:

``` text
Control Plane
192.168.29.20
      │
      │ VXLAN
      │
      ├──────────── Worker 01
      │             192.168.29.21
      │
      └──────────── Worker 02
                    192.168.29.22
```

Flannel uses:

``` text
Backend: VXLAN
VNI:     1
Port:    4789
```

The cluster was verified with Flannel running on all nodes.

------------------------------------------------------------------------

# Cluster Components

The bootstrap cluster currently contains the standard Kubernetes
control-plane components.

## Control Plane

Running on:

``` text
talos-controlplane-01
```

Components include:

-   kube-apiserver
-   kube-controller-manager
-   kube-scheduler
-   etcd
-   kubelet
-   kube-proxy

## Worker Nodes

Each worker runs:

-   kubelet
-   containerd
-   kube-proxy
-   Flannel

## CoreDNS

CoreDNS is deployed in:

``` text
kube-system
```

The cluster currently has two CoreDNS replicas.

------------------------------------------------------------------------

# Current Cluster State

The cluster has been verified with:

``` bash
kubectl get nodes -o wide
```

Expected topology:

``` text
NAME                    STATUS   ROLES           INTERNAL-IP
talos-controlplane-01   Ready    control-plane   192.168.29.20
talos-worker-01         Ready    <none>          192.168.29.21
talos-worker-02         Ready    <none>          192.168.29.22
```

All three nodes are expected to report:

``` text
STATUS: Ready
```

The Talos health check has also been run across the complete cluster.

The health workflow verifies:

-   etcd health
-   etcd membership consistency
-   control-plane membership
-   Talos API readiness
-   node memory sizes
-   node disk sizes
-   diagnostics
-   kubelet health
-   boot sequence completion
-   Kubernetes node registration
-   control-plane static pods
-   control-plane component readiness
-   Kubernetes node readiness
-   kube-proxy readiness
-   CoreDNS readiness
-   node schedulability

------------------------------------------------------------------------

# Repository Structure

``` text
homelab/
│
├── docs/
│   ├── Pi-hole_Setup.md
│   └── Proxmox_Homelab_Setup.md
│
├── kubernetes/
│   ├── apps/
│   ├── monitoring/
│   ├── namespaces/
│   ├── networking/
│   │   ├── cloudflare/
│   │   ├── ingress/
│   │   ├── load-balancer/
│   │   ├── network-policies/
│   │   └── services/
│   ├── operators/
│   ├── security/
│   │   ├── cert-manager/
│   │   ├── rbac/
│   │   ├── secrets/
│   │   └── service-accounts/
│   └── storage/
│
├── labs/
│   ├── 01-pod/
│   ├── 02-replicaset/
│   ├── 03-deployment/
│   ├── 04-daemonset/
│   ├── 05-statefulset/
│   ├── 06-job/
│   ├── 07-cronjob/
│   ├── 08-service-clusterip/
│   ├── 09-service-nodeport/
│   ├── 10-service-loadbalancer/
│   ├── 11-configmap/
│   ├── 12-secret/
│   ├── 13-namespace/
│   ├── 14-serviceaccount/
│   ├── 15-persistentvolume/
│   ├── 16-persistentvolumeclaim/
│   ├── 17-storageclass/
│   ├── 18-ingress/
│   ├── 19-networkpolicy/
│   ├── 20-rbac/
│   ├── 21-resource-requests-limits/
│   ├── 22-probes/
│   ├── 23-taints-tolerations/
│   ├── 24-node-affinity/
│   ├── 25-pod-affinity/
│   └── 26-pod-anti-affinity/
│
├── talos/
│   └── patches/
│
└── templates/
```

------------------------------------------------------------------------

# Configuration Management

The repository follows a separation between **public declarative
configuration** and **private generated credentials**.

### Public repository

Contains:

-   Kubernetes manifests
-   Kubernetes labs
-   reusable templates
-   Talos patches
-   documentation
-   architecture configuration

### Local-only configuration

Not committed:

``` text
talos/controlplane.yaml
talos/worker.yaml
talos/talosconfig
```

These generated files are protected by `.gitignore`.

This approach allows the repository to remain public while avoiding
publication of cluster credentials.

------------------------------------------------------------------------

# Security and Secrets

This repository is intended to be public.

Therefore, credentials and generated authentication material must never
be committed.

The `.gitignore` protects:

``` text
.env
.env.*
*.key
*.pem
*.crt
*.cer
*.p12
*.pfx
kubeconfig
*.kubeconfig
.kube/
admin.conf
talos/talosconfig
talos/controlplane.yaml
talos/worker.yaml
```

Before committing infrastructure changes, check:

``` bash
git status
```

and inspect staged files:

``` bash
git diff --cached --name-only
```

For sensitive changes, inspect the staged contents:

``` bash
git diff --cached
```

Never commit:

-   Talos credentials
-   Kubernetes admin kubeconfigs
-   private keys
-   API tokens
-   Cloudflare tunnel tokens
-   passwords
-   cloud credentials
-   generated authentication certificates

Public documentation may contain private RFC1918 addresses such as
`192.168.29.x`; these are intentionally used to document the internal
homelab topology.

------------------------------------------------------------------------

# Verification

## Check Kubernetes nodes

``` bash
kubectl get nodes -o wide
```

Expected:

``` text
talos-controlplane-01   Ready    control-plane
talos-worker-01         Ready    <none>
talos-worker-02         Ready    <none>
```

## Check all system pods

``` bash
kubectl get pods -A -o wide
```

## Check API server readiness

``` bash
kubectl get --raw='/readyz?verbose'
```

The command should finish with:

``` text
readyz check passed
```

## Check services

``` bash
kubectl get svc -A -o wide
```

## Check Flannel

``` bash
kubectl get pods -n kube-system | grep flannel
```

## Check CoreDNS

``` bash
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
```

## Check Talos cluster health

``` bash
talosctl health \
  --control-plane-nodes 192.168.29.20 \
  --worker-nodes 192.168.29.21,192.168.29.22
```

A healthy cluster should finish with all health checks reporting:

``` text
OK
```

including:

``` text
waiting for all k8s nodes to report ready: OK
waiting for kube-proxy to report ready: OK
waiting for coredns to report ready: OK
waiting for all k8s nodes to report schedulable: OK
```

------------------------------------------------------------------------

# Useful Commands

## Kubernetes

``` bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get svc -A
kubectl get namespaces
kubectl get events -A
```

Describe a node:

``` bash
kubectl describe node talos-worker-01
```

Watch pods:

``` bash
kubectl get pods -A --watch
```

Inspect cluster information:

``` bash
kubectl cluster-info
```

------------------------------------------------------------------------

## Talos

Check version:

``` bash
talosctl version
```

Check cluster members:

``` bash
talosctl get members
```

Check etcd members:

``` bash
talosctl get etcdmembers
```

Check machine status:

``` bash
talosctl get machinestatus
```

Check services:

``` bash
talosctl services
```

Check disks:

``` bash
talosctl get disks
```

Check network links:

``` bash
talosctl get links
```

Run cluster health:

``` bash
talosctl health \
  --control-plane-nodes 192.168.29.20 \
  --worker-nodes 192.168.29.21,192.168.29.22
```

------------------------------------------------------------------------

# Proxmox Verification

On `pve`:

``` bash
qm list
```

Expected Kubernetes-related VMs:

``` text
101  control-plane
```

On `pve-i3`:

``` bash
qm list
```

Expected:

``` text
102  worker-01
103  worker-02
```

Check a VM:

``` bash
qm status 101
qm config 101
```

For workers:

``` bash
qm status 102
qm status 103
```

------------------------------------------------------------------------

# Current Limitations

This is a learning and development cluster rather than a production HA
platform.

### Single control plane

There is currently only one control-plane node:

``` text
192.168.29.20
```

Therefore:

``` text
etcd:            single member
API server:      single instance
scheduler:       single instance
controller:      single instance
```

If the control-plane VM or its Proxmox host fails, the Kubernetes
control plane becomes unavailable.

### Worker capacity

Each worker currently has:

``` text
1 vCPU
4 GiB RAM
32 GiB disk
```

This is sufficient for lightweight workloads and Kubernetes
experimentation but limits resource-heavy applications.

### Proxmox host placement

Both workers currently reside on:

``` text
pve-i3
```

Therefore, failure of `pve-i3` removes both worker nodes simultaneously.

The control plane resides on:

``` text
pve
```

This provides basic host separation between control plane and workers
but is not equivalent to production-grade fault tolerance.

------------------------------------------------------------------------

# Next Steps

The cluster foundation is now established.

Planned infrastructure progression includes:

1.  Verify and document the base cluster
2.  Kubernetes namespace organization
3.  MetalLB load balancing
4.  Ingress controller
5.  cert-manager
6.  Internal/external DNS integration
7.  Storage architecture
8.  Persistent workloads
9.  RBAC and service accounts
10. Network policies
11. Monitoring
12. Prometheus
13. Grafana
14. Alertmanager
15. Application deployments
16. Secure external exposure where appropriate
17. Backup and disaster recovery
18. Cluster hardening
19. GitOps
20. Platform engineering workloads

The exact implementation should evolve as the homelab grows.

------------------------------------------------------------------------

# Project Goals

This homelab is intended to provide hands-on experience with:

### Kubernetes

-   Pods
-   ReplicaSets
-   Deployments
-   DaemonSets
-   StatefulSets
-   Jobs
-   CronJobs
-   Services
-   ConfigMaps
-   Secrets
-   Namespaces
-   ServiceAccounts
-   PersistentVolumes
-   PersistentVolumeClaims
-   StorageClasses
-   Ingress
-   NetworkPolicies
-   RBAC
-   Resource requests and limits
-   Probes
-   Taints and tolerations
-   Node affinity
-   Pod affinity
-   Pod anti-affinity

### Platform Engineering

-   Proxmox virtualization
-   Talos Linux
-   Kubernetes cluster lifecycle
-   Cluster networking
-   Load balancing
-   Ingress
-   TLS
-   DNS
-   Storage
-   Observability
-   Security
-   Infrastructure automation
-   Git-based configuration management

### CKA preparation

The `labs/` directory contains progressively organized Kubernetes
exercises and CKA-oriented practice scenarios.

Each lab is intended to be independently reproducible and serves as both
a learning exercise and a reference for future troubleshooting.

------------------------------------------------------------------------

# Checkpoint

Current infrastructure checkpoint:

``` text
Proxmox Hosts
├── pve
│   ├── Pi-hole
│   └── Kubernetes Control Plane
│
└── pve-i3
    ├── Kubernetes Worker 01
    └── Kubernetes Worker 02

Kubernetes
├── Control Plane
│   └── 192.168.29.20
│
├── Worker 01
│   └── 192.168.29.21
│
└── Worker 02
    └── 192.168.29.22
```

At this checkpoint:

``` text
3 Kubernetes nodes
1 control plane
2 workers
3 Talos Linux VMs
2 Proxmox hosts
Flannel CNI
CoreDNS
etcd
containerd
```

The cluster is operational and forms the foundation for the next phase
of the homelab.
