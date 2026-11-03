# MetalLB Setup

## Overview

MetalLB provides LoadBalancer functionality for the bare-metal Kubernetes cluster.

Unlike managed Kubernetes platforms, a bare-metal cluster does not automatically receive external load balancer implementations. MetalLB assigns IP addresses from a configured pool and makes services accessible on the local network.

## Architecture

```text
          LAN Network
               |
               v
        MetalLB IP Pool
               |
               v
       L2Advertisement
               |
               v
      LoadBalancer Service
               |
               v
        Kubernetes Pods
```

## Installation

MetalLB is deployed in the Kubernetes cluster.

| Component | Version |
|---|---|
| MetalLB | v0.16.1 |
| Operating Mode | Layer 2 |

Verify the installation:

```bash
kubectl get pods -n metallb-system
kubectl get crds | grep metallb
```

## IPAddressPool

The `IPAddressPool` defines the range of LAN IP addresses MetalLB can assign to Kubernetes LoadBalancer services.

The configured range must:

- Belong to the same LAN subnet as the Kubernetes nodes.
- Be excluded from DHCP allocation to avoid IP conflicts.
- Contain enough addresses for the services that need external access.

Inspect the configured pool:

```bash
kubectl get ipaddresspools -n metallb-system
kubectl describe ipaddresspool -n metallb-system
```

## L2Advertisement

The `L2Advertisement` enables MetalLB's Layer 2 mode.

In this mode, MetalLB announces service IP addresses on the local network using ARP. Devices on the LAN can then resolve those IP addresses to the MAC address of the announcing node.

Verify the configuration:

```bash
kubectl get l2advertisements -n metallb-system
kubectl describe l2advertisement -n metallb-system
```

## Exposing a Service

Create or configure a Kubernetes Service with the `LoadBalancer` type.

Example:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: example-service
spec:
  type: LoadBalancer
  selector:
    app: example
  ports:
    - port: 80
      targetPort: 8080
```

MetalLB assigns an external IP from the configured pool.

Check the assigned address:

```bash
kubectl get services -A
```

## Validation

Check MetalLB resources:

```bash
kubectl get pods -n metallb-system
kubectl get ipaddresspools -n metallb-system
kubectl get l2advertisements -n metallb-system
```

Check LoadBalancer services:

```bash
kubectl get svc -A
```

Test connectivity to an assigned IP:

```bash
curl http://<EXTERNAL-IP>
```

## Result

MetalLB provides external IP allocation for bare-metal Kubernetes services.

It enables LAN devices to access services through stable LoadBalancer IP addresses without requiring a cloud load balancer.
