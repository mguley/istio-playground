## Istio: From Zero to Service Mesh

#### Table of Contents

- [Introduction](#introduction)
- [What is Istio](#what-is-istio)
- [Step 1: Setting Up the Cluster](#step-1-setting-up-the-cluster)
- [Step 2: Installing Istio](#step-2-installing-istio)
- [Step 3: Deploying a Sample Application](#step-3-deploying-a-sample-application)
- [Step 4: Understanding Sidecar Injection](#step-4-understanding-sidecar-injection)
- [Step 5: Inspecting the Istio Components](#step-5-inspecting-the-istio-components)
- [Step 6: Accessing the Application](#step-6-accessing-the-application)
- [Step 7: Installing the Istio Addons](#step-7-installing-the-istio-addons)
- [Step 8: Exploring the Istio Dashboards](#step-8-exploring-the-istio-dashboards)
- [Step 9: Generating Traffic](#step-9-generating-traffic)
- [Cleanup](#cleanup)
- [Understanding What Happened Under the Hood](#understanding-what-happened-under-the-hood)

#### Introduction

In this first scenario of our series, we'll set up Istio on a local Kubernetes cluster and deploy a simple "Hello World" application.
This hands-on approach will establish a solid foundation for exploring more complex Istio scenarios in future installments.

As organizations transition from monolithic applications to microservices, they face new challenges in managing service-to-service
communication, security, and observability.
Istio addresses these challenges by implementing a service mesh architecture that doesn't require modifying your application code.

This separation of concerns allows developers to focus on business logic while platform teams handle network-level concerns
consistently across all services.

#### What is Istio?

Istio is an open-source service mesh platform that provides a way to control how microservices share data with one another.
But what exactly is a service mesh? Think of it as an infrastructure layer that handles all network communication between
services, essentially adding a layer of intelligence to your network.

Istio's architecture consists of two main components:
1. `Data Plane`: This consists of Envoy proxies (also called `"sidecars"`) deployed alongside each application container.
   These proxies intercept all network traffic going to and from your services, enabling features like traffic routing, load balancing,
   and security without changing your application code.
2. `Control Plane`: Centralized components (primarily `istiod`) that configure and manage the proxies, allowing them to work
   together as a cohesive mesh.

Istio provides several key capabilities that solve common microservice challenges:
- `Traffic Management`: Route traffic between services with fine-grained control, implement canary deployments, A/B testing,
  and more sophisticated traffic patterns than what Kubernetes alone provides.
- `Security`: Automatically encrypt traffic between services with mutual TLS (mTLS), manage authentication and authorization
  policies, and ensure only authorized services can communicate with each other.
- `Observability`: Collect consistent metrics, logs, and traces across all services without code changes, making it easier
  to monitor and troubleshoot complex distributed systems.

Compared to other service mesh solutions like `Linkerd` or `Consul Connect`, `Istio` tends to be more feature-rich but also
more complex.
It's particularly well-suited for enterprise environments with sophisticated networking and security requirements.

#### Step 1: Setting Up the Cluster

First, we'll use our script to create a Kubernetes cluster with Istio. For this tutorial, we're using `kind` (Kubernetes in Docker),
which allows us to quickly spin up a multi-node Kubernetes cluster locally:

```bash
# Create a 3-node Kubernetes cluster with Istio
bash istio-cluster-manager.sh create istio-demo 3
```

This command accomplishes several important tasks:
- Creates a Kubernetes cluster named `"istio-demo"`
- Sets up one control plane node and two worker nodes
- Installs Istio with the `"demo"` profile
- Enables automatic sidecar injection for the default namespace

Let's verify that both the cluster and Istio are running correctly:

```bash
# Check cluster status
bash istio-cluster-manager.sh status istio-demo
```

The output should show your Kubernetes nodes in a `Ready` state and the essential Istio components running in the `istio-system` namespace.

#### Step 2: Installing Istio

If you're using an existing cluster and did not install Istio during the creation process, you can install it separately:

```bash
# Install Istio with the demo profile
bash istio-cluster-manager.sh install-istio istio-demo demo
```

Istio offers several different installation profiles to match your needs:
- `default`: A balanced profile with sensible defaults
- `demo`: A feature-rich setup perfect for learning (what we're using)
- `minimal`: A lightweight installation with just core features
- `remote`: For multi-cluster setups
- `empty`: A baseline profile you can customize completely

The `"demo"` profile we're using includes all the core components plus additional features suitable for learning, while
not being too resource-intensive for a local environment.

#### Step 3: Deploying a Sample Application

Now, let's deploy a simple "Hello World" application to our Istio-enabled cluster. We'll use a basic web service that displays
a greeting message.

Let's create a file called `hello-world-app.yaml`:

```bash
cat > hello-world-app.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: hello-world
  labels:
    app: hello-world
    service: hello-world
spec:
  ports:
    - port: 80
      targetPort: 5678
      name: http
  selector:
    app: hello-world
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-world-v1
  labels:
    app: hello-world
    version: v1
spec:
  replicas: 1
  selector:
    matchLabels:
      app: hello-world
      version: v1
  template:
    metadata:
      labels:
        app: hello-world
        version: v1
    spec:
      containers:
        - name: hello-world
          image: docker.io/hashicorp/http-echo:0.2.3
          args:
            - "-text=Hello World from Istio v1"
          ports:
            - containerPort: 5678
          resources:
            requests:
              cpu: "100m"
              memory: "64Mi"
            limits:
              cpu: "200m"
              memory: "128Mi"
EOF
```

This YAML configuration defines:
- A Kubernetes Service `hello-world` that exposes the application internally within the cluster
- A Deployment `hello-world-v1` that creates and manages a single pod running our application

Note the important `targetPort: 5678` specification in the service definition, which correctly routes traffic to our application
container's listening port.
Without this explicit mapping, the service would incorrectly try to send traffic to port 80 on the container, resulting in connection errors.

Next, we need to create Istio-specific resources to expose our application to external traffic.

Let's create a file called `hello-world-gateway.yaml`:

```bash
cat > hello-world-gateway.yaml << 'EOF'
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: hello-world-gateway
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "*"
---
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: hello-world
spec:
  hosts:
  - "*"
  gateways:
  - hello-world-gateway
  http:
  - match:
    - uri:
        prefix: /
    route:
    - destination:
        host: hello-world
        port:
          number: 80
EOF
```

These Istio resources define:
- A `Gateway` that configures the Istio ingress gateway to accept external traffic on port 80
- A `VirtualService` that defines routing rules for that traffic, sending requests with path prefix `"/"` to our `hello-world` service

The `Gateway` acts as the entry point for external traffic into your service mesh, while the `VirtualService` defines how
that traffic is routed once it enters the mesh.
This separation of concerns allows for sophisticated traffic management scenarios we'll explore in future scenarios.

Now let's apply these resources to our cluster:

```bash
# Apply the application manifests
kubectl apply -f hello-world-app.yaml
kubectl apply -f hello-world-gateway.yaml
```

#### Step 4: Understanding Sidecar Injection

One of Istio's key features is the automatic injection of sidecar proxies into your application pods.

Let's examine this in action:

```bash
# Get the pods with their containers
kubectl get pods -o=jsonpath='{range .items[*]}{.metadata.name}{": "}{range .spec.containers[*]}{.name}{", "}{end}{"\n"}{end}'
```

You should see output similar to:
```hello-world-v1-xxxxxxxxx-xxxxx: hello-world, istio-proxy,```

Notice that there are two containers in the pod:
1. `hello-world`: Our application container
2. `istio-proxy`: The Envoy proxy sidecar injected by Istio

This sidecar injection happened automatically because we previously enabled injection for the default namespace.
The sidecar proxy intercepts all inbound and outbound network traffic, allowing Istio to implement its traffic management,
security, and observability features.

Let's examine the pod in more detail:

```bash
kubectl describe pod -l app=hello-world
```

In the output, you'll see comprehensive details about both containers.
Pay special attention to:
- The `istio-init` init container that sets up network rules
- The environment variables injected into the `istio-proxy` container
- The volume mounts that allow the proxy to access certificates and configuration

This transparent injection of the proxy sidecar is what makes Istio so powerful - it enhances your applications with advanced
networking capabilities without requiring any changes to your application code.

#### Step 5: Inspecting the Istio Components

Let's take a deeper look at the Istio components running in the `istio-system` namespace:

```bash
# List Istio components
kubectl get pods -n istio-system
```

You should see several pods:
- `istiod`: The Istio control plane that manages configuration for the entire mesh
- `istio-ingressgateway`: The gateway that handles incoming traffic from outside the mesh
- `istio-egressgateway`: The gateway that handles outgoing traffic from the mesh to external services

Let's examine these components in more detail:

```bash
# Get details about istiod
kubectl describe deployment istiod -n istio-system

# Get details about the ingress gateway
kubectl describe deployment istio-ingressgateway -n istio-system
```

`istiod` is the brain of the operation. It:
- Converts a high-level Istio configuration into a low-level proxy configuration
- Distributes configuration to all proxies
- Manages certificate generation and distribution for secure mTLS communication
- Validates configuration to prevent misconfigurations

The `ingress gateway` is a specialized Envoy proxy that:
- Acts as the entry point for external traffic into your mesh
- Applies routing, security, and monitoring policies to incoming traffic
- Provides a central point for TLS termination and authentication

Understanding these components is crucial for effective troubleshooting and advanced configuration of your Istio service mesh.

#### Step 6: Accessing the Application

Now, let's access our application through the Istio ingress gateway:

```bash
# Get the ingress gateway service
kubectl get svc istio-ingressgateway -n istio-system
```

When running in a cloud environment, the `istio-ingressgateway` service would typically be assigned an external IP address.
However, since we're using `kind` locally, we need to use port forwarding to access the service:

```bash
# Forward the ingress gateway port to localhost
kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80
```

This command forwards traffic from port 8080 on your local machine to port 80 on the Istio ingress gateway.

Now you can access the application by navigating to:

```http://localhost:8080/```

You should see the message `"Hello World from Istio v1"` in your browser. This confirms that:
1. Your application is running properly
2. The Istio ingress gateway is correctly configured
3. The VirtualService is properly routing traffic to your application

#### Step 7: Installing the Istio Addons

While Istio's core functionality provides substantial value, its observability features truly shine when paired with its
visualization addons.

Let's install them:

```bash
# Install Istio addons (Kiali, Prometheus, Grafana, Jaeger)
bash istio-cluster-manager.sh install-addons istio-demo
```

This command installs four powerful tools that complement Istio:
- `Kiali`: A visualization dashboard for the service mesh that shows the topology, health, and metrics of your services
- `Prometheus`: A monitoring system that collects and stores metrics data from all your services and Istio components
- `Grafana`: A dashboard tool that provides pre-configured dashboards to visualize Istio metrics stored in Prometheus
- `Jaeger`: A distributed tracing system that allows you to track requests as they flow through multiple services, helping
  you understand service dependencies and identify performance bottlenecks

These tools together provide a comprehensive observability stack that gives you deep insights into your service mesh without
requiring code changes to your applications - all the data collection happens automatically through the Istio proxies.

#### Step 8: Exploring the Istio Dashboards

Now let's access the dashboards to visualize our service mesh:

```bash
# Access Kiali dashboard
kubectl port-forward -n istio-system svc/kiali 20001:20001
```

Open a web browser and navigate to:
```http://localhost:20001/```

In the `Kiali` dashboard, you'll see a graph representation of your service mesh.
Initially, you may not see much traffic, but we'll generate some in the next step.

You can also explore:
- The `Applications` view to see your applications and their health
- The `Services` view for service-level metrics
- The `Workloads` view for pod-level metrics
- The `Istio Config` view to validate your Istio configuration

Similarly, you can access the other dashboards:
```bash
# Access Prometheus
kubectl port-forward -n istio-system svc/prometheus 9090:9090

# Access Grafana
kubectl port-forward -n istio-system svc/grafana 3000:3000

# Access Jaeger
kubectl port-forward -n istio-system svc/tracing 8585:80
```

Each dashboard offers unique insights:
- `Prometheus` allows you to query and graph any metric collected by Istio
- `Grafana` provides pre-configured dashboards for service mesh monitoring
- `Jaeger` shows detailed trace data for requests flowing through your services

These tools are invaluable for understanding, monitoring, and troubleshooting your service mesh in production environments.

#### Step 9: Generating Traffic

To see meaningful data in our dashboards, let's generate some traffic to our application:

```bash
# Run this in a separate terminal window
for i in {1..100}; do
  curl -s http://localhost:8080/ > /dev/null
  sleep 0.5
done
```

This script sends 100 requests to our application with a half-second delay between each request,
creating a stream of traffic that will be visible in our observability tools.
Now go back to the `Kiali` dashboard, and you should see:
- Traffic flowing from the ingress gateway to your hello-world service
- Health indicators showing the service is operating normally
- Metrics like request volume, success rate, and latency

Take some time to explore the different visualizations available. The graph view in `Kiali` is particularly useful for understanding
service dependencies and traffic patterns, which become increasingly valuable as your service mesh grows in complexity.

#### Cleanup

When you're done experimenting, you can clean up all resources:

```bash
# Delete the kind cluster
bash istio-cluster-manager.sh delete istio-demo
```

This command completely removes the Kubernetes cluster and all resources running on it, including Istio and your application.

#### Understanding What Happened Under the Hood

In this tutorial, we've accomplished quite a lot:

1. Created a Kubernetes cluster with Istio installed
2. Deployed a simple application with an Istio sidecar proxy injected
3. Created Istio Gateway and VirtualService resources to expose the application
4. Explored the Istio components and their functions
5. Installed and explored Istio's observability add-ons

Let's take a moment to understand the key architectural elements at work:
- `Sidecar Pattern`: Each application pod received an Envoy proxy sidecar container that intercepted all network traffic.
  This pattern allows for consistent network behavior across all services without modifying application code.
- `Control and Data Plane Separation`: The Istio control plane `istiod` manages the configuration of all proxies (the data plane),
  which do the actual traffic handling. This separation allows for centralized management and consistent policy enforcement.
- `Declarative Configuration`: We defined our desired traffic routing through Kubernetes resources (Gateway and VirtualService),
  and Istio handled the implementation details. This declarative approach makes it easy to version and automate your network configuration.
- `Unified Observability`: The Envoy proxies automatically collected telemetry data that was visualized through the addon dashboards,
  providing deep visibility into service communication without code changes.

This architecture enables Istio to provide powerful traffic management, security, and observability features while maintaining
a clean separation from your application logic.