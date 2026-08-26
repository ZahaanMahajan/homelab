Absolutely. Below is a README based on what we **actually implemented**, including the Proxmox VM design, physical HDD passthrough, OMV installation, single-disk filesystem, NFS configuration, permissions issue, and final validation.

# NAS Setup — OpenMediaVault on Proxmox

This document describes the complete setup of the homelab NAS using **OpenMediaVault (OMV)** running as a virtual machine on **Proxmox `pve-i3`**.

The NAS is intended to provide **NFS-backed persistent storage to the Kubernetes cluster**. Kubernetes CSI integration is a separate phase and is not covered as an implemented component here.

---

## 1. Architecture

The final NAS architecture is:

```text
                         Proxmox pve-i3
                              │
                 ┌────────────┼────────────┐
                 │            │            │
                 ▼            ▼            ▼
             worker-01    worker-02      nas VM
                                             │
                                             │ physical HDD
                                             ▼
                                  ST1000DM003-1SB102
                                     931.5 GiB
                                             │
                                             ▼
                                         /dev/sdb
                                             │
                                             ▼
                                         /dev/sdb1
                                             │
                                             ▼
                                            EXT4
                                             │
                                             ▼
                                      OMV Shared Folder
                                         "kubernetes"
                                             │
                                             ▼
                                            NFS
                                             │
                                             ▼
                                      Kubernetes cluster
```

The important architectural separation is:

```text
Proxmox
    ↓
Virtualization

OpenMediaVault
    ↓
NAS / storage management

EXT4
    ↓
Filesystem

NFS
    ↓
Network storage protocol

Kubernetes NFS CSI
    ↓
Kubernetes storage integration
```

---

# 2. Host Environment

The NAS VM is hosted on:

```text
Proxmox node: pve-i3
IP:           192.168.29.3
```

Host hardware:

```text
CPU:
Intel Core i3-9100F
4 physical cores

RAM:
16 GiB
```

Existing Kubernetes VMs:

```text
VMID 102
worker-01
1 vCPU
4 GiB RAM
32 GiB disk

VMID 103
worker-02
1 vCPU
4 GiB RAM
32 GiB disk
```

The NAS VM was intentionally kept lightweight so that the existing Kubernetes workers could continue running without resource changes.

---

# 3. NAS VM

The NAS VM is:

```text
VMID: 104
Name: nas
```

VM configuration:

```text
CPU:
2 vCPU

RAM:
4 GiB

Boot disk:
32 GiB

Network:
vmbr0

Data disk:
Physical 1 TB HDD
```

The VM has two storage devices:

```text
scsi0
    ↓
32 GiB virtual disk
    ↓
local-lvm
    ↓
NVMe SSD
    ↓
OMV operating system


scsi1
    ↓
Physical HDD
    ↓
ST1000DM003-1SB102
    ↓
931.5 GiB
    ↓
NAS data
```

---

# 4. Why the Boot Disk and Data Disk Are Separate

The OMV operating system is installed on a small virtual disk backed by the Proxmox NVMe.

The 1 TB HDD is dedicated to NAS data.

```text
NVMe SSD
   │
   └── local-lvm
          │
          └── OMV boot disk
               32 GiB


1 TB HDD
   │
   └── physical passthrough
          │
          └── OMV data storage
```

This prevents the NAS data from being stored inside Proxmox's `local-lvm`.

---

# 5. Physical HDD Identification

The dedicated NAS HDD was identified on `pve-i3` using:

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL,SERIAL
```

The disk was:

```text
Device: /dev/sda
Size:   931.5 GiB
Model:  ST1000DM003-1SB102
Serial: ZN14TJN6
```

Initially the disk contained:

```text
/dev/sda1    500.6G    NTFS
/dev/sda2    430.9G    NTFS
```

The user confirmed that the disk contained no required data.

---

# 6. Disk Safety

The disk was identified using its persistent Proxmox disk-by-ID path rather than relying only on `/dev/sda`.

Persistent path:

```text
/dev/disk/by-id/ata-ST1000DM003-1SB102_ZN14TJN6
```

Verification:

```bash
ls -l /dev/disk/by-id/ | grep ZN14TJN6
```

Result:

```text
ata-ST1000DM003-1SB102_ZN14TJN6 -> ../../sda
```

This is safer than relying exclusively on `/dev/sda`, because Linux device names can change after reboots or hardware changes.

---

# 7. Physical HDD Passthrough to OMV

The physical HDD was attached directly to VM 104.

Command used:

```bash
qm set 104 --scsi1 /dev/disk/by-id/ata-ST1000DM003-1SB102_ZN14TJN6
```

The resulting VM configuration contained:

```text
scsi0: local-lvm:vm-104-disk-0,iothread=1,size=32G

scsi1: /dev/disk/by-id/ata-ST1000DM003-1SB102_ZN14TJN6,size=976762584K
```

Therefore:

```text
scsi0 → OMV system disk
scsi1 → physical 1 TB HDD
```

The physical HDD was **not** added as a normal Proxmox virtual disk.

---

# 8. OMV Installation

OpenMediaVault was installed on VM 104.

The installation ISO used was:

```text
openmediavault_8.3.1-amd64.iso
```

During installation:

```text
32 GiB disk → OMV operating system
1 TB disk   → left untouched
```

The OMV hostname was configured as:

```text
nas
```

The domain was configured as:

```text
zahaan.online
```

Resulting hostname/FQDN:

```text
nas.zahaan.online
```

The NAS remains private because the domain name itself does not expose the system to the Internet. Access remains restricted to the homelab network.

---

# 9. OMV Network Configuration

OMV received the following LAN address:

```text
IP:
192.168.29.223

Interface:
ens18

Network:
192.168.29.0/24

Gateway:
192.168.29.1
```

Verification:

```bash
ip -br addr
```

Result:

```text
ens18    UP    192.168.29.223/24
```

Routing:

```text
default via 192.168.29.1
192.168.29.0/24 dev ens18
```

The OMV VM is connected to:

```text
vmbr0
```

and therefore exists as a normal LAN host.

---

# 10. OMV Web UI

The OMV Web UI administrator account is:

```text
Username:
admin
```

The administrator password was configured during the installation/recovery process.

The `root` Linux password and the OMV Web UI `admin` password are separate credentials.

---

# 11. Web UI Authentication Issue

Initially, the Web UI returned:

```text
Bad Request
Incorrect username or password
```

The OMV engine was checked:

```bash
systemctl status openmediavault-engined --no-pager
```

The service was healthy:

```text
Active: active (running)
```

The logs showed:

```text
pam_faillock(openmediavault:auth):
Consecutive login failures for user admin account temporarily locked
```

The administrator password was reset using:

```bash
omv-firstaid
```

The relevant OMV first-aid option was:

```text
Change Workbench administrator password
```

The failed-login counter was then reset using:

```text
Reset failed login attempt counter
```

After that, Web UI login succeeded.

---

# 12. Data Disk Preparation

The 1 TB HDD was visible inside OMV as:

```text
/dev/sdb
931.51 GiB
```

The device name changed from:

```text
/dev/sda
```

on the Proxmox host to:

```text
/dev/sdb
```

inside the OMV VM.

This is normal because the disk is now being presented through the VM.

The disk was verified before destruction using its known identity:

```text
ST1000DM003-1SB102
Serial: ZN14TJN6
```

---

# 13. Destructive Disk Operation

The existing two partitions were removed because the disk contained no required data.

Original layout:

```text
/dev/sdb
├── sdb1
│   └── ~500.6 GiB NTFS
│
└── sdb2
    └── ~430.9 GiB NTFS
```

The disk was wiped through the OMV Web UI.

The final intended layout was:

```text
/dev/sdb
└── /dev/sdb1
      │
      └── ~931.5 GiB
```

This creates a simple single-filesystem NAS data disk.

---

# 14. Filesystem

An `EXT4` filesystem was created using the OMV Web UI.

Final storage layout:

```text
Physical HDD
    ↓
/dev/sdb
    ↓
/dev/sdb1
    ↓
EXT4
```

The filesystem was mounted by OMV.

The resulting mount was visible as:

```text
/dev/sdb1
```

and was confirmed writable:

```text
rw,relatime
```

---

# 15. Kubernetes Shared Folder

A dedicated OMV Shared Folder was created:

```text
kubernetes
```

The storage hierarchy is:

```text
/dev/sdb1
    │
    └── kubernetes/
```

This keeps Kubernetes storage logically separated from any future general NAS storage.

The intention is:

```text
1 TB HDD
   ↓
EXT4
   ↓
kubernetes shared folder
   ↓
NFS
   ↓
Kubernetes
```

---

# 16. NFS Configuration

NFS was enabled through:

```text
Services → NFS
```

Supported NFS versions were configured as:

```text
NFSv2    disabled
NFSv3    enabled
NFSv4    enabled
NFSv4.1  enabled
NFSv4.2  enabled
```

For Kubernetes testing, NFSv4.1 was selected.

---

# 17. NFS Export

The `kubernetes` shared folder was exported through NFS.

Client network:

```text
192.168.29.0/24
```

Permission:

```text
Read/Write
```

The export was therefore restricted to the homelab LAN.

The exported path reported by OMV was:

```text
/export/kubernetes
```

The NFS server IP was:

```text
192.168.29.223
```

---

# 18. NFS Export Configuration

The generated export was eventually configured as:

```text
/export/kubernetes
192.168.29.0/24
rw
insecure
no_root_squash
```

Verified with:

```bash
exportfs -v
```

Result:

```text
/export/kubernetes
    192.168.29.0/24(
        sync,
        wdelay,
        hide,
        fsid=...,
        sec=sys,
        rw,
        insecure,
        no_root_squash,
        no_all_squash
    )
```

The parent `/export` remained:

```text
ro
root_squash
```

The Kubernetes client uses the specific:

```text
/export/kubernetes
```

export.

---

# 19. Why `no_root_squash` Was Required for This Export

Initially the NFS export used:

```text
root_squash
```

When the client accessed the NFS export as root, NFS mapped the remote root identity to:

```text
nobody:nogroup
```

UID/GID:

```text
65534:65534
```

The shared folder initially had:

```text
root:users
2775
```

Therefore the squashed `nobody` identity could not write to the directory.

The test confirmed:

```bash
sudo -u nobody touch /export/kubernetes/test-direct.txt
```

returned:

```text
Permission denied
```

The export was therefore changed to:

```text
no_root_squash
```

This allowed root from an authorized NFS client to retain root privileges on this dedicated Kubernetes export.

### Security consideration

`no_root_squash` has security implications.

It means:

```text
root on authorized NFS client
        ↓
root on this NFS export
```

Therefore:

* The export is restricted to `192.168.29.0/24`.
* It is dedicated to Kubernetes storage.
* NFS is not exposed to the Internet.
* It should not be reused for general personal files.

A future hardened configuration can restrict the export further to only the Kubernetes node IPs.

---

# 20. NFS Connectivity Test

NFS availability was first tested locally.

Export discovery:

```bash
showmount -e 192.168.29.223
```

Result:

```text
Export list for 192.168.29.223:
/export            192.168.29.0/24
/export/kubernetes 192.168.29.0/24
```

NFS port connectivity:

```bash
nc -zv 192.168.29.223 2049
```

Result:

```text
Connection to 192.168.29.223 2049 port [tcp/nfs] succeeded!
```

This verified that the NFS server was listening and reachable.

---

# 21. NFSv4.1 Mount Test

The NFS share was mounted using:

```bash
mount -t nfs4 -o vers=4.1 192.168.29.223:/kubernetes /mnt/nas-test
```

The resulting mount was:

```text
192.168.29.223:/kubernetes
    on /mnt/nas-test
    type nfs4
    vers=4.1
```

---

# 22. Read/Write Validation

A write test was performed:

```bash
echo "NFS test from OMV" > /mnt/nas-test/test.txt
```

The file was then read:

```bash
cat /mnt/nas-test/test.txt
```

Result:

```text
NFS test from OMV
```

The file was successfully created:

```text
-rw-r--r-- 1 root users 18 ... test.txt
```

This proved:

```text
NFS mount
    ↓
Read
    ✓

NFS mount
    ↓
Write
    ✓
```

---

# 23. External NFS Validation

The final test was performed from outside the NAS VM using the Proxmox host:

```text
pve-i3
```

The NFS share was mounted:

```bash
mount -t nfs4 -o vers=4.1 192.168.29.223:/kubernetes /mnt/nas-test
```

Then a file was written:

```bash
echo "NFS test from pve-i3" > /mnt/nas-test/test.txt
```

The file was successfully read:

```bash
cat /mnt/nas-test/test.txt
```

Result:

```text
NFS test from pve-i3
```

This validated the complete path:

```text
pve-i3
   │
   │ NFSv4.1
   ▼
OMV
192.168.29.223
   │
   ▼
/export/kubernetes
   │
   ▼
/dev/sdb1
   │
   ▼
1 TB HDD
```

Both read and write operations succeeded.

---

# 24. Final NAS Storage Stack

The current storage stack is:

```text
Physical HDD
ST1000DM003-1SB102
931.5 GiB
      │
      ▼
Proxmox physical disk passthrough
      │
      ▼
OMV VM
      │
      ▼
/dev/sdb
      │
      ▼
/dev/sdb1
      │
      ▼
EXT4
      │
      ▼
OMV Shared Folder
"kubernetes"
      │
      ▼
NFS
      │
      ▼
192.168.29.223:/kubernetes
```

---

# 25. Current NAS Network

```text
OMV NAS:
192.168.29.223

Network:
192.168.29.0/24

Gateway:
192.168.29.1

Interface:
ens18

Proxmox bridge:
vmbr0
```

The NFS export is restricted to:

```text
192.168.29.0/24
```

---

# 26. Security Boundaries

The NAS is intended to remain an internal infrastructure service.

Do not expose:

```text
OMV Web UI
NFS
SSH
```

to the Internet.

The storage architecture does not use:

```text
MetalLB
Traefik
Ingress
cert-manager
Cloudflare
```

The correct path is:

```text
Kubernetes node
      │
      │ LAN
      ▼
OMV NAS
      │
      ▼
NFS
      │
      ▼
HDD
```

Storage traffic is infrastructure traffic, not application HTTP traffic.

---

# 27. Important Limitation

The NAS currently has only:

```text
1 physical HDD
```

Therefore there is:

```text
NO disk redundancy
```

The architecture is:

```text
1 HDD
 ↓
EXT4
 ↓
NFS
```

If the HDD fails:

```text
HDD failure
    ↓
NAS storage unavailable
    ↓
NFS unavailable
    ↓
Kubernetes persistent storage unavailable
```

There is currently no RAID, mirror, or redundant storage device.

---

# 28. NAS Is Not a Backup

The following should not be confused:

```text
NAS ≠ Backup

NFS ≠ Backup

Filesystem ≠ Backup

Disk ≠ Backup
```

The current NAS provides persistent network storage, but it does not protect against physical HDD failure.

A future backup architecture should provide an independent copy of important data.

---

# 29. Kubernetes Integration — Next Phase

The NAS is now independently validated.

The next phase is Kubernetes integration:

```text
Kubernetes
    │
    ▼
NFS CSI Driver
    │
    ▼
StorageClass
    │
    ▼
PVC
    │
    ▼
Dynamic PV
    │
    ▼
NFS
    │
    ▼
OMV
    │
    ▼
EXT4
    │
    ▼
1 TB HDD
```

The Kubernetes side will use the current supported NFS CSI driver.

The CSI driver should be verified with:

```bash
kubectl get csidrivers
kubectl get csinodes
```

After installation, dynamic provisioning will be tested with:

```text
PVC
 ↓
StorageClass
 ↓
NFS CSI
 ↓
PV automatically created
 ↓
Pod mounts PVC
```

---

# 30. Dynamic Provisioning Goal

The current NAS is designed to support Kubernetes dynamic provisioning.

### Static provisioning

Previously learned:

```text
Admin
 ↓
PV
 ↓
PVC
```

### Dynamic provisioning

Target architecture:

```text
PVC
 ↓
StorageClass
 ↓
NFS CSI
 ↓
PV automatically created
 ↓
NFS
 ↓
OMV
```

This will be the practical application of the Kubernetes StorageClass and CSI concepts already studied.

---

# 31. RWX Goal

NFS is particularly useful for demonstrating:

```text
ReadWriteMany
```

The target Kubernetes architecture is:

```text
                 PVC
                  │
                  ▼
                 RWX
                  │
       ┌──────────┼──────────┐
       ▼          ▼          ▼
     Pod A      Pod B      Pod C
       │          │          │
       └──────────┼──────────┘
                  ▼
                 NFS
                  │
                  ▼
                 OMV
                  │
                  ▼
                1 TB HDD
```

RWX provides shared filesystem access but does not automatically make an application safe for concurrent writes.

---

# 32. Troubleshooting Model

The storage architecture should be troubleshot layer-by-layer:

```text
Pod
 ↓
PVC
 ↓
PV
 ↓
StorageClass
 ↓
CSI Driver
 ↓
NFS
 ↓
OMV
 ↓
Filesystem
 ↓
Physical disk
```

For example:

```text
Pod cannot mount volume
```

should not immediately be assumed to be a Kubernetes problem.

Possible causes include:

```text
PVC problem
PV problem
CSI problem
NFS unavailable
NFS permissions
OMV unavailable
filesystem problem
physical disk problem
network problem
```

Always identify the failing layer first.

---

# 33. Useful OMV Commands

Check filesystem:

```bash
findmnt
```

Check mounted storage:

```bash
df -h
```

Check NFS exports:

```bash
exportfs -v
```

List NFS exports:

```bash
showmount -e 192.168.29.223
```

Check NFS service:

```bash
systemctl status nfs-server
```

Check OMV engine:

```bash
systemctl status openmediavault-engined
```

Check network:

```bash
ip -br addr
ip route
```

---

# 34. Useful Proxmox Commands

List VMs:

```bash
qm list
```

Inspect NAS VM:

```bash
qm config 104
```

Check Proxmox storage:

```bash
pvesm status
```

Identify physical disks:

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL,SERIAL
```

Identify persistent disk paths:

```bash
ls -l /dev/disk/by-id/
```

The NAS VM's physical disk is identified by:

```text
/dev/disk/by-id/ata-ST1000DM003-1SB102_ZN14TJN6
```

---

# 35. Final VM Configuration

Current conceptual VM configuration:

```text
VMID:
104

Name:
nas

CPU:
2 vCPU

RAM:
4 GiB

Network:
virtio
vmbr0

System disk:
32 GiB
local-lvm
NVMe-backed

Data disk:
Physical HDD
ST1000DM003-1SB102
Serial: ZN14TJN6
~931.5 GiB

Filesystem:
EXT4

NFS:
Enabled

NFS version tested:
4.1

NFS export:
192.168.29.223:/kubernetes
```

---

# 36. Success Criteria

The NAS phase is currently:

```text
[✓] OMV VM created
[✓] OMV installed
[✓] 32 GiB boot disk on NVMe
[✓] Physical 1 TB HDD passed through
[✓] HDD verified before destruction
[✓] HDD wiped
[✓] Single partition created
[✓] EXT4 filesystem created
[✓] Filesystem mounted
[✓] Kubernetes shared folder created
[✓] NFS enabled
[✓] NFSv4.1 tested
[✓] NFS Read/Write configured
[✓] NFS restricted to homelab LAN
[✓] NFS export validated
[✓] NFS write tested
[✓] NFS read tested
[✓] External pve-i3 NFS test completed
[✓] Data successfully written to/read from HDD-backed NFS storage

```
---

# 37. Final Architecture

```text
                         Proxmox Cluster
                              │
                ┌─────────────┴─────────────┐
                │                           │
               pve                        pve-i3
                │                           │
                │                  ┌────────┼────────┐
                │                  │        │        │
                │             worker-01 worker-02  nas
                │                           │        │
                │                           │        ▼
                │                           │    Physical HDD
                │                           │    931.5 GiB
                │                           │        │
                │                           │        ▼
                │                           │       EXT4
                │                           │        │
                │                           │        ▼
                │                           │  kubernetes folder
                │                           │        │
                │                           │        ▼
                │                           │       NFS
                │                           │        │
                └───────────────────────────┼────────┘
                                            │
                                      192.168.29.0/24
                                            │
                                            ▼
                                      Kubernetes
                                            │
                                            ▼
                                         NFS CSI
                                            │
                                            ▼
                                       StorageClass
                                            │
                                            ▼
                                           PVC
                                            │
                                            ▼
                                           PV
                                            │
                                            ▼
                                           Pod
```

---

## Current Status

**NAS layer: COMPLETE**

```text
Proxmox → OMV → Physical HDD → EXT4 → NFS
```

**Kubernetes storage integration: NEXT PHASE**

```text
NFS → NFS CSI → StorageClass → PVC → Dynamic PV → Pod
```

Longhorn is intentionally **not** part of this phase.

