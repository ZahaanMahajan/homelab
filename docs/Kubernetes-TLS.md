# Kubernetes TLS

## Overview

TLS certificates are managed inside the Kubernetes cluster using **cert-manager** and **Let's Encrypt**.

Cloudflare DNS-01 validation is used to prove domain ownership and issue certificates without exposing services publicly for HTTP validation.

## Architecture

```text
          Kubernetes
               |
               v
          cert-manager
               |
               v
          ClusterIssuer
               |
               v
          Let's Encrypt
               |
               v
       DNS-01 Challenge
               |
               v
           Cloudflare
               |
               v
       TLS Certificate
               |
               v
       Gateway / Ingress
               |
               v
          HTTPS Access
```

## Components

| Component | Configuration |
|---|---|
| Certificate Manager | cert-manager |
| Version | v1.21.1 |
| Certificate Authority | Let's Encrypt |
| DNS Provider | Cloudflare |
| Challenge Type | DNS-01 |
| Domain | `zahaan.online` |

## cert-manager

cert-manager automates certificate issuance, renewal, and management inside Kubernetes.

Verify the installation:

```bash
kubectl get pods -n cert-manager
kubectl get crds | grep cert-manager
```

## Cloudflare DNS-01 Validation

Cloudflare is used to manage DNS records for `zahaan.online`.

The DNS-01 challenge works by creating a temporary TXT record under:

```text
_acme-challenge.<domain>
```

Let's Encrypt checks this record to verify domain ownership before issuing the certificate.

A Cloudflare API token is stored in a Kubernetes Secret and referenced by the cert-manager issuer configuration.

**Important:** Keep the API token out of Git and restrict its permissions to the required DNS zone.

## ClusterIssuer

A `ClusterIssuer` defines the certificate authority and challenge configuration used by cert-manager.

Inspect the configured issuer:

```bash
kubectl get clusterissuer
kubectl describe clusterissuer <issuer-name>
```

The issuer uses Let's Encrypt with Cloudflare DNS-01 validation.

## Certificates

A Kubernetes `Certificate` resource requests a certificate and stores the issued certificate and private key in a Kubernetes Secret.

Inspect certificates:

```bash
kubectl get certificates -A
kubectl describe certificate <certificate-name> -n <namespace>
```

Check certificate-related resources:

```bash
kubectl get certificaterequests -A
kubectl get challenges -A
kubectl get orders -A
```

## HTTPS Configuration

The issued TLS Secret is referenced by the Gateway or Ingress configuration.

This allows applications to serve traffic over HTTPS.

HTTP-to-HTTPS redirection is configured at the edge routing layer.

## Validation

Check certificate readiness:

```bash
kubectl get certificates -A
kubectl get secrets -A | grep tls
```

Test an application endpoint:

```bash
curl -I https://<application-domain>
```

Inspect the certificate:

```bash
openssl s_client -connect <application-domain>:443 \
  -servername <application-domain>
```

## Result

The TLS integration provides:

- Automated certificate issuance through Let's Encrypt.
- DNS-01 domain validation using Cloudflare.
- Kubernetes-managed certificate storage.
- Automated certificate renewal.
- HTTPS access for exposed applications.

---

cert-manager manages the certificate lifecycle, Cloudflare handles DNS validation, and the Gateway or Ingress layer serves HTTPS traffic.
