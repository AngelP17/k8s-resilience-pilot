################################################################################
# Variables for The Resilience Pilot Cluster
#
# These variables allow customization of the k3d cluster for different
# environments and resource constraints.
################################################################################

variable "cluster_name" {
  description = "Name of the k3d cluster"
  type        = string
  default     = "resilience-pilot"
}

variable "server_count" {
  description = "Number of server (control plane) nodes. Keep at 1 for local development."
  type        = number
  default     = 1
  
  validation {
    condition     = var.server_count >= 1 && var.server_count <= 3
    error_message = "Server count must be between 1 and 3."
  }
}

variable "agent_count" {
  description = "Number of agent (worker) nodes. More agents allow better pod distribution."
  type        = number
  default     = 2
  
  validation {
    condition     = var.agent_count >= 1 && var.agent_count <= 5
    error_message = "Agent count must be between 1 and 5."
  }
}

variable "api_port" {
  description = "Host port for Kubernetes API server access"
  type        = number
  default     = 6443
}

variable "lb_host_port" {
  description = "Host port mapped to the loadbalancer (for ingress access)"
  type        = number
  default     = 8080
}

variable "k3s_image" {
  description = "K3s image to use for the cluster nodes"
  type        = string
  default     = "rancher/k3s:v1.28.5-k3s1"
}
