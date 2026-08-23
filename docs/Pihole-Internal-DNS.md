# When Pi-hole's Local A Records Break IPv6 Lookups: Solving Split-Horizon DNS with dnsmasq Local-Only Zones

> A practical homelab troubleshooting story: why a local Pi-hole A record can work perfectly with `dig`, while `resolvectl` and applications intermittently report `Name not found`—and how declaring internal names as local-only fixed it.

## The Problem

I run a homelab where Kubernetes services are exposed internally through a single MetalLB/Ingress IP:

```text
192.168.29.240
```

The public domain is:

```text
example.dev
```

Public DNS remains hosted by Cloudflare, but internal-only application names should resolve through Pi-hole:

```text
app1.example.dev
app2.example.dev
path.example.dev
```

The intended split-horizon architecture was:

```text
                    example.dev
                         │
             ┌───────────┴───────────┐
             │                       │
             ▼                       ▼
      Public Internet              LAN
             │                       │
             ▼                       ▼
       Cloudflare DNS            Pi-hole
       Public records          192.168.29.10
                                     │
                                     ▼
                              192.168.29.240
```

The initial Pi-hole configuration used hosts-style local records, effectively:

```text
192.168.29.240 app1.example.dev
192.168.29.240 app2.example.dev
192.168.29.240 path.example.dev
```

A-record lookups worked.

But AAAA lookups created a surprising problem.

---

# What Made the Problem Difficult?

A direct A query worked consistently:

```bash
dig @192.168.29.10 A app2.example.dev +short
```

returned:

```text
192.168.29.240
```

But an AAAA query was different:

```bash
dig @192.168.29.10 AAAA app2.example.dev
```

Pi-hole could forward the AAAA query upstream because the hosts-style entry only supplied an A record.

The upstream resolver was Cloudflare:

```text
1.1.1.1
1.0.0.1
```

The internal hostname did not exist in the public DNS zone, so the upstream path could produce a negative response.

That created a mismatch between the local A record and the DNS behavior for the same hostname.

---

# Why `dig` and `resolvectl` Behaved Differently

This was one of the most important clues.

A command such as:

```bash
dig @192.168.29.10 A app2.example.dev
```

asks one precise DNS question:

```text
A app2.example.dev
```

It receives the locally configured A record.

Normal system resolution is more complicated.

`resolvectl query app2.example.dev` can involve both IPv4 and IPv6 address resolution:

```text
A?
AAAA?
```

If the AAAA side receives an NXDOMAIN-shaped negative answer, the resolver can treat that response as evidence that the name itself does not exist.

That is very different from a clean:

```text
NOERROR
```

with an empty AAAA answer (NODATA).

So the application-level lookup could fail even though:

```text
A app2.example.dev
```

was perfectly valid locally.

---

# The Critical Pi-hole Distinction

The key discovery was that a hosts-style record is not the same thing as declaring a DNS name locally authoritative.

A hosts-style entry like:

```text
192.168.29.240 app2.example.dev
```

effectively establishes:

```text
A app2.example.dev = 192.168.29.240
```

It does not mean:

```text
"I am authoritative for every possible RR type for app2.example.dev."
```

So the DNS behavior can be summarized as:

```text
A app2.example.dev
        │
        ▼
Pi-hole has local A mapping
        │
        ▼
Answered locally


AAAA app2.example.dev
        │
        ▼
No local AAAA mapping
        │
        ▼
Normal forwarding path
        │
        ▼
Upstream resolver
```

That distinction was the root of the problem.

---

# Why Cloudflare Was Involved

Cloudflare was not inherently the problem.

Cloudflare was simply the configured upstream DNS provider.

The flow was:

```text
Fedora
   │
   ▼
Pi-hole
192.168.29.10
   │
   │ A record exists locally
   └──────────────► local answer


Fedora
   │
   ▼
Pi-hole
192.168.29.10
   │
   │ AAAA not known locally
   ▼
1.1.1.1 / 1.0.0.1
   │
   ▼
Public DNS
```

The internal hostname was intentionally never published publicly.

That is completely valid for split-horizon DNS.

The problem was that Pi-hole's hosts-style local mapping did not establish the desired local-only behavior for unmatched record types.

---

# The Correct Architecture

The fix was to distinguish between:

1. Providing the local A address.
2. Declaring the internal name as local-only.

The desired behavior is:

```text
app2.example.dev
        │
        ▼
Pi-hole
        │
        ├── A    → 192.168.29.240
        │
        └── AAAA → local NODATA
                    │
                    └── never forwarded
```

Everything else should continue using the normal upstream DNS path:

```text
Other DNS names
      │
      ▼
Pi-hole
      │
      ▼
1.1.1.1 / 1.0.0.1
```

So Pi-hole becomes authoritative for the internal names while Cloudflare remains authoritative for the public zone.

---

# The Fix

Pi-hole v6 does not load `/etc/dnsmasq.d/*.conf` by default in the same way older installations did, so the first step was enabling that configuration path:

```bash
sudo pihole-FTL --config misc.etc_dnsmasq_d true
```

Then I created:

```text
/etc/dnsmasq.d/05-zahaan-local.conf
```

with:

```conf
# Declare these internal names as local-only.
# DNS queries for these names are never forwarded upstream.
server=/app1.example.dev/app2.example.dev/path.example.dev/#

# Provide the internal IPv4 address.
address=/app1.example.dev/app2.example.dev/path.example.dev/192.168.29.240
```

Then restarted Pi-hole FTL:

```bash
sudo systemctl restart pihole-FTL
```

---

# What the Two Directives Do

## `server=/.../#`

This is the important part.

```conf
server=/app1.example.dev/app2.example.dev/path.example.dev/#
```

It tells dnsmasq/FTL that these names should be handled locally rather than forwarded to an upstream server.

Conceptually:

```text
Query for internal name
        │
        ▼
Is it one of the locally declared names?
        │
       YES
        │
        ▼
Do NOT forward upstream
```

Therefore an unmatched AAAA query can receive a local negative answer instead of being sent to Cloudflare.

---

## `address=/.../192.168.29.240`

This supplies the actual IPv4 address:

```conf
address=/app1.example.dev/app2.example.dev/path.example.dev/192.168.29.240
```

So:

```text
A app1.example.dev
        ↓
192.168.29.240

A app2.example.dev
        ↓
192.168.29.240

A path.example.dev
        ↓
192.168.29.240
```

The two directives therefore solve different parts of the problem:

```text
server=/.../#
    ↓
Keep these names local

address=/.../IP
    ↓
Give them the internal IPv4 address
```

---

# Why This Fixed the AAAA Problem

Before the change:

```text
AAAA app2.example.dev
        │
        ▼
No local AAAA record
        │
        ▼
Forward upstream
        │
        ▼
Public DNS
        │
        ▼
Negative response
```

After the change:

```text
AAAA app2.example.dev
        │
        ▼
Name declared local-only
        │
        ▼
Never forwarded
        │
        ▼
Local NODATA
```

The important improvement is consistency.

The resolver no longer has to interpret different upstream negative responses for an internal-only name.

---

# Verification

After restarting Pi-hole, I verified the configuration from both sides.

## Pi-hole configuration

```bash
sudo pihole-FTL --config misc.etc_dnsmasq_d
```

The setting should report:

```text
true
```

The configuration file can be inspected with:

```bash
sudo cat /etc/dnsmasq.d/05-zahaan-local.conf
```

---

# Verify the A Record

```bash
dig @192.168.29.10 A app2.example.dev +short
```

Expected:

```text
192.168.29.240
```

This preserves the original behavior.

---

# Verify AAAA

```bash
dig @192.168.29.10 AAAA app2.example.dev
```

The important behavior is:

```text
NOERROR
```

with no AAAA address returned (NODATA), rather than an upstream NXDOMAIN.

Also inspect Pi-hole's log:

```bash
sudo pihole tail
```

There should no longer be an upstream forwarding event for this internal name.

---

# Flush the Client Resolver Cache

Because the Fedora workstation may have cached the previous negative response, flush `systemd-resolved`:

```bash
sudo resolvectl flush-caches
```

Then test repeatedly:

```bash
for i in {1..10}; do
    resolvectl query app2.example.dev
done
```

The important result is consistency.

No intermittent:

```text
Name not found
```

and no dependency on repeatedly flushing the cache.

---

# Application-Level Test

Once DNS is stable, normal applications can use the internal hostnames:

```bash
curl http://app1.example.dev
curl http://app2.example.dev
curl http://path.example.dev/
curl http://path.example.dev/api/
```

The complete request path is then:

```text
Application
    │
    ▼
systemd-resolved
    │
    ▼
Pi-hole
192.168.29.10
    │
    ▼
192.168.29.240
    │
    ▼
MetalLB
    │
    ▼
Ingress Controller
    │
    ▼
Kubernetes Service
    │
    ▼
Pod
```

---

# Split-Horizon DNS: The Final Architecture

The final architecture is:

```text
                    example.dev
                          │
             ┌────────────┴────────────┐
             │                         │
             ▼                         ▼
      Public Internet                 LAN
             │                         │
             ▼                         ▼
   Cloudflare authoritative        Pi-hole
      public zone              192.168.29.10
                                       │
                         ┌─────────────┴─────────────┐
                         │                           │
                         ▼                           ▼
                Internal-only names           Everything else
                         │                           │
                         ▼                           ▼
                  192.168.29.240              Upstream DNS
                         │
                         ▼
                      MetalLB
                         │
                         ▼
                  Ingress Controller
```

Cloudflare remains responsible for the public DNS namespace.

Pi-hole provides the internal split-horizon view.

The internal names are explicitly treated as local-only, preventing unintended upstream queries.

---

# The Important Lesson

The major lesson is:

> **A local DNS A-record override is not necessarily the same thing as declaring a DNS name local-only.**

These are different concepts.

A hosts-style mapping provides:

```text
name + RR type → value
```

A local-only DNS rule provides:

```textname → local DNS authority / no upstream forwarding
```

For internal services under a publicly delegated domain, that distinction matters.

The clean architecture is therefore:

```text
Public DNS
    │
    └── Cloudflare

Internal DNS
    │
    └── Pi-hole
          │
          └── Local-only internal names
```

rather than trying to make public DNS know about internal-only services.

---

# Troubleshooting Checklist

When an internal hostname behaves inconsistently:

```bash
# Check A
dig @192.168.29.10 A app2.example.dev

# Check AAAA
dig @192.168.29.10 AAAA app2.example.dev

# Watch Pi-hole
sudo pihole tail

# Check FTL configuration
sudo pihole-FTL --config misc.etc_dnsmasq_d

# Flush client resolver cache
sudo resolvectl flush-caches

# Test system resolver repeatedly
for i in {1..10}; do
    resolvectl query app2.example.dev
done
```

If `dig` works but `resolvectl` intermittently reports `Name not found`, investigate both A and AAAA behavior rather than testing only the A record.

---

# Final Result

The problem was not:

- MetalLB
- Kubernetes
- Traefik
- Cloudflare delegation
- The public DNS architecture itself

The issue was the interaction between:

```text
Pi-hole hosts-style local A records
        +
unmatched AAAA queries
        +
upstream forwarding
        +
negative DNS responses/caching
        +
systemd-resolved behavior
```

The solution was to make the internal names explicitly **local-only** in Pi-hole/dnsmasq and then provide their internal A address.

That restored consistent split-horizon DNS behavior while keeping the public `example.dev` DNS zone unchanged.

## Key configuration

```conf
server=/app1.example.dev/app2.example.dev/path.example.dev/#
address=/app1.example.dev/app2.example.dev/path.example.dev/192.168.29.240
```

This is the configuration that fixed the issue in my homelab.
