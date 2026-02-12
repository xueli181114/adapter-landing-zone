# Makefile for HyperFleet Adapter Landing Zone
#
# Usage:
#   make help              - Show this help
#   make helm-lint         - Lint helm chart
#   make helm-template     - Render helm templates
#   make helm-test         - Run all helm tests

.PHONY: help test test-helm \
        helm-lint helm-template helm-template-broker helm-template-rabbitmq helm-test helm-dry-run helm-package \
        helm-template-full \
        helm-install helm-upgrade helm-uninstall helm-status \
        run-local run-maestro validate-adapter-yaml validate

# Default values
RELEASE_NAME ?= landing-zone
NAMESPACE ?= hyperfleet-system
CHART_DIR := ./charts

# Colors for output
GREEN := \033[0;32m
YELLOW := \033[0;33m
NC := \033[0m # No Color

##@ General

help: ## Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Testing

test: ## Run all tests (placeholder for pre-submit jobs)
	@echo "$(GREEN)Running tests...$(NC)"
	@echo "No tests configured yet. This is a placeholder to unblock pre-submit jobs."
	@exit 0

##@ Helm Chart Testing

helm-lint: ## Lint the helm chart
	@echo "$(GREEN)Linting helm chart...$(NC)"
	helm lint $(CHART_DIR)

helm-template: ## Render helm templates with default values
	@echo "$(GREEN)Rendering helm templates (default values)...$(NC)"
	helm template $(RELEASE_NAME) $(CHART_DIR)

helm-template-broker: ## Render helm templates with Google Pub/Sub broker
	@echo "$(GREEN)Rendering helm templates (Google Pub/Sub broker)...$(NC)"
	helm template $(RELEASE_NAME) $(CHART_DIR) \
		--set broker.type=googlepubsub \
		--set broker.googlepubsub.projectId=test-project \
		--set broker.googlepubsub.topic=test-topic \
		--set broker.googlepubsub.subscription=test-subscription

helm-template-rabbitmq: ## Render helm templates with RabbitMQ broker
	@echo "$(GREEN)Rendering helm templates (RabbitMQ broker)...$(NC)"
	helm template $(RELEASE_NAME) $(CHART_DIR) \
		--set broker.type=rabbitmq \
		--set broker.rabbitmq.url="amqp://guest:guest@rabbitmq:5672/"

helm-template-full: ## Render helm templates with full configuration
	@echo "$(GREEN)Rendering helm templates (full configuration)...$(NC)"
	helm template $(RELEASE_NAME) $(CHART_DIR) \
		--namespace $(NAMESPACE) \
		--set broker.type=googlepubsub \
		--set broker.googlepubsub.projectId=my-project \
		--set broker.googlepubsub.topic=my-topic \
		--set broker.googlepubsub.subscription=my-subscription \
		--set broker.googlepubsub.deadLetterTopic=my-dlq \
		--set broker.subscriber.parallelism=20 \
		--set hyperfleetApi.baseUrl=https://api.hyperfleet.example.com \
		--set rbac.create=true \
		--set rbac.namespaceAdmin=true

test-helm: helm-lint helm-template-broker helm-template-rabbitmq ## Run all helm chart tests (lint + template rendering)
	@echo "$(GREEN)All helm chart tests passed!$(NC)"

helm-dry-run: ## Simulate helm install (requires cluster connection)
	@echo "$(YELLOW)Simulating helm install (dry-run)...$(NC)"
	helm install $(RELEASE_NAME) $(CHART_DIR) \
		--namespace $(NAMESPACE) \
		--create-namespace \
		--dry-run \
		--debug \
		--set broker.type=googlepubsub \
		--set broker.googlepubsub.projectId=test-project \
		--set broker.googlepubsub.topic=test-topic \
		--set broker.googlepubsub.subscription=test-subscription

helm-package: ## Package helm chart
	@echo "$(GREEN)Packaging helm chart...$(NC)"
	helm package $(CHART_DIR)

##@ Helm Chart Deployment

helm-install: ## Install helm chart to cluster
	@echo "$(GREEN)Installing helm chart...$(NC)"
	helm install $(RELEASE_NAME) $(CHART_DIR) \
		--namespace $(NAMESPACE) \
		--create-namespace

helm-upgrade: ## Upgrade helm chart
	@echo "$(GREEN)Upgrading helm chart...$(NC)"
	helm upgrade $(RELEASE_NAME) $(CHART_DIR) \
		--namespace $(NAMESPACE)

helm-uninstall: ## Uninstall helm chart
	@echo "$(YELLOW)Uninstalling helm chart...$(NC)"
	helm uninstall $(RELEASE_NAME) --namespace $(NAMESPACE)

helm-status: ## Show helm release status
	helm status $(RELEASE_NAME) --namespace $(NAMESPACE)

##@ Local Development

run-local: ## Run adapter locally in K8s mode (auto-sources .env if exists)
	@./run-local.sh

run-maestro: ## Run adapter locally in Maestro mode
	@ADAPTER_MODE=maestro ./run-local.sh

##@ Validation

validate-adapter-yaml: ## Validate charts/configs/adapter-landing-zone.yaml syntax
	@echo "$(GREEN)Validating charts/configs/adapter-landing-zone.yaml...$(NC)"
	@cat charts/configs/adapter-landing-zone.yaml | yq '.' > /dev/null && echo "adapter-landing-zone.yaml is valid YAML" || echo "adapter-landing-zone.yaml has syntax errors"

validate-broker-pubsub: ## Validate charts/configs/broker-pubsub.yaml syntax
	@echo "$(GREEN)Validating charts/configs/broker-pubsub.yaml...$(NC)"
	@cat charts/configs/broker-pubsub.yaml | yq '.' > /dev/null && echo "broker-pubsub.yaml is valid YAML" || echo "broker-pubsub.yaml has syntax errors"

validate-broker-rabbitmq: ## Validate charts/configs/broker-rabbitmq.yaml syntax
	@echo "$(GREEN)Validating charts/configs/broker-rabbitmq.yaml...$(NC)"
	@cat charts/configs/broker-rabbitmq.yaml | yq '.' > /dev/null && echo "broker-rabbitmq.yaml is valid YAML" || echo "broker-rabbitmq.yaml has syntax errors"

validate: validate-adapter-yaml validate-broker-pubsub validate-broker-rabbitmq ## Validate all YAML files
