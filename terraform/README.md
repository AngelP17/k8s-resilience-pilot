# Terraform k3d Infrastructure

This directory contains Terraform configuration for provisioning a local k3d Kubernetes cluster.

## Requirements

| Tool | Version | Installation |
|------|---------|-------------|
| Terraform | >= 1.0.0 | `brew install terraform` |
| Docker | Latest | [Docker Desktop](https://docker.com) |
| k3d | >= 5.0 | `brew install k3d` |

## Quick Start

```bash
# Initialize Terraform
terraform init

# Preview changes
terraform plan

# Create cluster
terraform apply -auto-approve

# Verify cluster
kubectl get nodes
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `cluster_name` | resilience-pilot | Name of the k3d cluster |
| `server_count` | 1 | Control plane nodes |
| `agent_count` | 2 | Worker nodes |
| `lb_host_port` | 8080 | Host port for LoadBalancer |

## Architecture

After deployment, run `terraform output architecture_diagram` to get a Mermaid.js diagram.

## Cleanup

```bash
terraform destroy -auto-approve
```
