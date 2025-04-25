# Traffic Management - Basic Routing

#### Table of Contents

- [Introduction](#introduction)
- [What is Traffic Management in Istio?](#what-is-traffic-management-in-istio)
- [Step 1: Setting Up the Cluster](#step-1-setting-up-the-cluster)
- [Step 2: Deploy Multiple Versions of the Application](#step-2-deploy-multiple-versions-of-the-application)
- [Step 3: Create Basic Routing Rules](#step-3-create-basic-routing-rules)
- [Step 4: Implement Traffic Splitting](#step-4-implement-traffic-splitting)
- [Step 5: Implement Gradual Traffic Shifting](#step-5-implement-gradual-traffic-shifting)
- [Step 6: Implement Blue-Green Deployment](#step-6-implement-blue-green-deployment)
- [Step 7: Implement Canary Deployment](#step-7-implement-canary-deployment)
- [Step 8: Monitoring Traffic Distribution](#step-8-monitoring-traffic-distribution)
- [Cleanup](#cleanup)
- [Understanding What Happened Under the Hood](#understanding-what-happened-under-the-hood)

#### Introduction

In this second scenario, we'll explore Istio's traffic management capabilities.
This aspect of service mesh technology truly sets it apart from traditional Kubernetes deployments, allowing for sophisticated
traffic routing and fine-grained control over how requests flow through your system.

We'll deploy multiple versions of an application and demonstrate different traffic distribution patterns,
including percentage-based routing, blue-green deployments, and canary releases.
These patterns are essential for modern software delivery and enable techniques like A/B testing, gradual rollouts, and instant rollbacks.

#### What is Traffic Management in Istio?

Traffic management is one of Istio's core features, granting you the ability to control the flow of traffic and API calls between services.
This becomes particularly powerful when rolling out new versions of applications or implementing resilient service architectures.

Istio's traffic management relies on three main custom resources:
1. `VirtualService`: Defines routing rules that control how requests are routed to a service
2. `DestinationRule`: Defines policies that apply to traffic after routing has occurred, such as load balancing configurations and connection pool settings
3. `Gateway`: Controls ingress traffic, acting as a load balancer operating at the edge of the mesh

Using these resources together enables sophisticated patterns like:
- `Traffic Splitting`: Route a specified percentage of traffic to different service versions
- `Blue-Green Deployment`: Maintain two identical environments and switch traffic completely from one to the other
- `Canary Deployment`: Gradually increase traffic to a new version while monitoring for issues
- `Shadow/Mirror Deployment`: Send a copy of live traffic to a new version for testing without affecting the user experience

The benefit of implementing these patterns with Istio is that they can be done entirely through configuration,
without requiring changes to your application code or the actual Kubernetes infrastructure.

#### Step 1: Setting Up the Cluster

First, let's use our script to create a Kubernetes cluster with Istio:

```bash
# Create a 3-node Kubernetes cluster with Istio
bash istio-cluster-manager.sh create istio-colors 3
```

This will:
- Create a Kubernetes cluster named `"istio-colors"`
- Set up one control plane node and two worker nodes
- Install Istio with the `"demo"` profile
- Enable automatic sidecar injection for the default namespace

Let's verify that the cluster and Istio are running:

```bash
# Check cluster status
bash istio-cluster-manager.sh status istio-colors
```

#### Step 2: Deploy Multiple Versions of the Application

For this scenario, we'll use a simple color application that displays different colored pages.
We'll create three versions: `blue (v1)`, `green (v2)`, and `red (v3)`.
Each version is identical except for the color scheme and version identifier.

Let's create the files:

```bash
cat > blue-deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: color-v1
  labels:
    app: color
    version: v1
spec:
  replicas: 1
  selector:
    matchLabels:
      app: color
      version: v1
  template:
    metadata:
      labels:
        app: color
        version: v1
    spec:
      containers:
      - name: color
        image: docker.io/hashicorp/http-echo:0.2.3
        args:
        - "-text=<h1 style='color: white; background-color: blue; padding: 50px; font-family: Arial;'>Blue Version (v1)</h1>"
        - "-listen=:8080"
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: "100m"
            memory: "64Mi"
          limits:
            cpu: "200m"
            memory: "128Mi"
EOF
```

```bash
cat > green-deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: color-v2
  labels:
    app: color
    version: v2
spec:
  replicas: 1
  selector:
    matchLabels:
      app: color
      version: v2
  template:
    metadata:
      labels:
        app: color
        version: v2
    spec:
      containers:
      - name: color
        image: docker.io/hashicorp/http-echo:0.2.3
        args:
        - "-text=<h1 style='color: white; background-color: green; padding: 50px; font-family: Arial;'>Green Version (v2)</h1>"
        - "-listen=:8080"
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: "100m"
            memory: "64Mi"
          limits:
            cpu: "200m"
            memory: "128Mi"
EOF
```

```bash
cat > red-deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: color-v3
  labels:
    app: color
    version: v3
spec:
  replicas: 1
  selector:
    matchLabels:
      app: color
      version: v3
  template:
    metadata:
      labels:
        app: color
        version: v3
    spec:
      containers:
      - name: color
        image: docker.io/hashicorp/http-echo:0.2.3
        args:
        - "-text=<h1 style='color: white; background-color: red; padding: 50px; font-family: Arial;'>Red Version (v3)</h1>"
        - "-listen=:8080"
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: "100m"
            memory: "64Mi"
          limits:
            cpu: "200m"
            memory: "128Mi"
EOF
```

Let's apply the deployment manifests for all three versions:

```bash
# Apply the deployments
kubectl apply -f blue-deployment.yaml
kubectl apply -f green-deployment.yaml
kubectl apply -f red-deployment.yaml
```

Now, let's create a Kubernetes service that will select all versions:

```bash
cat > color-service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: color-service
  labels:
    app: color
    service: color
spec:
  ports:
  - port: 80
    targetPort: 8080
    name: http
  selector:
    app: color
EOF
```

```bash
# Apply the service
kubectl apply -f color-service.yaml
```

Finally, let's create an Istio gateway to expose our application:

```bash
cat > color-gateway.yaml << 'EOF'
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: color-gateway
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
EOF
```

```bash
# Apply the gateway
kubectl apply -f color-gateway.yaml
```

Let's verify that all the pods are running:

```bash
# Check if the pods are running
kubectl get pods
```

You should see three pods running, one for each version of our application:
- `color-v1-xxxx (blue)`
- `color-v2-xxxx (green)`
- `color-v3-xxxx (red)`

#### Step 3: Create Basic Routing Rules

By default, Kubernetes services distribute traffic randomly to all matching pods.
We want more control over which version receives traffic, so we'll use Istio's traffic management features.

First, let's create a DestinationRule that defines the subsets for our different versions:

```bash
cat > destination-rule.yaml << 'EOF'
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: color-service
spec:
  host: color-service
  subsets:
  - name: v1
    labels:
      version: v1
  - name: v2
    labels:
      version: v2
  - name: v3
    labels:
      version: v3
EOF
```

```bash
# Apply the destination rule
kubectl apply -f destination-rule.yaml
```

Now, let's create a VirtualService that routes all traffic to the `v1 (blue)` version:

```bash
cat > virtual-service-v1.yaml << 'EOF'
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: color-service
spec:
  hosts:
  - "*"
  gateways:
  - color-gateway
  http:
  - route:
    - destination:
        host: color-service
        subset: v1
        port:
          number: 80
      weight: 100
EOF
```

```bash
# Apply the virtual service - all traffic to v1
kubectl apply -f virtual-service-v1.yaml
```

Let's access our application to verify that all traffic is going to the blue version:

```bash
# Set up port forwarding to the Istio ingress gateway
kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80
```

Open your browser and navigate to:
```
http://localhost:8080/
```

You should see only the blue page. Try refreshing multiple times - you should still only see the blue version.

#### Step 4: Implement Traffic Splitting

Now let's split traffic between our service versions. We'll configure it to send:
- `70%` of traffic to `v1 (blue)`
- `20%` of traffic to `v2 (green)`
- `10%` of traffic to `v3 (red)`

Apply the updated VirtualService:

```bash
cat > virtual-service-split.yaml << 'EOF'
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: color-service
spec:
  hosts:
  - "*"
  gateways:
  - color-gateway
  http:
  - route:
    - destination:
        host: color-service
        subset: v1
        port:
          number: 80
      weight: 70
    - destination:
        host: color-service
        subset: v2
        port:
          number: 80
      weight: 20
    - destination:
        host: color-service
        subset: v3
        port:
          number: 80
      weight: 10
EOF
```

```bash
# Apply the virtual service - split traffic
kubectl apply -f virtual-service-split.yaml
```

```bash
# Set up port forwarding to the Istio ingress gateway
kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80
```

Open your browser and navigate to:
```
http://localhost:8080/
```

If you refresh your browser multiple times, you should start seeing a mix of blue, green, and red pages in approximately the configured ratio.
This is a simple way to implement A/B testing or slowly introduce new features to a subset of users.

#### Step 5: Implement Gradual Traffic Shifting

One of the most powerful patterns enabled by Istio is the ability to gradually shift traffic from one version to another.
This is often used during a canary deployment to increase confidence in a new version.

Let's simulate shifting traffic gradually from `v1 (blue)` to `v2 (green)`:

1. Start with 90% to v1, 10% to v2:

```bash
cat > virtual-service-shift-90-10.yaml << 'EOF'
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: color-service
spec:
  hosts:
  - "*"
  gateways:
  - color-gateway
  http:
  - route:
    - destination:
        host: color-service
        subset: v1
        port:
          number: 80
      weight: 90
    - destination:
        host: color-service
        subset: v2
        port:
          number: 80
      weight: 10
EOF
```

```bash
# Apply first shift - 90/10 split
kubectl apply -f virtual-service-shift-90-10.yaml
```

```bash
# Set up port forwarding to the Istio ingress gateway
kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80
```

Open your browser and navigate to:
```
http://localhost:8080/
```

2. After some monitoring, shift to 75% to v1, 25% to v2:

```bash
cat > virtual-service-shift-75-25.yaml << 'EOF'
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: color-service
spec:
  hosts:
  - "*"
  gateways:
  - color-gateway
  http:
  - route:
    - destination:
        host: color-service
        subset: v1
        port:
          number: 80
      weight: 75
    - destination:
        host: color-service
        subset: v2
        port:
          number: 80
      weight: 25
EOF
```

```bash
# Apply second shift - 75/25 split
kubectl apply -f virtual-service-shift-75-25.yaml
```

```bash
# Set up port forwarding to the Istio ingress gateway
kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80
```

Open your browser and navigate to:
```
http://localhost:8080/
```

3. Continue shifting: 50% to v1, 50% to v2:

```bash
cat > virtual-service-shift-50-50.yaml << 'EOF'
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: color-service
spec:
  hosts:
  - "*"
  gateways:
  - color-gateway
  http:
  - route:
    - destination:
        host: color-service
        subset: v1
        port:
          number: 80
      weight: 50
    - destination:
        host: color-service
        subset: v2
        port:
          number: 80
      weight: 50
EOF
```

```bash
# Apply third shift - 50/50 split
kubectl apply -f virtual-service-shift-50-50.yaml
```

```bash
# Set up port forwarding to the Istio ingress gateway
kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80
```

Open your browser and navigate to:
```
http://localhost:8080/
```

4. Near completion: 25% to v1, 75% to v2:

```bash
cat > virtual-service-shift-25-75.yaml << 'EOF'
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: color-service
spec:
  hosts:
  - "*"
  gateways:
  - color-gateway
  http:
  - route:
    - destination:
        host: color-service
        subset: v1
        port:
          number: 80
      weight: 25
    - destination:
        host: color-service
        subset: v2
        port:
          number: 80
      weight: 75
EOF
```

```bash
# Apply fourth shift - 25/75 split
kubectl apply -f virtual-service-shift-25-75.yaml
```

```bash
# Set up port forwarding to the Istio ingress gateway
kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80
```

Open your browser and navigate to:
```
http://localhost:8080/
```

5. Complete migration: 0% to v1, 100% to v2:

```bash
cat > virtual-service-shift-0-100.yaml << 'EOF'
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: color-service
spec:
  hosts:
  - "*"
  gateways:
  - color-gateway
  http:
  - route:
    - destination:
        host: color-service
        subset: v2
        port:
          number: 80
      weight: 100
EOF
```

```bash
# Apply final shift - 0/100 split
kubectl apply -f virtual-service-shift-0-100.yaml
```

```bash
# Set up port forwarding to the Istio ingress gateway
kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80
```

Open your browser and navigate to:
```
http://localhost:8080/
```

After each step, refresh your browser multiple times to observe the changing traffic distribution.

#### Step 6: Implement Blue-Green Deployment

Blue-green deployment is a technique where two identical environments exist, but only one serves production traffic.
Once the new version `(green)` is verified, traffic is switched all at once from the old version `(blue)` to the new one.

With Istio, this pattern becomes a simple configuration change:

1. First, ensure both `blue (v1)` and `green (v2)` deployments are running and ready
2. Direct all traffic to the `blue deployment (v1)`:

```bash
cat > virtual-service-v1.yaml << 'EOF'
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: color-service
spec:
  hosts:
  - "*"
  gateways:
  - color-gateway
  http:
  - route:
    - destination:
        host: color-service
        subset: v1
        port:
          number: 80
      weight: 100
EOF
```

```bash
# All traffic to blue (v1)
kubectl apply -f virtual-service-v1.yaml
```

3. When ready to switch, direct all traffic to the `green deployment (v2)`:

```bash
cat > virtual-service-v2.yaml << 'EOF'
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: color-service
spec:
  hosts:
  - "*"
  gateways:
  - color-gateway
  http:
  - route:
    - destination:
        host: color-service
        subset: v2
        port:
          number: 80
      weight: 100
EOF
```

```bash
# Switch all traffic to green (v2)
kubectl apply -f virtual-service-v2.yaml
```

4. If an issue is discovered, you can instantly roll back by switching traffic back to blue (v1):

```bash
# Roll back to blue (v1)
kubectl apply -f virtual-service-v1.yaml
```

This approach provides instant cutover with instant rollback capability, all without redeploying any containers or changing any infrastructure.

#### Step 7: Implement Canary Deployment

A canary deployment is similar to gradual traffic shifting but with more emphasis on monitoring and automatic health checks.
In a real-world scenario, you would:

1. Deploy the new version
2. Send a small percentage of traffic to it
3. Monitor key metrics (error rates, latency, etc.)
4. Gradually increase traffic if metrics look good
5. Roll back if metrics show problems

For our demonstration, we'll simulate a canary deployment using manual steps:

```bash
cat > virtual-service-canary-start.yaml << 'EOF'
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: color-service
spec:
  hosts:
  - "*"
  gateways:
  - color-gateway
  http:
  - route:
    - destination:
        host: color-service
        subset: v2
        port:
          number: 80
      weight: 95
    - destination:
        host: color-service
        subset: v3
        port:
          number: 80
      weight: 5
EOF
```

```bash
cat > virtual-service-canary-increase.yaml << 'EOF'
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: color-service
spec:
  hosts:
  - "*"
  gateways:
  - color-gateway
  http:
  - route:
    - destination:
        host: color-service
        subset: v2
        port:
          number: 80
      weight: 60
    - destination:
        host: color-service
        subset: v3
        port:
          number: 80
      weight: 40
EOF
```

```bash
cat > virtual-service-canary-complete.yaml << 'EOF'
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: color-service
spec:
  hosts:
  - "*"
  gateways:
  - color-gateway
  http:
  - route:
    - destination:
        host: color-service
        subset: v3
        port:
          number: 80
      weight: 100
EOF
```

```bash
# Start with a small percentage to v3 (red)
kubectl apply -f virtual-service-canary-start.yaml

# After verification, increase traffic to v3
kubectl apply -f virtual-service-canary-increase.yaml

# Complete migration to v3
kubectl apply -f virtual-service-canary-complete.yaml
```

In production, you would typically use a tool like `Flagger`, which can automate these steps based on metric analysis.

#### Step 8: Monitoring Traffic Distribution

Now that we've implemented various traffic management patterns, let's use Istio's observability features to visualize and monitor the traffic:

```bash
# Install Istio addons if not already installed
bash istio-cluster-manager.sh install-addons istio-colors

# Access Kiali dashboard
kubectl port-forward -n istio-system svc/kiali 20001:20001
```

Open your browser and navigate to:
```
http://localhost:20001/
```

In `Kiali`:
1. Go to the `"Graph"` section
2. Select the `"default"` namespace
3. You should see a visual representation of traffic flow between the ingress gateway and your services
4. The graph will show how traffic is distributed among the different versions

Generate some traffic by refreshing your application page multiple times:
```bash
# Simple traffic generator
for i in {1..100}; do
  curl -s http://localhost:8080/ > /dev/null
  sleep 0.1
done
```

Observe the `Kiali` dashboard to see the traffic distribution in real-time.

#### Cleanup

When you're done, you can clean up all resources:

```bash
# Delete the kind cluster
bash istio-cluster-manager.sh delete istio-colors
```

#### Understanding What Happened Under the Hood

In this scenario, we explored Istio's powerful traffic management capabilities:

1. `Multiple Service Versions`: We deployed three versions of our application, each with distinct visual differences.
2. `Subsets with DestinationRule`: We defined subsets based on version labels, allowing Istio to distinguish between different versions of the same service.
3. `Traffic Routing with VirtualService`: We controlled which version receives traffic and in what proportion, all through configuration changes without modifying the application.
4. `Traffic Shifting`: We gradually moved traffic from one version to another, demonstrating how to safely introduce changes.
5. `Deployment Patterns`: We implemented blue-green and canary deployments purely through Istio configuration.
6. `Visualization`: We used `Kiali` to visualize and verify our traffic routing configurations.

The key advantage of using Istio for these patterns is the clean separation between application deployment and traffic routing.

This separation allows for:
- More flexible deployment strategies
- Faster rollbacks (just a configuration change)
- Sophisticated traffic patterns without application changes
- Clear visualization of traffic flows

Traditional Kubernetes services can only route traffic based on simple label selectors, but Istio allows routing based on weights,
headers, paths, and many other factors, giving you unprecedented control over your service traffic.