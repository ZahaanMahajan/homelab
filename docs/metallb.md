# MetalLB

## Purpose
Provide LoadBalancer IP allocation for bare-metal Kubernetes.

## Planned configuration
- Mode: Layer 2
- Namespace: metallb-system
- IP address: 192.168.29.240
- Intended use: LAN access to Traefik

## Validation
- [ ] MetalLB controller and speakers are healthy
- [ ] IPAddressPool is configured
- [ ] L2Advertisement is configured
- [ ] LoadBalancer IP allocation verified
- [ ] LAN reachability verified

## References
- https://metallb.io/installation/
- https://metallb.io/configuration/

## Installation

- Version: v0.16.1
- Method: Official native Kubernetes manifest
- Namespace: metallb-system
- Mode: Layer 2
- Address pool: 192.168.29.240/32
- Automatic allocation: Disabled
- Intended LoadBalancer: Traefik

### Installation command

kubectl apply -f \
  https://raw.githubusercontent.com/metallb/metallb/v0.16.1/config/manifests/metallb-native.yaml

### Validation

- [ ] Controller Deployment is available
- [ ] Speaker DaemonSet is ready
- [ ] MetalLB CRDs are registered


