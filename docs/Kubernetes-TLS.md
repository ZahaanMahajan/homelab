# TLS & HTTPS with cert-manager

This document is a complete runbook for reproducing the **TLS/HTTPS + automated certificate management** setup in the Homelab Kubernetes cluster.

It is intentionally written so that the TLS configuration can be rebuilt by following this document without needing to reconstruct the reasoning from the original setup session.

---

# 1. Overview

The Homelab uses:

* **Talos Linux** Kubernetes
* **Flannel** CNI
* **MetalLB** for the LAN LoadBalancer IP
* **Traefik** as the Ingress Controller
* **Pi-hole** for internal split-horizon DNS
* **cert-manager** for automated certificate management
* **Let's Encrypt** as the Certificate Authority
* **Cloudflare DNS** for ACME DNS-01 validation

The final request flow is:

```text
                         LAN Client
                             │
                             │ DNS
                             ▼
                       Pi-hole
                     192.168.29.10
                             │
                             │ app1.zahaan.online
                             │ → 192.168.29.240
                             ▼
                      192.168.29.240
                             │
                             ▼
                          MetalLB
                             │
                             ▼
                         Traefik
                    ┌────────┴────────┐
                    │                 │
                  :80               :443
                    │                 │
             HTTP redirect            │
                    │                 │
                    └──────► HTTPS ◄──┘
                                      │
                                      ▼
                               TLS termination
                                      │
                                      ▼
                               Ingress routing
                                      │
                                      ▼
                               Kubernetes Service
                                      │
                                      ▼
                                    Pods
```

Certificate automation:

```text
                     cert-manager
                          │
                          ▼
                  ClusterIssuer
                          │
                          ▼
                        ACME
                          │
                          ▼
                      DNS-01
                          │
                          ▼
                     Cloudflare
                          │
                          ▼
                    Let's Encrypt
                          │
                          ▼
                    Certificate
                          │
                          ▼
                  Kubernetes Secret
                          │
                          ▼
                       Traefik
                          │
                          ▼
                         HTTPS
```

---

# 2. Current Environment

## Kubernetes

```text
Kubernetes: v1.36.2
Talos:      v1.13.8
```

Nodes:

```text
talos-controlplane-01   192.168.29.20
talos-worker-01         192.168.29.21
talos-worker-02         192.168.29.22
```

---

## Networking

```text
Network: 192.168.29.0/24
Gateway: 192.168.29.1
```

Pi-hole:

```text
192.168.29.10
```

MetalLB VIP:

```text
192.168.29.240
```

---

## Domain

Public domain:

```text
zahaan.online
```

Internal application:

```text
app1.zahaan.online
```

Pi-hole resolves:

```text
app1.zahaan.online → 192.168.29.240
```

The application is **not publicly exposed**.

Certificate validation is performed using DNS-01, so Let's Encrypt does not need direct access to the internal application.

---

# 3. Components

The TLS stack consists of:

```text
Traefik
    │
    ├── HTTP :80
    │
    └── HTTPS :443
             │
             └── TLS termination

cert-manager
    │
    └── ACME certificate automation
             │
             └── Let's Encrypt

Cloudflare
    │
    └── DNS-01 TXT record
```

---

# 4. TLS Architecture

TLS provides:

1. **Encryption**

   Prevents network observers from reading application traffic.

2. **Authentication**

   Allows the client to verify that the certificate was issued for the requested hostname by a trusted Certificate Authority.

3. **Integrity**

   Prevents undetected modification of encrypted traffic.

The important distinction is:

```text
Encryption ≠ Authentication
```

TLS provides both when certificate validation succeeds.

---

# 5. TLS Termination

TLS is terminated at Traefik.

```text
Client
   │
   │ HTTPS
   ▼
Traefik :443
   │
   │ TLS termination
   ▼
HTTP inside cluster
   │
   ▼
Kubernetes Service
   │
   ▼
Pod
```

The TLS private key is therefore held in a Kubernetes TLS Secret consumed by Traefik.

The application itself does not need to implement HTTPS for this setup.

---

# 6. TLS Termination vs TLS Passthrough

## TLS Termination

Current architecture:

```text
Client
   │
   │ TLS
   ▼
Traefik
   │
   │ decrypt
   ▼
HTTP
   │
   ▼
Service
   │
   ▼
Pod
```

Traefik owns:

* TLS certificate
* TLS private key
* SNI handling
* TLS handshake
* HTTPS routing

This is the preferred architecture for the current Homelab.

---

## TLS Passthrough

Passthrough would look like:

```text
Client
   │
   │ TLS
   ▼
Traefik
   │
   │ encrypted TLS
   ▼
Service
   │
   ▼
Application
```

The application would terminate TLS itself.

This is **not** the architecture currently used.

---

# 7. Certificates

A certificate contains information such as:

```text
Certificate
├── Subject
├── Subject Alternative Names
├── Issuer
├── Validity period
├── Public key
└── Signature
```

For this application:

```text
DNS: app1.zahaan.online
```

is present in the certificate SAN.

Modern clients use **Subject Alternative Name (SAN)** for hostname validation.

---

# 8. SNI

SNI means:

```text
Server Name Indication
```

The client includes the hostname during the TLS handshake.

For example:

```text
ClientHello
    │
    └── SNI = app1.zahaan.online
```

Traefik can therefore host multiple HTTPS applications on the same IP:

```text
192.168.29.240:443
        │
        ├── app1.zahaan.online
        ├── app2.zahaan.online
        └── grafana.zahaan.online
```

Each hostname can have a different certificate.

---

# 9. TLS Handshake

Simplified flow:

```text
Client
   │
   │ ClientHello
   │ SNI = app1.zahaan.online
   ▼
Traefik
   │
   │ ServerHello
   │ Certificate
   ▼
Client
   │
   │ Validate certificate
   │ Perform key exchange
   ▼
Encrypted TLS connection
   │
   ▼
HTTP request
```

The client verifies:

```text
Hostname
    ↓
SAN
    ↓
Certificate chain
    ↓
Trusted CA
    ↓
Validity period
```

---

# 10. Why cert-manager?

Without cert-manager:

```text
Generate certificate
       ↓
Create TLS Secret
       ↓
Configure Ingress
       ↓
Certificate expires
       ↓
Renew manually
       ↓
Replace Secret
       ↓
Repeat
```

With cert-manager:

```text
Certificate resource
        ↓
cert-manager
        ↓
ACME
        ↓
Let's Encrypt
        ↓
Certificate
        ↓
Kubernetes TLS Secret
        ↓
Traefik
```

cert-manager automatically handles certificate issuance and renewal.

---

# 11. cert-manager Resources

cert-manager introduces several Kubernetes resources.

## ClusterIssuer

Defines a cluster-wide certificate authority configuration.

```text
ClusterIssuer
      │
      ▼
ACME server
      │
      ▼
Let's Encrypt
```

---

## Issuer

An `Issuer` is namespace-scoped.

A `ClusterIssuer` is cluster-scoped.

This Homelab uses:

```text
ClusterIssuer
```

because certificates may eventually be issued in multiple namespaces.

---

## Certificate

Defines the desired certificate.

Example:

```text
Certificate
├── DNS name
├── Issuer
└── TLS Secret
```

Example relationship:

```text
Certificate
    │
    ├── DNS: app1.zahaan.online
    │
    ├── Issuer:
    │      letsencrypt-production
    │
    └── Secret:
           app1-zahaan-online-tls
```

---

## CertificateRequest

Represents a request generated by cert-manager for a certificate.

```text
Certificate
      ↓
CertificateRequest
      ↓
ACME
```

---

## Order

Represents the ACME certificate order.

```text
CertificateRequest
       ↓
Order
```

---

## Challenge

Represents the ACME validation challenge.

For DNS-01:

```text
Order
  ↓
Challenge
  ↓
TXT record
  ↓
Let's Encrypt validation
```

---

# 12. ACME

ACME means:

```text
Automatic Certificate Management Environment
```

It is the protocol used to automate certificate issuance.

The Homelab uses:

```text
ACME
  ↓
Let's Encrypt
  ↓
DNS-01
```

---

# 13. HTTP-01 vs DNS-01

## HTTP-01

Let's Encrypt attempts to access:

```text
http://app1.zahaan.online/.well-known/acme-challenge/<token>
```

The application must therefore be reachable by the Certificate Authority over the public Internet.

That is unsuitable for the internal-only Homelab applications.

---

## DNS-01

DNS-01 validates domain ownership using a TXT record:

```text
_acme-challenge.app1.zahaan.online
```

The flow is:

```text
cert-manager
    │
    ▼
Cloudflare API
    │
    ▼
TXT record
_acme-challenge.app1.zahaan.online
    │
    ▼
Let's Encrypt
    │
    ▼
Domain ownership verified
    │
    ▼
Certificate issued
```

This allows:

```text
Application:
PRIVATE

Certificate validation:
PUBLIC DNS
```

Therefore DNS-01 is the correct validation method for this Homelab.

---

# 14. Why DNS-01 Works for Internal Applications

The application resolves internally:

```text
app1.zahaan.online
        │
        ▼
Pi-hole
        │
        ▼
192.168.29.240
```

Let's Encrypt does not need to access:

```text
192.168.29.240
```

Instead, it validates the domain through public DNS.

```text
                  Public Internet
                        │
                        ▼
                   Cloudflare
                        │
                TXT _acme-challenge
                        │
                        ▼
                  Let's Encrypt

LAN:
Client → Pi-hole → 192.168.29.240 → Traefik
```

These two paths are independent.

---

# 15. Install cert-manager

The installation used in this Homelab was the official cert-manager release manifest.

Version:

```text
v1.21.1
```

Install:

```bash
kubectl apply -f \
  https://github.com/cert-manager/cert-manager/releases/download/v1.21.1/cert-manager.yaml
```

This creates:

```text
cert-manager namespace
cert-manager
cert-manager-cainjector
cert-manager-webhook
```

and the required CRDs.

---

# 16. Verify cert-manager

Check:

```bash
kubectl get pods -n cert-manager
```

Expected:

```text
cert-manager             1/1 Running
cert-manager-cainjector  1/1 Running
cert-manager-webhook     1/1 Running
```

Check deployments:

```bash
kubectl get deployments -n cert-manager
```

Check CRDs:

```bash
kubectl get crd | grep cert-manager
```

Expected CRDs include:

```text
certificates.cert-manager.io
certificaterequests.cert-manager.io
challenges.acme.cert-manager.io
clusterissuers.cert-manager.io
issuers.cert-manager.io
orders.acme.cert-manager.io
```

Verify the resources:

```bash
kubectl get clusterissuer
kubectl get issuer -A
kubectl get certificates -A
kubectl get certificaterequests -A
```

If cert-manager is already installed, **do not install it again**.

---

# 17. Important Helm Note

The cert-manager components in this Homelab were installed using the official release manifest:

```text
kubectl apply -f cert-manager.yaml
```

An attempt to install the Helm chart afterwards resulted in:

```text
ServiceAccount "cert-manager-cainjector" exists and cannot be imported
```

because the existing resources were not owned by Helm.

Therefore, do not mix the two installation methods on an existing installation.

If rebuilding from scratch, choose one supported installation method and use it consistently.

---

# 18. Cloudflare DNS API Token

DNS-01 requires cert-manager to modify DNS records.

The architecture is:

```text
cert-manager
      │
      │ API token
      ▼
Cloudflare
      │
      ▼
DNS TXT record
```

The Cloudflare token must follow the principle of least privilege.

Recommended permissions:

```text
Zone:
    zahaan.online

Permissions:
    Zone → DNS → Edit
```

Avoid giving cert-manager unrestricted Cloudflare account access.

---

# 19. Store the Cloudflare Token in Kubernetes

Create the Secret:

```bash
kubectl create secret generic cloudflare-api-token-secret \
  -n cert-manager \
  --from-literal=api-token='<CLOUDFLARE_API_TOKEN>'
```

Verify:

```bash
kubectl get secret cloudflare-api-token-secret -n cert-manager
```

Expected:

```text
NAME                           TYPE     DATA
cloudflare-api-token-secret   Opaque   1
```

Never commit this Secret to Git.

Never place the actual token into a Git-tracked YAML file.

---

# 20. Secret Security

The Cloudflare API token should never appear in:

```text
Git
README files
Helm values
Shell history
Screenshots
Logs
Chat messages
Public repositories
```

The Kubernetes Secret should remain outside Git.

If the token is compromised:

1. Revoke the token in Cloudflare.
2. Create a replacement token.
3. Update the Kubernetes Secret.
4. Restart/reconcile cert-manager if necessary.
5. Verify certificate issuance.

---

# 21. Verify Cloudflare DNS

Find the authoritative nameservers:

```bash
dig NS zahaan.online +short
```

Example:

```text
annabel.ns.cloudflare.com.
elias.ns.cloudflare.com.
```

Internal DNS:

```bash
dig A app1.zahaan.online +short
```

Expected:

```text
192.168.29.240
```

From Pi-hole:

```bash
dig @192.168.29.10 A app1.zahaan.online +short
```

Expected:

```text
192.168.29.240
```

The public DNS record may intentionally differ because the application is internal-only.

---

# 22. Let's Encrypt Staging

Always test certificate issuance against Let's Encrypt staging first.

Staging endpoint:

```text
https://acme-staging-v02.api.letsencrypt.org/directory
```

Staging certificates are **not trusted by normal browsers**.

Their purpose is to test:

* cert-manager
* Cloudflare credentials
* DNS-01
* ACME
* certificate issuance
* Secret creation
* Traefik integration

without unnecessarily consuming production issuance limits.

---

# 23. Staging ClusterIssuer

Example:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    email: YOUR_EMAIL
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-staging-account-key

    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-api-token-secret
              key: api-token
```

Apply:

```bash
kubectl apply \
  -f kubernetes/networking/cert-manager/clusterissuer-staging.yaml
```

Verify:

```bash
kubectl get clusterissuer
```

Expected:

```text
letsencrypt-staging   True
```

Inspect:

```bash
kubectl describe clusterissuer letsencrypt-staging
```

The important condition is:

```text
Type:    Ready
Status:  True
Reason:  ACMEAccountRegistered
```

---

# 24. Test Certificate

Example:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: app1-zahaan-online
  namespace: default
spec:
  secretName: app1-zahaan-online-tls

  issuerRef:
    name: letsencrypt-staging
    kind: ClusterIssuer

  dnsNames:
    - app1.zahaan.online
```

Apply:

```bash
kubectl apply \
  -f kubernetes/networking/cert-manager/app1-staging-certificate.yaml
```

Check:

```bash
kubectl get certificate -n default
```

Initially:

```text
READY   False
```

is normal.

---

# 25. Follow the ACME Lifecycle

When issuance is occurring:

```bash
kubectl get certificate -n default
```

Then:

```bash
kubectl get certificaterequest -n default
```

Then:

```bash
kubectl get order -A
```

Then:

```bash
kubectl get challenge -A
```

The lifecycle is:

```text
Certificate
      │
      ▼
CertificateRequest
      │
      ▼
Order
      │
      ▼
Challenge
      │
      ▼
DNS-01
      │
      ▼
Cloudflare TXT
      │
      ▼
Let's Encrypt
      │
      ▼
Certificate
      │
      ▼
TLS Secret
```

Once successful:

```text
Certificate READY=True
```

---

# 26. Verify the Staging Secret

```bash
kubectl get secret app1-zahaan-online-tls -n default
```

Expected:

```text
TYPE: kubernetes.io/tls
DATA: 2
```

The Secret contains:

```text
tls.crt
tls.key
```

Do not decode or commit the private key.

---

# 27. Inspect the Certificate

```bash
kubectl get secret app1-zahaan-online-tls \
  -n default \
  -o jsonpath='{.data.tls\.crt}' \
  | base64 -d \
  | openssl x509 \
      -noout \
      -subject \
      -issuer \
      -dates \
      -ext subjectAltName
```

For staging, the issuer will identify the Let's Encrypt staging CA.

Expected SAN:

```text
DNS:app1.zahaan.online
```

---

# 28. Production ClusterIssuer

After staging has been successfully validated, create the production ClusterIssuer.

Example:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-production
spec:
  acme:
    email: YOUR_EMAIL
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-production-account-key

    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-api-token-secret
              key: api-token
```

Apply:

```bash
kubectl apply \
  -f kubernetes/networking/cert-manager/clusterissuer-production.yaml
```

Verify:

```bash
kubectl get clusterissuer
```

Expected:

```text
letsencrypt-production   True
letsencrypt-staging      True
```

Inspect:

```bash
kubectl describe clusterissuer letsencrypt-production
```

Expected:

```text
Type:    Ready
Status:  True
Reason:  ACMEAccountRegistered
```

---

# 29. Production Certificate

Change the certificate's issuer:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: app1-zahaan-online
  namespace: default
spec:
  secretName: app1-zahaan-online-tls

  issuerRef:
    name: letsencrypt-production
    kind: ClusterIssuer

  dnsNames:
    - app1.zahaan.online
```

Apply:

```bash
kubectl apply \
  -f kubernetes/networking/cert-manager/app1-certificate.yaml
```

Check:

```bash
kubectl get certificate app1-zahaan-online -n default -o wide
```

Expected:

```text
READY   True
ISSUER  letsencrypt-production
```

---

# 30. Verify Production Certificate

```bash
kubectl describe certificate app1-zahaan-online -n default
```

Important fields:

```text
Status:
    Certificate is up to date and has not expired

Issuer:
    letsencrypt-production

Revision:
    2
```

The certificate should have a future:

```text
Not After
```

and a calculated:

```text
Renewal Time
```

cert-manager handles renewal automatically.

---

# 31. Certificate Renewal

cert-manager does not wait until the certificate expires.

It calculates a renewal window.

Example:

```text
Certificate
    │
    │ valid
    ▼
Renewal Time
    │
    ▼
cert-manager
    │
    ▼
New ACME order
    │
    ▼
DNS-01
    │
    ▼
New certificate
    │
    ▼
TLS Secret updated
    │
    ▼
Traefik reloads certificate
```

Do not repeatedly force production issuance just to test renewal.

Use Let's Encrypt staging when experimenting.

---

# 32. Configure Traefik TLS

The existing Traefik configuration is stored at:

```text
kubernetes/networking/ingress/traefik-values.yaml
```

The existing baseline is:

```yaml
ingressClass:
  enabled: true
  isDefaultClass: true

providers:
  kubernetesIngress:
    enabled: true

service:
  enabled: true
  annotations:
    metallb.io/loadBalancerIPs: 192.168.29.240
  spec:
    type: LoadBalancer
```

---

# 33. Configure Ingress TLS

The existing Ingress:

```text
kubernetes/networking/ingress/app-routing.yaml
```

contains:

```yaml
spec:
  ingressClassName: traefik

  tls:
    - hosts:
        - app1.zahaan.online
      secretName: app1-zahaan-online-tls

  rules:
    - host: app1.zahaan.online
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app1-service
                port:
                  number: 80
```

The relationship is:

```text
Certificate
    │
    ▼
app1-zahaan-online-tls
    │
    ▼
Ingress
    │
    ▼
Traefik
```

---

# 34. TLS Secret

The TLS Secret must be:

```text
Type:
kubernetes.io/tls
```

Verify:

```bash
kubectl get secret app1-zahaan-online-tls -n default
```

Expected:

```text
TYPE
kubernetes.io/tls
```

The Secret contains:

```text
tls.crt
tls.key
```

The private key must never be committed to Git.

---

# 35. HTTPS Validation

Test HTTPS:

```bash
curl -v https://app1.zahaan.online/
```

Important output:

```text
SSL certificate verified via OpenSSL.
```

and:

```text
HTTP/2 200
```

The application response should be returned.

---

# 36. Inspect the Certificate From the Network

Use:

```bash
openssl s_client \
  -connect app1.zahaan.online:443 \
  -servername app1.zahaan.online \
  </dev/null 2>/dev/null \
  | openssl x509 \
      -noout \
      -subject \
      -issuer \
      -dates \
      -ext subjectAltName
```

Expected:

```text
subject=CN=app1.zahaan.online
issuer=C=US, O=Let's Encrypt, CN=YR2
notBefore=...
notAfter=...
X509v3 Subject Alternative Name:
    DNS:app1.zahaan.online
```

The exact Let's Encrypt intermediate/issuer name may change over time.

The important properties are:

```text
Correct hostname
Trusted Let's Encrypt chain
Valid dates
Correct SAN
```

---

# 37. Browser Validation

Open:

```text
https://app1.zahaan.online
```

from a LAN client.

The browser should recognize the certificate as trusted.

The fact that the application resolves to:

```text
192.168.29.240
```

does **not** make HTTPS insecure.

Certificate validation is based on:

```text
app1.zahaan.online
```

not:

```text
192.168.29.240
```

The private IP can therefore legitimately serve a publicly trusted certificate.

---

# 38. HTTP → HTTPS Redirect

The final Traefik configuration uses entrypoint redirection.

The relevant configuration is:

```yaml
ports:
  web:
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true
```

This produces Traefik arguments equivalent to:

```text
--entryPoints.web.http.redirections.entryPoint.to=:443
--entryPoints.web.http.redirections.entryPoint.scheme=https
--entryPoints.web.http.redirections.entryPoint.permanent=true
```

---

# 39. Why EntryPoint Redirect?

The redirect happens before application routing:

```text
HTTP :80
   │
   ▼
Traefik web entrypoint
   │
   ▼
308 Permanent Redirect
   │
   ▼
HTTPS :443
   │
   ▼
TLS
   │
   ▼
Ingress routing
```

This is preferable to creating a separate redirect Ingress.

---

# 40. Apply the Traefik Configuration

Always render the Helm chart first.

```bash
helm template traefik \
  traefik/traefik \
  --namespace traefik \
  --version 41.3.0 \
  -f kubernetes/networking/ingress/traefik-values.yaml \
  > /tmp/traefik-rendered.yaml
```

Inspect the redirect:

```bash
grep -n -A5 -B5 "redirections" /tmp/traefik-rendered.yaml
```

Expected:

```text
--entryPoints.web.http.redirections.entryPoint.to=:443
--entryPoints.web.http.redirections.entryPoint.scheme=https
--entryPoints.web.http.redirections.entryPoint.permanent=true
```

Then upgrade:

```bash
helm upgrade traefik \
  traefik/traefik \
  --namespace traefik \
  --version 41.3.0 \
  -f kubernetes/networking/ingress/traefik-values.yaml
```

Verify:

```bash
helm status traefik -n traefik
```

---

# 41. Verify Traefik After Upgrade

```bash
kubectl get pods -n traefik
```

Expected:

```text
traefik-xxxxx   1/1   Running
```

Verify Service:

```bash
kubectl get svc traefik -n traefik
```

Expected:

```text
TYPE           LoadBalancer
EXTERNAL-IP    192.168.29.240
PORTS          80,443
```

The MetalLB IP must remain:

```text
192.168.29.240
```

---

# 42. Test HTTP Redirect

Use:

```bash
curl -I http://app1.zahaan.online
```

Expected:

```text
HTTP/1.1 308 Permanent Redirect
Location: https://app1.zahaan.online/
```

This confirms:

```text
HTTP
 ↓
Traefik :80
 ↓
308
 ↓
HTTPS
```

---

# 43. Test the Complete Redirect Chain

Use:

```bash
curl -IL http://app1.zahaan.online
```

Expected behavior:

```text
HTTP/1.1 308 Permanent Redirect
Location: https://app1.zahaan.online/

HTTP/2 200
```

This verifies both:

```text
HTTP redirect
```

and:

```text
HTTPS application response
```

---

# 44. Final HTTPS Test

```bash
curl -v https://app1.zahaan.online/
```

Expected:

```text
SSL certificate verified via OpenSSL.
```

followed by:

```text
HTTP/2 200
```

and the application response.

---

# 45. Troubleshooting

Always troubleshoot certificate issuance layer by layer.

```text
Certificate
     │
     ▼
CertificateRequest
     │
     ▼
Order
     │
     ▼
Challenge
     │
     ▼
DNS-01
     │
     ▼
Cloudflare
     │
     ▼
Let's Encrypt
```

---

## Certificate

```bash
kubectl get certificate -A
```

```bash
kubectl describe certificate <certificate-name> -n <namespace>
```

---

## CertificateRequest

```bash
kubectl get certificaterequest -A
```

```bash
kubectl describe certificaterequest <name> -n <namespace>
```

---

## Order

```bash
kubectl get order -A
```

```bash
kubectl describe order <name> -n <namespace>
```

---

## Challenge

```bash
kubectl get challenge -A
```

```bash
kubectl describe challenge <name> -n <namespace>
```

Note that cert-manager may delete a completed Challenge quickly.

Therefore:

```bash
kubectl get challenge -A
```

returning no resources does not necessarily mean issuance failed.

Check:

```bash
kubectl get order -A
```

and:

```bash
kubectl get certificate -A
```

as well.

---

# 46. Kubernetes Events

```bash
kubectl get events --sort-by=.lastTimestamp
```

For cert-manager:

```bash
kubectl get events \
  -n cert-manager \
  --sort-by=.lastTimestamp
```

---

# 47. cert-manager Logs

```bash
kubectl logs \
  -n cert-manager \
  deployment/cert-manager
```

For webhook:

```bash
kubectl logs \
  -n cert-manager \
  deployment/cert-manager-webhook
```

For cainjector:

```bash
kubectl logs \
  -n cert-manager \
  deployment/cert-manager-cainjector
```

---

# 48. Traefik Logs

```bash
kubectl logs \
  -n traefik \
  deployment/traefik
```

Look for:

```text
TLS errors
Ingress configuration errors
Certificate errors
Router errors
Entrypoint errors
```

---

# 49. DNS-01 Troubleshooting

Check the TXT record:

```bash
dig TXT _acme-challenge.app1.zahaan.online
```

For direct authoritative DNS verification:

```bash
dig @annabel.ns.cloudflare.com \
  TXT _acme-challenge.app1.zahaan.online
```

and:

```bash
dig @elias.ns.cloudflare.com \
  TXT _acme-challenge.app1.zahaan.online
```

The authoritative nameservers may change; obtain them using:

```bash
dig NS zahaan.online +short
```

Do not assume the nameservers forever.

---

# 50. Common Failure: Empty TXT Record

If:

```bash
dig TXT _acme-challenge.app1.zahaan.online
```

returns nothing while a Challenge is pending, inspect:

```bash
kubectl get challenge -A
```

and:

```bash
kubectl describe challenge <name> -n <namespace>
```

Possible causes include:

* Invalid Cloudflare API token
* Incorrect token permissions
* Incorrect zone
* Incorrect Secret name
* Incorrect Secret key
* DNS propagation delay
* cert-manager solver failure

Do not immediately recreate everything.

Follow:

```text
Challenge
  ↓
Reason
  ↓
Cloudflare API
  ↓
TXT record
```

---

# 51. Common Failure: Certificate Not Trusted

If:

```bash
curl https://app1.zahaan.online
```

returns:

```text
unable to get local issuer certificate
```

check the certificate issuer.

For example, a staging certificate may contain:

```text
Let's Encrypt
(STAGING)
```

Staging certificates are intentionally not trusted by normal clients.

Do not attempt to disable TLS verification as a permanent fix.

Use:

```bash
curl -k
```

only as a temporary diagnostic tool when you intentionally need to inspect a staging certificate.

---

# 52. Common Failure: Wrong Certificate Served

If Traefik serves the wrong certificate, check:

```text
SNI
Ingress host
TLS hosts
Secret name
IngressClass
Traefik configuration
```

Verify the Ingress:

```bash
kubectl describe ingress app-routing -n default
```

Verify:

```yaml
tls:
  - hosts:
      - app1.zahaan.online
    secretName: app1-zahaan-online-tls
```

Then inspect the certificate:

```bash
openssl s_client \
  -connect app1.zahaan.online:443 \
  -servername app1.zahaan.online
```

The `-servername` option is important because it tests SNI.

---

# 53. Common Failure: HTTP Still Returns 200

If:

```bash
curl -I http://app1.zahaan.online
```

returns:

```text
HTTP/1.1 200 OK
```

instead of a redirect, inspect the Traefik configuration.

Check Helm values:

```bash
helm get values traefik -n traefik
```

Check the rendered configuration:

```bash
helm template traefik \
  traefik/traefik \
  --namespace traefik \
  --version 41.3.0 \
  -f kubernetes/networking/ingress/traefik-values.yaml \
  > /tmp/traefik-rendered.yaml
```

Then:

```bash
grep -n -A5 -B5 "redirections" /tmp/traefik-rendered.yaml
```

Expected:

```text
--entryPoints.web.http.redirections.entryPoint.to=:443
--entryPoints.web.http.redirections.entryPoint.scheme=https
--entryPoints.web.http.redirections.entryPoint.permanent=true
```

---

# 54. Certificate Lifecycle Summary

The complete lifecycle is:

```text
                    Certificate
                         │
                         ▼
                CertificateRequest
                         │
                         ▼
                       Order
                         │
                         ▼
                     Challenge
                         │
                         ▼
                     DNS-01
                         │
                         ▼
                    Cloudflare
                         │
                         ▼
                 _acme-challenge TXT
                         │
                         ▼
                  Let's Encrypt
                         │
                         ▼
                   Certificate
                         │
                         ▼
                Kubernetes Secret
                         │
                         ▼
                      Traefik
                         │
                         ▼
                       HTTPS
```

---

# 55. Current Certificate

Current application:

```text
app1.zahaan.online
```

TLS Secret:

```text
app1-zahaan-online-tls
```

Namespace:

```text
default
```

Production issuer:

```text
letsencrypt-production
```

Certificate status:

```text
Ready=True
```

The production certificate was successfully validated from Fedora.

---

# 56. Wildcard Certificates

After single-host certificates are understood and working, wildcard certificates can be considered.

Example:

```text
*.zahaan.online
```

A wildcard certificate covers:

```text
app1.zahaan.online
app2.zahaan.online
grafana.zahaan.online
```

It does not automatically cover:

```text
zahaan.online
```

or:

```text
foo.bar.zahaan.online
```

Wildcard certificates generally require DNS-01 validation.

Example:

```text
*.zahaan.online
```

would be appropriate if many internal services are expected.

However, the current Homelab deliberately uses a single-host certificate first.

---

# 57. Why We Started With a Single Host

The first certificate was deliberately:

```text
app1.zahaan.online
```

rather than:

```text
*.zahaan.online
```

This isolates problems.

The first experiment verifies:

```text
Cloudflare token
        ↓
DNS-01
        ↓
Let's Encrypt
        ↓
cert-manager
        ↓
TLS Secret
        ↓
Traefik
        ↓
SNI
        ↓
HTTPS
```

Only after this works should a wildcard certificate be introduced.

---

# 58. Security Requirements

Never commit:

```text
Cloudflare API tokens
Kubernetes Secrets
TLS private keys
Kubeconfigs
Talos generated configs
ACME account private keys
Generated certificates
```

Never use:

```bash
git add .
```

without inspecting the result.

Prefer:

```bash
git status
git diff
git diff --cached
git diff --cached --check
```

---

# 59. Git-Safe Repository Structure

Recommended structure:

```text
kubernetes/
└── networking/
    ├── cert-manager/
    │   ├── clusterissuer-staging.yaml
    │   ├── clusterissuer-production.yaml
    │   └── app1-certificate.yaml
    │
    └── ingress/
        ├── app-routing.yaml
        ├── path-routing.yaml
        └── traefik-values.yaml
```

The repository should contain **references to Secrets**, not the Secret values themselves.

For example, this is safe:

```yaml
apiTokenSecretRef:
  name: cloudflare-api-token-secret
  key: api-token
```

The actual token must remain outside Git.
# 60. Final Architecture

The completed Homelab TLS architecture is:

```text
                         LAN Client
                             │
                             │ DNS
                             ▼
                       Pi-hole
                     192.168.29.10
                             │
                             │
                  app1.zahaan.online
                             │
                             ▼
                      192.168.29.240
                             │
                             ▼
                          MetalLB
                             │
                             ▼
                         Traefik
                             │
                    ┌────────┴────────┐
                    │                 │
                  :80               :443
                    │                 │
             308 Redirect             │
                    │                 │
                    └──────► HTTPS ◄──┘
                                      │
                                      ▼
                               TLS termination
                                      │
                                      ▼
                               Ingress routing
                                      │
                                      ▼
                               app1-service
                                      │
                                      ▼
                                    Pods
```

Certificate automation:

```text
                         cert-manager
                              │
                              ▼
                     ClusterIssuer
                              │
                              ▼
                            ACME
                              │
                              ▼
                          DNS-01
                              │
                              ▼
                         Cloudflare
                              │
                              ▼
                    _acme-challenge TXT
                              │
                              ▼
                       Let's Encrypt
                              │
                              ▼
                        Certificate
                              │
                              ▼
                     Kubernetes Secret
                              │
                              ▼
                           Traefik
                              │
                              ▼
                            HTTPS
```

---

# 61. Final Validation Checklist

```text
TLS
[✓] TLS fundamentals understood
[✓] HTTPS understood
[✓] Certificates understood
[✓] Certificate Authorities understood
[✓] Certificate chains understood
[✓] SAN understood
[✓] SNI understood
[✓] TLS termination understood
[✓] TLS passthrough understood

cert-manager
[✓] cert-manager installed
[✓] cert-manager verified
[✓] CRDs installed
[✓] ClusterIssuer understood
[✓] Certificate understood
[✓] CertificateRequest understood
[✓] Order understood
[✓] Challenge understood
[✓] ACME understood

ACME
[✓] HTTP-01 understood
[✓] DNS-01 understood
[✓] DNS-01 selected for internal services
[✓] Cloudflare integration configured
[✓] Least-privilege Cloudflare token
[✓] Let's Encrypt staging tested
[✓] Production issuer configured
[✓] Production certificate issued

Traefik
[✓] TLS Secret configured
[✓] Ingress TLS configured
[✓] SNI tested
[✓] HTTPS tested
[✓] Browser HTTPS validated
[✓] HTTP → HTTPS redirect configured
[✓] HTTPS remains functional after Traefik upgrade

Operations
[✓] Certificate renewal behavior understood
[✓] Renewal time verified
[✓] Troubleshooting methodology documented
[✓] Secret security documented
[✓] Git security requirements documented
```

---

# 62. Important Commands — Quick Reference

## cert-manager

```bash
kubectl get pods -n cert-manager
kubectl get crd | grep cert-manager
kubectl get clusterissuer
kubectl get issuer -A
kubectl get certificate -A
kubectl get certificaterequest -A
kubectl get order -A
kubectl get challenge -A
```

## Certificate debugging

```bash
kubectl describe certificate <name> -n <namespace>
kubectl describe certificaterequest <name> -n <namespace>
kubectl describe order <name> -n <namespace>
kubectl describe challenge <name> -n <namespace>
```

## DNS

```bash
dig NS zahaan.online +short
dig @192.168.29.10 A app1.zahaan.online +short
dig TXT _acme-challenge.app1.zahaan.online +short
```

## HTTPS

```bash
curl -v https://app1.zahaan.online/
```

```bash
curl -I http://app1.zahaan.online
```

```bash
curl -IL http://app1.zahaan.online
```

## Certificate inspection

```bash
openssl s_client \
  -connect app1.zahaan.online:443 \
  -servername app1.zahaan.online \
  </dev/null 2>/dev/null \
  | openssl x509 \
      -noout \
      -subject \
      -issuer \
      -dates \
      -ext subjectAltName
```

## Traefik

```bash
helm status traefik -n traefik
helm get values traefik -n traefik
kubectl get pods -n traefik
kubectl get svc traefik -n traefik
kubectl logs -n traefik deployment/traefik
```

## Helm validation

```bash
helm template traefik \
  traefik/traefik \
  --namespace traefik \
  --version 41.3.0 \
  -f kubernetes/networking/ingress/traefik-values.yaml \
  > /tmp/traefik-rendered.yaml
```

---

# 63. Git Checkpoint

Before committing:

```bash
git status
```

Inspect only the expected files:

```bash
git diff -- kubernetes/networking/ingress/traefik-values.yaml
git diff -- kubernetes/networking/ingress/app-routing.yaml
git diff -- kubernetes/networking/cert-manager/
```

Check whitespace/errors:

```bash
git diff --check
```

If staging files:

```bash
git add kubernetes/networking/ingress/traefik-values.yaml
git add kubernetes/networking/ingress/app-routing.yaml
git add kubernetes/networking/cert-manager/clusterissuer-staging.yaml
git add kubernetes/networking/cert-manager/clusterissuer-production.yaml
git add kubernetes/networking/cert-manager/app1-certificate.yaml
```

Then inspect:

```bash
git diff --cached
git diff --cached --check
```

Before committing, verify that there is **no**:

```text
Cloudflare API token
TLS private key
Kubernetes Secret data
ACME account key
Generated certificate
Kubeconfig
Talos credentials
```

The Cloudflare Secret itself must **not** be committed.

---

# 64. Final Result

The Homelab has transformed from:

```text
HTTP
  ↓
Pi-hole
  ↓
MetalLB
  ↓
Traefik
  ↓
Ingress
  ↓
Service
  ↓
Pod
```

to:

```text
HTTPS
  ↓
Pi-hole
  ↓
MetalLB
  ↓
Traefik :443
  ↓
TLS termination
  ↓
Ingress
  ↓
Service
  ↓
Pod
```

with automated certificate management:

```text
cert-manager
     ↓
ACME DNS-01
     ↓
Cloudflare
     ↓
Let's Encrypt
     ↓
TLS Secret
     ↓
Traefik
```

and automatic HTTP redirection:

```text
HTTP :80
   ↓
308 Permanent Redirect
   ↓
HTTPS :443
```

The application remains **internal-only** while using a publicly trusted Let's Encrypt certificate. No public exposure of the Kubernetes application, Kubernetes API, Talos management, Proxmox, or Traefik LoadBalancer is required for certificate validation.
