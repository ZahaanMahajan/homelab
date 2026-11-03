# Internal DNS Setup

## Overview

Internal DNS resolution is handled by **dnsmasq** on the homelab network.

It resolves internal application domains to their private LAN IP addresses, allowing services hosted on Kubernetes to be accessed using domain names without relying on public DNS resolution.

## Architecture

```text
          Client Device
                |
                v
          DNS Server
         192.168.29.10
                |
                v
             dnsmasq
                |
        Internal DNS Records
                |
                v
       Kubernetes LAN IPs
                |
                v
        Internal Applications
```

## Network Configuration

| Component | Configuration |
|---|---|
| DNS Service | dnsmasq |
| DNS Server | `192.168.29.10` |
| LAN Subnet | `192.168.29.0/24` |
| Domain | `zahaan.online` |
| DNS Mode | Internal / Split-Horizon |

## dnsmasq Configuration

dnsmasq provides local DNS records for internal applications.

Example configuration:

```ini
# Internal application records
address=/argocd.zahaan.online/<INTERNAL-IP>
address=/grafana.zahaan.online/<INTERNAL-IP>

# Keep local domain queries from being forwarded upstream
local=/zahaan.online/
```

Replace the example IP addresses with the actual internal service or ingress IPs.

The `local` directive keeps queries for the configured domain local to dnsmasq rather than forwarding them to upstream DNS servers.

## DNS Validation

Check whether an internal domain resolves correctly:

```bash
dig @192.168.29.10 argocd.zahaan.online
```

Check the returned address:

```bash
dig @192.168.29.10 +short argocd.zahaan.online
```

Test application connectivity:

```bash
curl -I https://argocd.zahaan.online
```

## Result

The internal DNS setup provides:

- Local resolution for homelab application domains.
- Split-horizon DNS for `zahaan.online`.
- Private IP resolution without exposing internal services through public DNS.
- Domain-based access to Kubernetes applications.

---

dnsmasq handles internal DNS resolution, while Cloudflare manages public DNS for the domain.
