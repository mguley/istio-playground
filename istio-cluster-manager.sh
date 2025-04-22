#!/usr/bin/env bash
#
# istio-cluster-manager.sh - v1.1.0
# A helper script to manage Kubernetes clusters with Istio via kind.
#
# Prerequisites:
#   • Docker                 https://docs.docker.com/get-docker/
#   • kind                   https://kind.sigs.k8s.io/
#   • kubectl                https://kubernetes.io/docs/tasks/tools/
#   • istioctl               https://istio.io/latest/docs/setup/getting-started/#download
#
# Environment variables:
#   • ISTIO_VERSION  (default: 1.25.1)  – Istio control‑plane & addon version.
#
# Default values:
#   • Cluster name:   istio-cluster
#   • Node count:     1
#   • Node image:     (latest kindest/node)
#   • Istio profile:  demo
#
# Usage:
#   ./istio-cluster-manager.sh [command] [args]
#
# Commands:
#   create [name] [nodes] [node_image] [istio_profile]   Create a new kind cluster and install Istio
#                                                        Default profile is 'demo' if not specified
#   delete [name]                                        Delete a kind cluster
#   list                                                 List all kind clusters
#   status [name]                                        Show cluster status, Istio components, addons
#   use [name]                                           Switch kubectl context to a cluster
#   kubeconfig [name]                                    Print the kubeconfig for a cluster
#   contexts                                             List all kubectl contexts
#   install-istio [name] [profile]                       Install Istio on an existing cluster
#                                                        Default profile is 'demo' if not specified
#   install-addons [name]                                Install Istio addons (Kiali, Prometheus, …)
#   version                                              Show script, kind, kubectl & istioctl versions
#   help                                                 Display this help text
#
# Example:
#
#   # Create a 3‑node cluster named "istio-dev" with Istio demo profile
#   ./istio-cluster-manager.sh create istio-dev 3
#
#   # Create a single-node cluster with minimal Istio profile
#   ./istio-cluster-manager.sh create istio-test 1 "" minimal
#
#   # Install Istio on an existing cluster
#   ./istio-cluster-manager.sh install-istio my-cluster demo
#
#   # Install Istio addons (Kiali, Prometheus, Grafana, Jaeger)
#   ./istio-cluster-manager.sh install-addons istio-dev
#
#   # Delete "istio-dev" cluster
#   ./istio-cluster-manager.sh delete istio-dev
#

set -euo pipefail

SCRIPT_VERSION="1.1.0"
DEFAULT_CLUSTER_NAME="istio-cluster"
DEFAULT_ISTIO_PROFILE="demo"

: "${ISTIO_VERSION:=1.25.1}"
ISTIO_MAJOR_MINOR="${ISTIO_VERSION%.*}"           # 1.25.1 → 1.25
ADDON_BASE="https://raw.githubusercontent.com/istio/istio/release-${ISTIO_MAJOR_MINOR}/samples/addons"

# ANSI color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

#------------------------------------------------------------------------------
# Ensure required tools are installed
#------------------------------------------------------------------------------
check_prerequisites() {
    # Check Docker
    if ! command -v docker &>/dev/null; then
      echo -e "${RED}Error:${NC} Docker is not installed or not in your PATH."
      exit 1;
    fi

    # Check kind
    if ! command -v kind &>/dev/null; then
      echo -e "${RED}Error:${NC} kind is not installed or not in your PATH."
      exit 1
    fi

    # Check kubectl
    if ! command -v kubectl &>/dev/null; then
      echo -e "${RED}Error:${NC} kubectl is not installed or not in your PATH."
      exit 1
    fi

    # Check istioctl for commands that need it
    local cmd=$1
    if [[ "$cmd" =~ ^(install-istio|install-addons|create)$ ]] && ! command -v istioctl &>/dev/null
    then
        echo -e "${RED}istioctl not found.${NC}  Install ${ISTIO_VERSION}: https://istio.io/latest/docs/setup/getting-started/#download"
        exit 1
    fi
}

#------------------------------------------------------------------------------
# Install Istio on a cluster
#   args: [cluster_name] [istio_profile]
#------------------------------------------------------------------------------
install_istio() {
    local name="${1:-$DEFAULT_CLUSTER_NAME}"
    local profile="${2:-$DEFAULT_ISTIO_PROFILE}"

    echo -e "${BLUE}→ Installing Istio ${ISTIO_VERSION} on cluster '${name}' (profile '${profile}')...${NC}"

    # Check if the cluster exists
    if ! kind get clusters | grep -q "^${name}$"; then
        echo -e "${RED}✖ Cluster '${name}' not found.${NC}"; exit 1; fi

    # Switch kubectl context to the cluster
    kubectl config use-context "kind-${name}" &>/dev/null

    # Check if Istio is already installed
    if kubectl get ns istio-system &>/dev/null; then
        echo -e "${YELLOW}⚠ Istio already present – will attempt upgrade.${NC}"
    fi

    echo -e "${BLUE}→ Installing Istio with '${profile}' profile...${NC}"
    if ISTIO_VERSION="$ISTIO_VERSION" istioctl install --set profile="${profile}" -y; then
        echo -e "${GREEN}✔ Istio control‑plane installed.${NC}"

        # Enable automatic sidecar injection for default namespace
        echo -e "${BLUE}→ Enabling automatic sidecar injection for 'default' namespace...${NC}"
        kubectl label namespace default istio-injection=enabled --overwrite

        echo -e "${GREEN}✔ Automatic sidecar injection enabled for 'default' namespace.${NC}"
        echo -e "${BLUE}→ Verifying Istio installation:${NC}"
        kubectl get pods -n istio-system
    else
        echo -e "${RED}✖ Istio install failed.${NC}"; return 1
    fi
}

#------------------------------------------------------------------------------
# Install Istio addons (Kiali, Prometheus, Grafana, Jaeger)
#   args: [cluster_name]
#------------------------------------------------------------------------------
install_istio_addons() {
    local name="${1:-$DEFAULT_CLUSTER_NAME}"

    echo -e "${BLUE}→ Installing Istio ${ISTIO_VERSION} addons on '${name}'...${NC}"

    # Check if the cluster exists
    if ! kind get clusters | grep -q "^${name}$"; then
        echo -e "${RED}✖ Cluster '${name}' not found.${NC}"; exit 1; fi

    # Switch kubectl context to the cluster
    kubectl config use-context "kind-${name}" &>/dev/null

    # Check if Istio is installed
    if ! kubectl get ns istio-system &>/dev/null; then
        echo -e "${RED}✖ Istio is not installed. Run install-istio first.${NC}"; exit 1; fi

    for addon in prometheus grafana jaeger kiali; do
        echo -e "${BLUE}→ Applying $addon.yaml${NC}"
        kubectl apply -f "${ADDON_BASE}/${addon}.yaml"
    done

    # Wait for pods to be ready
    echo -e "${BLUE}→ Waiting for addon pods...${NC}"
    kubectl wait --for=condition=ready pod --all -n istio-system --timeout=180s

    echo -e "${GREEN}✔ Istio addons installation completed.${NC}"
    echo -e "${BLUE}→ Addons status:${NC}"
    kubectl get pods -n istio-system | grep -E 'kiali|prometheus|grafana|jaeger'

    echo -e "${BLUE}→ Access UIs with port-forwarding:${NC}"
    echo -e "  Kiali:      kubectl port-forward svc/kiali -n istio-system 20001:20001"
    echo -e "  Prometheus: kubectl port-forward svc/prometheus -n istio-system 9090:9090"
    echo -e "  Grafana:    kubectl port-forward svc/grafana -n istio-system 3000:3000"
    echo -e "  Jaeger:     kubectl port-forward svc/tracing -n istio-system 8585:80"
}

#------------------------------------------------------------------------------
# Create a kind cluster
#   args: [cluster_name] [node_count] [node_image (optional)] [istio_profile (optional)]
#------------------------------------------------------------------------------
create_cluster() {
    local name="${1:-$DEFAULT_CLUSTER_NAME}"
    local nodes="${2:-1}"
    local image="${3:-}"
    local istio_profile="${4:-$DEFAULT_ISTIO_PROFILE}"

    echo -e "${BLUE}→ Creating kind cluster '${name}' (${nodes} node(s))...${NC}"

    # Temp config file, guaranteed removal on exit
    local cfg; cfg=$(mktemp)
    trap 'rm -f "$cfg"' EXIT

    # Build enhanced kind config
    cat >"$cfg" <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${name}
nodes:
  - role: control-plane${image:+
    image: ${image}}
    # Required for Istio ingress gateway to function properly
    extraPortMappings:
      - containerPort: 30000
        hostPort: 30000
        protocol: TCP
      - containerPort: 30001
        hostPort: 30001
        protocol: TCP
      - containerPort: 30002
        hostPort: 30002
        protocol: TCP
      - containerPort: 30003
        hostPort: 30003
        protocol: TCP
      # Expose ports for addons
      - containerPort: 30004  # Kiali
        hostPort: 30004
        protocol: TCP
      - containerPort: 30005  # Prometheus
        hostPort: 30005
        protocol: TCP
      - containerPort: 30006  # Grafana
        hostPort: 30006
        protocol: TCP
      - containerPort: 30007  # Jaeger
        hostPort: 30007
        protocol: TCP
EOF

    # Add worker nodes if requested
    for ((i=1;i<nodes;i++)); do
        cat >>"$cfg" <<EOF
  - role: worker${image:+
    image: ${image}}
EOF
    done

    # Launch cluster
    if kind create cluster --config="$cfg"; then
        echo -e "${GREEN}✔ Cluster '${name}' created.${NC}"
        echo -e "${BLUE}→ Setting kubectl context to kind-${name}${NC}"
        kubectl config use-context "kind-${name}" &>/dev/null

        echo -e "${BLUE}→ Cluster Info:${NC}"
        kubectl cluster-info

        echo -e "${BLUE}→ Nodes:${NC}"
        kubectl get nodes

        # Install Istio
        install_istio "$name" "$istio_profile"
    else
        echo -e "${RED}✖ Cluster creation failed.${NC}"; exit 1
    fi

    # Clear the EXIT trap so we don't delete other temp files later
    trap - EXIT
}

#------------------------------------------------------------------------------
# Delete a kind cluster
#   args: [cluster_name]
#------------------------------------------------------------------------------
delete_cluster() {
    local name="${1:-$DEFAULT_CLUSTER_NAME}"
    echo -e "${YELLOW}→ Deleting kind cluster '${name}'...${NC}"

    if kind delete cluster --name "$name"; then
        echo -e "${GREEN}✔ Cluster '${name}' deleted.${NC}"
    else
        echo -e "${RED}✖ Could not delete cluster '${name}'.${NC}"
        exit 1
    fi
}

#------------------------------------------------------------------------------
# List all kind clusters
#------------------------------------------------------------------------------
list_clusters() {
    echo -e "${BLUE}→ Existing kind clusters:${NC}"
    kind get clusters || echo "(none)"
}

#------------------------------------------------------------------------------
# Switch kubectl context to a kind cluster
#   args: [cluster_name]
#------------------------------------------------------------------------------
use_context() {
    local name="${1:-$DEFAULT_CLUSTER_NAME}"
    echo -e "${BLUE}→ Switching kubectl context to kind-${name}...${NC}"
    kubectl config use-context "kind-${name}"
}

#------------------------------------------------------------------------------
# Print the kubeconfig for a kind cluster
#   args: [cluster_name]
#------------------------------------------------------------------------------
get_kubeconfig() {
    local name="${1:-$DEFAULT_CLUSTER_NAME}"
    echo -e "${BLUE}→ Kubeconfig for '${name}':${NC}"
    kind get kubeconfig --name "$name"
}

#------------------------------------------------------------------------------
# List all kubectl contexts
#------------------------------------------------------------------------------
list_contexts() {
    echo -e "${BLUE}→ All kubectl contexts:${NC}"
    kubectl config get-contexts
}

#------------------------------------------------------------------------------
# Show status of a cluster: nodes, pods & services
#   args: [cluster_name]
#------------------------------------------------------------------------------
cluster_status() {
    local name="${1:-$DEFAULT_CLUSTER_NAME}"
    echo -e "${BLUE}→ Status for '${name}':${NC}"

    if ! kind get clusters | grep -q "^${name}$"; then
      echo -e "${YELLOW}⚠ Cluster '${name}' not found.${NC}"
      exit 1
    fi

    echo -e "${GREEN}✔ Cluster '${name}' exists.${NC}"
    kubectl config use-context "kind-${name}" &>/dev/null

    echo -e "${BLUE}→ Nodes:${NC}"
    kubectl get nodes

    echo -e "${BLUE}→ Istio Status:${NC}"
    if kubectl get ns istio-system &>/dev/null; then
        echo -e "${GREEN}✔ Istio is installed${NC}"
        echo -e "${BLUE}→ Istio Components:${NC}"
        kubectl get pods -n istio-system

        echo -e "${BLUE}→ Istio Services:${NC}"
        kubectl get svc -n istio-system

        # Check for istio addons
        echo -e "${BLUE}→ Istio Addons:${NC}"
        if kubectl get deploy -n istio-system kiali &> /dev/null; then
            echo -e "Kiali: ${GREEN}✔ Installed${NC}"
        else
            echo -e "Kiali: ${YELLOW}⚠ Not installed${NC}"
        fi

        if kubectl get deploy -n istio-system prometheus &> /dev/null; then
            echo -e "Prometheus: ${GREEN}✔ Installed${NC}"
        else
            echo -e "Prometheus: ${YELLOW}⚠ Not installed${NC}"
        fi

        if kubectl get deploy -n istio-system grafana &> /dev/null; then
            echo -e "Grafana: ${GREEN}✔ Installed${NC}"
        else
            echo -e "Grafana: ${YELLOW}⚠ Not installed${NC}"
        fi

        if kubectl get deploy -n istio-system jaeger &> /dev/null; then
            echo -e "Jaeger: ${GREEN}✔ Installed${NC}"
        else
            echo -e "Jaeger: ${YELLOW}⚠ Not installed${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ Istio not installed.${NC}"
    fi

    echo -e "${BLUE}→ Namespaces with Istio injection:${NC}"
    kubectl get namespace -l istio-injection=enabled

    echo -e "${BLUE}→ Pods with Istio sidecars:${NC}"
    kubectl get pods --all-namespaces -o go-template='{{range .items}}{{$ns := .metadata.namespace}}{{$name := .metadata.name}}{{range .spec.containers}}{{if eq .name "istio-proxy"}}{{$ns}}/{{$name}}{{"\n"}}{{break}}{{end}}{{end}}{{end}}'
}

#------------------------------------------------------------------------------
# Show versions of script, kind, kubectl, and istioctl
#------------------------------------------------------------------------------
version() {
    echo -e "${BLUE}Script version: ${SCRIPT_VERSION}${NC}"
    echo -e "${BLUE}kind version: $(kind version)${NC}"
    echo -e "${BLUE}kubectl version:$(kubectl version --client)${NC}"

    if command -v istioctl &> /dev/null; then
        echo -e "${BLUE}istioctl version: $(istioctl version --remote=false)${NC}"
    else
        echo -e "${BLUE}istioctl: ${YELLOW}⚠ Not installed${NC}"
    fi
}

#------------------------------------------------------------------------------
# Display help / usage information
#------------------------------------------------------------------------------
show_help() {
    sed -n '1,56p' "$0";
}

#------------------------------------------------------------------------------
# Main dispatch
#------------------------------------------------------------------------------
cmd="${1:-help}"; shift || true
check_prerequisites "$cmd"

case "$cmd" in
    create)          create_cluster       "$@" ;;
    delete)          delete_cluster       "$@" ;;
    list)            list_clusters        ;;
    status)          cluster_status       "$@" ;;
    use)             use_context          "$@" ;;
    kubeconfig)      get_kubeconfig       "$@" ;;
    contexts)        list_contexts        ;;
    install-istio)   install_istio        "$@" ;;
    install-addons)  install_istio_addons "$@" ;;
    version)         version              ;;
    help|--help)     show_help            ;;
    *) echo -e "${RED}Unknown command:${NC} $cmd"; show_help; exit 1 ;;
esac

exit 0