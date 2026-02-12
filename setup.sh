#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="keycloak-cluster"
NAMESPACE="keycloak"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_tools=()
    
    if ! command_exists kubectl; then
        missing_tools+=("kubectl")
    fi
    
    if ! command_exists pulumi; then
        missing_tools+=("pulumi")
    fi
    
    if ! command_exists go; then
        missing_tools+=("go")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Please install the missing tools and run this script again."
        log_info "Installation guides:"
        log_info "  - kubectl: https://kubernetes.io/docs/tasks/tools/"
        log_info "  - pulumi: https://www.pulumi.com/docs/get-started/install/"
        log_info "  - go: https://golang.org/doc/install"
        exit 1
    fi
    
    log_success "All prerequisites are installed"
}

# Setup Kubernetes cluster
setup_kubernetes_cluster() {
    log_info "Setting up Kubernetes cluster..."
    
    # Check for available cluster options in order of preference
    if command_exists rancher-desktop; then
        log_info "Using Rancher Desktop (preferred option)"
        setup_rancher_desktop
    elif command_exists kind; then
        log_info "Using kind cluster"
        setup_kind_cluster
    elif command_exists minikube; then
        log_info "Using minikube cluster"
        setup_minikube_cluster
    else
        log_error "No supported Kubernetes cluster tool found!"
        log_info "Please install one of the following:"
        log_info "  - Rancher Desktop (preferred): https://rancherdesktop.io/"
        log_info "  - kind: https://kind.sigs.k8s.io/"
        log_info "  - minikube: https://minikube.sigs.k8s.io/"
        exit 1
    fi
}

# Setup Rancher Desktop
setup_rancher_desktop() {
    log_info "Configuring Rancher Desktop..."
    
    # Check if Rancher Desktop is running
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log_warning "Rancher Desktop cluster is not ready. Please:"
        log_info "  1. Start Rancher Desktop"
        log_info "  2. Enable Kubernetes in settings"
        log_info "  3. Wait for cluster to be ready"
        log_info "  4. Run this script again"
        exit 1
    fi
    
    log_success "Rancher Desktop cluster is ready"
}

# Setup kind cluster
setup_kind_cluster() {
    log_info "Setting up kind cluster..."
    
    # Create kind cluster config
    cat <<EOF > /tmp/kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${CLUSTER_NAME}
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 8443
    hostPort: 8443
    protocol: TCP
networking:
  disableDefaultCNI: false
EOF

    # Create cluster if it doesn't exist
    if ! kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        log_info "Creating kind cluster: ${CLUSTER_NAME}"
        kind create cluster --config /tmp/kind-config.yaml
    else
        log_info "Kind cluster ${CLUSTER_NAME} already exists"
    fi
    
    # Set kubectl context
    kubectl cluster-info --context kind-${CLUSTER_NAME}
    
    log_success "Kind cluster is ready"
}

# Setup minikube cluster
setup_minikube_cluster() {
    log_info "Setting up minikube cluster..."
    
    # Start minikube if not running
    if ! minikube status >/dev/null 2>&1; then
        log_info "Starting minikube cluster"
        minikube start --driver=docker --memory=4096 --cpus=2
    else
        log_info "Minikube cluster is already running"
    fi
    
    # Enable necessary addons
    minikube addons enable ingress
    
    log_success "Minikube cluster is ready"
}

# Setup Pulumi
setup_pulumi() {
    log_info "Setting up Pulumi..."
    
    # Login to local backend
    pulumi login --local
    
    # Create or select stack
    if ! pulumi stack ls | grep -q "dev"; then
        log_info "Creating new Pulumi stack: dev"
        pulumi stack init dev
    else
        log_info "Selecting existing Pulumi stack: dev"
        pulumi stack select dev
    fi
    
    log_success "Pulumi is configured"
}

# Deploy infrastructure
deploy_infrastructure() {
    log_info "Deploying Keycloak infrastructure..."
    
    # Install Go dependencies
    log_info "Installing Go dependencies..."
    go mod tidy
    
    # Deploy with Pulumi
    log_info "Running Pulumi deployment..."
    pulumi up --yes
    
    log_success "Infrastructure deployed successfully"
}

# Wait for pods to be ready
wait_for_deployment() {
    log_info "Waiting for Keycloak to be ready..."
    
    # Wait for namespace
    kubectl wait --for=condition=Ready namespace/${NAMESPACE} --timeout=60s
    
    # Wait for PostgreSQL
    kubectl wait --for=condition=available --timeout=300s deployment/postgres -n ${NAMESPACE}
    
    # Wait for Keycloak
    kubectl wait --for=condition=available --timeout=600s deployment/keycloak -n ${NAMESPACE}
    
    log_success "All deployments are ready"
}

# Setup local DNS
setup_local_dns() {
    log_info "Setting up local DNS..."
    
    # Get the service external IP or use localhost for port-forward
    local keycloak_ip="127.0.0.1"
    
    # Add entry to /etc/hosts if not exists
    if ! grep -q "keycloak.local" /etc/hosts; then
        log_info "Adding keycloak.local to /etc/hosts (requires sudo)"
        echo "${keycloak_ip} keycloak.local" | sudo tee -a /etc/hosts
    else
        log_info "keycloak.local already exists in /etc/hosts"
    fi
    
    log_success "Local DNS configured"
}

# Setup port forwarding
setup_port_forwarding() {
    log_info "Setting up port forwarding..."
    
    # Kill any existing port-forward processes
    pkill -f "kubectl.*port-forward.*keycloak" || true
    
    # Start port forwarding in background
    nohup kubectl port-forward -n ${NAMESPACE} service/keycloak 8443:8443 > /tmp/keycloak-port-forward.log 2>&1 &
    
    # Wait a moment for port-forward to establish
    sleep 5
    
    log_success "Port forwarding configured (logs in /tmp/keycloak-port-forward.log)"
}

# Display access information
display_access_info() {
    log_success "Keycloak deployment completed successfully!"
    echo ""
    echo "=================================================="
    echo "           ACCESS INFORMATION"
    echo "=================================================="
    echo ""
    echo "🌐 Keycloak URL: https://keycloak.local:8443"
    echo ""
    echo "👤 Admin Credentials:"
    
    # Get credentials from Pulumi outputs
    local admin_username=$(pulumi stack output keycloak-admin-username 2>/dev/null || echo "admin")
    local admin_password=$(pulumi stack output keycloak-admin-password 2>/dev/null || echo "Check Pulumi outputs")
    
    echo "   Username: ${admin_username}"
    echo "   Password: ${admin_password}"
    echo ""
    echo "=================================================="
    echo ""
    echo "📝 Additional Information:"
    echo "   - Namespace: ${NAMESPACE}"
    echo "   - TLS: Self-signed certificate (accept browser warning)"
    echo "   - Database: PostgreSQL (internal)"
    echo ""
    echo "🔧 Management Commands:"
    echo "   - View logs: kubectl logs -f deployment/keycloak -n ${NAMESPACE}"
    echo "   - Shell access: kubectl exec -it deployment/keycloak -n ${NAMESPACE} -- bash"
    echo "   - Stop port-forward: pkill -f 'kubectl.*port-forward.*keycloak'"
    echo ""
    echo "🗑️  Cleanup:"
    echo "   - Destroy infrastructure: pulumi destroy --yes"
    echo "   - Delete cluster: ./scripts/cleanup.sh"
    echo ""
}

# Main execution
main() {
    echo ""
    echo "=================================================="
    echo "     KEYCLOAK KUBERNETES DEPLOYMENT SCRIPT"
    echo "=================================================="
    echo ""
    
    # Record start time
    local start_time=$(date +%s)
    
    # Execute setup steps
    check_prerequisites
    setup_kubernetes_cluster
    setup_pulumi
    deploy_infrastructure
    wait_for_deployment
    setup_local_dns
    setup_port_forwarding
    
    # Record end time
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    display_access_info
    
    log_success "Total deployment time: ${duration} seconds"
    echo ""
}

# Run main function
main "$@"
