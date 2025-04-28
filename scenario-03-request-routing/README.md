# Request-Based Routing

#### Table of Contents

- [Introduction](#introduction)
- [What is Request-Based Routing?](#what-is-request-based-routing)
- [Step 1: Setting Up the Cluster](#step-1-setting-up-the-cluster)
- [Step 2: Deploy the Application Versions](#step-2-deploy-the-application-versions)
- [Step 3: Header-Based Routing](#step-3-header-based-routing)
- [Step 4: Path-Based Routing](#step-4-path-based-routing)
- [Step 5: User-Based Routing](#step-5-user-based-routing)
- [Step 6: Traffic Mirroring](#step-6-traffic-mirroring)
- [Step 7: Combining Routing Rules](#step-7-combining-routing-rules)
- [Step 8: Visualizing Request Routing](#step-8-visualizing-request-routing)
- [Cleanup](#cleanup)
- [Understanding What Happened Under the Hood](#understanding-what-happened-under-the-hood)

#### Introduction

In this third scenario, we'll explore Istio's advanced routing capabilities that go beyond simple percentage-based traffic splitting.
We'll learn how to route traffic based on HTTP headers, URI paths, and user identity, enabling sophisticated scenarios like feature flagging,
API versioning, and targeted deployments.

These techniques are crucial for modern application development practices such as:
- A/B testing specific user segments
- Feature flags for beta users
- API versioning
- Geographic routing
- Targeted deployments for specific client types

While the previous scenario showed us how to control traffic distribution with percentages,
this scenario demonstrates how to make routing decisions based on the actual content of the requests.
This provides much more precise control over who sees what version of your application.

#### What is Request-Based Routing?

Request-based routing allows you to direct traffic not just based on arbitrary percentages, but on the actual content of the requests themselves.
This enables much more precise control over who sees what version of your application.

Istio's VirtualService resource supports matching on various request attributes:
- `HTTP headers` (e.g., User-Agent, Cookie)
- `URI paths` and `query parameters`
- `HTTP methods` (GET, POST, etc.)
- `Source labels` (which service the request is coming from)

By using these matching capabilities, you can implement sophisticated routing strategies that tailor the user experience
based on who the user is, what device they're using, or what part of the application they're accessing.

Some common use cases include:
1. `Feature Flags`: Route users with a specific cookie or header to a new feature while others continue to use the existing version
2. `API Versioning`: Route `/v1/*` requests to one service and `/v2/*` requests to another
3. `Testing in Production`: Route internal users (based on headers) to a new version while external users use the stable version
4. `Device-Specific Experiences`: Serve different versions to mobile vs. desktop users
5. `Canary Releases for Specific Users`: Deploy new versions only to specific user segments before a full rollout

#### Step 1: Setting Up the Cluster

First, let's use our script to create a Kubernetes cluster with Istio:

```bash
# Create a 3-node Kubernetes cluster with Istio
bash istio-cluster-manager.sh create istio-routing 3
```

This will:
- Create a Kubernetes cluster named `"istio-routing"`
- Set up one control plane node and two worker nodes
- Install Istio with the `"demo"` profile
- Enable automatic sidecar injection for the default namespace

Let's verify that the cluster and Istio are running:

```bash
# Check cluster status
bash istio-cluster-manager.sh status istio-routing
```

#### Step 2: Deploy the Application Versions

We'll use the same color application from the previous scenario with three versions: `blue (v1)`, `green (v2)`, and `red (v3)`.
Each version has a different color scheme to make it easy to identify which version we're accessing.

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
apiVersion: networking.istio.io/v1
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

And let's define our destination rule that creates the subsets for each version:

```bash
cat > destination-rule.yaml << 'EOF'
apiVersion: networking.istio.io/v1
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

Let's verify that all the pods are running:

```bash
# Check if the pods are running
kubectl get pods
```

You should see three pods running, one for each version of our application:
- color-v1-xxxx (blue)
- color-v2-xxxx (green)
- color-v3-xxxx (red)

#### Step 3: Header-Based Routing

One of the most powerful request routing capabilities is directing traffic based on HTTP headers.
This can be used to enable feature flags, beta testing, or serving different versions to different client types.

Let's create a routing rule that directs `mobile` users to the `green version (v2)`, while `desktop` users go to the `blue version (v1)`:

```bash
cat > virtual-service-user-agent.yaml << 'EOF'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: color-service
spec:
  hosts:
  - "*"
  gateways:
  - color-gateway
  http:
  - match:
    - headers:
        user-agent:
          regex: ".*Mobile.*|.*Android.*|.*iPhone.*|.*iPad.*"
    route:
    - destination:
        host: color-service
        subset: v2
        port:
          number: 80
  - route:
    - destination:
        host: color-service
        subset: v1
        port:
          number: 80
EOF
```

```bash
# Apply the header-based routing rule
kubectl apply -f virtual-service-user-agent.yaml
```

Now, let's test this routing rule:

```bash
# Set up port forwarding to the Istio ingress gateway
kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80
```

In a browser, navigate to:
```
http://localhost:8080/
```

You should see the `blue version (v1)` since you're using a `desktop` browser. Now, let's simulate a mobile device using curl:

```bash
# Simulate a mobile device
curl -A "Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X)" http://localhost:8080/
```

This should return the `green version (v2)`. We can also view the page in a normal browser by setting the User-Agent header
using browser developer tools or a browser extension that allows you to change the User-Agent.

Let's try another header-based rule, this time using a custom header to enable a `"beta feature"`:

```bash
cat > virtual-service-custom-header.yaml << 'EOF'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: color-service
spec:
  hosts:
  - "*"
  gateways:
  - color-gateway
  http:
  - match:
    - headers:
        x-beta:
          exact: "true"
    route:
    - destination:
        host: color-service
        subset: v3
        port:
          number: 80
  - route:
    - destination:
        host: color-service
        subset: v1
        port:
          number: 80
EOF
```

```bash
# Apply the custom header rule
kubectl apply -f virtual-service-custom-header.yaml
```

Now, let's test this routing rule:

```bash
# Request without the beta header
curl http://localhost:8080/

# Request with the beta header
curl -H "x-beta: true" http://localhost:8080/
```

The first request should show the `blue version (v1)`, while the second request with the `beta header` should show the `red version (v3)`.

#### Step 4: Path-Based Routing

Another common scenario is routing based on the `URI path`, which is useful for API versioning or serving different services from different paths.

Let's create a routing rule that directs requests to different versions based on the URL path:

```bash
cat > virtual-service-uri.yaml << 'EOF'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: color-service
spec:
  hosts:
  - "*"
  gateways:
  - color-gateway
  http:
  - match:
    - uri:
        prefix: "/v3"
    route:
    - destination:
        host: color-service
        subset: v3
        port:
          number: 80
    rewrite:
      uri: "/"
  - match:
    - uri:
        prefix: "/v2"
    route:
    - destination:
        host: color-service
        subset: v2
        port:
          number: 80
    rewrite:
      uri: "/"
  - route:
    - destination:
        host: color-service
        subset: v1
        port:
          number: 80
EOF
```

```bash
# Apply the path-based routing rule
kubectl apply -f virtual-service-uri.yaml
```

Now, let's test this routing rule:

```bash
# Default path (should go to blue)
curl http://localhost:8080/

# V2 path (should go to green)
curl http://localhost:8080/v2

# V3 path (should go to red)
curl http://localhost:8080/v3
```

Notice how we can now access different versions of our application using different URL paths.
This is particularly useful for API versioning where you might want to maintain backward compatibility while introducing new API versions.

#### Step 5: User-Based Routing

In many applications, you might want to route users based on their identity or user group. This can be implemented using cookies or authentication headers.

Let's create a routing rule that directs `"premium" users` (identified by a cookie) to the `red version (v3)`, while `regular users` see the `blue version (v1)`:

```bash
cat > virtual-service-cookie.yaml << 'EOF'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: color-service
spec:
  hosts:
  - "*"
  gateways:
  - color-gateway
  http:
  - match:
    - headers:
        cookie:
          regex: ".*user-type=premium.*"
    route:
    - destination:
        host: color-service
        subset: v3
        port:
          number: 80
  - route:
    - destination:
        host: color-service
        subset: v1
        port:
          number: 80
EOF
```

```bash
# Apply the user-based routing rule
kubectl apply -f virtual-service-cookie.yaml
```

Now, let's test this routing rule:

```bash
# Regular user (without premium cookie)
curl http://localhost:8080/

# Premium user (with premium cookie)
curl --cookie "user-type=premium" http://localhost:8080/
```

The first request should show the `blue version (v1)`, while the second request with the `premium cookie` should show the `red version (v3)`.

#### Step 6: Traffic Mirroring

Traffic mirroring (sometimes called shadowing) is a powerful technique where live traffic is sent to a new version
without affecting the user experience. This allows you to test new versions with real production traffic while ensuring users only see responses from the stable version.

Let's create a routing rule that sends all traffic to the `blue version (v1)` but `mirrors` that traffic to the `red version (v3)` for testing:

```bash
cat > virtual-service-mirror.yaml << 'EOF'
apiVersion: networking.istio.io/v1
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
    mirror:
      host: color-service
      subset: v3
    mirrorPercentage:
      value: 100.0
EOF
```

```bash
# Apply the traffic mirroring rule
kubectl apply -f virtual-service-mirror.yaml
```

With this configuration:
- Users will only see responses from the blue version (v1)
- All requests will also be silently sent to the red version (v3)
- Any issues with the red version won't affect users

Let's generate some traffic:

```bash
# Generate traffic
for i in {1..20}; do
  curl http://localhost:8080/
  sleep 0.5
done
```

Now, let's check the logs for both versions to see if the traffic is being mirrored:

```bash
# Get pod names
BLUE_POD=$(kubectl get pod -l app=color,version=v1 -o jsonpath='{.items[0].metadata.name}')
RED_POD=$(kubectl get pod -l app=color,version=v3 -o jsonpath='{.items[0].metadata.name}')

# Check logs for blue pod (v1)
kubectl logs $BLUE_POD -c color

# Check logs for red pod (v3)
kubectl logs $RED_POD -c color
```

You should see similar request patterns in both logs, indicating that the traffic is being successfully mirrored.

#### Step 7: Combining Routing Rules

One of the most powerful aspects of Istio's routing capabilities is the ability to combine multiple routing rules in order of precedence.

Let's create a complex routing rule that combines multiple conditions:

```bash
cat > virtual-service-combined.yaml << 'EOF'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: color-service
spec:
  hosts:
  - "*"
  gateways:
  - color-gateway
  http:
  # Rule 1: Mobile + Beta header -> Red (v3)
  - match:
    - headers:
        user-agent:
          regex: ".*Mobile.*|.*Android.*|.*iPhone.*|.*iPad.*"
        x-beta:
          exact: "true"
    route:
    - destination:
        host: color-service
        subset: v3
        port:
          number: 80
  # Rule 2: Any Mobile -> Green (v2)
  - match:
    - headers:
        user-agent:
          regex: ".*Mobile.*|.*Android.*|.*iPhone.*|.*iPad.*"
    route:
    - destination:
        host: color-service
        subset: v2
        port:
          number: 80
  # Rule 3: Special path -> Red (v3)
  - match:
    - uri:
        prefix: "/special"
    route:
    - destination:
        host: color-service
        subset: v3
        port:
          number: 80
    rewrite:
      uri: "/"
  # Default rule: Everything else -> Blue (v1)
  - route:
    - destination:
        host: color-service
        subset: v1
        port:
          number: 80
EOF
```

```bash
# Apply the combined routing rule
kubectl apply -f virtual-service-combined.yaml
```

This complex rule implements the following logic:
1. If the request is from a mobile device (User-Agent header) AND has the beta header, send to red (v3)
2. If the request is from a mobile device (any kind), send to green (v2)
3. If the request path is `/special/`, send to red (v3)
4. All other requests go to blue (v1)

Let's test this complex routing:

```bash
# Regular desktop request (should go to blue)
curl http://localhost:8080/

# Mobile request (should go to green)
curl -A "Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X)" http://localhost:8080/

# Mobile request with beta header (should go to red)
curl -A "Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X)" -H "x-beta: true" http://localhost:8080/

# Special path request (should go to red)
curl http://localhost:8080/special
```

This demonstrates how you can create sophisticated routing logic by combining different match conditions.

#### Step 8: Visualizing Request Routing

Now that we've implemented various request-based routing patterns, let's use Istio's observability features to visualize and monitor the traffic:

```bash
# Install Istio addons if not already installed
bash istio-cluster-manager.sh install-addons istio-routing

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
3. You should see a visual representation of traffic flow between services

Generate various types of traffic to see the routing in action:
```bash
# Generate mixed traffic
for i in {1..5}; do
  # Regular request
  curl http://localhost:8080/
  
  # Mobile request
  curl -A "Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X)" http://localhost:8080/
  
  # Beta feature request
  curl -H "x-beta: true" http://localhost:8080/
  
  # Path-based request
  curl http://localhost:8080/v2/
  
  sleep 0.5
done
```

Observe the `Kiali` dashboard to see how traffic is being routed to different versions based on request attributes.

#### Cleanup

When you're done, you can clean up all resources:

```bash
# Delete the kind cluster
bash istio-cluster-manager.sh delete istio-routing
```

#### Understanding What Happened Under the Hood

In this scenario, we explored Istio's sophisticated request-based routing capabilities:

1. `Match Conditions`: We used various attributes of HTTP requests (headers, paths, etc.) to make routing decisions.
2. `Precise Control`: Instead of percentage-based traffic splitting, we implemented conditional logic that routes specific users or requests to specific service versions.
3. `Feature Flags`: We demonstrated how to use HTTP headers to enable beta features for specific users without affecting others.
4. `API Versioning`: We showed how path-based routing can be used to serve different API versions from different service versions.
5. `Traffic Mirroring`: We set up testing of a new version with real production traffic without affecting the user experience.
6. `Complex Logic`: We combined multiple match conditions to implement sophisticated routing scenarios.

These capabilities enable you to implement advanced deployment patterns that are tailored to your specific business needs.
By using request attributes for routing decisions, you can create highly personalized experiences and safely roll out new features to specific user segments.

Request-based routing also enables more sophisticated testing strategies, allowing you to validate new versions with
real-world traffic patterns before fully committing to them. This reduces risk and increases confidence in your deployments.

The power of Istio's request-based routing lies in its flexibility and the clean separation between routing logic and application code.
Your application remains simple and focused on business logic, while all the sophisticated routing decisions are handled by the service mesh.