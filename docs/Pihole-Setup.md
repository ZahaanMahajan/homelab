# Pi-hole — Homelab DNS Infrastructure

Pi-hole is deployed as the first infrastructure service in the homelab.

It runs in a dedicated Debian 13 VM on the existing Proxmox cluster and provides network-wide DNS resolution and ad blocking for the home LAN.

> **Scope:** This document starts at VM creation on Proxmox and covers Debian 13, Pi-hole installation/configuration, DHCP DNS integration, testing, and the final nftables firewall configuration.

---

## 1. Architecture

```text
                         Internet
                            │
                         Router
                      192.168.29.1
                            │
                           LAN
                            │
                    ┌───────┴────────┐
                    │                │
                 Fedora            Phone
                    │                │
                    └───────┬────────┘
                            │
                            │ DNS
                            ▼
                    Pi-hole VM
                    192.168.29.10
                            │
                  ┌─────────┴─────────┐
                  │                   │
             Local DNS           Upstream DNS
                  │                   │
                  │              Cloudflare
                  │              1.1.1.1
                  │              1.0.0.1
                  │
                  └── Local records
```

Pi-hole is intentionally deployed **outside Kubernetes** as infrastructure underneath the future Kubernetes environment.

---

# 2. Pi-hole VM

## 2.1 VM placement

The Pi-hole VM was created on:

```text
Proxmox node: pve
Node IP:      192.168.29.2
```

The reason for using `pve` is that Pi-hole is lightweight and does not require significant CPU or RAM.

## 2.2 VM resources

Initial VM resources:

```text
CPU:      1 vCPU
RAM:      1 GB
Disk:     ~8 GB
Network:  vmbr0
```

The VM uses the Proxmox bridge:

```text
vmbr0
```

and connects directly to the homelab LAN.

---

# 3. Debian 13 Installation

Debian 13 (Trixie) was installed inside the VM.

After installation, the VM was configured with the hostname:

```text
pi-hole
```

The VM network interface is:

```text
ens18
```

The Pi-hole VM received:

```text
IPv4:    192.168.29.10
Gateway: 192.168.29.1
```

The address was verified to be unused before assigning it to Pi-hole.

---

# 4. Initial Network Verification

Verify the VM's IP configuration:

```bash
ip addr
```

Verify routing:

```bash
ip route
```

Expected:

```text
default via 192.168.29.1
192.168.29.0/24 dev ens18
```

Test connectivity to the gateway:

```bash
ping -c 3 192.168.29.1
```

Test Internet connectivity:

```bash
ping -c 3 1.1.1.1
```

Verify DNS:

```bash
ping -c 3 google.com
```

---

# 5. Pi-hole Installation

The official Pi-hole installer was used.

Installation command:

```bash
wget -O basic-install.sh https://install.pi-hole.net
```

Then:

```bash
sudo bash basic-install.sh
```

The installer was completed through the interactive configuration wizard.

The following configuration was selected:

```text
Network interface: ens18
IPv4 address:     192.168.29.10
Upstream DNS:     Cloudflare
```

Cloudflare upstream DNS servers:

```text
1.1.1.1
1.0.0.1
```

The Pi-hole web dashboard was then accessed to configure and verify the installation.

---

# 6. Pi-hole DNS Configuration

Verify Pi-hole upstream DNS:

```bash
sudo pihole-FTL --config dns.upstreams
```

Expected:

```text
[ 1.1.1.1, 1.0.0.1 ]
```

Verify the listening mode:

```bash
sudo pihole-FTL --config dns.listeningMode
```

Expected:

```text
LOCAL
```

Check Pi-hole status:

```bash
pihole status
```

Pi-hole FTL should be listening on port 53 and blocking should be enabled.

---

# 7. Gravity / Blocklists

The default Pi-hole blocklist was updated using:

```bash
sudo pihole -g
```

The gravity database was successfully populated with approximately:

```text
98,950 domains
```

Verify status:

```bash
sudo pihole status
```

Blocking should report:

```text
Pi-hole blocking is enabled
```

No additional blocklists were added initially. Keeping the initial configuration simple makes troubleshooting easier and avoids unnecessary false positives.

---

# 8. Local DNS Test Record

A temporary local DNS record was configured to verify Pi-hole's local DNS functionality:

```text
pi-hole.zahaan.online → 192.168.29.10
```

Test from a LAN client:

```bash
dig pi-hole.zahaan.online @192.168.29.10
```

Expected:

```text
pi-hole.zahaan.online.    IN    A    192.168.29.10
```

This confirms that Pi-hole can resolve local DNS records.

> Internal homelab DNS naming such as `grafana.zahaan.online`, `gitea.zahaan.online`, etc. will be designed separately after the core Pi-hole setup is complete.

---

# 9. Router DHCP Integration

The router remains the DHCP server.

Pi-hole was **not** configured as a DHCP server.

The router's DHCP DNS configuration was changed to:

```text
DNS mode:      Use below

Primary DNS:   192.168.29.10
Secondary DNS: 192.168.29.10
```

The same Pi-hole address was used for both fields because the router requires a secondary DNS value and we do not want clients to bypass Pi-hole through another resolver.

The router continues to provide:

```text
IP address
Gateway
DHCP configuration
```

while Pi-hole provides:

```text
DNS
DNS filtering
Local DNS resolution
```

---

# 10. Client Verification

## Fedora

The Fedora client initially had a manually configured DNS server:

```text
1.1.1.1
```

NetworkManager was configured to accept DNS information from DHCP:

```bash
nmcli connection modify "Wired connection 1" \
  ipv4.dns "" \
  ipv4.ignore-auto-dns no
```

The connection was then reactivated:

```bash
nmcli connection up "Wired connection 1"
```

Verify:

```bash
resolvectl status
```

Expected:

```text
Current DNS Server: 192.168.29.10
DNS Servers:        192.168.29.10
```

Verify NetworkManager:

```bash
nmcli dev show | grep -E 'IP4.DNS|IP4.GATEWAY'
```

Expected:

```text
IP4.GATEWAY: 192.168.29.1
IP4.DNS[1]:  192.168.29.10
```

Test Internet DNS:

```bash
dig google.com
```

Test local DNS:

```bash
dig pi-hole.zahaan.online
```

Both successfully resolved through Pi-hole.

---

## Phone

A phone connected to the same Wi-Fi network was also verified through the Pi-hole Query Log.

The phone received:

```text
192.168.29.x
```

and its DNS queries appeared in Pi-hole.

This confirmed that Pi-hole is functioning as the network-wide DNS server for LAN clients.

---

# 11. DNS Architecture

The resulting DNS flow is:

```text
LAN Client
    │
    │ DNS
    ▼
192.168.29.10
Pi-hole
    │
    ├── Local DNS
    │
    ├── Blocklists
    │
    └── Upstream DNS
          │
          ├── 1.1.1.1
          └── 1.0.0.1
```

DNS uses:

```text
UDP 53
TCP 53
```

The Pi-hole web interface uses:

```text
TCP 80
TCP 443
```

SSH administration uses:

```text
TCP 22
```

---

# 12. SSH Configuration

Pi-hole is administered using SSH.

Example:

```bash
ssh zahaan@192.168.29.10
```

The SSH configuration was checked with:

```bash
sudo sshd -T | grep -E '^(permitrootlogin|passwordauthentication|pubkeyauthentication)'
```

Current configuration:

```text
permitrootlogin without-password
pubkeyauthentication yes
passwordauthentication yes
```

This means:

```text
Root + password authentication     disabled
Root + SSH key                     permitted
zahaan + password                  permitted
zahaan + SSH key                   permitted
```

The `zahaan` user has sudo privileges.

Password authentication was intentionally left enabled because SSH key authentication has not yet been established as the sole authentication mechanism.

---

# 13. nftables Firewall

The Debian VM initially had no active nftables rules:

```bash
sudo nft list ruleset
```

returned an empty ruleset.

nftables version:

```text
nftables v1.1.3
```

## 13.1 Firewall design

The final firewall is IPv4-only.

IPv6 was intentionally not included in the persistent firewall configuration because the ISP-provided IPv6 prefix is dynamically delegated.

The firewall policy is:

```text
INPUT  → DROP
OUTPUT → ACCEPT
```

Allowed inbound IPv4 traffic from the LAN:

```text
192.168.29.0/24
```

Services:

```text
SSH       TCP 22
DNS       UDP 53
DNS       TCP 53
HTTP      TCP 80
HTTPS     TCP 443
ICMP      IPv4
```

Established and related traffic is allowed.

Loopback traffic is allowed.

---

## 13.2 Final nftables configuration

The final `/etc/nftables.conf` is:

```nft
table inet filter {
    chain input {
        type filter hook input priority filter; policy drop;

        ct state established,related accept
        iifname "lo" accept

        ip saddr 192.168.29.0/24 tcp dport 22 accept

        ip saddr 192.168.29.0/24 udp dport 53 accept
        ip saddr 192.168.29.0/24 tcp dport 53 accept

        ip saddr 192.168.29.0/24 tcp dport 80 accept
        ip saddr 192.168.29.0/24 tcp dport 443 accept

        ip protocol icmp accept
    }

    chain output {
        type filter hook output priority filter; policy accept;
    }
}
```

---

# 14. Applying nftables

The configuration was validated with:

```bash
sudo nft -c -f /etc/nftables.conf
```

No syntax errors were reported.

nftables was enabled at boot:

```bash
sudo systemctl enable nftables
```

Verify:

```bash
sudo systemctl is-enabled nftables
```

Expected:

```text
enabled
```

The service was then started:

```bash
sudo systemctl start nftables
```

Verify:

```bash
sudo systemctl status nftables --no-pager
```

The service started successfully.

---

# 15. Firewall Verification

After enabling the firewall, the following tests were successful.

## DNS

```bash
dig google.com @192.168.29.10
```

Successful.

## Local DNS

```bash
dig pi-hole.zahaan.online @192.168.29.10
```

Successful:

```text
pi-hole.zahaan.online → 192.168.29.10
```

## SSH

```bash
ssh zahaan@192.168.29.10
```

Successful.

## Web dashboard

```text
http://192.168.29.10/admin
```

Accessible from the LAN.

---

# 16. Current Network Architecture

```text
                         Internet
                            │
                            ▼
                     JioFiber Router
                      192.168.29.1
                            │
                         DHCP
                            │
              DNS = 192.168.29.10
                            │
                       LAN Switch
                            │
          ┌─────────────────┼─────────────────┐
          │                 │                 │
       Fedora             Phone          Other Clients
          │                 │                 │
          └─────────────────┼─────────────────┘
                            │
                            ▼
                    Pi-hole VM
                    192.168.29.10
                            │
                 ┌──────────┴──────────┐
                 │                     │
              Local DNS            Upstream
                 │                     │
                 │               Cloudflare
                 │               1.1.1.1
                 │               1.0.0.1
                 │
                 └── *.zahaan.online
```

---

# 17. Current Status

| Component | Status |
|---|---|
| Proxmox Pi-hole VM | ✅ |
| Debian 13 | ✅ |
| Static/reserved IP | ✅ `192.168.29.10` |
| Pi-hole installed | ✅ |
| Cloudflare upstream DNS | ✅ |
| DNS port 53 | ✅ |
| Blocking enabled | ✅ |
| Gravity database | ✅ |
| Router DHCP integration | ✅ |
| Fedora DNS | ✅ |
| Phone DNS | ✅ |
| Local DNS test | ✅ |
| SSH | ✅ |
| nftables | ✅ |
| Persistent firewall | ✅ |
| Public service exposure | ❌ Not configured |

---

# 18. Important Security Boundary

Pi-hole is currently intended to be a **LAN infrastructure service**.

No port forwarding or public exposure has been configured for Pi-hole.

The homelab services using:

```text
*.zahaan.online
```

will initially be internal-only.

Public exposure will be designed separately in the future using appropriate components such as:

```text
Cloudflare
    │
Reverse Proxy / Ingress
    │
TLS
    │
Authentication
    │
Kubernetes
```

---

# 19. Future Homelab DNS Architecture

The next phase will be internal DNS naming.

Planned examples:

```text
homepage.zahaan.online
grafana.zahaan.online
nextcloud.zahaan.online
gitea.zahaan.online
```

These records will initially resolve only inside the home network.

The public DNS zone for `zahaan.online` will remain independent.

Future Kubernetes services will eventually use:

```text
Client
   │
   ▼
Pi-hole
   │
   ▼
Internal DNS
   │
   ▼
Kubernetes Ingress
   │
   ├── Homepage
   ├── Grafana
   ├── Gitea
   └── Nextcloud
```

---

# 20. Troubleshooting Commands

Useful commands for future troubleshooting:

### Network

```bash
ip addr
ip route
ping
```

### DNS

```bash
dig
nslookup
resolvectl status
```

### Listening ports

```bash
ss -lntup
```

### Pi-hole status

```bash
pihole status
```

### Gravity update

```bash
sudo pihole -g
```

### nftables

```bash
sudo nft list ruleset
```

### Firewall service

```bash
sudo systemctl status nftables
```

### Logs

```bash
journalctl
```

---

# 21. Design Principle

Pi-hole is intentionally kept simple:

```text
Proxmox
   │
   └── Pi-hole VM
          │
          └── Network DNS
```

It is **not** part of Kubernetes.

Kubernetes will be introduced later as a separate infrastructure layer:

```text
Proxmox
├── Pi-hole VM
│     └── DNS
│
└── Talos Kubernetes VMs
      └── Applications
```

This separation ensures that Kubernetes remains dependent on a stable infrastructure DNS layer rather than hosting the DNS service that the rest of the homelab depends on.
