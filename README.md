## Istio Playground

A hands-on learning environment for Istio service mesh patterns and implementation strategies.
This repository contains practical scenarios that demonstrate Istio concepts through guided exercises.

## Overview

This playground is designed to help you learn Istio concepts by doing.
Each scenario focuses on a specific pattern or technique used in production Istio service mesh environments.
The scenarios are self-contained and include step-by-step instructions, manifest files, and explanations.

## Prerequisites

Before starting, ensure you have the following installed:
- [Docker](https://docs.docker.com/get-docker/)
- [kind](https://kind.sigs.k8s.io/docs/user/quick-start/) (Kubernetes in Docker)
- [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
- [istioctl](https://istio.io/latest/docs/setup/getting-started/#download)

## Getting Started

This playground includes a handy cluster management script that makes it easy to create and manage local Kubernetes clusters with Istio:

```bash
# Clone this repository
git clone https://github.com/mguley/istio-playground.git
cd istio-playground

# Make the cluster manager script executable
chmod +x istio-cluster-manager.sh

# View available commands
./istio-cluster-manager.sh help
```

## Available Scenarios

### [Scenario 1: From Zero to Service Mesh](./scenario-01-simple-application/)

Learn the basics of Istio by setting up a service mesh and deploying a simple application. This scenario demonstrates how to install Istio, deploy a basic application, and visualize the service mesh using Istio's observability tools.

To begin this scenario:
```bash
cd scenario-01-simple-application
```

### [Scenario 2: Traffic Management](./scenario-02-traffic-management/)

Explore Istio's powerful traffic management capabilities. Deploy multiple versions of an application and implement sophisticated routing patterns, including traffic splitting, blue-green deployments, and canary releases. Learn how to control traffic flow with fine-grained precision without changing application code.

To begin this scenario:
```bash
cd scenario-02-traffic-management
```

### [Scenario 3: Request-Based Routing](./scenario-03-request-routing/)

Master advanced routing techniques by directing traffic based on HTTP headers, URI paths, and user identity. Implement sophisticated use cases like feature flagging, A/B testing specific user segments, API versioning, and traffic mirroring. Learn how to make routing decisions based on the content of requests for precise control over service access.

To begin this scenario:
```bash
cd scenario-03-request-routing
```

## Using the Cluster Manager

The included `istio-cluster-manager.sh` script simplifies cluster and Istio management operations:

```bash
# Create a 3-node cluster with Istio demo profile
./istio-cluster-manager.sh create istio-demo 3

# Create a cluster with minimal Istio profile
./istio-cluster-manager.sh create istio-test 1 "" minimal

# Install Istio addons (Kiali, Prometheus, Grafana, Jaeger)
./istio-cluster-manager.sh install-addons istio-demo

# Check cluster status
./istio-cluster-manager.sh status istio-demo

# Delete a cluster
./istio-cluster-manager.sh delete istio-demo
```

## Contributing

Contributions to add new scenarios or improve existing ones are welcome! To contribute:

1. Fork the repository
2. Create a new scenario directory following the existing pattern
3. Add comprehensive README.md with step-by-step instructions
4. Include all necessary manifest files
5. Submit a pull request

---

Happy learning! Istio is a powerful service mesh with many features to explore.