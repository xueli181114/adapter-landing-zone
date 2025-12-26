# HyperFleet Landing Zone Adapter

Event-driven adapter for HyperFleet cluster provisioning. Handles environment preparation and prerequisite setup for GCP-based cluster provisioning operations. Consumes CloudEvents from message brokers (GCP Pub/Sub, RabbitMQ), processes AdapterConfig, manages Kubernetes resources, and reports status via API.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Local Development](#local-development)
  - [GCP Authentication](#gcp-authentication)
- [Helm Chart Installation](#helm-chart-installation)
- [Configuration](#configuration)
- [Examples](#examples)
- [GCP Workload Identity Setup](#gcp-workload-identity-setup)
- [Notes](#notes)

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- GCP Workload Identity (for Pub/Sub access)
- `gcloud` CLI configured with appropriate permissions

## Local Development

Run the adapter locally for development and testing.

### Prerequisites

- `hyperfleet-adapter` binary installed and in PATH
- GCP service account key for Pub/Sub access (see [GCP Authentication](#gcp-authentication))
- Access to a GKE cluster (for applying Kubernetes resources)
- `podman` or `docker` for RabbitMQ (if `BROKER_TYPE=rabbitmq`)

### Setup

1. Copy environment template:

```bash
cp env.example .env
```

2. Edit `.env` with your configuration:

```bash
# Required for Google Pub/Sub (default)
GCP_PROJECT_ID="your-gcp-project-id"
BROKER_TOPIC="hyperfleet-adapter-topic"
BROKER_SUBSCRIPTION_ID="hyperfleet-adapter-landing-zone-subscription"

# Required for all broker types
HYPERFLEET_API_BASE_URL="https://localhost:8000"

# Optional (defaults provided)
SUBSCRIBER_PARALLELISM="1"
HYPERFLEET_API_VERSION="v1"

# Required for RabbitMQ (if BROKER_TYPE=rabbitmq)
# RABBITMQ_URL="amqp://guest:guest@localhost:5672/"
```

3. Set up GCP authentication (see [GCP Authentication](#gcp-authentication) for detailed steps):

```bash
# Create service account key and set in .env
export GOOGLE_APPLICATION_CREDENTIALS="./sa-key.json"
```

4. Connect to your GKE cluster (required for the adapter to apply Kubernetes resources):

```bash
# Get credentials for your GKE cluster (using variables from .env)
gcloud container clusters get-credentials "$GKE_CLUSTER_NAME" \
  --region "$GKE_CLUSTER_REGION" \
  --project "$GCP_PROJECT_ID"

# Verify connection
kubectl cluster-info
```

### Run

```bash
# For Google Pub/Sub (default)
make run-local

# For RabbitMQ
BROKER_TYPE=rabbitmq make run-local

# For RabbitMQ with Docker (override default podman)
BROKER_TYPE=rabbitmq CONTAINER_RUNTIME=docker make run-local
```

The script will:
- Auto-source `.env` if it exists
- Verify `hyperfleet-adapter` is installed
- Validate required environment variables
- **Auto-create Pub/Sub topic and subscription if missing** (for `googlepubsub` type)
- **Manage RabbitMQ container** (start/create for `rabbitmq` type)
- Generate broker config from `configs/broker-local-pubsub.yaml` or `configs/broker-local-rabbitmq.yaml`
- Start the adapter with verbose logging

### Local Environment Variables

| Variable | Required | Description | Default |
|----------|----------|-------------|---------|
| `GCP_PROJECT_ID` | Yes* | GCP project ID | - |
| `GKE_CLUSTER_NAME` | Yes | GKE cluster name for kubeconfig | - |
| `GKE_CLUSTER_REGION` | Yes | GKE cluster region (or use `GKE_CLUSTER_ZONE`) | - |
| `BROKER_TOPIC` | Yes* | Pub/Sub topic name | - |
| `BROKER_SUBSCRIPTION_ID` | Yes* | Pub/Sub subscription ID | - |
| `HYPERFLEET_API_BASE_URL` | Yes | HyperFleet API base URL | - |
| `SUBSCRIBER_PARALLELISM` | No | Number of parallel workers | `1` |
| `HYPERFLEET_API_VERSION` | No | API version | `v1` |
| `GOOGLE_APPLICATION_CREDENTIALS` | Yes* | Path to service account key file (recommended) | - |
| `RABBITMQ_URL` | No** | RabbitMQ connection URL (when using RabbitMQ broker) | `amqp://guest:guest@localhost:5672/` |
| `BROKER_TYPE` | No | Broker type: `googlepubsub` or `rabbitmq` | `googlepubsub` |
| `CONTAINER_RUNTIME` | No | Container runtime for RabbitMQ | `podman` |

\* Required when using GCP Pub/Sub broker (default)
\*\* Required when using RabbitMQ broker

### GCP Authentication

The adapter uses GCP Application Default Credentials (ADC). **Recommended:** Use a service account key file to avoid conflicts with other applications.

```bash
# 1. Create service account
gcloud iam service-accounts create hyperfleet-adapter-local \
  --project="$GCP_PROJECT_ID" \
  --display-name="HyperFleet Adapter Local Dev"

# 2. Grant Pub/Sub permissions
gcloud projects add-iam-policy-binding "$GCP_PROJECT_ID" \
  --member="serviceAccount:hyperfleet-adapter-local@${GCP_PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/pubsub.subscriber"

# 3. Create key file
gcloud iam service-accounts keys create ./sa-key.json \
  --iam-account="hyperfleet-adapter-local@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

# 4. Add to .env
export GOOGLE_APPLICATION_CREDENTIALS="./sa-key.json"
```

> ⚠️ **Warning:** Do NOT use `gcloud auth application-default login` - it will override your default credentials and may block other applications using ADC from a different project.

## Helm Chart Installation

### Installing the Chart

```bash
helm install landing-zone ./charts/
```

### Install to a Specific Namespace

```bash
helm install landing-zone ./charts/ \
  --namespace hyperfleet-system \
  --create-namespace
```

### Uninstalling the Chart

```bash
helm delete landing-zone

# Or with namespace
helm delete landing-zone --namespace hyperfleet-system
```

## Configuration

All configurable parameters are in `values.yaml`. For advanced customization, modify the templates directly.

### Image & Replica

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of replicas | `1` |
| `image.registry` | Image registry | `quay.io/openshift-hyperfleet` |
| `image.repository` | Image repository | `hyperfleet-adapter` |
| `image.tag` | Image tag | `latest` |
| `image.pullPolicy` | Image pull policy | `Always` |
| `imagePullSecrets` | Image pull secrets | `[]` |

### Naming

| Parameter | Description | Default |
|-----------|-------------|---------|
| `nameOverride` | Override chart name | `""` |
| `fullnameOverride` | Override full release name | `""` |

### ServiceAccount & RBAC

| Parameter | Description | Default |
|-----------|-------------|---------|
| `serviceAccount.create` | Create ServiceAccount | `true` |
| `serviceAccount.name` | ServiceAccount name (auto-generated if empty) | `""` |
| `serviceAccount.annotations` | ServiceAccount annotations (for Workload Identity) | `{}` |
| `rbac.create` | Create ClusterRole and ClusterRoleBinding | `false` |
| `rbac.namespaceAdmin` | Grant namespace admin permissions | `false` |

When `rbac.namespaceAdmin=true`, the adapter gets full access to:
- Namespaces (create, update, delete)
- Core resources (configmaps, secrets, serviceaccounts, services, pods, PVCs)
- Apps (deployments, statefulsets, daemonsets, replicasets)
- Batch (jobs, cronjobs)
- Networking (ingresses, networkpolicies)
- RBAC (roles, rolebindings)

### Logging

| Parameter | Description | Default |
|-----------|-------------|---------|
| `logging.level` | Log level (`debug`, `info`, `warn`, `error`) | `info` |
| `logging.format` | Log format (`text`, `json`) | `text` |
| `logging.output` | Log output (`stdout`, `stderr`) | `stderr` |

### Scheduling

| Parameter | Description | Default |
|-----------|-------------|---------|
| `nodeSelector` | Node selector | `{}` |
| `tolerations` | Tolerations | `[]` |
| `affinity` | Affinity rules | `{}` |

### Adapter Configuration

The adapter config is always created from `charts/configs/adapter-landing-zone.yaml`:
- Mounted at `/etc/adapter/adapter.yaml`
- Exposed via `ADAPTER_CONFIG_PATH` environment variable

To customize, edit `charts/configs/adapter-landing-zone.yaml` directly.

### Broker Configuration

The broker configuration generates a `broker.yaml` file that is mounted as a ConfigMap.

#### General Settings

| Parameter | Description | Default |
|-----------|-------------|---------|
| `broker.type` | Broker type: `googlepubsub` or `rabbitmq` (**required**) | `""` |
| `broker.subscriber.parallelism` | Number of parallel workers | `1` |
| `broker.yaml` | Raw YAML override (advanced use) | `""` |

#### Google Pub/Sub (when `broker.type=googlepubsub`)

| Parameter | Description | Default |
|-----------|-------------|---------|
| `broker.googlepubsub.projectId` | GCP project ID (**required**) | `""` |
| `broker.googlepubsub.topic` | Pub/Sub topic name (**required**) | `""` |
| `broker.googlepubsub.subscription` | Pub/Sub subscription ID (**required**) | `""` |
| `broker.googlepubsub.deadLetterTopic` | Dead letter topic name (optional) | `""` |

Other Pub/Sub settings (ack deadline, retention, goroutines, etc.) are configured with sensible defaults in the broker config template.

#### RabbitMQ (when `broker.type=rabbitmq`)

| Parameter | Description | Default |
|-----------|-------------|---------|
| `broker.rabbitmq.url` | RabbitMQ connection URL (**required**) | `""` |

> **Note:** The `broker.rabbitmq.url` must be provided via `--set` or values file. Do not commit credentials to version control.
> Format: `amqp://username:password@hostname:port/vhost`

Other RabbitMQ settings (exchange type, prefetch count, etc.) are configured with sensible defaults in the broker config template.

When `broker.type` is set:
- Generates `broker.yaml` from structured values
- Creates ConfigMap with `broker.yaml` key
- Mounts at `/etc/broker/broker.yaml`
- Sets `BROKER_CONFIG_FILE=/etc/broker/broker.yaml`

### HyperFleet API

| Parameter | Description | Default |
|-----------|-------------|---------|
| `hyperfleetApi.baseUrl` | HyperFleet API base URL | `""` |
| `hyperfleetApi.version` | API version | `v1` |

### Environment Variables

| Parameter | Description | Default |
|-----------|-------------|---------|
| `env` | Additional environment variables | `[]` |

Example:
```yaml
env:
  - name: MY_VAR
    value: "my-value"
  - name: MY_SECRET
    valueFrom:
      secretKeyRef:
        name: my-secret
        key: key
```

## Examples

### Basic Installation with Google Pub/Sub

```bash
helm install landing-zone ./charts/ \
  --set broker.type=googlepubsub \
  --set broker.googlepubsub.projectId=my-gcp-project \
  --set broker.googlepubsub.topic=my-topic \
  --set broker.googlepubsub.subscription=my-subscription
```

### With HyperFleet API Configuration

```bash
helm install landing-zone ./charts/ \
  --set hyperfleetApi.baseUrl=https://api.hyperfleet.example.com \
  --set broker.type=googlepubsub \
  --set broker.googlepubsub.projectId=my-gcp-project \
  --set broker.googlepubsub.topic=my-topic \
  --set broker.googlepubsub.subscription=my-subscription
```

### With RabbitMQ

```bash
helm install landing-zone ./charts/ \
  --set broker.type=rabbitmq \
  --set broker.rabbitmq.url="amqp://user:password@rabbitmq.svc:5672/"
```

> **Security:** For production, store credentials in a Kubernetes Secret and reference via `env`.

### With GCP Workload Identity and RBAC

First, grant Pub/Sub permissions to the KSA (before deploying):

```bash
# Get project number
gcloud projects describe my-gcp-project --format="value(projectNumber)"

# Grant permissions using direct principal binding (no GSA needed)
gcloud projects add-iam-policy-binding my-gcp-project \
  --role="roles/pubsub.subscriber" \
  --member="principal://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/my-gcp-project.svc.id.goog/subject/ns/hyperfleet-system/sa/landing-zone"
```

Then deploy:

```bash
helm install landing-zone ./charts/ \
  --namespace hyperfleet-system \
  --create-namespace \
  --set image.registry=us-central1-docker.pkg.dev/my-project/my-repo \
  --set image.repository=hyperfleet-adapter \
  --set image.tag=v0.1.0 \
  --set broker.type=googlepubsub \
  --set broker.googlepubsub.projectId=my-gcp-project \
  --set broker.googlepubsub.topic=my-topic \
  --set broker.googlepubsub.subscription=my-subscription \
  --set hyperfleetApi.baseUrl=https://api.hyperfleet.example.com \
  --set rbac.create=true \
  --set rbac.namespaceAdmin=true
```

### With Custom Logging

```bash
helm install landing-zone ./charts/ \
  --set logging.level=debug \
  --set logging.format=json \
  --set logging.output=stdout \
  --set broker.type=googlepubsub \
  --set broker.googlepubsub.projectId=my-gcp-project \
  --set broker.googlepubsub.topic=my-topic \
  --set broker.googlepubsub.subscription=my-subscription
```

### Using Existing ServiceAccount

```bash
helm install landing-zone ./charts/ \
  --set serviceAccount.create=false \
  --set serviceAccount.name=my-existing-sa
```

### With Values File

<details>
<summary>Example <code>my-values.yaml</code></summary>

```yaml
replicaCount: 2

image:
  registry: us-central1-docker.pkg.dev/my-project/my-repo
  repository: hyperfleet-adapter
  tag: v0.1.0

serviceAccount:
  create: true
  annotations:
    iam.gke.io/gcp-service-account: adapter@my-project.iam.gserviceaccount.com

rbac:
  create: true
  namespaceAdmin: true

logging:
  level: debug
  format: json
  output: stderr

hyperfleetApi:
  baseUrl: https://api.hyperfleet.example.com
  version: v1

broker:
  type: googlepubsub
  googlepubsub:
    projectId: my-gcp-project
    topic: hyperfleet-events
    subscription: hyperfleet-adapter-subscription
  subscriber:
    parallelism: 10
```

</details>

Install with values file:

```bash
helm install landing-zone ./charts/ -f my-values.yaml
```

## Deployment Environment Variables

The deployment sets these environment variables automatically:

| Variable | Value | Condition |
|----------|-------|-----------|
| `HYPERFLEET_API_BASE_URL` | From `hyperfleetApi.baseUrl` | When set |
| `HYPERFLEET_API_VERSION` | From `hyperfleetApi.version` | Always (default: v1) |
| `ADAPTER_CONFIG_PATH` | `/etc/adapter/adapter.yaml` | Always |
| `BROKER_CONFIG_FILE` | `/etc/broker/broker.yaml` | When `broker.type` is set |
| `BROKER_SUBSCRIPTION_ID` | From `broker.googlepubsub.subscription` | When `broker.type=googlepubsub` |
| `BROKER_TOPIC` | From `broker.googlepubsub.topic` | When `broker.type=googlepubsub` |
| `GCP_PROJECT_ID` | From `broker.googlepubsub.projectId` | When `broker.type=googlepubsub` |

## GCP Workload Identity Setup

Grant GCP Pub/Sub permissions to the Kubernetes Service Account using **Workload Identity Federation**.

### Step 1: Get Project Number

```bash
gcloud projects describe MY_PROJECT --format="value(projectNumber)"
```

### Step 2: Grant Pub/Sub Permissions to KSA (Direct Principal Binding)

Run this **before** deploying so the pod works immediately:

```bash
# Grant subscriber permission
gcloud projects add-iam-policy-binding MY_PROJECT \
  --role="roles/pubsub.subscriber" \
  --member="principal://iam.googleapis.com/projects/MY_PROJECT_NUMBER/locations/global/workloadIdentityPools/MY_PROJECT.svc.id.goog/subject/ns/MY_NAMESPACE/sa/landing-zone" \
  --condition=None

# Grant viewer permission (required to read subscription metadata)
gcloud projects add-iam-policy-binding MY_PROJECT \
  --role="roles/pubsub.viewer" \
  --member="principal://iam.googleapis.com/projects/MY_PROJECT_NUMBER/locations/global/workloadIdentityPools/MY_PROJECT.svc.id.goog/subject/ns/MY_NAMESPACE/sa/landing-zone" \
  --condition=None
```

> **Note:** This uses direct principal binding - no Google Service Account (GSA) required. The binding works even before the KSA exists.

### Step 3: Wait for IAM Propagation

IAM changes can take 1-2 minutes to propagate. Wait until permissions are active:

```bash
# Wait until permissions are propagated
echo "Waiting for IAM propagation..."
while ! gcloud pubsub subscriptions describe MY_SUBSCRIPTION \
  --project=MY_PROJECT &>/dev/null; do
  echo "  Waiting for permissions to propagate..."
  sleep 10
done
echo "Permissions propagated!"
```

### Step 4: Deploy

```bash
helm install landing-zone ./charts/ \
  --namespace MY_NAMESPACE \
  --create-namespace \
  --set broker.type=googlepubsub \
  --set broker.googlepubsub.projectId=MY_PROJECT \
  --set broker.googlepubsub.topic=MY_TOPIC \
  --set broker.googlepubsub.subscription=MY_SUBSCRIPTION \
  --set rbac.create=true \
  --set rbac.namespaceAdmin=true
```

> **Note:** Replace the following placeholders:
> - `MY_PROJECT` - Your GCP project ID
> - `MY_PROJECT_NUMBER` - Your GCP project number (from Step 1)
> - `MY_NAMESPACE` - Kubernetes namespace (e.g., `hyperfleet-system`)
> - `MY_TOPIC` - Pub/Sub topic name
> - `MY_SUBSCRIPTION` - Pub/Sub subscription name
> - `landing-zone` - The Helm release name (KSA name)

### Step 5: Verify Workload Identity

```bash
# Test authentication from pod
kubectl run -it --rm debug \
  --image=google/cloud-sdk:slim \
  --serviceaccount=landing-zone \
  --namespace=MY_NAMESPACE \
  -- gcloud auth list
```

## Notes

- The adapter runs as non-root user (UID 65532) with read-only filesystem
- Health probes are disabled by default (adapter is a message consumer, not HTTP server)
- Uses `distroless` base image for minimal attack surface
- Config checksum annotation triggers pod restart on ConfigMap changes
- Default resource limits: 500m CPU, 512Mi memory
- Default resource requests: 100m CPU, 128Mi memory

## License

See [LICENSE](LICENSE) for details.
