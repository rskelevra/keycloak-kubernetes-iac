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
    
    # First, check if any cluster is already available and working
    if kubectl cluster-info >/dev/null 2>&1; then
        local current_context=$(kubectl config current-context 2>/dev/null || echo "unknown")
        log_success "Found working Kubernetes cluster: ${current_context}"
        
        # Verify we can actually list nodes
        if kubectl get nodes >/dev/null 2>&1; then
            log_info "Cluster is healthy and ready to use"
            return 0
        else
            log_warning "Cluster context exists but not accessible. Trying to create new cluster..."
        fi
    else
        log_info "No working Kubernetes cluster found. Creating one..."
    fi
    
    # No working cluster found, try to create k3d cluster
    setup_k3d_cluster
}

# Setup k3d cluster (WSL2 compatible)
setup_k3d_cluster() {
    log_info "Setting up k3d cluster..."
    
    # Detect OS for installation
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS="linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
    elif [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys" ]]; then
        OS="windows"
    else
        OS="linux"  # Default fallback
    fi
    
    # Check if k3d is installed
    if ! command_exists k3d; then
        log_info "k3d not found. Installing k3d..."
        install_k3d
    fi
    
    # Force WSL2-friendly paths
    export HOME="${HOME:-/home/$(whoami)}"
    mkdir -p ~/.kube
    
    # Check if cluster already exists
    if k3d cluster list | grep -q "${CLUSTER_NAME}"; then
        log_info "k3d cluster '${CLUSTER_NAME}' already exists"
        k3d cluster start ${CLUSTER_NAME} 2>/dev/null || true
        
        # Always refresh kubeconfig for existing clusters
        log_info "Refreshing kubeconfig for existing cluster..."
        k3d kubeconfig get ${CLUSTER_NAME} > ~/.kube/config 2>/dev/null || true
        
    else
        log_info "Creating new k3d cluster: ${CLUSTER_NAME}"
        
        # Create cluster with explicit kubeconfig handling
        k3d cluster create ${CLUSTER_NAME} \
            --port "8443:8443@loadbalancer" \
            --port "80:80@loadbalancer" \
            --wait \
            --timeout 60s
        
        # Get kubeconfig immediately after creation
        log_info "Setting up kubeconfig..."
        k3d kubeconfig get ${CLUSTER_NAME} > ~/.kube/config
    fi
    
    # Set kubeconfig environment
    export KUBECONFIG=~/.kube/config
    
    # Quick test - try kubectl immediately with shorter timeout
    log_info "Testing cluster connectivity..."
    local retries=10
    while [ $retries -gt 0 ]; do
        if kubectl get nodes --request-timeout=10s >/dev/null 2>&1; then
            log_success "k3d cluster is ready!"
            kubectl get nodes --no-headers | head -3
            return 0
        fi
        
        # Try kubeconfig refresh if first few attempts fail
        if [ $retries -eq 7 ]; then
            log_info "Refreshing kubeconfig..."
            k3d kubeconfig get ${CLUSTER_NAME} > ~/.kube/config 2>/dev/null || true
        fi
        
        log_info "Waiting for cluster... (${retries} retries left)"
        sleep 3
        retries=$((retries - 1))
    done
    
    # If we get here, try one final kubeconfig fix
    log_warning "Initial connection failed, trying kubeconfig fix..."
    k3d kubeconfig get ${CLUSTER_NAME} > ~/.kube/config
    chmod 600 ~/.kube/config
    export KUBECONFIG=~/.kube/config
    
    # Final test
    if kubectl get nodes --request-timeout=15s >/dev/null 2>&1; then
        log_success "k3d cluster is ready after kubeconfig fix!"
        kubectl get nodes --no-headers | head -3
        return 0
    else
        log_error "Failed to connect to k3d cluster after all attempts"
        log_info "Debug information:"
        echo "KUBECONFIG: $KUBECONFIG"
        echo "Cluster status:"
        k3d cluster list ${CLUSTER_NAME} || true
        echo "Kubectl config:"
        kubectl config current-context 2>/dev/null || echo "No context set"
        return 1
    fi
}

# Install k3d if not present
install_k3d() {
    log_info "Installing k3d..."
    
    case $OS in
        macos)
            if command_exists brew; then
                brew install k3d
            else
                curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
            fi
            ;;
        linux)
            curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
            ;;
        windows)
            log_error "Please install k3d manually on Windows: https://k3d.io/v5.4.6/#installation"
            return 1
            ;;
    esac
    
    # Verify installation
    if command_exists k3d; then
        log_success "k3d installed successfully"
    else
        log_error "k3d installation failed"
        return 1
    fi
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
    echo "📋 Additional Information:"
    echo "   - Namespace: ${NAMESPACE}"
    echo "   - TLS: Self-signed certificate (accept browser warning)"
    echo "   - Database: PostgreSQL (internal)"
    echo ""
    echo "🔧 Management Commands:"
    echo "   - View logs: kubectl logs -f deployment/keycloak -n ${NAMESPACE}"
    echo "   - Shell access: kubectl exec -it deployment/keycloak -n ${NAMESPACE} -- bash"
    echo "   - Stop port-forward: pkill -f 'kubectl.*port-forward.*keycloak'"
    echo ""
    echo "🗑️ Cleanup:"
    echo "   - Destroy infrastructure: pulumi destroy --yes"
    echo "   - Delete cluster: k3d cluster delete ${CLUSTER_NAME}"
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