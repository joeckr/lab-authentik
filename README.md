# lab-authentik

Helm chart and local lab environment for deploying [Authentik](https://goauthentik.io/) on a hardened Talos Kubernetes cluster enforcing the `restricted` Pod Security Standard (PSS), using Traefik Kubernetes Gateway API alongside a Cloudflare Tunnel, Longhorn for persistent storage, and [`joeckr/oci-postgres`](https://github.com/joeckr/oci-postgres) as the rootless PostgreSQL backend.

> **Note**: Authentik 2025.10+ removed Redis completely—caching, sessions, and worker queues run directly on PostgreSQL.

---

## Architecture & Features

- **Authentik Server & Worker (`chart/`)**:
  - Runs `ghcr.io/goauthentik/server` (`2026.8.5`) as dedicated `server` and `worker` Deployments with health/readiness/startup probes.
  - Strictly compliant with Kubernetes **Restricted PSS** (`runAsNonRoot: true`, `runAsUser: 1000`, `fsGroup: 1000`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `seccompProfile: RuntimeDefault`, `automountServiceAccountToken: false`).
- **Rootless PostgreSQL Subchart ([`joeckr/oci-postgres`](https://github.com/joeckr/oci-postgres))**:
  - Declared as an OCI Helm dependency (`oci://ghcr.io/joeckr/charts`, `postgres` `0.2.3`) using `ghcr.io/joeckr/postgres:18`.
  - Runs rootless under Restricted PSS with `PGDATA=/tmp/data` backed by a Longhorn PVC.
  - Can be disabled (`postgres.enabled=false`) in favor of an external PostgreSQL database (`externalPostgres.*`).
- **Longhorn Storage (`persistence.media` & `postgres`)**:
  - PostgreSQL PVC defaults to `storageClass: "longhorn"` (`ReadWriteOnce`, `5Gi`).
  - Authentik `/media` PVC defaults to `storageClass: "longhorn"` (`ReadWriteMany`, `2Gi`) so `server` and `worker` can schedule across different Talos nodes. Switch to `ReadWriteOnce` for single-node clusters or disable `persistence.media.enabled` if not needed.
- **Traefik Kubernetes Gateway API + Cloudflare Tunnel (`HTTPRoute`)**:
  - Exposes Authentik via a `gateway.networking.k8s.io/v1` `HTTPRoute` attached to your Traefik `Gateway` (`parentRefs`).
  - Configures `AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS` so Authentik trusts `X-Forwarded-Proto` and `X-Forwarded-For` headers forwarded from Cloudflare Tunnel through Traefik.
- **Local Compose (`compose.yml`)**:
  - Runs `ghcr.io/joeckr/postgres:18` alongside Authentik `server` and `worker` locally with Podman Compose.

---

## Directory Structure

```text
.
├── .github/
│   └── workflows/
│       ├── lint.yml                # Lints workflows, commits, and shell scripts
│       ├── security.yml            # Scans for secrets and audits workflow security
│       ├── release.yml             # Semantic release and Helm chart publishing to GHCR
│       └── test_release.yml        # PR dry-run test for releases and chart packaging
├── chart/
│   ├── Chart.yaml                  # Helm chart definition + oci-postgres dependency
│   ├── Chart.lock                  # Locked OCI subchart dependencies
│   ├── values.yaml                 # Default configuration values
│   ├── .helmignore                 # Ignore rules for chart packaging
│   └── templates/
│       ├── _helpers.tpl            # Template helpers
│       ├── configmap.yaml          # Non-sensitive Authentik configuration
│       ├── secret.yaml             # Authentik secret key & DB credentials
│       ├── pvc.yaml                # Longhorn PVC for Authentik /media
│       ├── server-deployment.yaml  # Authentik server Deployment
│       ├── worker-deployment.yaml  # Authentik worker Deployment
│       ├── service.yaml            # ClusterIP Service for Authentik server
│       └── httproute.yaml          # Traefik Gateway API HTTPRoute
├── compose.yml                     # Local Podman Compose stack
├── hk.pkl                          # hk git hooks and checks configuration
├── mise.toml                       # Mise tools and tasks
└── README.md
```

---

## Security & Restricted PSS Compliance

| Security Dimension | Restricted PSS Requirement | Implementation |
|---|---|---|
| **Workload Execution** | Non-root UID (`runAsNonRoot: true`) | Authentik (`1000:1000`) & `oci-postgres` (rootless, `fsGroup: 1031`) |
| **Capabilities** | Must drop `ALL` capabilities | `capabilities.drop: ["ALL"]` on all containers |
| **Privilege Escalation** | Prohibited | `allowPrivilegeEscalation: false` |
| **Seccomp Profile** | `RuntimeDefault` or `Localhost` | `seccompProfile: { type: RuntimeDefault }` |
| **Service Account Token** | Disabled unless required | `automountServiceAccountToken: false` |
| **Port Binding** | Unprivileged (> 1024) | Authentik `9000`/`9443`/`9300`, PostgreSQL `5432` |
| **Ingress / Routing** | Gateway API `HTTPRoute` | `gateway.networking.k8s.io/v1` attached to Traefik `Gateway` |

---

## Traefik Gateway API & Cloudflare Tunnel Setup

This chart assumes your Talos cluster runs:
1. **Traefik** with the Kubernetes Gateway API provider enabled and a `Gateway` resource (default: `traefik-gateway` in namespace `gateway`, listener `web`) with `allowedRoutes.namespaces.from: All` (or matching your target namespace).
2. **Cloudflare Tunnel (`cloudflared`)** routing your Authentik hostname (e.g., `auth.joeckr.dev`) to the Traefik Gateway service (e.g., `http://traefik.traefik.svc.cluster.local:80`).

> [!IMPORTANT]
> In Cloudflare Dashboard, set SSL/TLS encryption mode to **Full** or **Full (strict)** to avoid redirect loops. Authentik's `AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS` is preconfigured for private cluster CIDRs so `X-Forwarded-Proto: https` is honored.

---

## Deploying to Talos Kubernetes

### 1. Prepare Target Namespace (Restricted PSS)

```sh
kubectl create namespace authentik
kubectl label namespace authentik \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/enforce-version=latest
```

### 2. Build Dependencies & Lint

```sh
mise run helm-l
mise run helm-t
```

### 3. Install the Chart

Generate strong random credentials and install:

```sh
helm upgrade --install authentik chart/ \
  --namespace authentik \
  --set authentik.secretKey="$(openssl rand -base64 48)" \
  --set postgres.postgres.password="$(openssl rand -base64 24)" \
  --set httpRoute.hostnames[0]="auth.joeckr.dev" \
  --set httpRoute.parentRefs[0].name="traefik-gateway" \
  --set httpRoute.parentRefs[0].namespace="gateway"
```

Alternatively, pass an existing Kubernetes Secret via `authentik.existingSecret` containing `AUTHENTIK_SECRET_KEY` and `AUTHENTIK_POSTGRESQL__PASSWORD`.

### 4. Verify Deployment

```sh
kubectl -n authentik get pods,pvc,httproute
kubectl -n authentik logs -l app.kubernetes.io/component=server -f
```

After initial startup, complete setup at `https://<your-hostname>/if/flow/initial-setup/` (or via port-forward: `kubectl -n authentik port-forward svc/authentik-lab-authentik-server 9000:9000`).

---

## Key Configuration (`chart/values.yaml`)

| Parameter | Description | Default |
|---|---|---|
| `authentik.image.repository` | Authentik container image | `ghcr.io/goauthentik/server` |
| `authentik.image.tag` | Authentik image tag | `"2026.8.5"` |
| `authentik.secretKey` | Authentik signing/encryption secret | placeholder |
| `authentik.existingSecret` | Existing Secret name (skips creating Secret) | `""` |
| `authentik.trustedProxyCidrs` | Trusted proxy CIDRs for `X-Forwarded-*` | RFC1918 + loopback |
| `persistence.media.enabled` | Enable Longhorn PVC for `/media` | `true` |
| `persistence.media.storageClass` | StorageClass for `/media` PVC | `"longhorn"` |
| `persistence.media.accessMode` | Access mode for `/media` PVC | `ReadWriteMany` |
| `persistence.media.size` | Storage size for `/media` PVC | `2Gi` |
| `httpRoute.enabled` | Create Gateway API `HTTPRoute` | `true` |
| `httpRoute.parentRefs` | Target Traefik `Gateway` reference | `gateway/traefik-gateway` (`web`) |
| `httpRoute.hostnames` | Hostnames matched by the `HTTPRoute` | `["auth.joeckr.dev"]` |
| `postgres.enabled` | Deploy embedded `oci-postgres` subchart | `true` |
| `postgres.postgres.image` | Rootless PostgreSQL image | `ghcr.io/joeckr/postgres` |
| `postgres.postgres.tag` | PostgreSQL major version tag | `"18"` |
| `postgres.postgres.storageClass` | StorageClass for PostgreSQL PVC | `"longhorn"` |
| `postgres.postgres.storageSize` | Storage size for PostgreSQL PVC | `5Gi` |

---

## Local Development & Tasks

Run tasks with `mise run <task>`:

| Task | Description | Command |
|---|---|---|
| `install` | Install tools and set up git hooks | `hk install --mise` |
| `hk` (or `check`) | Run all linters and hook checks | `hk check --all` |
| `compose` | Start local stack with Podman Compose | `podman compose up -d` |
| `down` | Stop local Podman Compose stack | `podman compose down` |
| `logs` | View Podman Compose logs | `podman compose logs -f` |
| `helm-d` | Build Helm chart dependencies | `helm dependency build chart/` |
| `helm-l` | Lint Helm chart | `helm lint chart/` |
| `helm-t` | Render Helm chart templates to `rendered.yaml` | `helm template test chart/ > rendered.yaml` |
| `helm-i` | Install Helm chart to current Kubernetes cluster | `helm install test chart/` |
| `helm-u` | Uninstall Helm chart release from cluster | `helm uninstall test` |
| `trivy-fs` | Scan repository filesystem for vulnerabilities | `trivy fs .` |

## License

Please refer to the `LICENSE` file for details.
