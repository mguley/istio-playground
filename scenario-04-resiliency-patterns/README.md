# Resiliency Patterns in Istio

#### Table of Contents

- [Introduction](#introduction)
- [What are Resiliency Patterns?](#what-are-resiliency-patterns-and-why-do-we-need-resilience)
- [Step 1: Setting Up the Cluster](#step-1-setting-up-the-cluster)
- [Step 2: Deploy the Application Services](#step-2-deploy-the-application-services)
- [Step 3: Testing the Application Without Resiliency](#step-3-testing-the-application-without-resiliency)
- [Step 4: Implementing Timeouts](#step-4-implementing-timeouts)
- [Step 5: Implementing Retries](#step-5-implementing-retries)
- [Step 6: Implementing Circuit Breakers](#step-6-implementing-circuit-breakers)
- [Step 7: Implementing Outlier Detection](#step-7-implementing-outlier-detection)
- [Step 8: Implementing Fault Injection](#step-8-implementing-fault-injection)
- [Step 9: Visualizing Resilience in Action](#step-9-visualizing-resilience-in-action)
- [Cleanup](#cleanup)
- [Understanding What Happened Under the Hood](#understanding-what-happened-under-the-hood)

#### Introduction

Welcome to our exploration of resilience in microservices!
Think of this tutorial as building a house that can withstand storms, earthquakes, and power outages - except we're building a digital
system that can withstand network failures, service crashes, and unexpected delays.

In real-world distributed systems, failures aren't just possible - they're inevitable.
Networks become unreliable, services get overloaded, and unexpected errors occur.
Just as we don't expect a house to collapse when a single window breaks, we shouldn't expect our entire application to fail when a single service has issues.

In this scenario, we'll build a simple e-commerce application with several microservices:
- A `frontend` service that users interact with
- A `product` service that retrieves product information
- A `pricing` service that calculates prices (sometimes slow)
- An `inventory` service that checks stock availability (occasionally fails)

Then, we'll implement various resilience patterns to protect our application from these potential failures:
- `Timeouts` to prevent clients from waiting too long for responses
- `Retries` to automatically attempt failed requests
- `Circuit Breakers` to prevent cascade failures
- `Outlier Detection` to automatically remove unhealthy instances
- `Fault Injection` to test resilience

The best part? We'll implement all of these patterns using Istio, meaning we won't have to modify our application code.
This approach separates the business logic (what your application does) from resilience concerns (how it handles failures).

#### What are Resiliency Patterns and Why Do We Need Resilience?

Imagine you're at a restaurant. If the kitchen is running efficiently, your food arrives quickly.
But what happens if one chef calls in sick? What if the vegetable supplier is late? What if the oven breaks?
A well-run restaurant has systems in place to handle these issues without ruining your dining experience.

Similarly, resiliency patterns are design patterns that help applications recover from failures and continue operating.
In a microservice architecture, these patterns are essential because there are more potential points of failure.

#### Key Resiliency Patterns

1. **Timeout**: Like setting a timer when waiting for food at a restaurant.
   If your appetizer doesn't arrive within 15 minutes, you might ask the waiter for an update rather than sitting there indefinitely.
   In microservices, timeouts limit how long a service will wait for a response from another service, preventing a slow service from blocking the entire request chain.

2. **Retry**: Similar to redialing a phone number when you get a busy signal. Sometimes, a second or third attempt will go through.
   Retry logic automatically attempts failed requests, with optional backoff strategies to allow the other service time to recover.

3. **Circuit Breaker**: Think of an electrical circuit breaker in your home. When there's a power surge, the breaker trips to prevent damage to your appliances and potential fires.
   In microservices, circuit breakers prevent cascade failures by temporarily "breaking the circuit" when a service is failing, stopping requests to failing services until they recover.

4. **Outlier Detection**: Like a restaurant manager noticing that one chef is consistently burning dishes and temporarily reassigning them to simpler tasks.
   Outlier detection automatically removes unhealthy instances from the load balancing pool, directing traffic only to healthy instances.

5. **Bulkheading**: Named after ship compartmentalization that prevents a single breach from sinking the entire vessel.
   Bulkheading isolates failures to prevent them from affecting the entire system, typically by partitioning service instances or resources.

6. **Fallback**: When a restaurant runs out of a specific dish, they might suggest an alternative rather than telling you they can't serve you at all.
   Fallback mechanisms provide alternative responses when a service fails, such as cached data or simplified functionality.

7. **Rate Limiting**: Similar to how a nightclub limits how many people can enter to prevent overcrowding.
   Rate limiting protects services from being overwhelmed by limiting the number of requests they receive.

Istio implements these patterns at the network level through the Envoy proxy, allowing you to configure them declaratively and consistently across all services.
This means you don't need to implement these patterns in each service's code, reducing development complexity and ensuring consistent behavior.

#### Step 1: Setting Up the Cluster

Before we can build our resilient application, we need a Kubernetes cluster with Istio installed.
Think of this as preparing the construction site and bringing in the tools before building a house.

Let's use our script to create a Kubernetes cluster with Istio:

```bash
# Create a 3-node Kubernetes cluster with Istio
bash istio-cluster-manager.sh create istio-resilience 3
```

This command does several important things:
- Creates a Kubernetes cluster named `"istio-resilience"`
- Sets up one control plane node and two worker nodes
- Installs Istio with the `"demo"` profile
- Enables automatic sidecar injection for the default namespace

The automatic sidecar injection is particularly important - it means every pod we deploy will have an Istio proxy (Envoy) automatically added to it.
This proxy intercepts all network traffic to and from the pod, allowing Istio to implement resilience patterns without changing our application code.

Let's verify that everything is running correctly:

```bash
# Check cluster status
bash istio-cluster-manager.sh status istio-resilience
```

If everything is set up correctly, you should see confirmation that the cluster and Istio are running.

#### Step 2: Deploy the Application Services

Now that our foundation is in place, let's build our e-commerce application. We'll create four microservices that work together to deliver the complete user experience.

First, let's create the `frontend` service, which users interact with:

```bash
cat > frontend.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: frontend
  labels:
    app: frontend
    service: frontend
spec:
  ports:
  - port: 80
    targetPort: 9090
    name: http
  selector:
    app: frontend
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  labels:
    app: frontend
    version: v1
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
      version: v1
  template:
    metadata:
      labels:
        app: frontend
        version: v1
    spec:
      containers:
      - name: frontend
        image: ghcr.io/nicholasjackson/fake-service:v0.26.2
        env:
        - name: NAME
          value: "frontend"
        - name: UPSTREAM_URIS     # tell it to call the product service
          value: "http://product"
        ports:
        - containerPort: 9090
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "200m"
            memory: "256Mi"
EOF
```

Next, the `product` service that retrieves product information:

```bash
cat > product.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: product
  labels:
    app: product
    service: product
spec:
  ports:
  - port: 80
    targetPort: 9090
    name: http
  selector:
    app: product
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: product
  labels:
    app: product
    version: v1
spec:
  replicas: 1
  selector:
    matchLabels:
      app: product
      version: v1
  template:
    metadata:
      labels:
        app: product
        version: v1
    spec:
      containers:
      - name: product
        image: ghcr.io/nicholasjackson/fake-service:v0.26.2
        env:
        - name: NAME
          value: "product"
        - name: UPSTREAM_URIS       # sequential → fine for demo
          value: "http://pricing,http://inventory"
        ports:
        - containerPort: 9090
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "200m"
            memory: "256Mi"
EOF
```

Then, the `pricing` service, which will simulate being slow some of the time:

```bash
cat > pricing.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: pricing
  labels:
    app: pricing
    service: pricing
spec:
  ports:
  - port: 80
    targetPort: 9090
    name: http
  selector:
    app: pricing
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pricing
  labels:
    app: pricing
    version: v1
spec:
  replicas: 1
  selector:
    matchLabels:
      app: pricing
      version: v1
  template:
    metadata:
      labels:
        app: pricing
        version: v1
    spec:
      containers:
        - name: pricing
          image: ghcr.io/nicholasjackson/fake-service:v0.26.2
          env:
            - name: NAME
              value: "pricing"
            # 40% of calls wait 3s → client time‑out candidate
            - name: ERROR_RATE
              value: "0.4"        # 40%
            - name: ERROR_TYPE
              value: "delay"
            - name: ERROR_DELAY
              value: "3s"
          ports:
            - containerPort: 9090
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "200m"
              memory: "256Mi"
EOF
```

Finally, the `inventory` service, which will occasionally fail:

```bash
cat > inventory.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: inventory
  labels:
    app: inventory
    service: inventory
spec:
  ports:
  - port: 80
    targetPort: 9090
    name: http
  selector:
    app: inventory
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inventory
  labels:
    app: inventory
    version: v1
spec:
  replicas: 1
  selector:
    matchLabels:
      app: inventory
      version: v1
  template:
    metadata:
      labels:
        app: inventory
        version: v1
    spec:
      containers:
        - name: inventory
          image: ghcr.io/nicholasjackson/fake-service:v0.26.2
          env:
            - name: NAME
              value: "inventory"
            # 30% of calls return HTTP 500
            - name: ERROR_RATE
              value: "0.3"      # 30%
            - name: ERROR_TYPE
              value: "http_error"
            - name: ERROR_CODE
              value: "500"
          ports:
            - containerPort: 9090
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "200m"
              memory: "256Mi"
EOF
```

Let's also create an Istio Gateway to access our application from outside the cluster:

```bash
cat > gateway.yaml << 'EOF'
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: ecommerce-gateway
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
  name: frontend
spec:
  hosts:
  - "*"
  gateways:
  - ecommerce-gateway
  http:
  - match:
    - uri:
        prefix: /
    route:
    - destination:
        host: frontend
        port:
          number: 80
EOF
```

Now, let's deploy all of these services:

```bash
# Deploy all services
kubectl apply -f frontend.yaml
kubectl apply -f product.yaml
kubectl apply -f pricing.yaml
kubectl apply -f inventory.yaml
kubectl apply -f gateway.yaml
```

Let's verify that all our services are running:

```bash
# Check the status of all pods
kubectl get pods
```

You should see all four services running:
- `frontend-xxx`
- `product-xxx`
- `pricing-xxx`
- `inventory-xxx`

`Understanding Our Application Architecture`

Before we continue, let's understand how these services interact:

1. Users interact with the `frontend` service
2. The `frontend` service calls the `product` service
3. The `product` service calls both the `pricing` service and the `inventory` service

We've intentionally built in some challenges:
- The `pricing` service is slow 40% of the time (it waits 3 seconds)
- The `inventory` service fails with an error 30% of the time

These challenges simulate real-world problems that can occur in production systems, giving us the opportunity to implement resilience patterns to handle them.

#### Step 3: Testing the Application Without Resiliency

Before adding any resilience patterns, let's see how our application behaves "out of the box". This will help us understand the problems we're trying to solve.

First, let's set up port forwarding to access our application:

```bash
# Set up port forwarding to the Istio ingress gateway
kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80
```

You can now open your browser and navigate to:
```
http://localhost:8080/
```

Try refreshing a few times. You might notice that:
- Some requests take a long time (when the pricing service is slow)
- Some requests fail completely (when the inventory service returns an error)
- The overall user experience is inconsistent and unreliable

To get a more systematic view of the application's behavior, let's create a traffic generator:

```bash
cat > traffic-generator.yaml << 'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: traffic-generator
spec:
  template:
    metadata:
      labels:
        app: traffic-generator
    spec:
      restartPolicy: Never
      containers:
        - name: traffic
          image: pstauffer/curl
          command: ["/bin/sh", "-c"]
          args:
            - |
              echo "Starting traffic generation..."
              total_requests=50
              success=0
              errors=0
              timeouts=0
    
              overall_start=$(date +%s.%N)
    
              for i in $(seq 1 $total_requests); do
                echo "Request $i of $total_requests"
              
                req_start=$(date +%s.%N)
                code=$(curl -o /dev/null -s -w "%{http_code}" --max-time 5 http://frontend/)
                req_end=$(date +%s.%N)
              
                req_time=$(echo "$req_end $req_start" | awk '{printf "%.3f", $1-$2}')
              if [ "$code" -eq 200 ]; then
                echo "  Success ($code) in ${req_time}s"
                success=$((success+1))
              elif [ "$code" -eq 000 ]; then
                echo "  Timeout after ${req_time}s"
                timeouts=$((timeouts+1))
              else
                echo "  Error: $code in ${req_time}s"
                errors=$((errors+1))
              fi
              
              sleep 0.5
              done
    
              overall_end=$(date +%s.%N)
              total_time=$(echo "$overall_end $overall_start" | awk '{printf "%.3f", $1-$2}')
    
              pct () { echo "$1 $total_requests" | awk '{printf "%.2f", ($1*100)/$2}'; }
    
              echo
              echo "Results:"
              echo "  Total requests: $total_requests"
              echo "  Successful: $success ($(pct $success)%)"
              echo "  Errors: $errors ($(pct $errors)%)"
              echo "  Timeouts: $timeouts ($(pct $timeouts)%)"
              echo "  Total time: ${total_time}s"
              echo "Traffic generation complete."
  backoffLimit: 1
EOF
```

```bash
# Generate traffic to the application
kubectl apply -f traffic-generator.yaml
```

Check the logs to see the results:

```bash
# Get the pod name of the traffic generator
TRAFFIC_POD=$(kubectl get pod -l app=traffic-generator -o jsonpath='{.items[0].metadata.name}')

# Check logs
kubectl logs $TRAFFIC_POD
```

You'll likely see high error rates and timeouts.
This is what happens without resilience patterns - users experience slow responses and errors when underlying services have issues.

Imagine this was a real e-commerce site.
Customers would likely leave and shop elsewhere if they encountered these delays and errors. Let's improve the situation by implementing resilience patterns.

#### Step 4: Implementing Timeouts

`What Are Timeouts and Why Do We Need Them?`

Imagine you're on hold with customer service.

Would you wait indefinitely, or would you hang up after a reasonable amount of time? Most of us have a mental "timeout" after which we'll give up and try again later.

In microservices, timeouts serve a similar purpose. They prevent a client service from waiting too long for a response from a dependent service.

Without timeouts, a slow service could tie up resources indefinitely, potentially bringing down the entire system.

`How Timeouts Work in Istio`

In Istio, timeouts are implemented at the proxy level.

When Service A calls Service B, the Envoy proxy for Service A starts a timer.

If Service B doesn't respond within the specified time, the proxy terminates the request and returns an error.

This happens before the request reaches Service A's application code, meaning your services don't need to implement their own timeout logic.

`Implementing Timeouts`

Let's configure timeouts for the calls to our slow `pricing` service and our error-prone `inventory` service:

```bash
cat > timeout-config.yaml << 'EOF'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: pricing
spec:
  hosts:
  - pricing
  http:
  - route:
    - destination:
        host: pricing
    timeout: 1s
---
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: inventory
spec:
  hosts:
  - inventory
  http:
  - route:
    - destination:
        host: inventory
    timeout: 0.5s
EOF
```

```bash
# Apply the timeout configuration
kubectl apply -f timeout-config.yaml
```

Let's break down what these configurations do:

- For the `pricing` service, we've set a 1-second timeout. This means that if the pricing service doesn't respond within 1 second, the request will be terminated.
- For the `inventory` service, we've set an even stricter 500ms timeout. This service should respond quickly, and if it doesn't, we'll fail fast.

These timeout values should be set based on your service's expected performance and the importance of a fast response.
For critical user-facing operations, shorter timeouts are often better, while background tasks might allow for longer timeouts.

`Testing Timeouts in Action`

Let's run our traffic generator again to see the impact of timeouts:

```bash
kubectl delete -f traffic-generator.yaml

# Generate traffic with timeouts configured
kubectl apply -f traffic-generator.yaml
```

Check the logs:

```bash
# Get the pod name of the traffic generator
TRAFFIC_POD=$(kubectl get pod -l app=traffic-generator -o jsonpath='{.items[0].metadata.name}')

# Check logs
kubectl logs $TRAFFIC_POD
```

You should notice:
- Requests that previously took a long time (3+ seconds) now fail much faster
- The overall response time becomes more consistent
- While we still have errors, our system is now responding predictably

`Why Timeouts Matter`

Without timeouts, a single slow service can degrade the entire system. For example:
1. If the `pricing` service takes 30 seconds to respond
2. The `product` service would wait 30 seconds for that response
3. The `frontend` service would wait 30 seconds for the `product` service
4. The user would wait 30 seconds for a page to load
5. During that 30 seconds, resources (threads, connections, memory) are tied up
6. These tied-up resources are not available for other requests
7. System capacity is gradually exhausted, leading to cascading failures

With timeouts, we fail fast and maintain system health:
1. If the `pricing` service is slow, the request fails quickly (1 second)
2. Resources are freed up to handle other requests
3. The system maintains its capacity to serve users
4. Even though some requests fail, the overall system remains responsive

However, timeouts alone just convert "slow" into "failed." To improve success rates, we need to combine timeouts with retries.

#### Step 5: Implementing Retries

`What Are Retries and Why Do We Need Them?`

Think about when you're trying to call someone in an area with poor cell service.

If the call drops, you don't give up forever - you try calling again, hoping that the connection will be better the next time.
This is exactly what retries do in a microservices architecture.

Retries automatically attempt failed requests again, which is particularly useful for handling transient failures like network glitches,
temporary service overloads, or database deadlocks.

Instead of immediately returning an error to the user, the system can try again and potentially succeed.

`How Retries Work in Istio`

In Istio, retries are also implemented at the proxy level.
When a request fails or times out, the Envoy proxy can automatically resend the request to the same service.

Istio provides fine-grained control over:

- How many retry attempts to make
- How long to wait between retries
- Which types of failures should trigger retries
- How long each retry attempt should take before giving up

`Implementing Retries`

Let's configure retries for calls to our services:

```bash
cat > retry-config.yaml << 'EOF'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: pricing-with-retry
spec:
  hosts:
  - pricing
  http:
  - route:
    - destination:
        host: pricing
    timeout: 2.5s
    retries:
      attempts: 3
      perTryTimeout: 0.5s
      retryOn: gateway-error,connect-failure,refused-stream,unavailable,5xx
---
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: inventory-with-retry
spec:
  hosts:
  - inventory
  http:
  - route:
    - destination:
        host: inventory
    timeout: 2s
    retries:
      attempts: 3
      perTryTimeout: 0.5s
      retryOn: gateway-error,connect-failure,refused-stream,unavailable,5xx
EOF
```

```bash
# Apply the retry configuration
kubectl apply -f retry-config.yaml
```

Let's break down these configurations:

**For both services:**
- `attempts: 3` - Try each request up to 3 times (initial request + 2 retries)
- `perTryTimeout: 0.5s` - Each attempt has a 500ms timeout
- `retryOn: gateway-error,connect-failure,refused-stream,unavailable,5xx` - Retry on various types of errors, including HTTP 5xx status codes

**Adjusted timeouts:**
- `pricing` timeout increased to 2.5s (to accommodate 3 attempts × 0.5s each + some overhead)
- `inventory` timeout increased to 2s (similarly, to give enough time for retries)

It's important to note that the overall timeout (`timeout: 2.5s`) must be larger than the product of `attempts` × `perTryTimeout`,
or else some retry attempts would be cut short.

`Testing Retries in Action`

Let's run our traffic generator again to see the impact of retries combined with timeouts:

```bash
kubectl delete -f traffic-generator.yaml

# Generate traffic with timeouts and retries configured
kubectl apply -f traffic-generator.yaml
```

Check the logs:

```bash
# Get the pod name of the traffic generator
TRAFFIC_POD=$(kubectl get pod -l app=traffic-generator -o jsonpath='{.items[0].metadata.name}')

# Check logs
kubectl logs $TRAFFIC_POD
```

You should notice:
- Higher success rates than with timeouts alone
- Some requests that would have failed now succeed (after retries)
- The overall response time is now more predictable, even though some requests take longer due to retries

`Why Retries Matter`

Retries can significantly improve the reliability of your system by automatically recovering from transient failures.
Consider what happens when the `inventory` service occasionally fails:

Without retries:
1. If the first request to `inventory` fails, the user gets an error
2. The user might need to manually retry their action (refresh the page)
3. A large percentage of requests fail, giving users a poor experience

With retries:
1. If the first request to `inventory` fails, the system tries again automatically
2. If the issue was temporary, the retry succeeds, and the user never sees an error
3. A higher percentage of requests succeed, giving users a better experience

However, retries aren't a silver bullet.
If a service is consistently failing or overloaded, retries can actually make the situation worse by adding more load.
This is where circuit breakers come in.

#### Step 6: Implementing Circuit Breakers

`What Are Circuit Breakers and Why Do We Need Them?`

Imagine you're in a house where several appliances are connected to the same electrical circuit.
If one appliance shorts out and you don't have a circuit breaker, it could damage all the other appliances or even start a fire.
That's why electrical systems have circuit breakers - to isolate problems and prevent them from cascading.

In microservices, circuit breakers serve a similar purpose.
They monitor for failures and, when too many occur, they "trip" (open the circuit) to prevent further requests from being sent to a failing service.

This:
- Prevents overloading already-struggling services with more requests
- Allows failing services time to recover
- Fails fast instead of letting requests hang until they timeout
- Isolates problems to stop them from spreading through your entire system

`How Circuit Breakers Work in Istio`

In Istio, circuit breakers are implemented in the Envoy proxies using two main components:

1. **Connection pools** - Limit how many connections and requests can be pending/active
2. **Outlier detection** - Monitor for failures and eject problematic hosts

When too many requests fail, the circuit "trips" and subsequent requests immediately receive error responses instead of being sent to the failing service.

`Implementing Circuit Breakers`

Let's configure circuit breakers for our inventory and pricing services:

```bash
cat > circuit-breaker.yaml << 'EOF'
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: inventory-circuit-breaker
spec:
  host: inventory
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 1
      http:
        http1MaxPendingRequests: 1
        maxRequestsPerConnection: 1
    outlierDetection:
      consecutive5xxErrors: 5
      interval: 10s
      baseEjectionTime: 60s
      maxEjectionPercent: 100
---
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: pricing-circuit-breaker
spec:
  host: pricing
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 1
      http:
        http1MaxPendingRequests: 1
        maxRequestsPerConnection: 1
    outlierDetection:
      consecutive5xxErrors: 5
      interval: 10s
      baseEjectionTime: 60s
      maxEjectionPercent: 100
EOF
```

```bash
# Apply the circuit breaker configuration
kubectl apply -f circuit-breaker.yaml
```

Let's break down what these parameters mean:

**Connection Pool Settings** (limit number of connections to prevent overwhelming the service):
- `maxConnections: 1` - Only allow 1 TCP connection to the service at a time
- `http1MaxPendingRequests: 1` - Only allow 1 request to queue up while waiting
- `maxRequestsPerConnection: 1` - Close the connection after 1 request (prevents connection reuse)

**Outlier Detection Settings** (detect and eject failing instances):
- `consecutive5xxErrors: 5` - Trip the circuit after 5 consecutive errors
- `interval: 10s` - Check for errors every 10 seconds
- `baseEjectionTime: 60s` - Once tripped, keep the circuit open for 1 minute
- `maxEjectionPercent: 100` - Allow all instances to be ejected if necessary

> **Note:** In our architecture, the Product service's sidecar is the client that will trip the breaker when making calls to Pricing and Inventory services.

`Testing Circuit Breakers in Action`

To see circuit breakers in action, we'll need to generate more traffic than our connection pool settings allow.

This will cause the circuit to trip and protect our services.

Let's create a job that sends a high volume of concurrent requests:

```bash
cat > high-traffic-generator.yaml << 'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: high-traffic-generator
spec:
  template:
    metadata:
      labels:
        app: traffic-generator
    spec:
      restartPolicy: Never
      containers:
        - name: traffic
          image: xr09/alpine-bash:latest      # Bash + curl ready to go
          command: ["bash", "-c"]
          args:
            - |
              set -euo pipefail
              
              # ─── Wait for Envoy ─────────────────────────────────────────────
              echo "Waiting for Envoy sidecar to be ready…"
              until curl -s -f -o /dev/null 127.0.0.1:15021/healthz/ready; do
                sleep 1
              done
              echo "Envoy is ready."
    
              # ─── Load‑test parameters ───────────────────────────────────────              
              total=200          # total requests
              concurrency=20     # max parallel curls
              url=http://frontend/
              
              echo "Starting high‑volume traffic generation (${total} req, ${concurrency} parallel)…"
              
              one() {
                resp=$(curl -s -w '\n%{http_code}' --max-time 5 "$url")
                code=$(tail -n1 <<<"$resp")
                body=$(sed '$d' <<<"$resp")
                
                if   [ "$code" -eq 200 ];          then echo OK
                elif [ "$code" -eq 000 ];          then echo TIMEOUT
                elif [ "$code" -eq 500 ];          then echo CBOPEN       # breaker
                elif grep -qiE 'overflow|circuit' <<<"$body"; then echo CBOPEN
                else                                       echo ERR
                fi
              }
              
              export -f one         # export the *function*
              export url            # export the *variable*
              
              results=/tmp/results
              : >"$results"         # truncate / create
              
              running=0
              for i in $(seq 1 "$total"); do
                bash -c one >>"$results" &
                running=$((running+1))
                if [ "$running" -ge "$concurrency" ]; then
                  wait -n
                  running=$((running-1))
                fi
              done
              wait
              
              ok=$(grep -c '^OK$'       "$results" || true)
              err=$(grep -c '^ERR$'     "$results" || true)
              tmo=$(grep -c '^TIMEOUT$' "$results" || true)
              cbo=$(grep -c '^CBOPEN$'  "$results" || true)
              
              pct() { awk -v n="$1" -v t="$total" 'BEGIN{printf "%.2f", (n*100)/t}'; }
              
              echo
              echo "Results:"
              echo "  Total requests: $total"
              echo "  Successful:   $ok  ($(pct "$ok")%)"
              echo "  Errors:       $err ($(pct "$err")%)"
              echo "  Timeouts:     $tmo ($(pct "$tmo")%)"
              echo "  Circuit open: $cbo ($(pct "$cbo")%)"
              echo "Traffic generation complete."
  backoffLimit: 1
EOF
```

```bash
# Generate high traffic to trigger the circuit breaker
kubectl apply -f high-traffic-generator.yaml
```

`Understanding Circuit Breaker Behavior`

Once you run the high-traffic test, check the logs:

```bash
# Get the pod name of the traffic generator
TRAFFIC_POD=$(kubectl get pod -l app=traffic-generator -o jsonpath='{.items[0].metadata.name}')

# Check logs
kubectl logs $TRAFFIC_POD
```

You should see output similar to:
```
Waiting for Envoy sidecar to be ready…
Envoy is ready.
Starting high‑volume traffic generation (200 req, 20 parallel)…

Results:
  Total requests: 200
  Successful:   1  (0.50%)
  Errors:       0 (0.00%)
  Timeouts:     0 (0.00%)
  Circuit open: 199 (99.50%)
Traffic generation complete.
```

`What's Happening Behind the Scenes?`

When our test sends multiple concurrent requests, here's what happens:

1. Initial requests go through normally (a small percentage succeed)
2. As concurrent requests exceed our connection pool limits (`maxConnections: 1`), the circuit breaker trips
3. Subsequent requests immediately fail with a "circuit open" response
4. These fast failures prevent resources from being tied up with requests that would eventually fail
5. The system continues to function (albeit in a degraded state) rather than completely crashing

You can see the actual circuit breaker events in the Envoy proxy logs:

```bash
PRODUCT=$(kubectl get pod -l app=product -o jsonpath='{.items[0].metadata.name}')
kubectl logs "$PRODUCT" -c istio-proxy | grep '503'
```

These logs show `503` errors with `upstream_reset_before_response_started{overflow}` messages - this confirms that the circuit breaker is working as expected.

`Visualizing Circuit Breakers in Kiali`

For a more intuitive understanding, let's visualize the circuit breaker in action:

```bash
# install Istio addons
bash istio-cluster-manager.sh install-addons istio-resilience

kubectl port-forward svc/kiali -n istio-system 20001:20001
```

Open your browser to `http://localhost:20001/` and navigate to:
- `Traffic Graph` → `default namespace` → `Traffic Animation`

Re-run our high-traffic generator to observe the circuit breaker in action
```bash
kubectl delete -f high-traffic-generator.yaml

# Generate high traffic to trigger the circuit breaker
kubectl apply -f high-traffic-generator.yaml
```

While the circuit breaker is open, you'll see red edges from `Product` to `Pricing` and `Product` to `Inventory`.

This visual representation makes it easy to spot which services are experiencing circuit breaker events.

`Why Circuit Breakers Matter`

Let's consider what would happen without circuit breakers:

1. During failures, each new request would tie up resources waiting for a response
2. These tied-up resources would prevent the system from handling other requests
3. Resources would become exhausted, causing cascading failures across services
4. The entire system could crash, requiring a full restart

With circuit breakers, the system gracefully degrades instead of crashing:
- Failing services get a chance to recover without additional load
- Users receive fast error responses instead of hanging requests
- Critical functionality can remain available even when some services fail
- The system is more resilient and can self-heal

#### Step 7: Implementing Outlier Detection

`What Is Outlier Detection and Why Do We Need It?`

Imagine you're managing a team of customer service representatives.
If one representative is consistently providing incorrect information to customers, you'd want to temporarily remove them from the rotation until they receive additional training.

This is exactly what outlier detection does in a microservices architecture.

Outlier detection automatically identifies and removes unhealthy service instances from the load balancing pool, directing traffic only to healthy instances.

This is particularly useful when you have multiple replicas of a service and some instances start failing while others remain healthy.

`How Outlier Detection Works in Istio`

In Istio, outlier detection monitors the health of each service instance by tracking error rates and response times.

When an instance exceeds certain error thresholds, it's temporarily "ejected" from the load balancing pool.

After a specified period, the instance is allowed back into the pool and given another chance to prove its reliability.

`Implementing Outlier Detection`

First, let's scale up our inventory service to have multiple instances:

```bash
# Scale up the inventory service
kubectl scale deployment inventory --replicas=3
```

Now we have three instances of the inventory service. Let's configure outlier detection:

```bash
cat > outlier-detection.yaml << 'EOF'
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: inventory-outlier
spec:
  host: inventory
  trafficPolicy:
    outlierDetection:
      consecutive5xxErrors: 5
      interval: 10s
      baseEjectionTime: 30s
      maxEjectionPercent: 50
EOF
```

```bash
# Apply the outlier detection configuration
kubectl apply -f outlier-detection.yaml
```

Let's break down what these parameters mean:

- `consecutive5xxErrors: 5` - Eject an instance after 5 consecutive errors
- `interval: 10s` - Check instances for errors every 10 seconds
- `baseEjectionTime: 30s` - Keep ejected instances out of rotation for 30 seconds
- `maxEjectionPercent: 50` - Never eject more than 50% of instances (ensuring service availability)

`Introducing a Consistently Failing Instance`

To demonstrate outlier detection, let's introduce an instance that fails more frequently than the others:

```bash
cat > failing-instance-config.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inventory-failing
  labels:
    app: inventory
    version: failing
spec:
  replicas: 1
  selector:
    matchLabels:
      app: inventory
      version: failing
  template:
    metadata:
      labels:
        app: inventory
        version: failing
    spec:
      containers:
      - name: inventory
        image: ghcr.io/nicholasjackson/fake-service:v0.26.2
        env:
          - name: NAME
            value: "inventory"
          # 90% of requests will return an error
          - name: ERROR_RATE
            value: "0.9"    # 90%
          - name: ERROR_TYPE
            value: "http_error"
          - name: ERROR_CODE
            value: "500"
        ports:
        - containerPort: 9090
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "200m"
            memory: "256Mi"
EOF
```

```bash
# Introduce failures to one instance
kubectl apply -f failing-instance-config.yaml
```

This deploys an additional instance of the inventory service that fails 90% of the time, compared to the regular instances that fail 30% of the time.

`Observing Outlier Detection in Action`

Turn on verbose outlier‑detection messages
```bash
PRODUCT=$(kubectl get pod -l app=product -o jsonpath='{.items[0].metadata.name}')

istioctl proxy-config log "$PRODUCT" --level upstream:debug
```

Let's generate traffic and observe how outlier detection responds:

```bash
kubectl delete -f traffic-generator.yaml --ignore-not-found
kubectl delete -f high-traffic-generator.yaml --ignore-not-found

# Generate traffic with outlier detection configured
kubectl apply -f traffic-generator.yaml
```

Verifying ejection status in Istio proxy logs:

```bash
# Check the Envoy logs for outlier detection events
kubectl logs $PRODUCT -c istio-proxy | grep -i "outlier"
```

Look for lines containing messages like:
```
was ejected by the outlier detector
```

These log entries confirm that the Envoy proxy has detected and ejected the failing instance.

`What's Happening Behind the Scenes?`

When we run our test with outlier detection enabled:

1. Initially, requests are distributed among all inventory instances
2. The failing instance (`inventory-failing`) returns errors 90% of the time
3. Envoy proxies (sidecars) track the error rates for each instance they communicate with
4. Once an instance hits 5 consecutive errors, the outlier detection ejects that instance
5. Subsequent requests are only routed to the healthy instances
6. After 30 seconds (our `baseEjectionTime`), the failing instance is allowed back into the pool
7. If it continues to fail, it's ejected again

This cycle continues, with the failing instance being periodically ejected and allowed back in, but spending most of its time outside the load balancing pool.

`Why Outlier Detection Matters`

Outlier detection provides several key benefits:

1. **Automatic healing** - The system can identify and isolate problematic instances without human intervention
2. **Higher availability** - Even when some instances fail, traffic is routed to healthy instances
3. **Early problem detection** - Outlier detection can identify problematic instances before they cause widespread failures
4. **Graceful degradation** - The system can continue operating with reduced capacity, rather than complete failure

Combined with circuit breakers, retries, and timeouts, outlier detection creates a multi-layered defense against service failures.

#### Step 8: Implementing Fault Injection

`What Is Fault Injection and Why Do We Need It?`

Imagine you're a car manufacturer. You wouldn't wait until a customer has an accident to discover a safety issue - you'd test the car under various stress
conditions in a controlled environment first.

Similarly, fault injection allows us to deliberately introduce failures or delays to test our application's resilience before real failures occur in production.

Fault injection is a form of chaos engineering that helps answer questions like:
- What happens if Service A becomes slow?
- How does the system respond when Service B returns errors?
- Is our resilience configuration working as expected?

`How Fault Injection Works in Istio`

Istio allows us to inject two types of faults:
1. **Delays** - Artificially increase latency to simulate slow services or network delays
2. **Aborts** - Return error codes to simulate service failures

These faults can be applied selectively (to a percentage of traffic) and targeted at specific services.

`Implementing Fault Injection`

Let's configure fault injection for our services:

```bash
cat > fault-injection.yaml << 'EOF'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: inventory-fault
spec:
  hosts:
  - inventory
  http:
  - fault:
      delay:
        percentage:
          value: 10
        fixedDelay: 2s
    route:
    - destination:
        host: inventory
---
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: pricing-fault
spec:
  hosts:
  - pricing
  http:
  - fault:
      abort:
        percentage:
          value: 5
        httpStatus: 500
    route:
    - destination:
        host: pricing
EOF
```

```bash
# Apply the fault injection configuration
kubectl apply -f fault-injection.yaml
```

Let's break down what these configurations do:

For the inventory service:
- `percentage: value: 10` - Affect 10% of requests
- `fixedDelay: 2s` - Add a 2-second delay

For the pricing service:
- `percentage: value: 5` - Affect 5% of requests
- `httpStatus: 500` - Return a 500 error

`Testing Fault Injection in Action`

Let's generate traffic and observe how our system responds to these artificial faults:

```bash
kubectl delete -f traffic-generator.yaml --ignore-not-found
kubectl delete -f high-traffic-generator.yaml --ignore-not-found

# Generate traffic with fault injection configured
kubectl apply -f traffic-generator.yaml
```

Check the logs:

```bash
# Get the pod name of the traffic generator
TRAFFIC_POD=$(kubectl get pod -l app=traffic-generator -o jsonpath='{.items[0].metadata.name}')

# Check logs
kubectl logs $TRAFFIC_POD
```

`What's Happening Behind the Scenes?`

When we inject faults:

1. For the inventory service, 10% of requests are delayed by 2 seconds. This tests whether our timeout settings are effective.
2. For the pricing service, 5% of requests fail with a 500 error. This tests whether our retry and circuit breaker settings are effective.

These artificial faults help validate our resilience patterns in a controlled environment.

`Why Fault Injection Matters`

Fault injection provides several important benefits:

1. **Proactive testing** - Find issues before they affect real users
2. **Confidence in resilience** - Verify that resilience patterns are working as expected
3. **Realistic scenarios** - Test how your system responds to common failure modes
4. **Continuous improvement** - Identify areas where additional resilience is needed

By regularly injecting faults into your system, you can continuously improve its resilience and ensure that it can withstand real-world failures.

#### Step 9: Visualizing Resilience in Action

Now that we've implemented various resilience patterns, let's use Istio's observability features to visualize how they affect our system.

`Installing Istio Addons`

First, let's install the Istio addons for visualization:

```bash
# install Istio addons if not already installed
bash istio-cluster-manager.sh install-addons istio-resilience
```

`Using Kiali to Visualize Service Interactions`

`Kiali` provides a graphical view of your service mesh, showing traffic flows, error rates, and more:

```bash
# access Kiali dashboard
kubectl port-forward -n istio-system svc/kiali 20001:20001
```

Open your browser and navigate to:
```
http://localhost:20001/
```

In `Kiali`:
1. Go to the `"Graph"` section
2. Select the `"default"` namespace
3. You'll see a visual representation of traffic flow between services

Try enabling `"Traffic Animation"` to see real-time traffic flows. You can also hover over connections to see detailed metrics like error rates and response times.

`Using Grafana for Detailed Metrics`

Grafana provides more detailed metrics about your services:

```bash
# access Grafana dashboard
kubectl port-forward -n istio-system svc/grafana 3000:3000
```

Open your browser and navigate to:
```
http://localhost:3000/
```

In `Grafana`:
1. Navigate to the `"Istio Service Dashboard"`
2. Select different services to see their metrics
3. Look at error rates, request volumes, and latencies

These metrics help you understand how your resilience patterns are affecting system behavior over time.

`Generating Load for Visualization`

To see the resilience patterns in action, generate continuous traffic:

```bash
cat > continuous-traffic.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: continuous-traffic
spec:
  replicas: 1
  selector:
    matchLabels:
      app: continuous-traffic
  template:
    metadata:
      labels:
        app: continuous-traffic
    spec:
      containers:
      - name: traffic
        image: busybox
        command: ["/bin/sh", "-c"]
        args:
        - |
          while true; do
            wget -q -O - --timeout=2 http://frontend || true
            sleep 0.5
          done
EOF
```

```bash
# Deploy continuous traffic generator
kubectl apply -f continuous-traffic.yaml
```

Now watch the `Kiali` graph as traffic flows through your system. You should be able to see:
- How timeouts prevent long-running requests
- How retries attempt to recover from failures
- How circuit breakers trip when services are overloaded
- How outlier detection routes traffic away from failing instances

This visual representation helps you understand how resilience patterns work together to create a robust system.

#### Cleanup

When you're done experimenting, clean up all resources:

```bash
# delete the kind cluster
bash istio-cluster-manager.sh delete istio-resilience
```

#### Understanding What Happened Under the Hood

In this scenario, we've implemented a comprehensive set of resilience patterns to protect our application from various types of failures:

**1. Timeouts**: Timeouts prevented slow services from blocking the entire request chain.
By setting strict time limits on service calls, we ensured that users received prompt responses, even when backend services were experiencing delays.

**2. Retries**: Retries automatically attempted to recover from transient failures.
Instead of immediately returning errors to users, our system made additional attempts that often succeeded, improving the overall user experience.

**3. Circuit Breakers**: Circuit breakers prevented cascade failures by stopping requests to failing services.
This protected our system from overload and gave failing services time to recover, enabling graceful degradation rather than catastrophic failure.

**4. Outlier Detection**: Outlier detection automatically removed unhealthy instances from the load balancing pool.
By routing traffic only to healthy instances, we maintained system availability even when some instances were failing.

**5. Fault Injection**: Fault injection allowed us to test our resilience patterns by deliberately introducing failures and delays.
This proactive testing approach helped us verify that our resilience strategies were working as expected.

The power of implementing these patterns with Istio is that they operate at the infrastructure level, not in your application code:

- **Separation of concerns** - Developers can focus on business logic while operations teams handle resilience
- **Consistent implementation** - Patterns are applied uniformly across all services
- **Declarative configuration** - Resilience is defined in YAML, not code
- **Runtime adjustability** - Patterns can be adjusted without redeploying applications
- **Observability** - Built-in tools help visualize and understand system behavior

By implementing these patterns, we've created a robust system that can withstand various types of failures while maintaining acceptable user experience.

In a real-world scenario, this translates to higher availability, better user satisfaction, and fewer late-night emergency calls for your team.

Remember, resilience isn't about preventing all failures - it's about designing systems that can detect, respond to, and recover from failures when they inevitably occur.

With Istio's service mesh capabilities, you can build resilient microservice architectures that gracefully handle the challenges of distributed systems.