################################################################################
# Terraform Outputs
#
# These outputs provide useful information after cluster creation,
# including values needed for kubectl configuration and service access.
################################################################################

output "cluster_name" {
  description = "Name of the created k3d cluster"
  value       = k3d_cluster.resilience_pilot.name
}

output "api_endpoint" {
  description = "Kubernetes API endpoint"
  value       = "https://127.0.0.1:${var.api_port}"
}

output "lb_endpoint" {
  description = "LoadBalancer endpoint for application access"
  value       = "http://localhost:${var.lb_host_port}"
}

output "node_count" {
  description = "Total number of nodes in the cluster"
  value       = var.server_count + var.agent_count
}

output "kubeconfig_hint" {
  description = "How to access the cluster"
  value       = "kubectl config use-context k3d-${var.cluster_name}"
}

################################################################################
# Architecture Diagram (Mermaid)
#
# This output generates a Mermaid.js diagram for documentation.
# Copy this to README.md for visual representation.
################################################################################

output "architecture_diagram" {
  description = "Mermaid.js diagram of the cluster architecture"
  value       = <<-EOT
    ```mermaid
    graph TB
        subgraph "Local Machine"
            subgraph "k3d Cluster: ${var.cluster_name}"
                LB[LoadBalancer<br/>:${var.lb_host_port} → :80]
                
                subgraph "Control Plane"
                    S1[Server Node<br/>k3d-${var.cluster_name}-server-0]
                end
                
                subgraph "Worker Nodes"
                    A1[Agent Node 1<br/>k3d-${var.cluster_name}-agent-0]
                    A2[Agent Node 2<br/>k3d-${var.cluster_name}-agent-1]
                end
                
                LB --> S1
                S1 --> A1
                S1 --> A2
            end
        end
        
        User[👤 User] --> |http://localhost:${var.lb_host_port}| LB
        
        subgraph "Workloads"
            Pod1[FastAPI Pod 1]
            Pod2[FastAPI Pod 2]
            Pod3[FastAPI Pod 3]
        end
        
        A1 --> Pod1
        A1 --> Pod2
        A2 --> Pod3
        
        style LB fill:#e1f5fe
        style S1 fill:#fff3e0
        style A1 fill:#e8f5e9
        style A2 fill:#e8f5e9
        style Pod1 fill:#fce4ec
        style Pod2 fill:#fce4ec
        style Pod3 fill:#fce4ec
    ```
  EOT
}
