#!/bin/bash
# Local development runner for HyperFleet Landing Zone Adapter
#
# Usage:
#   make run-local                      # K8s mode with Pub/Sub (default)
#   make run-maestro                    # Maestro mode
#   BROKER_TYPE=rabbitmq make run-local # RabbitMQ broker
#   ADAPTER_MODE=maestro make run-local # Maestro mode (alternative)
#
# Environment variables:
#   ADAPTER_MODE              - "k8s" (default) or "maestro"
#   HYPERFLEET_ADAPTER_CONFIG - Override adapter config path
#   HYPERFLEET_TASK_CONFIG    - Override task config path
#
# Setup:
#   cp env.example .env
#   # Edit .env with your values

set -e

# Auto-source .env if exists
if [ -f .env ]; then
  echo "Loading .env..."
  set -a
  source .env
  set +a
fi

# Check if hyperfleet-adapter is installed
if ! command -v hyperfleet-adapter &> /dev/null; then
  echo "Error: hyperfleet-adapter is not installed or not in PATH"
  exit 1
fi

# Set defaults for envsubst (envsubst doesn't support ${VAR:-default} syntax)
export BROKER_TYPE="${BROKER_TYPE:-googlepubsub}"
export SUBSCRIBER_PARALLELISM="${SUBSCRIBER_PARALLELISM:-1}"
export HYPERFLEET_API_VERSION="${HYPERFLEET_API_VERSION:-v1}"
export HYPERFLEET_DEBUG_CONFIG="${HYPERFLEET_DEBUG_CONFIG:-false}"
export RABBITMQ_URL="${RABBITMQ_URL:-amqp://guest:guest@localhost:5672/}"
export SIMULATE_RESULT="${SIMULATE_RESULT:-success}"

# Check required env vars based on broker type
: "${HYPERFLEET_API_BASE_URL:?Set HYPERFLEET_API_BASE_URL}"

# Configure kubeconfig for GKE cluster (required for K8s resource management)
# KUBECONFIG should be set in .env to ensure adapter uses kubeconfig instead of in-cluster config
: "${KUBECONFIG:?Set KUBECONFIG in .env (e.g., export KUBECONFIG=\$HOME/.kube/config)}"
echo "Using KUBECONFIG: $KUBECONFIG"

if [ -n "$GKE_CLUSTER_NAME" ] && [ -n "$GCP_PROJECT_ID" ]; then
  if [ -n "$GKE_CLUSTER_REGION" ]; then
    echo "Configuring kubeconfig for GKE cluster: $GKE_CLUSTER_NAME (region: $GKE_CLUSTER_REGION)..."
    gcloud container clusters get-credentials "$GKE_CLUSTER_NAME" \
      --region "$GKE_CLUSTER_REGION" \
      --project "$GCP_PROJECT_ID" --quiet
  elif [ -n "$GKE_CLUSTER_ZONE" ]; then
    echo "Configuring kubeconfig for GKE cluster: $GKE_CLUSTER_NAME (zone: $GKE_CLUSTER_ZONE)..."
    gcloud container clusters get-credentials "$GKE_CLUSTER_NAME" \
      --zone "$GKE_CLUSTER_ZONE" \
      --project "$GCP_PROJECT_ID" --quiet
  else
    echo "Warning: GKE_CLUSTER_NAME is set but GKE_CLUSTER_REGION or GKE_CLUSTER_ZONE is missing."
    echo "Set one of them in .env to auto-configure kubeconfig."
  fi
else
  echo "Warning: GKE_CLUSTER_NAME not set. Assuming kubeconfig is already configured."
fi

if [ "$BROKER_TYPE" = "rabbitmq" ]; then
  echo "Using RabbitMQ broker..."
  : "${RABBITMQ_URL:=amqp://guest:guest@localhost:5672/}"

  # Check if RabbitMQ is running, start if not
  CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-podman}"
  RABBITMQ_CONTAINER="rabbitmq-local"
  
  if ! $CONTAINER_RUNTIME ps --format '{{.Names}}' 2>/dev/null | grep -q "^${RABBITMQ_CONTAINER}$"; then
    if $CONTAINER_RUNTIME ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${RABBITMQ_CONTAINER}$"; then
      echo "Starting existing RabbitMQ container..."
      $CONTAINER_RUNTIME start "$RABBITMQ_CONTAINER"
    else
      echo "Starting new RabbitMQ container..."
      $CONTAINER_RUNTIME run -d \
        --name "$RABBITMQ_CONTAINER" \
        -p 5672:5672 \
        -p 15672:15672 \
        rabbitmq:3-management
    fi
    echo "Waiting for RabbitMQ to be ready..."
    sleep 5
  else
    echo "RabbitMQ container already running."
  fi
else
  echo "Using Google Pub/Sub broker..."
  : "${GCP_PROJECT_ID:?Set GCP_PROJECT_ID}"
  : "${BROKER_TOPIC:?Set BROKER_TOPIC}"
  : "${BROKER_SUBSCRIPTION_ID:?Set BROKER_SUBSCRIPTION_ID}"

  # Set up Application Default Credentials (ADC) for Go SDK
  # This is separate from gcloud CLI auth (gcloud auth login)
  if [ -n "$GOOGLE_APPLICATION_CREDENTIALS" ]; then
    if [ ! -f "$GOOGLE_APPLICATION_CREDENTIALS" ]; then
      echo "Error: GOOGLE_APPLICATION_CREDENTIALS file not found: $GOOGLE_APPLICATION_CREDENTIALS"
      exit 1
    fi
    echo "Using service account key: $GOOGLE_APPLICATION_CREDENTIALS"
  else
    ADC_FILE="${HOME}/.config/gcloud/application_default_credentials.json"
    if [ ! -f "$ADC_FILE" ]; then
      echo "Error: GCP credentials not configured."
      echo ""
      echo "Create a service account key with these steps:"
      echo ""
      echo "  # 1. Create service account"
      echo "  gcloud iam service-accounts create hyperfleet-adapter-local \\"
      echo "    --project=\"$GCP_PROJECT_ID\" \\"
      echo "    --display-name=\"HyperFleet Adapter Local Dev\""
      echo ""
      echo "  # 2. Grant Pub/Sub permissions"
      echo "  gcloud projects add-iam-policy-binding \"$GCP_PROJECT_ID\" \\"
      echo "    --member=\"serviceAccount:hyperfleet-adapter-local@${GCP_PROJECT_ID}.iam.gserviceaccount.com\" \\"
      echo "    --role=\"roles/pubsub.subscriber\""
      echo ""
      echo "  # 3. Create key file"
      echo "  gcloud iam service-accounts keys create ./sa-key.json \\"
      echo "    --iam-account=\"hyperfleet-adapter-local@${GCP_PROJECT_ID}.iam.gserviceaccount.com\""
      echo ""
      echo "  # 4. Add to .env"
      echo "  export GOOGLE_APPLICATION_CREDENTIALS=\"./sa-key.json\""
      echo ""
      echo "⚠️  WARNING: Do NOT use 'gcloud auth application-default login' - it will override credentials"
      echo "   and may block other applications using ADC from a different project."
      exit 1
    fi
    # Set quota project to match GCP_PROJECT_ID
    export GOOGLE_CLOUD_QUOTA_PROJECT="$GCP_PROJECT_ID"
    echo "⚠️  Using Application Default Credentials (may block other apps using ADC from a different project)"
    echo "   Quota project: $GCP_PROJECT_ID"
    echo "   Recommended: Set GOOGLE_APPLICATION_CREDENTIALS instead"
  fi

  # Create Pub/Sub topic if not exists
  if ! gcloud pubsub topics describe "$BROKER_TOPIC" --project="$GCP_PROJECT_ID" &>/dev/null; then
    echo "Creating Pub/Sub topic: $BROKER_TOPIC..."
    gcloud pubsub topics create "$BROKER_TOPIC" --project="$GCP_PROJECT_ID"
  fi

  # Create Pub/Sub subscription if not exists
  if ! gcloud pubsub subscriptions describe "$BROKER_SUBSCRIPTION_ID" --project="$GCP_PROJECT_ID" &>/dev/null; then
    echo "Creating Pub/Sub subscription: $BROKER_SUBSCRIPTION_ID..."
    gcloud pubsub subscriptions create "$BROKER_SUBSCRIPTION_ID" \
      --topic="$BROKER_TOPIC" \
      --project="$GCP_PROJECT_ID" \
      --ack-deadline=60
  fi
fi

# Set adapter mode (k8s or maestro)
ADAPTER_MODE="${ADAPTER_MODE:-k8s}"
echo "Adapter mode: $ADAPTER_MODE"

# Generate configs from templates
CONFIG_DIR="${TMPDIR:-/tmp}"
BROKER_CONFIG="${CONFIG_DIR}/broker-config.yaml"

# Select broker config template based on broker type
if [ "$BROKER_TYPE" = "rabbitmq" ]; then
  BROKER_CONFIG_TEMPLATE="configs/broker-local-rabbitmq.yaml"
else
  BROKER_CONFIG_TEMPLATE="configs/broker-local-pubsub.yaml"
fi

echo "Generating broker config from $BROKER_CONFIG_TEMPLATE..."
envsubst < "$BROKER_CONFIG_TEMPLATE" > "$BROKER_CONFIG"

# Set config paths based on mode
# If HYPERFLEET_ADAPTER_CONFIG is already set, use it (allows override)
if [ -z "$HYPERFLEET_ADAPTER_CONFIG" ]; then
  if [ "$ADAPTER_MODE" = "maestro" ]; then
    export HYPERFLEET_ADAPTER_CONFIG="./configs/maestro/adapter-config.yaml"
  else
    # Generate adapter config from template for k8s mode
    ADAPTER_CONFIG="${CONFIG_DIR}/adapter-config.yaml"
    echo "Generating adapter config from configs/adapter-config-local.yaml..."
    envsubst < "configs/adapter-config-local.yaml" > "$ADAPTER_CONFIG"
    export HYPERFLEET_ADAPTER_CONFIG="$ADAPTER_CONFIG"
  fi
fi

# Set task config based on mode (if not already set)
if [ -z "$HYPERFLEET_TASK_CONFIG" ]; then
  if [ "$ADAPTER_MODE" = "maestro" ]; then
    export HYPERFLEET_TASK_CONFIG="./configs/maestro/adapter-task-config.yaml"
  else
    export HYPERFLEET_TASK_CONFIG="./configs/k8s/adapter-landing-zone.yaml"
  fi
fi

export BROKER_CONFIG_FILE="$BROKER_CONFIG"

echo "Starting adapter..."
echo "  Mode: $ADAPTER_MODE"
echo "  Broker type: $BROKER_TYPE"
echo "  Adapter config: $HYPERFLEET_ADAPTER_CONFIG"
echo "  Broker config: $BROKER_CONFIG_FILE"
echo "  Task config: $HYPERFLEET_TASK_CONFIG"
exec hyperfleet-adapter serve \
  --config="$HYPERFLEET_ADAPTER_CONFIG" \
  --task-config="$HYPERFLEET_TASK_CONFIG" \
  --log-level="${LOG_LEVEL:-debug}" \
  --log-format="${LOG_FORMAT:-text}" \
  --log-output="${LOG_OUTPUT:-stderr}" \
  "$@"
