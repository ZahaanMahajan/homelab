# Rebuild Procedure

If TLS needs to be recreated from scratch, follow this sequence.

## Step 1 — Verify the cluster

```bash
kubectl get nodes
kubectl get pods -A
```

---

## Step 2 — Verify Traefik

```bash
kubectl get pods -n traefik
kubectl get svc traefik -n traefik
kubectl get ingressclass
```

Expected LoadBalancer:

```text
192.168.29.240
```

---

## Step 3 — Verify Pi-hole

```bash
dig @192.168.29.10 A app1.zahaan.online +short
```

Expected:

```text
192.168.29.240
```

---

## Step 4 — Verify cert-manager

```bash
kubectl get pods -n cert-manager
kubectl get crd | grep cert-manager
```

If cert-manager does not exist, install:

```bash
kubectl apply -f \
  https://github.com/cert-manager/cert-manager/releases/download/v1.21.1/cert-manager.yaml
```

Wait until:

```bash
kubectl get pods -n cert-manager
```

shows all components as:

```text
Running
```

---

## Step 5 — Create Cloudflare Secret

```bash
kubectl create secret generic cloudflare-api-token-secret \
  -n cert-manager \
  --from-literal=api-token='<CLOUDFLARE_API_TOKEN>'
```

---

## Step 6 — Create Staging ClusterIssuer

```bash
kubectl apply \
  -f kubernetes/networking/cert-manager/clusterissuer-staging.yaml
```

Verify:

```bash
kubectl get clusterissuer
```

Wait for:

```text
letsencrypt-staging   True
```

---

## Step 7 — Create Staging Certificate

```bash
kubectl apply \
  -f kubernetes/networking/cert-manager/app1-staging-certificate.yaml
```

Monitor:

```bash
kubectl get certificate -n default
kubectl get certificaterequest -n default
kubectl get order -A
kubectl get challenge -A
```

Wait until:

```text
Certificate READY=True
```

---

## Step 8 — Verify the Staging Certificate

```bash
kubectl get secret app1-zahaan-online-tls -n default
```

Inspect:

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

---

## Step 9 — Create Production ClusterIssuer

```bash
kubectl apply \
  -f kubernetes/networking/cert-manager/clusterissuer-production.yaml
```

Verify:

```bash
kubectl get clusterissuer
```

Wait for:

```text
letsencrypt-production   True
```

---

## Step 10 — Change Certificate to Production

Apply:

```bash
kubectl apply \
  -f kubernetes/networking/cert-manager/app1-certificate.yaml
```

Then:

```bash
kubectl get certificate app1-zahaan-online -n default -o wide
```

Wait for:

```text
READY=True
```

and:

```text
ISSUER=letsencrypt-production
```

---

## Step 11 — Configure Ingress TLS

Ensure:

```yaml
tls:
  - hosts:
      - app1.zahaan.online
    secretName: app1-zahaan-online-tls
```

Apply:

```bash
kubectl apply \
  -f kubernetes/networking/ingress/app-routing.yaml
```

---

## Step 12 — Configure Traefik Redirect

Ensure:

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

Render:

```bash
helm template traefik \
  traefik/traefik \
  --namespace traefik \
  --version 41.3.0 \
  -f kubernetes/networking/ingress/traefik-values.yaml \
  > /tmp/traefik-rendered.yaml
```

Verify:

```bash
grep -n -A5 -B5 "redirections" /tmp/traefik-rendered.yaml
```

---

## Step 13 — Upgrade Traefik

```bash
helm upgrade traefik \
  traefik/traefik \
  --namespace traefik \
  --version 41.3.0 \
  -f kubernetes/networking/ingress/traefik-values.yaml
```

Verify:

```bash
kubectl get pods -n traefik
kubectl get svc traefik -n traefik
```

---

## Step 14 — Test HTTPS

```bash
curl -v https://app1.zahaan.online/
```

Expected:

```text
SSL certificate verified via OpenSSL.
```

and:

```text
HTTP/2 200
```

---

## Step 15 — Test HTTP Redirect

```bash
curl -I http://app1.zahaan.online
```

Expected:

```text
HTTP/1.1 308 Permanent Redirect
Location: https://app1.zahaan.online/
```

---

## Step 16 — Test Complete Flow

```bash
curl -IL http://app1.zahaan.online
```

Expected:

```text
HTTP/1.1 308 Permanent Redirect
Location: https://app1.zahaan.online/

HTTP/2 200
```
