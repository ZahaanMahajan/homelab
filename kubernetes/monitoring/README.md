# Kubernetes Observability

## Deployed Stack

* Helm release: `monitoring`
* Chart: `prometheus-community/kube-prometheus-stack`
* Chart version: `91.4.1`
* Namespace: `monitoring`

Components:

* Prometheus
* Grafana
* Alertmanager
* Prometheus Operator

## Access

All three application services use `ClusterIP` and are not directly exposed externally.

Start port-forwards as needed:

```bash
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-alertmanager 9093:9093
```

URLs:

* Grafana: http://localhost:3000
* Prometheus: http://localhost:9090
* Alertmanager: http://localhost:9093

Grafana username is `admin`. Retrieve its password from the Kubernetes Secret; do not commit or share it.

## Persistent Storage

All three monitoring PVCs were observed Bound to `nfs-storage`:

| Component    | Requested size | Access mode |
| ------------ | -------------: | ----------- |
| Grafana      |            5Gi | RWO         |
| Prometheus   |            8Gi | RWO         |
| Alertmanager |            2Gi | RWO         |

## Validation

* Monitoring Pods reached Running/Ready.
* Grafana and Prometheus interfaces opened through port-forwarding.
* Alertmanager interface opened through port-forwarding.
* `kubectl top nodes` and `kubectl top pods -A` returned resource metrics.
* Default rules include `KubeNodeNotReady` and `KubePodCrashLooping`, each configured with a 15-minute pending duration.
* NFS CSI dynamically provisioned a 1Gi RWX PVC.
* A test Pod on `talos-worker-01` wrote a file; a second Pod on `talos-worker-02` read the same file successfully.

## Notes

* PodSecurity warnings appeared for the NFS test Pods and Grafana's `init-chown-data` container.
* The temporary NFS test Pods were deleted after validation.
* The test PVC was intentionally retained because its PV reclaim policy is `Delete`.
* Monitoring storage persistence was validated through PVC binding; backup/restore and failure-recovery testing were not performed.
