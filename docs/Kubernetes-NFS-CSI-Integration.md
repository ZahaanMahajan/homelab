# Kubernetes NFS CSI Integration

## Overview

This phase integrates the existing **OpenMediaVault (OMV) NFS storage** into the Talos Kubernetes cluster using the **NFS CSI driver**.

The goal is to move Kubernetes storage from manually created static PVs to **dynamic provisioning** through:

```text
PVC
 ↓
StorageClass
 ↓
NFS CSI Driver
 ↓
NFS
 ↓
OMV NAS
```

The NAS itself was already configured and independently validated before this phase. This document covers **only the Kubernetes-side NFS CSI integration**.

---

## Architecture

```text
                         Kubernetes Cluster
                                │
                                │
                         PersistentVolumeClaim
                                │
                                ▼
                         StorageClass
                         nfs-storage
                                │
                                ▼
                       NFS CSI Driver
                       nfs.csi.k8s.io
                                │
                ┌───────────────┴───────────────┐
                │                               │
                ▼                               ▼
        CSI Controller                    CSI Node Plugin
        talos-controlplane-01            Kubernetes nodes
                                                │
                                                ▼
                                           NFS mount
                                                │
                                                ▼
                                      192.168.29.223:/kubernetes
                                                │
                                                ▼
                                           OMV NAS
```

### Storage path

```text
Pod
 ↓
PVC
 ↓
PV
 ↓
NFS CSI Driver
 ↓
NFSv4.1
 ↓
192.168.29.223:/kubernetes
```

---

# 1. Kubernetes Environment

The Kubernetes cluster used during this phase:

| Component     | Version / Value |
| ------------- | --------------- |
| Kubernetes    | `v1.36.2`       |
| Talos Linux   | `v1.13.8`       |
| Kernel        | `6.18.42-talos` |
| containerd    | `2.2.6`         |
| CNI           | Flannel         |
| Control Plane | `192.168.29.20` |
| Worker 01     | `192.168.29.21` |
| Worker 02     | `192.168.29.22` |

Nodes:

```text
talos-controlplane-01   192.168.29.20
talos-worker-01         192.168.29.21
talos-worker-02         192.168.29.22
```

---

# 2. Existing Kubernetes Storage State

Before the NFS CSI integration, Kubernetes had a manually created static storage experiment:

```text
PV
└── static-pv

PVC
└── static-pvc
```

The existing storage experiment was intentionally preserved.

Initial storage state:

```text
StorageClass
└── None

CSIDriver
└── None

CSINode drivers
└── 0
```

The static PV/PVC was **not modified or deleted** because it provides a useful comparison between static and dynamic provisioning.

---

# 3. Verify Cluster Health

Before installing the CSI driver, the Kubernetes cluster was inspected.

```bash
kubectl get nodes -o wide
```

The cluster was healthy:

```text
talos-controlplane-01   Ready
talos-worker-01         Ready
talos-worker-02         Ready
```

The existing workloads and system components were also checked:

```bash
kubectl get pods -A
```

The cluster was already running:

```text
Flannel
MetalLB
Traefik
cert-manager
```

The NFS integration did not require changes to these components.

---

# 4. Talos NFS Capability Verification

Because the Kubernetes nodes use **Talos Linux**, traditional package-management instructions such as:

```bash
apt install nfs-common
```

were not used.

Instead, the node environment was inspected using `talosctl`.

### Check Talos services

```bash
talosctl service --nodes 192.168.29.21
```

```bash
talosctl service --nodes 192.168.29.22
```

The relevant node services were healthy, including:

```text
containerd   Running   OK
cri          Running   OK
kubelet      Running   OK
```

### Check Talos extensions

```bash
talosctl get extensions --nodes 192.168.29.21
```

```bash
talosctl get extensions --nodes 192.168.29.22
```

No extensions were reported.

### Check kernel filesystem support

The nodes were checked for NFS kernel support:

```bash
talosctl read /proc/filesystems --nodes 192.168.29.21
```

```bash
talosctl read /proc/filesystems --nodes 192.168.29.22
```

Both nodes reported:

```text
nodev   nfs
nodev   nfs4
```

Therefore the Talos kernel provided NFS/NFSv4 filesystem support.

The presence of:

```text
nfs
nfs4
```

confirmed that kernel-level NFS support was available.

---

# 5. NFS Mount Utility Check

The traditional mount helper was checked:

```bash
talosctl read /sbin/mount.nfs --nodes 192.168.29.21
```

and:

```bash
talosctl read /sbin/mount.nfs --nodes 192.168.29.22
```

The file was not present:

```text
error reading: rpc error: code = NotFound desc = stat /sbin/mount.nfs: no such file or directory
```

The important distinction was that Talos already provided kernel NFS support, while the CSI driver itself would provide the required NFS functionality through its node plugin.

No traditional Linux package installation was performed.

---

# 6. NFS CSI Driver

The Kubernetes NFS CSI implementation selected for the integration was:

```text
csi-driver-nfs
```

Driver:

```text
nfs.csi.k8s.io
```

Version installed:

```text
4.13.4
```

The Helm repository was added:

```bash
helm repo add csi-driver-nfs \
  https://kubernetes-csi.github.io/csi-driver-nfs
```

The repository was updated:

```bash
helm repo update csi-driver-nfs
```

Available versions were verified:

```bash
helm search repo csi-driver-nfs --versions
```

The selected version was:

```text
csi-driver-nfs  4.13.4  4.13.4
```

---

# 7. Inspect the Helm Manifest Before Installation

The chart was rendered locally before installation:

```bash
helm template csi-driver-nfs csi-driver-nfs/csi-driver-nfs \
  --namespace kube-system \
  --version 4.13.4 \
  > /tmp/csi-driver-nfs-4.13.4.yaml
```

The rendered Kubernetes resources included:

```text
ServiceAccount
ServiceAccount
ClusterRole
ClusterRole
ClusterRoleBinding
ClusterRoleBinding
DaemonSet
Deployment
CSIDriver
```

The container images were also inspected:

```bash
grep 'image:' /tmp/csi-driver-nfs-4.13.4.yaml
```

The important images included:

```text
registry.k8s.io/sig-storage/nfsplugin:v4.13.4
registry.k8s.io/sig-storage/csi-provisioner:v6.3.0
registry.k8s.io/sig-storage/csi-resizer:v2.2.0
registry.k8s.io/sig-storage/csi-snapshotter:v8.6.0
registry.k8s.io/sig-storage/csi-node-driver-registrar:v2.17.0
registry.k8s.io/sig-storage/livenessprobe:v2.19.0
```

---

# 8. CSI Node Plugin

The chart deploys the CSI node component as a DaemonSet:

```text
csi-nfs-node
```

The node plugin runs on each Linux Kubernetes node.

The relevant architecture is:

```text
Kubernetes Node
      │
      ▼
csi-nfs-node
      │
      ├── liveness-probe
      ├── node-driver-registrar
      └── nfsplugin
```

The NFS plugin runs privileged and has:

```yaml
capabilities:
  add:
    - SYS_ADMIN
```

It also mounts:

```text
/var/lib/kubelet/pods
```

with:

```text
mountPropagation: Bidirectional
```

This allows the CSI node plugin to participate in mounting volumes for Kubernetes Pods.

---

# 9. CSI Controller

The chart also creates:

```text
csi-nfs-controller
```

as a Deployment.

The controller contains the CSI control-plane components:

```text
csi-provisioner
csi-resizer
csi-snapshotter
liveness-probe
nfsplugin
```

The controller is responsible for operations such as dynamic volume provisioning.

The architecture is:

```text
PVC
 │
 ▼
CSI Controller
 │
 ├── csi-provisioner
 ├── csi-resizer
 ├── csi-snapshotter
 └── nfsplugin
```

---

# 10. Install the CSI Driver

The driver was installed using Helm:

```bash
helm install csi-driver-nfs csi-driver-nfs/csi-driver-nfs \
  --namespace kube-system \
  --version 4.13.4
```

Successful installation returned:

```text
NAME: csi-driver-nfs
NAMESPACE: kube-system
STATUS: deployed
REVISION: 1
```

---

# 11. Verify CSIDriver Registration

The CSI driver registration was checked:

```bash
kubectl get csidrivers
```

Result:

```text
NAME
nfs.csi.k8s.io
```

The registered driver reported:

```text
ATTACHREQUIRED: false
MODES: Persistent
```

The driver therefore became visible to Kubernetes as:

```text
nfs.csi.k8s.io
```

---

# 12. Verify CSI Pods

The deployed CSI components were checked:

```bash
kubectl get pods -n kube-system \
  -l app.kubernetes.io/instance=csi-driver-nfs \
  -o wide
```

Final state:

```text
csi-nfs-controller   5/5   Running
csi-nfs-node         3/3   Running
csi-nfs-node         3/3   Running
csi-nfs-node         3/3   Running
```

The node plugin was running on:

```text
talos-controlplane-01
talos-worker-01
talos-worker-02
```

Therefore the CSI node component was available across the Kubernetes cluster.

---

# 13. Verify CSINode Registration

Initially:

```bash
kubectl get csinodes
```

showed:

```text
DRIVERS
0
```

After the CSI node plugins became healthy:

```bash
kubectl get csinodes
```

reported:

```text
talos-controlplane-01   1
talos-worker-01         1
talos-worker-02         1
```

The detailed CSINode objects contained:

```yaml
drivers:
  - name: nfs.csi.k8s.io
    nodeID: talos-worker-01
```

and corresponding entries for the other nodes.

This verified that Kubernetes recognized the NFS CSI driver on each node.

---

# 14. CSIDriver vs CSINode

### CSIDriver

```text
CSIDriver
    =
cluster-level registration of the CSI driver
```

The installed object was:

```text
nfs.csi.k8s.io
```

It described capabilities such as:

```text
attachRequired: false
volumeLifecycleModes:
  - Persistent
fsGroupPolicy:
  File
```

### CSINode

```text
CSINode
    =
node-level registration of CSI drivers
```

Each Kubernetes node registered:

```text
nfs.csi.k8s.io
```

Therefore:

```text
CSIDriver
    ↓
"What is this CSI driver?"

CSINode
    ↓
"Which CSI drivers are available on this node?"
```

---

# 15. Create the NFS StorageClass

A dedicated StorageClass was created:

```text
nfs-storage
```

File:

```text
kubernetes/storage/storage-classes/nfs-storage.yaml
```

Configuration:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass

metadata:
  name: nfs-storage

provisioner: nfs.csi.k8s.io

parameters:
  server: 192.168.29.223
  share: /kubernetes

reclaimPolicy: Delete
volumeBindingMode: Immediate
allowVolumeExpansion: true

mountOptions:
  - nfsvers=4.1
```

---

# 16. Validate the StorageClass Before Applying

The manifest was validated using server-side dry run:

```bash
kubectl apply --dry-run=server \
  -f kubernetes/storage/storage-classes/nfs-storage.yaml
```

Result:

```text
storageclass.storage.k8s.io/nfs-storage created (server dry run)
```

The resource was then applied:

```bash
kubectl apply \
  -f kubernetes/storage/storage-classes/nfs-storage.yaml
```

---

# 17. StorageClass Verification

The StorageClass was verified:

```bash
kubectl get storageclass
```

Result:

```text
NAME          PROVISIONER      RECLAIMPOLICY   VOLUMEBINDINGMODE
nfs-storage   nfs.csi.k8s.io   Delete          Immediate
```

Detailed inspection:

```bash
kubectl describe storageclass nfs-storage
```

Confirmed:

```text
Provisioner:
nfs.csi.k8s.io
```

```text
Parameters:
server=192.168.29.223
share=/kubernetes
```

```text
MountOptions:
nfsvers=4.1
```

```text
ReclaimPolicy:
Delete
```

```text
VolumeBindingMode:
Immediate
```

```text
AllowVolumeExpansion:
True
```

---

# 18. StorageClass Configuration Explained

### `provisioner`

```yaml
provisioner: nfs.csi.k8s.io
```

Tells Kubernetes which CSI driver should handle provisioning requests.

---

### `server`

```yaml
server: 192.168.29.223
```

The NFS server address.

---

### `share`

```yaml
share: /kubernetes
```

The NFS storage export used by Kubernetes.

The Kubernetes storage path therefore becomes:

```text
192.168.29.223:/kubernetes
```

---

### `mountOptions`

```yaml
mountOptions:
  - nfsvers=4.1
```

Requests NFS version 4.1 when mounting the storage.

---

### `reclaimPolicy`

```yaml
reclaimPolicy: Delete
```

Dynamically provisioned volumes using this StorageClass are configured to use the `Delete` reclaim policy.

---

### `volumeBindingMode`

```yaml
volumeBindingMode: Immediate
```

The volume is provisioned immediately after the PVC requests storage.

---

### `allowVolumeExpansion`

```yaml
allowVolumeExpansion: true
```

Allows supported PVC expansion through the StorageClass.

---

# 19. Dynamic PVC

A test PVC was created:

```text
nfs-test-pvc
```

File:

```text
kubernetes/storage/persistent-volume-claims/nfs-test-pvc.yaml
```

The PVC requested:

```text
StorageClass:
nfs-storage
```

```text
Capacity:
1Gi
```

```text
Access Mode:
ReadWriteOnce
```

The manifest was first validated:

```bash
kubectl apply --dry-run=server \
  -f kubernetes/storage/persistent-volume-claims/nfs-test-pvc.yaml
```

Result:

```text
persistentvolumeclaim/nfs-test-pvc created (server dry run)
```

The PVC was then created:

```bash
kubectl apply \
  -f kubernetes/storage/persistent-volume-claims/nfs-test-pvc.yaml
```

---

# 20. Dynamic Provisioning

The PVC immediately became:

```text
Bound
```

```bash
kubectl get pvc nfs-test-pvc
```

Result:

```text
NAME           STATUS   VOLUME
nfs-test-pvc   Bound    pvc-722326ca-489b-43c2-9fbb-9fc79d1cedc3
```

Kubernetes automatically created:

```text
PV:
pvc-722326ca-489b-43c2-9fbb-9fc79d1cedc3
```

This demonstrated **dynamic provisioning**.

The workflow was:

```text
PVC
 ↓
StorageClass
 ↓
NFS CSI Controller
 ↓
PV automatically created
 ↓
NFS directory automatically created
```

No static PV was manually created for this test.

---

# 21. Verify the Dynamically Created PV

The dynamically created PV was inspected:

```bash
kubectl describe pv \
  pvc-722326ca-489b-43c2-9fbb-9fc79d1cedc3
```

Important fields included:

```text
StorageClass:
nfs-storage
```

```text
Reclaim Policy:
Delete
```

```text
Access Modes:
RWO
```

```text
Driver:
nfs.csi.k8s.io
```

```text
ReadOnly:
false
```

The PV also contained:

```text
server=192.168.29.223
share=/kubernetes
```

and:

```text
subdir=pvc-722326ca-489b-43c2-9fbb-9fc79d1cedc3
```

---

# 22. NFS Directory Created by CSI

The CSI driver dynamically created a directory under the NFS export.

On OMV:

```bash
ls -lah /export/kubernetes
```

The resulting directory was:

```text
pvc-722326ca-489b-43c2-9fbb-9fc79d1cedc3
```

The relationship was:

```text
Kubernetes PVC
nfs-test-pvc
        │
        ▼
Kubernetes PV
pvc-722326ca-489b-43c2-9fbb-9fc79d1cedc3
        │
        ▼
NFS subdirectory
pvc-722326ca-489b-43c2-9fbb-9fc79d1cedc3
        │
        ▼
192.168.29.223:/kubernetes
```

The directory was created by the CSI provisioning process rather than manually.

---

# 23. Test Pod

A test Pod was created:

```text
nfs-test-pod
```

File:

```text
kubernetes/storage/nfs-test-pod.yaml
```

The Pod mounted:

```text
nfs-test-pvc
```

at:

```text
/mnt/data
```

The Pod was validated using:

```bash
kubectl apply --dry-run=server \
  -f kubernetes/storage/nfs-test-pod.yaml
```

Then applied:

```bash
kubectl apply \
  -f kubernetes/storage/nfs-test-pod.yaml
```

---

# 24. Verify the NFS Volume Mount

The Pod became:

```text
Running
```

and was scheduled on:

```text
talos-worker-01
```

The Pod description showed:

```text
/mnt/data from nfs-storage (rw)
```

The container successfully executed:

```text
echo "Hello from Kubernetes NFS CSI" > /mnt/data/test.txt
```

---

# 25. Verify Data From the Pod

The file was read from inside the Pod:

```bash
kubectl exec nfs-test-pod -- \
  cat /mnt/data/test.txt
```

Output:

```text
Hello from Kubernetes NFS CSI
```

The mounted filesystem was also inspected:

```bash
kubectl exec nfs-test-pod -- \
  ls -lah /mnt/data
```

The file was present:

```text
test.txt
```

This verified:

```text
Pod
 ↓
PVC
 ↓
PV
 ↓
NFS CSI
 ↓
NFS
```

was operational.

---

# 26. Persistence Test

The Pod was deleted:

```bash
kubectl delete pod nfs-test-pod
```

The Pod disappeared:

```text
pods "nfs-test-pod" not found
```

The PVC remained:

```bash
kubectl get pvc nfs-test-pvc
```

Result:

```text
STATUS: Bound
```

The PV also remained:

```bash
kubectl get pv \
  pvc-722326ca-489b-43c2-9fbb-9fc79d1cedc3
```

Result:

```text
STATUS: Bound
```

The test Pod was then recreated:

```bash
kubectl apply \
  -f kubernetes/storage/nfs-test-pod.yaml
```

The original file was read again:

```bash
kubectl exec nfs-test-pod -- \
  cat /mnt/data/test.txt
```

Output:

```text
Hello from Kubernetes NFS CSI
```

---

# 27. Persistence Result

The persistence test proved that the data was not stored in the Pod's ephemeral container filesystem.

The actual storage path was:

```text
Pod
 ↓
PVC
 ↓
PV
 ↓
NFS CSI
 ↓
NFS subdirectory
 ↓
OMV filesystem
```

After:

```text
Pod A
 ↓
writes data
 ↓
Pod deleted
```

the data remained available to:

```text
Pod B
 ↓
same PVC
 ↓
same PV
 ↓
same NFS directory
```

Therefore:

```text
[✓] Dynamic provisioning
[✓] NFS-backed PV
[✓] Pod storage mount
[✓] Read/write access
[✓] Data persistence
[✓] Pod recreation
```

---

# 28. Final Kubernetes NFS Architecture

The completed Kubernetes-side architecture is:

```text
                    Kubernetes Cluster
                           │
                           ▼
                         PVC
                    nfs-test-pvc
                           │
                           ▼
                     StorageClass
                      nfs-storage
                           │
                           ▼
                    nfs.csi.k8s.io
                           │
              ┌────────────┴────────────┐
              │                         │
              ▼                         ▼
       CSI Controller              CSI Node Plugin
              │                         │
              │                   Kubernetes nodes
              │                         │
              └────────────┬────────────┘
                           │
                           ▼
                        NFSv4.1
                           │
                           ▼
                  192.168.29.223:/kubernetes
                           │
                           ▼
                       OMV NAS
                           │
                           ▼
                     NFS subdirectory
                           │
                           ▼
                         EXT4
```

---

# 29. Static vs Dynamic Provisioning

The homelab now contains both approaches for learning purposes.

### Static provisioning

```text
Administrator
    │
    ├── creates PV
    ├── creates PVC
    └── Pod consumes PVC
```

Existing example:

```text
static-pv
static-pvc
```

### Dynamic provisioning

```text
Administrator
    │
    ▼
StorageClass
    │
    ▼
Application creates PVC
    │
    ▼
CSI driver provisions PV
    │
    ▼
NFS directory created
    │
    ▼
Pod consumes PVC
```

Current example:

```text
nfs-storage
nfs-test-pvc
pvc-722326ca-489b-43c2-9fbb-9fc79d1cedc3
```

---

# 30. Validation Summary

The following Kubernetes NFS CSI components were successfully validated:

```text
[✓] Kubernetes cluster healthy
[✓] Talos NFS kernel support verified
[✓] csi-driver-nfs repository configured
[✓] csi-driver-nfs v4.13.4 installed
[✓] CSI controller running
[✓] CSI node plugin running on all nodes
[✓] CSIDriver registered
[✓] CSINode registration completed
[✓] nfs-storage StorageClass created
[✓] NFSv4.1 mount option configured
[✓] Dynamic PVC provisioning
[✓] Dynamic PV creation
[✓] NFS directory creation
[✓] Pod successfully mounted PVC
[✓] Pod successfully wrote data
[✓] Pod successfully read data
[✓] Pod deletion tested
[✓] Pod recreation tested
[✓] Data persistence verified
```

---

# 31. Result

The Kubernetes cluster can now dynamically consume the existing OMV NFS storage through the CSI architecture:

```text
Application
     │
     ▼
    PVC
     │
     ▼
StorageClass
     │
     ▼
NFS CSI Driver
     │
     ▼
     PV
     │
     ▼
NFSv4.1
     │
     ▼
192.168.29.223:/kubernetes
     │
     ▼
OMV
```

The NFS/CSI integration phase is therefore **complete and validated**.

