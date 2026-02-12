#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Detect OS
detect_os() {
    case "$(uname -s)" in
        Darwin)
            OS="macos"
            ;;
        Linux)
            OS="linux"
            ;;
        CYGWIN*|MINGW32*|MSYS*|MINGW*)
            OS="windows"
            ;;
        *)
            log_error "Unsupported operating system: $(uname -s)"
            exit 1
            ;;
    esac
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Install kubectl
install_kubectl() {
    if command_exists kubectl; then
        log_info "kubectl is already installed"
        return 0
    fi
    
    log_info "Installing kubectl..."
    
    case $OS in
        macos)
            if command_exists brew; then
                brew install kubectl
            else
                curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/amd64/kubectl"
                chmod +x kubectl
                sudo mv kubectl /usr/local/bin/
            fi
            ;;
        linux)
            curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
            chmod +x kubectl
            sudo mv kubectl /usr/local/bin/
            ;;
        windows)
            log_error "Please install kubectl manually on Windows: https://kubernetes.io/docs/tasks/tools/"
            return 1
            ;;
    esac
    
    log_success "kubectl installed successfully"
}

# Install Pulumi
install_pulumi() {
    if command_exists pulumi; then
        log_info "Pulumi is already installed"
        return 0
    fi
    
    log_info "Installing Pulumi..."
    
    curl -fsSL https://get.pulumi.com | sh
    
    # Add to PATH for current session
    export PATH=$PATH:$HOME/.pulumi/bin
    
    log_success "Pulumi installed successfully"
    log_warning "Please add $HOME/.pulumi/bin to your PATH permanently"
}

# Install Go
install_go() {
    if command_exists go; then
        log_info "Go is already installed"
        return 0
    fi
    
    log_info "Installing Go..."
    
    local go_version="1.21.5"
    
    case $OS in
        macos)
            if command_exists brew; then
                brew install go
            else
                curl -LO "https://golang.org/dl/go${go_version}.darwin-amd64.tar.gz"
                sudo tar -C /usr/local -xzf "go${go_version}.darwin-amd64.tar.gz"
                rm "go${go_version}.darwin-amd64.tar.gz"
            fi
            ;;
        linux)
            curl -LO "https://golang.org/dl/go${go_version}.linux-amd64.tar.gz"
            sudo tar -C /usr/local -xzf "go${go_version}.linux-amd64.tar.gz"
            rm "go${go_version}.linux-amd64.tar.gz"
            ;;
        windows)
            log_error "Please install Go manually on Windows: https://golang.org/doc/install"
            return 1
            ;;
    esac
    
    # Add to PATH for current session
    export PATH=$PATH:/usr/local/go/bin
    
    log_success "Go installed successfully"
    log_warning "Please add /usr/local/go/bin to your PATH permanently"
}

# Install Kind
install_kind() {
    if command_exists kind; then
        log_info "kind is already installed"
        return 0
    fi
    
    log_info "Installing kind..."
    
    case $OS in
        macos)
            if command_exists brew; then
                brew install kind
            else
                curl -Lo ./kind "https://kind.sigs.k8s.io/dl/v0.20.0/kind-darwin-amd64"
                chmod +x ./kind
                sudo mv ./kind /usr/local/bin/kind
            fi
            ;;
        linux)
            curl -Lo ./kind "https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64"
            chmod +x ./kind
            sudo mv ./kind /usr/local/bin/kind
            ;;
        windows)
            log_error "Please install kind manually on Windows: https://kind.sigs.k8s.io/"
            return 1
            ;;
    esac
    
    log_success "kind installed successfully"
}

# Install Docker (required for kind)
install_docker() {
    if command_exists docker; then
        log_info "Docker is already installed"
        return 0
    fi
    
    log_info "Installing Docker..."
    
    case $OS in
        macos)
            log_warning "Please install Docker Desktop for Mac from: https://docs.docker.com/desktop/install/mac-install/"
            ;;
        linux)
            # Install Docker using the convenience script
            curl -fsSL https://get.docker.com -o get-docker.sh
            sudo sh get-docker.sh
            rm get-docker.sh
            
            # Add current user to docker group
            sudo usermod -aG docker $USER
            
            log_warning "Please log out and log back in to use Docker without sudo"
            ;;
        windows)
            log_warning "Please install Docker Desktop for Windows from: https://docs.docker.com/desktop/install/windows-install/"
            ;;
    esac
    
    log_success "Docker installation initiated (may require restart)"
}

# Install Rancher Desktop (optional, preferred)
install_rancher_desktop() {
    if command_exists rancher-desktop; then
        log_info "Rancher Desktop is already installed"
        return 0
    fi
    
    log_info "Rancher Desktop installation info..."
    
    case $OS in
        macos)
            log_info "Install Rancher Desktop via:"
            log_info "  - Homebrew: brew install --cask rancher"
            log_info "  - Download: https://rancherdesktop.io/"
            ;;
        linux)
            log_info "Install Rancher Desktop from: https://rancherdesktop.io/"
            ;;
        windows)
            log_info "Install Rancher Desktop from: https://rancherdesktop.io/"
            ;;
    esac
}

# Main installation function
main() {
    echo ""
    echo "=================================================="
    echo "       PREREQUISITES INSTALLATION SCRIPT"
    echo "=================================================="
    echo ""
    
    detect_os
    log_info "Detected OS: $OS"
    echo ""
    
    log_info "Installing required tools..."
    
    # Core requirements
    install_kubectl
    install_pulumi
    install_go
    
    # Kubernetes cluster options (Rancher Desktop PREFERRED per assignment)
    install_rancher_desktop
    install_docker
    install_kind
    
    echo ""
    echo "=================================================="
    echo "           INSTALLATION SUMMARY"
    echo "=================================================="
    echo ""
    
    # Check what was installed
    local installed=()
    local missing=()
    
    for tool in kubectl pulumi go docker kind; do
        if command_exists $tool; then
            installed+=($tool)
        else
            missing+=($tool)
        fi
    done
    
    if [ ${#installed[@]} -gt 0 ]; then
        log_success "Installed tools: ${installed[*]}"
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_warning "Missing tools: ${missing[*]}"
    fi
    
    echo ""
    log_info "Next steps:"
    echo "  1. Restart your terminal or source your shell profile"
    echo "  2. If using Rancher Desktop, start it and enable Kubernetes"
    echo "  3. Run: ./setup.sh"
    echo ""
    
    if [ ${#missing[@]} -eq 0 ]; then
        log_success "All prerequisites installed successfully!"
    else
        log_warning "Some tools need manual installation"
    fi
}

# Run main function
main "$@"
