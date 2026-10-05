# Proxmox Infrastructure

This directory contains the **OpenTofu configuration for the Proxmox
infrastructure** used by the homelab.

OpenTofu is used to declaratively manage the virtual machines that
provide the foundation for the Talos Kubernetes cluster and supporting
infrastructure.

The current configuration uses the
[`bpg/proxmox`](https://registry.terraform.io/providers/bpg/proxmox/latest)
provider and manages VM resources through the Proxmox API.

------------------------------------------------------------------------

## Overview

The current Proxmox environment consists of two Proxmox nodes:

``` text
                    Proxmox Cluster
                         │
              ┌──────────┴──────────┐
              │                     │
             pve                  pve-i3
              │                     │
       ┌──────┴──────┐       ┌──────┼──────────────┐
       │             │       │      │              │
     DNSmasq     Control   Worker  Worker          NAS
                  Plane       01      02
```

OpenTofu manages the VM definitions, while the operating-system and
Kubernetes configuration are handled separately.

The infrastructure relationship is:

``` text
Git Repository
      │
      │ OpenTofu configuration
      ▼
   OpenTofu
      │
      │ Proxmox API
      ▼
 Proxmox Cluster
      │
      ├── dnsmasq VM
      ├── Kubernetes control-plane VM
      ├── Kubernetes worker-01 VM
      ├── Kubernetes worker-02 VM
      └── NAS VM
             │
             └── Physical 1 TB HDD
```

------------------------------------------------------------------------

## Proxmox Nodes

  Node       Role
  ---------- ------------------------------------------------------
  `pve`      Hosts the DNSmasq VM and Kubernetes control-plane VM
  `pve-i3`   Hosts the Kubernetes worker VMs and NAS VM

The Proxmox node configuration itself is not currently defined by
OpenTofu in this directory. The OpenTofu configuration consumes the
existing Proxmox environment and manages virtual machines through the
Proxmox API.

------------------------------------------------------------------------

## Virtual Machine Inventory

  VM                  VM ID Proxmox Node     vCPU       RAM   OS Disk
  ----------------- ------- -------------- ------ --------- ---------
  `dnsmasq`             100 `pve`               1       ---     16 GB
  `control-plane`       101 `pve`               4   6144 MB     32 GB
  `worker-01`           102 `pve-i3`            1   5120 MB     32 GB
  `worker-02`           103 `pve-i3`            1   5120 MB     32 GB
  `nas`                 104 `pve-i3`            2   4096 MB     32 GB

The `dnsmasq` VM does not currently define a dedicated memory block in
OpenTofu, so its memory allocation is left to the existing
Proxmox/default configuration.

All currently defined VMs use:

-   BIOS: SeaBIOS
-   OS type: `l26`
-   SCSI hardware: `virtio-scsi-single`
-   Network bridge: `vmbr0`
-   Proxmox VM firewall: enabled
-   `on_boot = false`

------------------------------------------------------------------------

## OpenTofu Structure

``` text
proxmox/
├── cluster.tf
├── main.tf
├── network.tf
├── outputs.tf
├── providers.tf
├── storage.tf
├── terraform.tfstate
├── terraform.tfstate.backup
├── terraform.tfvars
├── terraform.tfvars.example
├── variables.tf
├── versions.tf
└── vms.tf
```

### Configuration Files

  -----------------------------------------------------------------------
  File                                Purpose
  ----------------------------------- -----------------------------------
  `providers.tf`                      Configures the Proxmox provider and
                                      API connection

  `versions.tf`                       Defines OpenTofu/provider version
                                      constraints

  `variables.tf`                      Declares configurable and sensitive
                                      variables

  `vms.tf`                            Defines the Proxmox virtual
                                      machines

  `cluster.tf`                        Reserved for cluster-related
                                      configuration

  `network.tf`                        Reserved for network-related
                                      configuration

  `storage.tf`                        Reserved for storage-related
                                      configuration

  `outputs.tf`                        Reserved for OpenTofu outputs

  `main.tf`                           Reserved for general/root
                                      configuration

  `terraform.tfvars`                  Local variable values; should
                                      remain private

  `terraform.tfvars.example`          Example variable file for
                                      repository users

  `terraform.tfstate`                 OpenTofu state; should be treated
                                      as sensitive infrastructure data

  `terraform.tfstate.backup`          OpenTofu state backup
  -----------------------------------------------------------------------

The currently meaningful infrastructure definitions are primarily in
`providers.tf`, `versions.tf`, `variables.tf`, and `vms.tf`.

------------------------------------------------------------------------

## Provider Configuration

The homelab uses the `bpg/proxmox` provider:

``` hcl
terraform {
  required_version = ">= 1.11.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.112.0"
    }
  }
}
```

The provider connects to the Proxmox API using an API token:

``` hcl
provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token

  insecure = true
}
```

### Provider Variables

Two variables are currently required:

``` hcl
variable "proxmox_endpoint" {
  description = "Proxmox API endpoint"
  type        = string
  sensitive   = true
}

variable "proxmox_api_token" {
  description = "Proxmox API token"
  type        = string
  sensitive   = true
}
```

Both values should be supplied outside the version-controlled
infrastructure definitions.

> **Security note:** `insecure = true` disables TLS certificate
> verification for the Proxmox API connection. This may be acceptable
> for the isolated homelab environment, but it should be reconsidered if
> the infrastructure is moved into a production or less-trusted network.

------------------------------------------------------------------------

## Virtual Machines

All VM resources are defined in `vms.tf` using:

``` hcl
resource "proxmox_virtual_environment_vm" "..." {
  ...
}
```

### DNSmasq

``` text
Name:       dnsmasq
VM ID:      100
Node:       pve
CPU:        1 core
Disk:       16 GB
Datastore:  local-lvm
Network:    vmbr0
```

The VM uses a fixed MAC address and has the Proxmox firewall enabled.

------------------------------------------------------------------------

### Kubernetes Control Plane

``` text
Name:       control-plane
VM ID:      101
Node:       pve
CPU:        4 cores
RAM:        6 GB
Disk:       32 GB
Datastore:  local-lvm
Network:    vmbr0
```

This VM provides the compute foundation for the Talos Kubernetes
control-plane node.

The Kubernetes/Talos configuration itself is maintained separately
under:

``` text
talos/
```

------------------------------------------------------------------------

### Kubernetes Worker 01

``` text
Name:       worker-01
VM ID:      102
Node:       pve-i3
CPU:        1 core
RAM:        5 GB
Disk:       32 GB
Datastore:  local-lvm
Network:    vmbr0
```

------------------------------------------------------------------------

### Kubernetes Worker 02

``` text
Name:       worker-02
VM ID:      103
Node:       pve-i3
CPU:        1 core
RAM:        5 GB
Disk:       32 GB
Datastore:  local-lvm
Network:    vmbr0
```

------------------------------------------------------------------------

### NAS

``` text
Name:       nas
VM ID:      104
Node:       pve-i3
CPU:        2 cores
RAM:        4 GB
OS Disk:    32 GB
Network:    vmbr0
```

The NAS VM has two storage devices.

#### Operating-system disk

``` hcl
disk {
  datastore_id = "local-lvm"
  interface    = "scsi0"
  size         = 32
  iothread     = true
}
```

#### Physical 1 TB HDD

The NAS also receives a physical 1 TB HDD directly from `pve-i3`:

``` hcl
disk {
  datastore_id      = ""
  path_in_datastore = "/dev/disk/by-id/ata-ST1000DM003-1SB102_ZN14TJN6"
  interface         = "scsi1"
}
```

This disk is intentionally different from the VM operating-system disk.

The OS disk is stored on Proxmox `local-lvm`, while the 1 TB disk is
passed through to the NAS VM for storage workloads.

------------------------------------------------------------------------

## Networking

The currently defined VM network configuration uses the Proxmox bridge:

``` text
vmbr0
```

Each VM receives a network device similar to:

``` hcl
network_device {
  bridge      = "vmbr0"
  mac_address = "..."
  firewall    = true
}
```

Each VM has an explicitly defined MAC address.

The OpenTofu configuration does **not** currently define the Proxmox
bridge itself. The bridge is expected to already exist on the Proxmox
nodes.

The higher-level homelab network configuration is documented separately.

------------------------------------------------------------------------

## Storage

The VM operating-system disks currently use:

``` text
Datastore: local-lvm
Interface: scsi
Hardware:  virtio-scsi-single
```

The NAS is the exception because it additionally receives a physical
disk:

``` text
pve-i3
  │
  └── Physical 1 TB HDD
          │
          ▼
       NAS VM
          │
          ▼
       NFS storage
          │
          ▼
 Kubernetes NFS CSI
          │
          ▼
 Persistent Volumes / PVCs
```

The Kubernetes storage layer is therefore built on top of the NAS VM
rather than directly on Proxmox storage.

------------------------------------------------------------------------

## VM Lifecycle

The current configuration explicitly sets:

``` hcl
on_boot = false
```

for all defined VMs.

This means VM startup after a Proxmox host reboot is not enabled through
the current OpenTofu configuration.

If this behavior is changed later, it should be reflected in the VM
definitions and documented here.

------------------------------------------------------------------------

# OpenTofu Workflow

Infrastructure changes should follow the normal OpenTofu workflow.

``` text
       Edit configuration
              │
              ▼
          tofu fmt
              │
              ▼
        tofu validate
              │
              ▼
           tofu plan
              │
              ▼
       Review changes
              │
              ▼
          tofu apply
              │
              ▼
        Proxmox API
              │
              ▼
       Actual VM state
```

------------------------------------------------------------------------

## Initialize

From the repository root:

``` bash
cd proxmox
tofu init
```

This initializes the OpenTofu working directory and downloads the
required provider.

------------------------------------------------------------------------

## Format

Format the configuration before committing changes:

``` bash
tofu fmt
```

To check formatting without modifying files:

``` bash
tofu fmt -check
```

------------------------------------------------------------------------

## Validate

Validate the configuration:

``` bash
tofu validate
```

This checks whether the OpenTofu configuration is syntactically and
structurally valid.

------------------------------------------------------------------------

## Plan

Before changing infrastructure:

``` bash
tofu plan
```

The plan should be reviewed before applying changes.

The plan represents the difference between:

``` text
OpenTofu configuration
        │
        ▼
Desired state
        │
        │ compare
        ▼
OpenTofu state
        │
        ▼
Current infrastructure
```

------------------------------------------------------------------------

## Apply

Apply the reviewed infrastructure changes:

``` bash
tofu apply
```

For normal homelab operations, prefer reviewing the generated plan
before confirming the apply.

------------------------------------------------------------------------

## State Management

OpenTofu maintains state to track the relationship between the
configuration and resources managed in Proxmox.

The current directory contains:

``` text
terraform.tfstate
terraform.tfstate.backup
```

State can contain sensitive infrastructure information and should
therefore be treated as sensitive.

Do not expose state contents publicly.

Before making the repository public, verify:

``` bash
git status
git ls-files proxmox/terraform.tfstate
git ls-files proxmox/terraform.tfvars
```

If these files are tracked and contain sensitive information, they
should be removed from version control and appropriate `.gitignore`
rules should be added.

> State management is an important part of the infrastructure lifecycle.
> Losing or corrupting state can cause OpenTofu to lose its
> understanding of resources it previously managed.

------------------------------------------------------------------------

## Variables and Secrets

The provider requires:

``` text
proxmox_endpoint
proxmox_api_token
```

These are declared as sensitive variables.

The intended pattern is:

``` text
terraform.tfvars.example
        │
        │ example structure
        ▼
terraform.tfvars
        │
        │ private values
        ▼
OpenTofu
```

The real `terraform.tfvars` file should not contain values that are
committed to a public repository.

The example file should document the required variable names without
exposing credentials.

Example structure:

``` hcl
proxmox_endpoint  = "https://<proxmox-host>:8006/"
proxmox_api_token = "<proxmox-api-token>"
```

Do not replace the placeholders with real credentials in the example
file.

------------------------------------------------------------------------

# Infrastructure Boundaries

The Proxmox layer is responsible for providing the **virtualization
foundation**.

``` text
┌─────────────────────────────────────────────┐
│                  Homelab                    │
├─────────────────────────────────────────────┤
│                                             │
│  Proxmox / OpenTofu                         │
│      │                                      │
│      ├── VM lifecycle                       │
│      ├── VM CPU / memory                    │
│      ├── VM disks                           │
│      ├── VM networking                      │
│      └── physical disk attachment           │
│                                             │
│              ↓                              │
│                                             │
│  Talos Linux                                │
│      │                                      │
│      └── Kubernetes nodes                   │
│                                             │
│              ↓                              │
│                                             │
│  Kubernetes                                 │
│      ├── Infrastructure                     │
│      ├── Platform services                  │
│      └── Applications                       │
│                                             │
└─────────────────────────────────────────────┘
```

OpenTofu does **not** currently configure the Kubernetes resources in
this directory.

Kubernetes resources are maintained under:

``` text
kubernetes/
```

Talos machine configuration is maintained under:

``` text
talos/
```

This separation keeps the virtualization, operating-system, and
Kubernetes layers independently manageable.

------------------------------------------------------------------------

# Relationship to Talos and Kubernetes

The infrastructure stack is layered:

``` text
                    Git Repository
                          │
             ┌────────────┴────────────┐
             │                         │
         OpenTofu                    Talos
             │                         │
             ▼                         ▼
         Proxmox VMs          Talos machine configuration
             │                         │
             └────────────┬────────────┘
                          ▼
                     Kubernetes
                          │
             ┌────────────┼────────────┐
             ▼            ▼            ▼
        Infrastructure  Platform   Applications
```

The responsibilities are intentionally separated:

  Layer        Responsibility
  ------------ ----------------------------------
  OpenTofu     Proxmox VM infrastructure
  Proxmox      Virtualization
  Talos        Kubernetes node operating system
  Kubernetes   Container orchestration
  Argo CD      GitOps reconciliation
  Helm         Application packaging

------------------------------------------------------------------------

# Troubleshooting

## OpenTofu cannot connect to Proxmox

Check:

``` bash
tofu plan
```

Verify:

-   Proxmox API endpoint
-   API token
-   network connectivity
-   Proxmox API availability
-   TLS configuration

The provider currently uses:

``` hcl
insecure = true
```

so certificate verification is disabled.

------------------------------------------------------------------------

## VM already exists

If OpenTofu reports that a VM already exists but is not present in
state, inspect the Proxmox VM and OpenTofu state before making changes.

Useful commands:

``` bash
tofu state list
tofu plan
```

Do not blindly recreate an existing VM.

------------------------------------------------------------------------

## Unexpected infrastructure changes

Always inspect:

``` bash
tofu plan
```

before applying.

If the plan proposes destroying or recreating an important VM, stop and
determine why before running:

``` bash
tofu apply
```

For this homelab, this is particularly important for:

-   the NAS VM
-   the physical disk attachment
-   Kubernetes control-plane VM
-   Kubernetes worker VMs

------------------------------------------------------------------------

# Useful Commands

From `proxmox/`:

``` bash
tofu init
tofu fmt
tofu fmt -check
tofu validate
tofu plan
tofu apply
tofu state list
```

Inspect the current OpenTofu state:

``` bash
tofu show
```

List managed resources:

``` bash
tofu state list
```

------------------------------------------------------------------------

# Design Principles

The Proxmox layer follows these principles:

### 1. Infrastructure as Code

Proxmox VM configuration is represented declaratively in OpenTofu rather
than relying exclusively on manual VM creation.

### 2. Reproducibility

VM characteristics such as:

-   VM IDs
-   node placement
-   CPU
-   memory
-   disks
-   network bridge
-   MAC addresses

are explicitly represented in configuration.

### 3. Separation of Layers

Proxmox infrastructure, Talos configuration, and Kubernetes resources
are maintained separately.

### 4. Review Before Apply

Infrastructure changes should be inspected through:

``` bash
tofu plan
```

before applying them.

### 5. Minimize Manual Configuration

Where practical, infrastructure changes should be represented in Git and
applied through OpenTofu.

