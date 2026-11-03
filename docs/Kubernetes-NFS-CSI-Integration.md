# Kubernetes NFS CSI Integration

## Overview

The Kubernetes NFS CSI driver integrates the external NAS with the Talos Kubernetes cluster.

It enables dynamic provisioning of PersistentVolumes through PersistentVolumeClaims (PVCs), allowing applications to request persistent storage without manually creating individual volumes.

## Architecture

```text
        Kubernetes Workloads
                 |
                 v
          PersistentVolumeClaim
                 |
                 v
             StorageClass
       cocktail-nfs-storage
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
```

## Infrastructure

| Component | Configuration |
|---|---|
| CSI Driver | NFS CSI Driver |
| Provisioner | `nfs.csi.k8s.io` |
| StorageClass | `cocktail-nfs-storage` |
| NFS Server | `192.168.29.100` |
| NFS Export | `/kubernetes` |
| NFS Version | 4.1 |
| Access Mode | RWX |

## CSI Driver

The NFS CSI driver allows Kubernetes to provision and mount NFS-backed volumes.

Verify the driver installation:

```bash
kubectl get pods -A | grep nfs
kubectl get csidriver
```

The CSI driver handles volume creation, mounting, and cleanup based on Kubernetes storage resources.

## StorageClass

The `cocktail-nfs-storage` StorageClass connects Kubernetes dynamic provisioning to the NAS export.

Example configuration:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: cocktail-nfs-storage
provisioner: nfs.csi.k8s.io
parameters:
  server: 192.168.29.100
  share: /kubernetes
mountOptions:
  - nfsvers=4.1
```

Apply and verify:

```bash
kubectl apply -f storageclass.yaml
kubectl get storageclass
```

## PersistentVolumeClaim

Applications request storage using a PVC referencing the StorageClass.

Example:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nfs-test-pvc
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: cocktail-nfs-storage
  resources:
    requests:
      storage: 1Gi
```

Apply and verify:

```bash
kubectl apply -f pvc.yaml
kubectl get pvc
kubectl get pv
```

A successfully provisioned PVC should reach the `Bound` state.

## Validation

Check the storage resources:

```bash
kubectl get storageclass
kubectl get pvc -A
kubectl get pv
kubectl get csidriver
```

Inspect a PVC:

```bash
kubectl describe pvc nfs-test-pvc
```

Verify that an application pod can mount the volume and access the NFS-backed filesystem.

## Result

The NFS CSI integration provides:

- Dynamic PersistentVolume provisioning.
- Shared storage through `ReadWriteMany` access.
- Centralized application data on the NAS.
- Persistent storage independent of Kubernetes pod lifecycles.

---

The NAS provides the storage backend, while the NFS CSI driver connects it to Kubernetes storage resources.
