# Kubernetes Resource Templates

Reusable Kubernetes templates for CKA practice and homelab work.

## Included

| Template | Kind / Purpose |
|---|---|
| `namespace.yaml` | Namespace |
| `pod.yaml` | Pod |
| `replicaset.yaml` | ReplicaSet |
| `deployment.yaml` | Deployment |
| `daemonset.yaml` | DaemonSet |
| `statefulset.yaml` | StatefulSet |
| `job.yaml` | Job |
| `cronjob.yaml` | CronJob |
| `service-clusterip.yaml` | ClusterIP Service |
| `service-nodeport.yaml` | NodePort Service |
| `service-loadbalancer.yaml` | LoadBalancer Service |
| `ingress.yaml` | Kubernetes Ingress |
| `configmap.yaml` | ConfigMap |
| `secret.yaml` | Secret |
| `serviceaccount.yaml` | ServiceAccount |
| `role.yaml` | Namespace-scoped RBAC Role |
| `rolebinding.yaml` | RoleBinding |
| `clusterrole.yaml` | ClusterRole |
| `clusterrolebinding.yaml` | ClusterRoleBinding |
| `persistentvolume.yaml` | PersistentVolume |
| `persistentvolumeclaim.yaml` | PersistentVolumeClaim |
| `storageclass.yaml` | StorageClass |
| `networkpolicy.yaml` | NetworkPolicy |
| `node-affinity.yaml` | Node affinity snippet |
| `pod-affinity.yaml` | Pod affinity snippet |
| `pod-anti-affinity.yaml` | Pod anti-affinity snippet |
| `toleration.yaml` | Toleration snippet |
| `taint.yaml` | Node taint command reference |
| `probes.yaml` | Probe snippets |
| `resource-requests-limits.yaml` | Resource request/limit snippet |

## How to use

Replace every `<placeholder>` before applying a resource.

Example:

```bash
kubectl apply -f deployment.yaml
```

Validate before applying:

```bash
kubectl apply --dry-run=client -f deployment.yaml
```

Inspect generated YAML:

```bash
kubectl explain deployment.spec
kubectl explain pod.spec.containers
```

## Important distinction

Not every file in this directory is a standalone Kubernetes object.

These are **snippets/reference templates**:

- `node-affinity.yaml`
- `pod-affinity.yaml`
- `pod-anti-affinity.yaml`
- `toleration.yaml`
- `probes.yaml`
- `resource-requests-limits.yaml`
- `taint.yaml`

They are intended to be copied into the appropriate section of a Pod, Deployment, StatefulSet, DaemonSet, Job, or CronJob.

## Deliberately excluded

`Endpoint` is not included here because modern Kubernetes service discovery normally uses `EndpointSlice`, and manually managing endpoints is a special-case operation.

Traefik's `IngressRoute` is also not included because it is a **Traefik Custom Resource**, not a built-in Kubernetes `Ingress`. If you use Traefik CRDs in the homelab, it should have its own template such as `ingressroute.yaml`.

## Security note

`secret.yaml` uses `stringData` for readability. Kubernetes converts it into the Secret's `data` field. Do not commit real credentials to Git.
