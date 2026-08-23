# Proxmox Homelab Setup

This document records the Proxmox setup completed before starting the
Pi-hole configuration.

## 1. Homelab Goal

The goal is to build a small Proxmox-based homelab that will later host
a Talos Kubernetes cluster and various self-hosted services.

The initial physical setup consists of two machines connected through a
physical Ethernet switch.

``` text
                         LAN
                          |
                       Switch
                    +-----+-----+
                    |           |
              192.168.29.2  192.168.29.3
                  pve         pve-i3
               Ryzen       Intel i3

```


------------------------------------------------------------------------

## 2. Physical Nodes

### Node 1 --- `pve`

  Property         Value
  ---------------- -------------------
  Hostname         `pve`
  IP address       `192.168.29.2`
  CPU              AMD Ryzen 5 5500U
  RAM              8 GB
  Storage          256 GB NVMe SSD
  Proxmox          9.2.2
  Kernel           7.0.2-6-pve
  Network bridge   `vmbr0`
  Gateway          `192.168.29.1`

### Node 2 --- `pve-i3`

  Property         Value
  ---------------- ------------------------
  Hostname         `pve-i3`
  IP address       `192.168.29.3`
  CPU              Intel i3-9100F
  RAM              16 GB
  Storage          512 GB NVMe + 1 TB HDD
  Proxmox          9.2.2
  Kernel           7.0.2-6-pve
  Network bridge   `vmbr0`
  Gateway          `192.168.29.1`

The 1 TB HDD on `pve-i3` was left untouched during the initial Proxmox
and cluster setup.

------------------------------------------------------------------------

## 3. Network Setup

Both machines were connected to the same physical LAN using Ethernet
through a switch.

The network uses:

``` text
Network: 192.168.29.0/24
Gateway: 192.168.29.1
```

The Proxmox hosts use `vmbr0` for their main network connection.

### `pve`

``` text
vmbr0 → 192.168.29.2/24
default gateway → 192.168.29.1
```

### `pve-i3`

``` text
vmbr0 → 192.168.29.3/24
default gateway → 192.168.29.1
```

The two nodes were verified to communicate directly:

``` bash
ping -c 4 192.168.29.3
```

from `pve`, and:

``` bash
ping -c 4 192.168.29.2
```

from `pve-i3`.

Both directions worked with 0% packet loss.

------------------------------------------------------------------------

## 4. Hostname Configuration

The two machines were given unique hostnames:

``` text
pve
pve-i3
```

Verified using:

``` bash
hostnamectl
```

This is important because Proxmox cluster nodes must have unique
hostnames.

------------------------------------------------------------------------

## 5. `/etc/hosts` Configuration

Before creating the cluster, both nodes were configured to resolve both
Proxmox nodes locally.

### `/etc/hosts` on `pve`

``` text
127.0.0.1 localhost.localdomain localhost

192.168.29.2 pve.proxmox.homelab pve
192.168.29.3 pve-i3.hp.homelab pve-i3

# The following lines are desirable for IPv6 capable hosts

::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
ff02::3 ip6-allhosts
```

### `/etc/hosts` on `pve-i3`

``` text
127.0.0.1 localhost.localdomain localhost

192.168.29.2 pve.proxmox.homelab pve
192.168.29.3 pve-i3.hp.homelab pve-i3

# The following lines are desirable for IPv6 capable hosts

::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
ff02::3 ip6-allhosts
```

Name resolution was verified with:

``` bash
getent hosts pve
getent hosts pve-i3
```

Both nodes successfully resolved both hostnames to the correct IP
addresses.

------------------------------------------------------------------------

## 6. Time Synchronization

Cluster communication requires reliable time synchronization.

Both nodes were checked with:

``` bash
timedatectl
```

Both reported:

``` text
System clock synchronized: yes
NTP service: active
Time zone: Asia/Kolkata (IST, +0530)
```

This confirmed that NTP/time synchronization was active before cluster
creation.

------------------------------------------------------------------------

## 7. SSH Connectivity

SSH connectivity was verified in both directions.

From `pve`:

``` bash
ssh root@192.168.29.3
```

From `pve-i3`:

``` bash
ssh root@192.168.29.2
```

Both connections succeeded.

This confirmed that the nodes could communicate over the management
network before cluster creation.

------------------------------------------------------------------------

## 8. Proxmox Version Verification

Both nodes were running the same Proxmox version:

``` bash
pveversion
```

Result:

``` text
pve-manager/9.2.2/b9984c6d90a4bd80
```

Both were also running:

``` text
7.0.2-6-pve
```

Having matching Proxmox versions provided a consistent base for the
cluster.

------------------------------------------------------------------------

## 9. Confirming Both Nodes Were Standalone

Before creating the cluster, `pvecm status` was run on both nodes.

The result was:

``` text
Error: Corosync config '/etc/pve/corosync.conf' does not exist - is this node part of a cluster?
```

This was expected.

It confirmed that neither machine was already part of a Proxmox cluster.

------------------------------------------------------------------------

# 10. Creating the Proxmox Cluster

The first cluster node was created on `pve`.

The cluster name chosen was:

``` text
homelab
```

On `pve`:

``` bash
pvecm create homelab
```

Proxmox generated the Corosync authentication key and cluster
configuration.

Important files/services involved include:

``` text
/etc/corosync/authkey
/etc/pve/corosync.conf
```

After creation, the cluster was verified:

``` bash
pvecm status
```

Initial result:

``` text
Cluster information
-------------------
Name:             homelab
Config Version:   1
Transport:        knet
Secure auth:      on

Quorum information
------------------
Nodes:            1
Node ID:          0x00000001
Quorate:          Yes
```

At this point `pve` was the first and only node in the cluster.

------------------------------------------------------------------------

# 11. Joining `pve-i3` to the Cluster

The second node was then joined to the existing cluster.

On `pve-i3`:

``` bash
pvecm add 192.168.29.2
```

The command established an API connection with `pve`, authenticated
using the root password, and completed the local cluster setup.

The important success message was:

``` text
successfully added node 'pve-i3' to cluster.
```

The join process also automatically selected:

``` text
192.168.29.3
```

as the local cluster network address for `pve-i3`.

------------------------------------------------------------------------

# 12. Final Cluster Verification

The cluster was verified from both nodes.

On `pve`:

``` bash
pvecm status
```

Result:

``` text
Cluster information
-------------------
Name:             homelab
Config Version:   2
Transport:        knet
Secure auth:      on

Quorum information
------------------
Nodes:            2
Node ID:          0x00000001
Quorate:          Yes

Votequorum information
----------------------
Expected votes:   2
Highest expected: 2
Total votes:      2
Quorum:           2
Flags:            Quorate
```

Membership:

``` text
Nodeid      Votes Name
0x00000001     1  192.168.29.2 (local)
0x00000002     1  192.168.29.3
```

On `pve-i3`, the same cluster membership was visible:

``` text
Nodeid      Votes Name
0x00000001     1  192.168.29.2
0x00000002     1  192.168.29.3 (local)
```

The following command was also used:

``` bash
pvecm nodes
```

Final membership:

``` text
Membership information
----------------------
Nodeid      Votes Name
     1         1  pve
     2         1  pve-i3 (local)
```

------------------------------------------------------------------------

# 13. Final Proxmox Cluster Architecture

The completed infrastructure at this stage is:

``` text

                         Home LAN
                       192.168.29.0/24
                              |
                           Switch
                              |
               +--------------+--------------+
               |                             |
               |                             |
        pve - 192.168.29.2            pve-i3 - 192.168.29.3
        Ryzen 5 5500U                  Intel i3-9100F
        8 GB RAM                       16 GB RAM
        256 GB NVMe                    512 GB NVMe
               |                             |
               +--------------+--------------+
                              |
                         Proxmox Cluster
                            homelab
                              |
                         Corosync / KNET

```

Cluster state:

``` text
Cluster name:     homelab
Nodes:            2
Expected votes:   2
Total votes:      2
Quorum:           2
Quorate:          Yes
Transport:        knet
Secure auth:      on
```

------------------------------------------------------------------------

# 14. Current State

At this point:

-   [x] Proxmox installed on both physical machines
-   [x] Unique hostnames configured
-   [x] Static LAN addressing configured
-   [x] Both nodes connected through Ethernet
-   [x] Node-to-node connectivity verified
-   [x] `/etc/hosts` configured on both nodes
-   [x] Hostname resolution verified
-   [x] NTP/time synchronization verified
-   [x] SSH connectivity verified in both directions
-   [x] Matching Proxmox versions verified
-   [x] Both nodes confirmed as standalone before clustering
-   [x] `homelab` Proxmox cluster created
-   [x] `pve-i3` successfully joined the cluster
-   [x] Two-node quorum verified
-   [x] Cluster membership verified from both nodes

## Current Cluster

``` text
homelab
├── pve
│   └── 192.168.29.2
│
└── pve-i3
    └── 192.168.29.3
```

------------------------------------------------------------------------

# 15. Next Phase

The next phase is **networking with Pi-hole**.

Pi-hole will run as a **separate lightweight VM on `pve`**, not inside
Kubernetes.

Planned architecture:

``` text
Proxmox Cluster
      |
      +-- pve
      |    |
      |    +-- Pi-hole VM
      |
      +-- pve-i3
           |
           +-- Future workloads
```

After Pi-hole networking is established, the next major phase will be
Proxmox and Kubernetes storage configuration.

Application deployment and the Talos Kubernetes cluster will be built
incrementally based on actual requirements.
