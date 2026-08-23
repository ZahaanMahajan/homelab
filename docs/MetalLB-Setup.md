# MetalLB — Kubernetes LoadBalancer for the Homelab

MetalLB provides the Kubernetes `Service type: LoadBalancer` implementation for the Talos Kubernetes cluster running on the homelab's Proxmox infrastructure.

The cluster does not have a cloud-provider load balancer. MetalLB allows Kubernetes LoadBalancer Services to receive IP addresses from the physical LAN and makes those addresses reachable from other devices on the LAN.

---

## 1. Homelab Network

The current LAN is:

| Component | Address |
|---|---|
| Network | `192.168.29.0/24` |
| Gateway | `192.168.29.1` |
| Pi-hole | `192.168.29.10` |
| Kubernetes control plane | `192.168.29.20` |
| Kubernetes worker 01 | `192.168.29.21` |
| Kubernetes worker 02 | `192.168.29.22` |
| MetalLB LoadBalancer VIP | `192.168.29.240` |

Kubernetes networking:

| Network | CIDR |
|---|---|
| Pod network | `10.244.0.0/16` |
| Service network | `10.96.0.0/12` |

CNI:

```text
Flannel
```

MetalLB operates alongside Flannel. It does not replace the cluster CNI.

---

## 2. Why MetalLB?

In a cloud environment, creating:

```yaml
spec:
  type: LoadBalancer
```

usually causes the cloud provider to provision an external load balancer and assign an external IP.

A self-hosted Kubernetes cluster running on Proxmox does not automatically have such a cloud load-balancer integration.

Without MetalLB:

```text
Kubernetes Service
type: LoadBalancer
        |
        X
No external load-balancer implementation
```

With MetalLB:

```text
Kubernetes Service
type: LoadBalancer
        |
        v
     MetalLB
        |
        v
192.168.29.240
        |
        v
      LAN
```

MetalLB therefore bridges the gap between Kubernetes `LoadBalancer` Services and the physical homelab network.

---

## 3. MetalLB Architecture

The architecture used in this homelab is Layer 2 mode.

```text
                         LAN
                          |
                    192.168.29.0/24
                          |
                          v
                 192.168.29.240
                          |
                    MetalLB L2
                          |
             +------------+------------+
             |                         |
             v                         v
      MetalLB Speaker           Kubernetes Service
             |                         |
             |                         v
             |                    ClusterIP
             |                         |
             +-------------------------+
                                       |
                                       v
                                      Pods
```

More precisely:

```text
LAN Client
192.168.29.x
      |
      | ARP
      v
192.168.29.240
      |
      v
MetalLB Speaker
      |
      v
LoadBalancer Service
      |
      v
Kubernetes Service routing
      |
      +------------------+
      |                  |
      v                  v
Pod 10.244.x.x       Pod 10.244.x.x
```

MetalLB is not an HTTP reverse proxy and does not replace an Ingress Controller.

Its responsibility is to provide and advertise the external IP for a Kubernetes `LoadBalancer` Service.

---

## 4. MetalLB Components

### Controller

The MetalLB controller runs as a Deployment.

Its responsibilities include:

- Watching Kubernetes Services.
- Detecting `type: LoadBalancer` Services.
- Allocating IP addresses from configured `IPAddressPool` resources.
- Maintaining the desired MetalLB state.

Architecture:

```text
Kubernetes API
      |
      v
MetalLB Controller
      |
      v
LoadBalancer Service
      |
      v
IPAddressPool
```

### Speaker

The speaker runs as a DaemonSet.

There is one speaker Pod on each Linux Kubernetes node.

Current topology:

```text
talos-controlplane-01
192.168.29.20
        |
        +-- MetalLB Speaker

talos-worker-01
192.168.29.21
        |
        +-- MetalLB Speaker

talos-worker-02
192.168.29.22
        |
        +-- MetalLB Speaker
```

In Layer 2 mode, the speaker is responsible for advertising the LoadBalancer IP on the LAN.

---

## 5. Layer 2 Mode

This homelab uses MetalLB Layer 2 mode.

For IPv4, Layer 2 mode relies on ARP.

Suppose a client wants to access:

```text
192.168.29.240
```

The client needs to determine which MAC address owns that IP.

Conceptually:

```text
Client

Who has 192.168.29.240?

        |
        v

MetalLB Speaker

192.168.29.240 is reachable here.

        |
        v

Client sends Ethernet traffic
to the announcing Kubernetes node.
```

MetalLB therefore allows a Kubernetes Service to appear as a reachable host on the local Ethernet network.

---

## 6. IPAddressPool

The homelab uses a dedicated MetalLB address pool:

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: homelab-pool
  namespace: metallb-system
spec:
  addresses:
    - 192.168.29.240/32
```

The `/32` represents exactly one IPv4 address.

Therefore the current allocation pool contains:

```text
192.168.29.240
```

This address was intentionally selected from the LAN and verified before use.

### Why verify the address first?

MetalLB should never allocate an IP already being used by another device.

An IP conflict could cause:

- Intermittent connectivity.
- ARP instability.
- Requests reaching the wrong device.
- Difficult-to-diagnose network failures.

The address was tested from the LAN using ARP:

```bash
sudo arping -I enp5s0 -c 5 192.168.29.240
```

The test returned:

```text
Received 0 response(s)
```

The address was therefore not observed as being claimed by another LAN device at the time of configuration.

---

## 7. L2Advertisement

The pool is advertised using:

```yaml
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: homelab-l2
  namespace: metallb-system
spec:
  ipAddressPools:
    - homelab-pool
```

The relationship is:

```text
IPAddressPool
     |
     | 192.168.29.240/32
     v
homelab-pool
     |
     v
L2Advertisement
     |
     v
Layer 2 / ARP
     |
     v
LAN
```

The two resources have different responsibilities:

| Resource | Responsibility |
|---|---|
| `IPAddressPool` | Defines which IP addresses MetalLB may allocate |
| `L2Advertisement` | Defines that the pool is advertised using Layer 2 |

---

## 8. Current Configuration

The homelab configuration is stored in:

```text
kubernetes/networking/load-balancer/metallb.yaml
```

Current configuration:

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: homelab-pool
  namespace: metallb-system

spec:
  addresses:
    - 192.168.29.240/32

---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: homelab-l2
  namespace: metallb-system

spec:
  ipAddressPools:
    - homelab-pool
```

This file contains homelab-specific configuration and is intentionally tracked in Git.

---

## 9. Installation

MetalLB was installed using the upstream native manifest for version `v0.16.1`.

Installation:

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.16.1/config/manifests/metallb-native.yaml
```

This creates the MetalLB namespace, CRDs, controller, speakers, RBAC resources, webhook configuration, and supporting resources.

Verify the namespace:

```bash
kubectl get namespace metallb-system
```

Verify MetalLB Pods:

```bash
kubectl get pods -n metallb-system -o wide
```

Verify the controller:

```bash
kubectl get deployment -n metallb-system
```

Verify the speakers:

```bash
kubectl get daemonset -n metallb-system
```

Verify MetalLB CRDs:

```bash
kubectl get crd | grep metallb
```

---

## 10. Applying the Homelab Configuration

Apply the configuration:

```bash
kubectl apply -f kubernetes/networking/load-balancer/metallb.yaml
```

Verify the IP pool:

```bash
kubectl get ipaddresspools -n metallb-system
```

Expected configuration:

```text
NAME           AUTO ASSIGN   AVOID BUGGY IPS   ADDRESSES
homelab-pool   true          false             ["192.168.29.240/32"]
```

Verify the Layer 2 advertisement:

```bash
kubectl get l2advertisements -n metallb-system
```

Expected:

```text
NAME         IPADDRESSPOOLS
homelab-l2   ["homelab-pool"]
```

---

## 11. LoadBalancer Service

A Kubernetes Service must request the `LoadBalancer` type before MetalLB allocates an address.

Example:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: example
spec:
  type: LoadBalancer
  selector:
    app: example
  ports:
    - port: 80
      targetPort: 80
```

The flow becomes:

```text
Service
type: LoadBalancer
        |
        v
MetalLB Controller
        |
        v
IPAddressPool
        |
        v
192.168.29.240
        |
        v
MetalLB Speaker
        |
        v
LAN
```

---

## 12. Validation Performed

A temporary nginx workload was used to validate the complete MetalLB path.

The resulting Service showed:

```text
NAME           TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)
metallb-test   LoadBalancer   10.97.232.140   192.168.29.240   80:31356/TCP
```

The Service description confirmed:

```text
LoadBalancer Ingress: 192.168.29.240 (VIP)
```

MetalLB also reported:

```text
IPAllocated
Assigned IP ["192.168.29.240"]
```

and:

```text
nodeAssigned
announcing from node "talos-worker-02" with protocol "layer2"
```

The Service had two healthy endpoints:

```text
10.244.5.27:80
10.244.4.5:80
```

Finally, the LAN client successfully accessed:

```bash
curl http://192.168.29.240
```

and received the nginx HTTP response.

Therefore the following path has been successfully validated:

```text
LAN Client
192.168.29.146
      |
      | HTTP
      v
192.168.29.240
      |
      | Layer 2 / ARP
      v
MetalLB Speaker
talos-worker-02
192.168.29.22
      |
      v
LoadBalancer Service
10.97.232.140:80
      |
      v
Kubernetes Service routing
      |
      +----------------------+
      |                      |
      v                      v
10.244.5.27:80          10.244.4.5:80
nginx Pod                nginx Pod
```

This proves:

- MetalLB installation works.
- The IPAddressPool works.
- The L2Advertisement works.
- `192.168.29.240` is allocated successfully.
- Layer 2 advertisement works.
- The LAN can reach the LoadBalancer VIP.
- Kubernetes Service routing works.
- Traffic reaches the backend Pods.
- HTTP traffic successfully returns to the client.

---

## 13. Understanding the Three IP Layers

The successful test demonstrates three different address spaces.

### LoadBalancer VIP

```text
192.168.29.240
```

This is the address visible to LAN clients.

### Service ClusterIP

Example:

```text
10.97.232.140
```

This is the Kubernetes Service address.

### Pod IP

Examples:

```text
10.244.4.5
10.244.5.27
```

These belong to the Flannel Pod network.

The architecture is:

```text
LAN
192.168.29.0/24
      |
      v
LoadBalancer VIP
192.168.29.240
      |
      v
Service ClusterIP
10.97.x.x
      |
      v
Pod IP
10.244.x.x
```

These addresses have different responsibilities and should not be conflated.

---

## 14. MetalLB vs Service vs Ingress

MetalLB, Kubernetes Services, and Ingress solve different problems.

### MetalLB

Provides an external/LAN IP for a `LoadBalancer` Service.

```text
192.168.29.240
        |
        v
MetalLB
```

### Service

Provides stable Kubernetes networking to a group of Pods.

```text
Service
   |
   v
Pods
```

### Ingress

Provides HTTP/HTTPS application-layer routing.

For example:

```text
portfolio.zahaan.online
        |
        v
Ingress Controller
        |
        v
portfolio-service
```

Therefore:

```text
MetalLB != Ingress
```

MetalLB operates at the network/load-balancer exposure layer, while Ingress handles HTTP/HTTPS routing.

---

## 15. Relationship With Flannel

MetalLB does not replace Flannel.

The networking responsibilities are separated:

```text
Flannel
  |
  +-- Pod networking

Kubernetes Service / kube-proxy
  |
  +-- Service networking

MetalLB
  |
  +-- LoadBalancer IP allocation
  +-- External/LAN IP advertisement
```

Current architecture:

```text
LAN
 |
 v
MetalLB VIP
 |
 v
Kubernetes LoadBalancer Service
 |
 v
Kubernetes Service networking
 |
 v
Flannel Pod network
 |
 v
Pod
```

---

## 16. DNS and MetalLB

DNS is a separate concern from MetalLB.

DNS answers:

> Which IP address corresponds to this hostname?

For example:

```text
portfolio.zahaan.online
        |
        v
192.168.29.240
```

MetalLB answers a different problem:

> How does Kubernetes make `192.168.29.240` reachable as a LoadBalancer IP?

The combined architecture will eventually be:

```text
Client
  |
  | DNS query
  v
Pi-hole
192.168.29.10
  |
  | portfolio.zahaan.online
  v
192.168.29.240
  |
  v
MetalLB
  |
  v
Ingress Controller
  |
  v
portfolio Service
  |
  v
Pod
```

DNS does not route traffic to Pods.

MetalLB does not perform DNS resolution.

Ingress does not allocate the LoadBalancer IP.

Each component has a separate responsibility.

---

## 17. Internal DNS Architecture

The homelab uses Pi-hole:

```text
192.168.29.10
```

for internal DNS.

Eventually an internal hostname can resolve as:

```text
portfolio.zahaan.online
        |
        v
192.168.29.240
```

Multiple applications can share the same MetalLB VIP when an Ingress Controller is introduced:

```text
portfolio.zahaan.online  ─┐
blog.zahaan.online        ├──> 192.168.29.240
grafana.zahaan.online    ─┘
                              |
                              v
                       Ingress Controller
```

The Ingress Controller can then use the HTTP `Host` header to route each hostname to the appropriate Kubernetes Service.

---

## 18. Security Considerations

The MetalLB configuration exposes a LoadBalancer IP on the local LAN.

It does **not** mean the Kubernetes cluster should be exposed directly to the public internet.

The following management interfaces should remain protected:

```text
Kubernetes API
etcd
Talos management
Proxmox management
Pi-hole management
```

MetalLB should be used to expose intentionally selected application Services.

Do not assume that a private IP automatically makes an application secure. Authentication, authorization, network policies, firewalling, application security, and TLS remain separate concerns.

Secrets should never be stored in the public Git repository.

---

## 19. Troubleshooting

### Check MetalLB Pods

```bash
kubectl get pods -n metallb-system -o wide
```

### Check controller logs

```bash
kubectl logs -n metallb-system deployment/controller
```

### Check speaker logs

```bash
kubectl logs -n metallb-system daemonset/speaker
```

### Check IP pools

```bash
kubectl get ipaddresspools -n metallb-system
```

### Check advertisements

```bash
kubectl get l2advertisements -n metallb-system
```

### Inspect a LoadBalancer Service

```bash
kubectl describe svc <service-name>
```

Look for:

```text
LoadBalancer Ingress:
```

and Service events such as:

```text
IPAllocated
nodeAssigned
```

### Check Service endpoints

```bash
kubectl get endpoints <service-name>
```

For modern Kubernetes, EndpointSlices can also be inspected:

```bash
kubectl get endpointslice
```

### Check whether the VIP is reachable from the LAN

```bash
ping 192.168.29.240
```

For ARP-level troubleshooting:

```bash
sudo arping -I <interface> 192.168.29.240
```

### Check the client's route

```bash
ip route
```

### Check the neighbor table

```bash
ip neigh show 192.168.29.240
```

---

## 20. Common Failure Scenarios

### Service has no external IP

Check:

```bash
kubectl describe svc <service-name>
kubectl get ipaddresspools -n metallb-system
```

Possible causes include:

- MetalLB controller is not running.
- No suitable IPAddressPool exists.
- Pool configuration is invalid.
- The IP pool is exhausted.

### External IP is assigned but unreachable

Check:

```bash
kubectl get pods -n metallb-system -o wide
kubectl get l2advertisements -n metallb-system
kubectl describe svc <service-name>
```

Then investigate:

- MetalLB speaker health.
- Layer 2 advertisement.
- LAN connectivity.
- ARP resolution.
- Host/network firewall rules.
- Service endpoints.
- Kubernetes Service routing.

### Service has no endpoints

Check:

```bash
kubectl get pods
kubectl get endpoints <service-name>
```

A Service selector that does not match Pod labels can result in no endpoints.

### IP conflict

If another device already owns the LoadBalancer IP, investigate immediately.

Do not allow two devices to claim the same address.

---

## 21. Current Status

```text
MetalLB namespace             [✓]
MetalLB controller            [✓]
MetalLB speakers              [✓]
MetalLB CRDs                  [✓]
IPAddressPool                 [✓]
L2Advertisement               [✓]
192.168.29.240 allocation     [✓]
Layer 2 advertisement         [✓]
LAN connectivity              [✓]
LoadBalancer Service test     [✓]
HTTP request to VIP           [✓]
```

The MetalLB networking layer is therefore **successfully implemented and validated**.

The next architectural layer is intentionally separate:

```text
MetalLB
   |
   v
Ingress Controller
   |
   v
HTTP/HTTPS routing
   |
   v
DNS
   |
   v
TLS / cert-manager
```

Ingress should not be considered part of the MetalLB implementation itself. It is the next layer of the application exposure architecture.
