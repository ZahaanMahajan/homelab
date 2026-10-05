# Kubernetes

This directory contains the Kubernetes configuration for the homelab
cluster.

The cluster is managed as a **GitOps-oriented Kubernetes platform**.
Kubernetes resources are separated by responsibility into:

-   **Infrastructure** --- components required to provide networking,
    storage, certificates, and cluster-level capabilities.
-   **Platform** --- shared services that support workloads and cluster
    operations.
-   **Applications** --- workload-specific Helm charts.
-   **Argo CD** --- the GitOps control plane that continuously
    reconciles the desired state stored in Git.
-   **Labs** --- isolated Kubernetes learning and CKA practice
    manifests.

The goal is to keep the Kubernetes configuration declarative,
reproducible, understandable, and easy to operate.

------------------------------------------------------------------------

## Architecture

The Kubernetes layer follows this high-level dependency model:

``` text
                         Git Repository
                               │
                               │ desired state
                               ▼
                           Argo CD
                               │
                    ┌──────────┼──────────┐
                    │          │          │
                    ▼          ▼          ▼
             Infrastructure  Platform  Applications
                    │          │          │
                    │          │          ├── Linkding
                    │          │          ├── Nextcloud
                    │          │          └── Portfolio
                    │          │
                    │          ├── Argo CD
                    │          ├── Homepage
                    │          └── Monitoring
                    │
          ┌─────────┼──────────┬──────────┐
          ▼         ▼          ▼          ▼
       MetalLB   Gateway API  cert-manager  NFS CSI
          │         │          │             │
          │         │          │             ▼
          │         │          │          OMV NFS
          │         │          │
          │         │          ▼
          │         │       Let's Encrypt
          │         │
          │         ▼
          │      HTTP routing
          │
          ▼
      LoadBalancer IPs
```

The application traffic path is conceptually:

``` text
Client
  │
  ▼
Cloudflare / DNS
  │
  ▼
Cloudflared / Gateway API
  │
  ▼
Gateway / HTTPRoute
  │
  ▼
Kubernetes Service
  │
  ▼
Pod
```

The exact path varies by workload and by the networking resources used
by that application.

------------------------------------------------------------------------

## Cluster

The Kubernetes cluster runs on **Talos Linux** virtual machines hosted
on Proxmox.

  Component               Configuration
  ----------------------- ------------------------------
  Kubernetes              v1.36.2
  OS                      Talos Linux v1.13.8
  Container runtime       containerd 2.2.6
  CNI                     Flannel
  Pod CIDR                `10.244.0.0/16`
  Service CIDR            `10.96.0.0/12`
  Load balancing          MetalLB
  Gateway                 Gateway API
  Certificates            cert-manager + Let's Encrypt
  DNS                     Cloudflare / Pi-hole
  External connectivity   Cloudflared
  Storage                 NFS CSI
  GitOps                  Argo CD
  Application packaging   Helm

### Nodes

Current node configuration:

  Node                      Role            Address
  ------------------------- --------------- -----------------
  `talos-controlplane-01`   Control plane   `192.168.29.20`
  `talos-worker-01`         Worker          `192.168.29.21`
  `talos-worker-02`         Worker          `192.168.29.22`

> The repository contains configuration for a potential
> `talos-worker-03`. Its presence in Git does not by itself mean that
> the node is currently part of the running cluster. Verify the live
> cluster with `kubectl get nodes`.

------------------------------------------------------------------------

## Repository Structure

``` text
kubernetes/
├── README.md
│
├── argocd/
│   ├── bootstrap/
│   │   └── root.yaml
│   │
│   └── applications/
│       ├── applications.yaml
│       ├── infrastructure.yaml
│       ├── platform.yaml
│       └── workloads/
│           ├── linkding.yaml
│           ├── nextcloud.yaml
│           └── portfolio.yaml
│
├── infrastructure/
│   ├── networking/
│   │   ├── cert-manager/
│   │   ├── cloudflared/
│   │   ├── gateway-api/
│   │   ├── metallb/
│   │   └── README.md
│   │
│   ├── security/
│   │   └── README.md
│   │
│   └── storage/
│       └── nfs/
│           ├── README.md
│           └── storage-classes/
│
├── platform/
│   ├── argocd/
│   ├── homepage/
│   └── monitoring/
│
└── applications/
    ├── linkding/
    ├── nextcloud/
    └── portfolio/
```

------------------------------------------------------------------------

# 1. Infrastructure

`kubernetes/infrastructure/` contains cluster-level capabilities.

Infrastructure exists to provide services that workloads depend on
rather than representing an individual application.

## Networking

Location:

``` text
kubernetes/infrastructure/networking/
```

### MetalLB

MetalLB provides `LoadBalancer` functionality for the bare-metal
Kubernetes environment.

``` text
Kubernetes Service
       │
       │ type: LoadBalancer
       ▼
     MetalLB
       │
       ▼
LAN IP address
```

This fills the role normally provided automatically by a cloud
provider's load-balancer service.

Configuration:

``` text
kubernetes/infrastructure/networking/metallb/
```

------------------------------------------------------------------------

### Gateway API

Gateway API provides the cluster's modern HTTP routing model.

The architecture separates:

-   **GatewayClass** --- defines the controller implementation.
-   **Gateway** --- defines the network entry point.
-   **HTTPRoute** --- defines application routing rules.

Conceptually:

``` text
GatewayClass
     │
     ▼
  Gateway
     │
     ▼
 HTTPRoute
     │
     ▼
 Service
     │
     ▼
   Pods
```

Configuration:

``` text
kubernetes/infrastructure/networking/gateway-api/
```

Application-specific Gateway and HTTPRoute resources remain inside the
relevant application chart.

------------------------------------------------------------------------

### cert-manager

cert-manager manages TLS certificates inside Kubernetes.

This homelab uses:

``` text
cert-manager
      │
      ▼
Let's Encrypt
      │
      ▼
ACME DNS-01
      │
      ▼
Cloudflare DNS
```

ClusterIssuers are stored at:

``` text
kubernetes/infrastructure/networking/cert-manager/
```

There are separate staging and production issuers.

Use the staging issuer when testing certificate configuration to avoid
unnecessary Let's Encrypt production issuance.

------------------------------------------------------------------------

### Cloudflared

Cloudflared provides the Cloudflare-side connectivity used by the
homelab.

Configuration:

``` text
kubernetes/infrastructure/networking/cloudflared/
```

The Cloudflare integration allows selected services to be exposed
without directly exposing the homelab Kubernetes nodes to the public
Internet.

------------------------------------------------------------------------

## Storage

Storage configuration lives under:

``` text
kubernetes/infrastructure/storage/
```

The cluster uses the Kubernetes **NFS CSI driver** to dynamically
provision persistent storage from the OMV NAS.

Architecture:

``` text
Application
    │
    ▼
PersistentVolumeClaim
    │
    ▼
StorageClass
    │
    ▼
NFS CSI Driver
    │
    ▼
OMV NFS Server
    │
    ▼
NFS Export
```

The StorageClass is located at:

``` text
kubernetes/infrastructure/storage/nfs/storage-classes/
```

Detailed documentation is maintained in:

``` text
kubernetes/infrastructure/storage/nfs/README.md
```

------------------------------------------------------------------------

# 2. Platform

`kubernetes/platform/` contains shared services used to operate or
present the cluster.

Current platform components include:

``` text
platform/
├── argocd/
├── homepage/
└── monitoring/
```

These are not application workloads in the same sense as Linkding,
Nextcloud, or the portfolio.

They provide cluster-level operational functionality.

------------------------------------------------------------------------

## Argo CD

Argo CD is the GitOps controller for the Kubernetes environment.

The desired state is stored in Git and Argo CD reconciles that state
with the Kubernetes cluster.

The basic workflow is:

``` text
Git
 │
 │ desired state
 ▼
Argo CD
 │
 │ reconciliation
 ▼
Kubernetes API
 │
 ▼
Cluster resources
```

Argo CD configuration and Application definitions live under:

``` text
kubernetes/argocd/
```

The bootstrap entry point is:

``` text
kubernetes/argocd/bootstrap/root.yaml
```

The repository uses an application hierarchy to separate:

``` text
Infrastructure
Platform
Applications / Workloads
```

------------------------------------------------------------------------

## Homepage

Homepage provides a dashboard for accessing homelab services.

Configuration:

``` text
kubernetes/platform/homepage/
```

The configuration includes:

-   Namespace
-   RBAC
-   ConfigMap
-   Deployment
-   Service
-   Ingress
-   Certificate

------------------------------------------------------------------------

## Monitoring

Monitoring resources live under:

``` text
kubernetes/platform/monitoring/
```

The current repository contains the monitoring namespace,
ingress/routing configuration, certificate configuration, and secret
material.

Monitoring is treated as a platform capability rather than an individual
application workload.

------------------------------------------------------------------------

# 3. Applications

Application workloads are packaged as Helm charts.

Location:

``` text
kubernetes/applications/
```

Current charts:

``` text
applications/
├── linkding/
├── nextcloud/
└── portfolio/
```

Each application owns its workload-specific Kubernetes resources.

A typical Helm chart contains:

``` text
Chart.yaml
values.yaml
templates/
```

This keeps application configuration together instead of scattering
manifests across the repository.

------------------------------------------------------------------------

## Linkding

Linkding is deployed as a Helm application.

The chart contains resources for:

-   Deployment
-   Service
-   PersistentVolumeClaim
-   IngressRoute
-   Certificate

Location:

``` text
kubernetes/applications/linkding/
```

------------------------------------------------------------------------

## Nextcloud

Nextcloud is deployed as a Helm application with supporting database and
cache components.

The chart contains:

``` text
nextcloud/
└── templates/
    ├── nextcloud/
    │   ├── certificate.yaml
    │   ├── deployment.yaml
    │   ├── ingress.yaml
    │   ├── pvc.yaml
    │   └── service.yaml
    │
    ├── postgres/
    │   ├── pvc.yaml
    │   ├── service.yaml
    │   └── statefulset.yaml
    │
    └── redis/
        ├── deployment.yaml
        └── service.yaml
```

This makes Nextcloud a multi-component application rather than a single
Pod deployment.

------------------------------------------------------------------------

## Portfolio

The portfolio application is packaged as a Helm chart.

Location:

``` text
kubernetes/applications/portfolio/
```

The chart contains resources for:

-   Deployment
-   Service
-   Gateway
-   HTTPRoute
-   Certificate
-   EnvoyProxy

The portfolio is also the main application used to exercise the newer
Gateway API-based routing architecture.

------------------------------------------------------------------------

# 4. GitOps Application Model

The Argo CD configuration separates resources into logical groups.

``` text
Argo CD
   │
   ├── Infrastructure
   │
   ├── Platform
   │
   └── Workloads
       ├── Linkding
       ├── Nextcloud
       └── Portfolio
```

The corresponding Application definitions are:

``` text
kubernetes/argocd/applications/
├── infrastructure.yaml
├── platform.yaml
├── applications.yaml
└── workloads/
    ├── linkding.yaml
    ├── nextcloud.yaml
    └── portfolio.yaml
```

The intended responsibility boundary is:

  Layer            Responsibility
  ---------------- ---------------------------------------
  Infrastructure   Cluster capabilities and dependencies
  Platform         Shared operational services
  Applications     User-facing workloads
  Labs             Learning and CKA exercises
  Argo CD          Reconciliation of desired state

------------------------------------------------------------------------

# 5. Labs

The `labs/` directory is deliberately separate from the
production-oriented Kubernetes configuration.

It contains isolated Kubernetes learning exercises and CKA practice.

Examples include:

``` text
labs/
├── 01-pod/
├── 02-replicaset/
├── 03-deployment/
├── 04-daemonset/
├── 05-statefulset/
├── 06-job/
├── 07-cronjob/
├── 08-service-clusterip/
├── 09-service-nodeport/
├── 10-service-loadbalancer/
├── 11-configmap/
├── 12-secret/
├── 13-namespace/
├── 14-serviceaccount/
├── 15-persistentvolume/
├── 16-persistentvolumeclaim/
├── 17-storageclass/
├── 18-ingress/
├── 19-networkpolicy/
├── 20-rbac/
├── 21-resource-requests-limits/
├── 22-probes/
├── 23-taints-tolerations/
├── 24-node-affinity/
├── 25-pod-affinity/
└── 26-pod-anti-affinity/
```

These manifests are learning material and should not be confused with
the GitOps-managed production workloads.

The labs are intended to support a progression from:

``` text
Pod
  ↓
ReplicaSet
  ↓
Deployment
  ↓
Services
  ↓
Storage
  ↓
Networking
  ↓
Security
  ↓
Scheduling
  ↓
Troubleshooting
```

The Kubernetes learning process is practical and CKA-oriented:
understand the concept, apply it, inspect the resulting resources,
deliberately introduce failures where useful, troubleshoot the behavior,
and document the resulting mental model.

------------------------------------------------------------------------

# 6. Common Kubernetes Operations

The following commands are useful when inspecting the cluster.

## Cluster state

``` bash
kubectl get nodes
kubectl get namespaces
kubectl get pods -A
```

## Workloads

``` bash
kubectl get deployments -A
kubectl get statefulsets -A
kubectl get daemonsets -A
kubectl get jobs -A
kubectl get cronjobs -A
```

## Networking

``` bash
kubectl get svc -A
kubectl get gateway -A
kubectl get httproute -A
```

## Storage

``` bash
kubectl get storageclass
kubectl get pv
kubectl get pvc -A
```

## Certificates

``` bash
kubectl get certificates -A
kubectl get certificaterequests -A
kubectl get clusterissuers
```

## Argo CD resources

``` bash
kubectl get applications -n argocd
```

For troubleshooting:

``` bash
kubectl describe <resource> <name> -n <namespace>
kubectl get events -A --sort-by=.lastTimestamp
```

------------------------------------------------------------------------

# 7. Troubleshooting Workflow

Kubernetes troubleshooting should follow the dependency chain rather
than jumping directly to random commands.

A general workload troubleshooting flow is:

``` text
Application
    │
    ▼
Pod
    │
    ├── Container
    ├── Image
    ├── Probes
    └── Resources
    │
    ▼
Service
    │
    ▼
Gateway / HTTPRoute
    │
    ▼
Certificate / DNS
    │
    ▼
External connectivity
```

For a failing application, start with the workload itself:

``` bash
kubectl get pods -n <namespace>
kubectl describe pod <pod> -n <namespace>
kubectl logs <pod> -n <namespace>
```

Then inspect the surrounding resources:

``` bash
kubectl get deploy,svc,pvc -n <namespace>
kubectl get events -n <namespace> --sort-by=.lastTimestamp
```

For Gateway API-based applications:

``` bash
kubectl get gateway -n <namespace>
kubectl get httproute -n <namespace>
kubectl describe gateway <name> -n <namespace>
kubectl describe httproute <name> -n <namespace>
```

For storage problems:

``` bash
kubectl get pvc -n <namespace>
kubectl get pv
kubectl get storageclass
```

For certificate problems:

``` bash
kubectl get certificate -A
kubectl get certificaterequest -A
kubectl describe certificate <name> -n <namespace>
```

The key principle is:

``` text
Observe
   ↓
Identify the failing layer
   ↓
Inspect the resource
   ↓
Inspect controller/events
   ↓
Fix the source of the problem
   ↓
Verify reconciliation
```

------------------------------------------------------------------------

# 8. Declarative Management

The Kubernetes configuration should normally be changed through
Git-managed manifests or Helm values rather than by making undocumented
imperative changes directly in the cluster.

Preferred model:

``` text
Edit Git
   ↓
Review change
   ↓
Commit
   ↓
Push
   ↓
Argo CD detects desired-state change
   ↓
Argo CD reconciles
   ↓
Kubernetes
```

Imperative `kubectl` commands remain useful for:

-   Investigation
-   Troubleshooting
-   CKA practice
-   Temporary experiments
-   Inspecting resources

They should not silently become the source of truth for GitOps-managed
resources.

------------------------------------------------------------------------

# 9. Important Boundaries

This directory intentionally separates several concerns.

### Kubernetes infrastructure

``` text
kubernetes/infrastructure/
```

Contains capabilities required by the cluster.

### Kubernetes platform

``` text
kubernetes/platform/
```

Contains shared operational services.

### Kubernetes applications

``` text
kubernetes/applications/
```

Contains application-specific Helm charts.

### Argo CD

``` text
kubernetes/argocd/
```

Contains the GitOps control structure that connects Git to the cluster.

### Kubernetes labs

``` text
labs/
```

Contains learning and CKA exercises and is intentionally outside the
GitOps application hierarchy.

This separation prevents the repository from becoming a single
collection of unrelated manifests.

------------------------------------------------------------------------

# 10. Related Documentation

Detailed documentation is maintained closer to the component it
describes.

  Topic                   Documentation
  ----------------------- ---------------------------------------------------
  Overall architecture    `docs/Architecture.md`
  Kubernetes operations   `docs/Operations.md`
  Argo CD                 `kubernetes/argocd/README.md`
  Networking              `kubernetes/infrastructure/networking/README.md`
  NFS CSI                 `kubernetes/infrastructure/storage/nfs/README.md`
  Kubernetes labs         `labs/README.md`
  Talos                   `talos/README.md`
  Proxmox                 `proxmox/README.md`

------------------------------------------------------------------------

# 11. Design Principles

The Kubernetes configuration follows these principles:

1.  **Declarative configuration**\
    Desired state is represented as code.

2.  **Git as the source of truth**\
    GitOps-managed resources should be reproducible from the repository.

3.  **Separation of concerns**\
    Infrastructure, platform services, workloads, and learning labs have
    different responsibilities.

4.  **Helm for application packaging**\
    Applications are maintained as self-contained charts.

5.  **Argo CD for reconciliation**\
    Application state is continuously reconciled against Git.

6.  **Modern Kubernetes networking**\
    Gateway API is used for newer HTTP routing rather than extending
    legacy Ingress configuration indefinitely.

7.  **Externalized persistent storage**\
    Persistent application data is backed by the NFS CSI integration
    with the OMV NAS.

8.  **Automation over manual configuration**\
    Repeated configuration should be represented in code.

9.  **Operational observability**\
    Resources should be inspectable through Kubernetes status, events,
    logs, and platform monitoring.

10. **CKA-oriented practical learning**\
    The `labs/` hierarchy provides isolated exercises for building
    operational Kubernetes knowledge.

------------------------------------------------------------------------

## Current Kubernetes Layer

At a high level, the homelab Kubernetes platform is structured as:

``` text
                         Kubernetes
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
        ▼                    ▼                    ▼
 Infrastructure           Platform           Applications
        │                    │                    │
        │                    │                    ├── Linkding
        │                    │                    ├── Nextcloud
        │                    │                    └── Portfolio
        │                    │
        │                    ├── Argo CD
        │                    ├── Homepage
        │                    └── Monitoring
        │
        ├── MetalLB
        ├── Gateway API
        ├── cert-manager
        ├── Cloudflared
        └── NFS CSI
```

This document is intentionally an **overview and navigation document**.
Component-specific implementation details belong in the corresponding
README or documentation rather than being duplicated here.
