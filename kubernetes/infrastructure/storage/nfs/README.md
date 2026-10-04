# Kubernetes NFS CSI Integration

## Overview

This phase integrates the existing OpenMediaVault (OMV) NFS share with the Talos Kubernetes cluster using the Kubernetes NFS CSI driver.

The objective is to enable Kubernetes workloads to request persistent storage dynamically and access shared storage across worker nodes.

This documentation covers **only the Kubernetes NFS CSI integration and its validation**. It does not cover the NAS VM installation or NFS server configuration.

## Objectives

* Deploy the Kubernetes NFS CSI driver.
* Configure a Kubernetes StorageClass for dynamic NFS provisioning.
* Create a PersistentVolumeClaim (PVC).
* Verify dynamic PersistentVolume (PV) provisioning.
* Mount the claim in a Kubernetes Pod.
* Validate writing and reading data.
* Validate cross-worker read access.
* Verify data remains accessible after deleting the original writer Pod.
* Clean up temporary test Pods without deleting persistent storage.

## Environment

| Component               | Configuration     |
| ----------------------- | ----------------- |
| Kubernetes distribution | Talos Linux       |
| Kubernetes version      | v1.36.2           |
| Talos version           | v1.13.8           |
| Container runtime       | containerd 2.2.6  |
| CNI                     | Flannel           |
| Worker 1                | `talos-worker-01` |
| Worker 1 IP             | `192.168.29.21`   |
| Worker 2                | `talos-worker-02` |
| Worker 2 IP             | `192.168.29.22`   |
| NAS server              | `192.168.29.50`   |
| NFS share path          | `/kubernetes`     |
| CSI driver              | `nfs.csi.k8s.io`  |
| CSI driver version      | 4.13.4            |
| StorageClass            | `nfs-storage`     |
| NFS protocol version    | NFSv4.1           |

## Architecture

```text
                  Kubernetes Cluster
             Kubernetes v1.36.2 / Talos
                          |
                NFS CSI Driver
                 nfs.csi.k8s.io
                          |
                  StorageClass
                   nfs-storage
                          |
                PersistentVolumeClaim
                    nfs-test-pvc
                          |
                 PersistentVolume
                          |
             NFS server: 192.168.29.50
                  Share: /kubernetes
                          |
                  OMV NAS storage
```

### RUN THIS COMMAND TO INSTALL AND UNINSTALL CSI DRIVER 

``` bash
curl -skSL https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/v4.13.4/deploy/install-driver.sh | bash -s v4.13.4 --
```

```bash
curl -skSL https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/v4.13.4/deploy/uninstall-driver.sh | bash -s v4.13.4 --
```


The CSI driver dynamically provisions a directory on the existing NFS share for the PVC. Kubernetes represents the provisioned storage using a PersistentVolume.

The same RWX claim can be mounted by workloads scheduled on different worker nodes, subject to the NFS server and filesystem permissions.

## 1. Verify the CSI Driver

Check the CSI-related resources:

```bash
kubectl get csidriver
kubectl get pods -n kube-system
```

The NFS CSI driver is installed in `kube-system`.

Driver name:

```text
nfs.csi.k8s.io
```

Installed version:

```text
4.13.4
```

## 2. StorageClass

The StorageClass is named `nfs-storage`.

Inspect its live configuration:

```bash
kubectl get storageclass nfs-storage -o yaml
```

Important configuration observed:

| Setting             | Value            |
| ------------------- | ---------------- |
| Provisioner         | `nfs.csi.k8s.io` |
| NFS server          | `192.168.29.50`  |
| NFS share           | `/kubernetes`    |
| NFS version         | `4.1`            |
| Reclaim policy      | `Delete`         |
| Volume binding mode | `Immediate`      |
| Volume expansion    | Enabled          |

The `Delete` reclaim policy is important: deleting a PVC can cause its dynamically provisioned PV and backing directory to be removed. Do not delete the test PVC or PV casually.

## 3. PersistentVolumeClaim

Manifest location:

```text
kubernetes/storage/persistent-volume-claims/nfs-test-pvc.yaml
```

Manifest:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nfs-test-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: nfs-storage
  resources:
    requests:
      storage: 1Gi
```

Apply the manifest when creating the test claim:

```bash
kubectl apply -f kubernetes/storage/persistent-volume-claims/nfs-test-pvc.yaml
```

Check the claim:

```bash
kubectl get pvc nfs-test-pvc -n default
```

Expected state:

```text
STATUS: Bound
ACCESS MODES: RWX
STORAGECLASS: nfs-storage
```

### Access mode

The manifest specifies `ReadWriteMany` (RWX), allowing the claim to be mounted read-write by multiple nodes.

The manifest originally specified `ReadWriteOnce`. It was corrected to `ReadWriteMany` to match the live claim and the intended shared-storage test.

## 4. Verify Dynamic Provisioning

Inspect the PVC and its bound PV:

```bash
kubectl get pvc nfs-test-pvc -n default
kubectl get pv
```

The test PVC was bound to:

```text
pvc-f88753e5-78cc-4909-bc65-d8d4559e6e3c
```

Inspect the PV:

```bash
kubectl get pv pvc-f88753e5-78cc-4909-bc65-d8d4559e6e3c -o yaml
```

The provisioned volume uses the existing NFS server and share, with a dynamically provisioned subdirectory.

Observed NFS source:

```text
Server: 192.168.29.50
Share:  /kubernetes
NFS:    4.1
```

## 5. Write and Read from Worker 1

The writer test Pod mounts `nfs-test-pvc` at:

```text
/mnt/data
```

It writes the following content:

```text
Hello from Kubernetes NFS CSI
```

The writer Pod was scheduled on:

```text
talos-worker-01
192.168.29.21
```

### Verify Pod placement

```bash
kubectl get pod nfs-test-pod -n default -o wide
```

### Verify the write

```bash
kubectl logs nfs-test-pod -n default
```

Observed output:

```text
Data written successfully
```

### Read the file from the writer

```bash
kubectl exec nfs-test-pod -n default -- cat /mnt/data/test.txt
```

Observed output:

```text
Hello from Kubernetes NFS CSI
```

**Result:** The writer Pod successfully mounted the PVC and wrote data that could be read back.

## 6. Cross-Worker Read Validation

A temporary reader Pod was scheduled on `talos-worker-02`.

The reader mounted the same PVC as read-only and read:

```text
/mnt/data/test.txt
```

The reader completed successfully with exit code `0`.

Observed output:

```text
Hello from Kubernetes NFS CSI
```

This validates that the data written from worker 1 was readable by a Pod running on worker 2 through the shared NFS-backed claim.

### What this test proves

* The same PVC can be mounted by Pods scheduled on different workers.
* Data written from worker 1 was visible from worker 2.
* The test reader accessed the mounted volume read-only.

This was a sequential read test; it did not test simultaneous multi-writer access.

## 7. Persistence After Writer Pod Deletion

After the initial write/read and cross-worker read tests, the original writer Pod was deleted:

```bash
kubectl delete pod nfs-test-pod -n default
```

The PVC remained `Bound` to the same PV.

A fresh Pod named `nfs-persistence-reader` was then created on `talos-worker-02`. It mounted the existing PVC read-only and executed:

```bash
cat /mnt/data/test.txt
```

Observed output:

```text
Hello from Kubernetes NFS CSI
```

The container completed with:

```text
Reason: Completed
Exit Code: 0
```

**Result:** The data remained accessible after deleting the original writer Pod and creating a fresh reader Pod on the other worker.

This validates persistence across Pod deletion and recreation. It does not, by itself, validate recovery after a NAS reboot, NFS outage, or storage-server failure.

## 8. Cleanup

The temporary reader Pods were removed:

```bash
kubectl delete pod nfs-reader-pod nfs-persistence-reader -n default
```

The original writer Pod had already been deleted.

Final verification:

```bash
kubectl get pods -n default -o wide
kubectl get pvc nfs-test-pvc -n default
kubectl get pv pvc-f88753e5-78cc-4909-bc65-d8d4559e6e3c
```

Observed final state:

* No Pods remained in the `default` namespace.
* `nfs-test-pvc` remained `Bound`.
* The existing PV remained `Bound`.
* The persistent claim and volume were not deleted.

### Important storage safety note

The PV reclaim policy is `Delete`.

**Do not delete `nfs-test-pvc` or its PV as part of routine Pod cleanup.** Deleting the claim may trigger removal of the dynamically provisioned backing directory.

Only delete the PVC when you intentionally want to retire the test volume and have verified that its contents are no longer needed.

## 9. Troubleshooting Commands

### Inspect the claim

```bash
kubectl describe pvc nfs-test-pvc -n default
```

### Inspect the PV

```bash
kubectl describe pv pvc-f88753e5-78cc-4909-bc65-d8d4559e6e3c
```

### Inspect CSI driver resources

```bash
kubectl get csidriver
kubectl get pods -n kube-system
```

### Inspect StorageClass

```bash
kubectl describe storageclass nfs-storage
```

### Inspect Pod events and mount status

```bash
kubectl describe pod <pod-name> -n default
```

### Inspect NFS CSI logs

First identify the driver Pods:

```bash
kubectl get pods -n kube-system
```

Then inspect the relevant CSI controller or node Pod logs:

```bash
kubectl logs -n kube-system <csi-pod-name> --all-containers
```

Use the actual Pod name returned by the cluster.

## 10. Validation Summary

| Test                                | Result |
| ----------------------------------- | ------ |
| NFS CSI driver installed            | Passed |
| StorageClass available              | Passed |
| PVC dynamically provisioned         | Passed |
| PVC bound to PV                     | Passed |
| RWX claim mounted on worker 1       | Passed |
| Write and read from worker 1        | Passed |
| Cross-worker read on worker 2       | Passed |
| Read after original writer deletion | Passed |
| Temporary test Pod cleanup          | Passed |
| PVC and PV preserved after cleanup  | Passed |

## 11. Remaining Tests / Limitations

The following are **not claimed as validated** by this phase:

* Simultaneous multi-writer access.
* Data availability during an NFS server outage.
* Recovery after NAS reboot or NFS service restart.
* Recovery after a Kubernetes worker reboot.
* Backup and restore of NFS-backed application data.
* Application-level use of this StorageClass.
* NAS-side verification of the test file after the Kubernetes tests.

These can be tested separately if required.

## 12. Git Change

The PVC manifest correction was committed locally.

```text
Commit: 1a82cf5
Message: fix(storage): set NFS test PVC to ReadWriteMany
```

The working tree was clean after the commit.

The local branch was reported as two commits ahead of `origin/main`; the commits had not yet been pushed at the time of this documentation.

---

## Phase Conclusion

The Kubernetes NFS CSI integration has been functionally validated for dynamic provisioning, RWX mounting, write/read access, cross-worker readability, and data accessibility after writer Pod deletion.

The temporary test Pods were cleaned up while preserving the PVC and PV.

The next work can move to the remaining homelab validation and documentation tasks without rebuilding the NAS or reinstalling the NFS CSI driver.

