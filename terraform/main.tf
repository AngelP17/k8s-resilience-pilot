################################################################################
# The Resilience Pilot - Terraform Configuration
# 
# This configuration creates a local k3d Kubernetes cluster optimized for
# SRE demonstrations: self-healing, observability, and GitOps workflows.
#
# Architecture:
#   - 1 Server node (control plane)
#   - 2 Agent nodes (workers for pod scheduling)
#   - LoadBalancer with port mapping for external access
################################################################################

terraform {
  required_version = ">= 1.0.0"
  
  required_providers {
    k3d = {
      source  = "pvotal-tech/k3d"
      version = "~> 0.0.7"
    }
  }
}

# Configure the k3d provider
provider "k3d" {}

################################################################################
# K3D CLUSTER RESOURCE
#
# SRE Concepts Demonstrated:
# - Multi-node cluster for realistic pod anti-affinity
# - LoadBalancer for production-like ingress
# - Configurable through variables for different environments
################################################################################

resource "k3d_cluster" "resilience_pilot" {
  name    = var.cluster_name
  servers = var.server_count
  agents  = var.agent_count

  # Kubeconfig settings
  kube_api {
    host_ip   = "127.0.0.1"
    host_port = var.api_port
  }

  # Image configuration (using stable k3s version)
  image = var.k3s_image

  # Port mappings for external access
  # Maps host port 8080 to loadbalancer port 80
  port {
    host_port      = var.lb_host_port
    container_port = 80
    node_filters   = ["loadbalancer"]
  }

  # k3d runtime settings
  k3d {
    disable_load_balancer = false
    disable_image_volume  = false
  }

  # k3s runtime arguments
  k3s {
    extra_args {
      arg          = "--disable=traefik"
      node_filters = ["server:*"]
    }
  }

  # Kubeconfig behavior
  kubeconfig {
    update_default_kubeconfig = true
    switch_current_context    = true
  }
}
