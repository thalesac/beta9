<!--- app-name: beta9 -->

# Beta9

Beam.cloud Beta9 is an open-source platform for running scalable serverless GPU workloads across cloud providers.

## TL;DR

Assuming you have a Kubernetes cluster running:

```console
git clone https://github.com/beam-cloud/beta9.git
cd deploy/charts/beta9/
vim values-override.yaml # Modify as needed
helm install beta9 ./ -f values-override.yaml --namespace beta9
```

## Introduction

Beta9 is an open-source serverless platform designed for running scalable GPU-accelerated workloads. It provides developers with a simple, Python-first interface for deploying machine learning models, AI applications, and compute-intensive tasks with automatic scaling, resource management, and cost optimization.

### Key Features

- **Serverless GPU Computing**: Automatic scaling from zero to hundreds of GPUs based on demand
- **Multi-Cloud Support**: Deploy across AWS, GCP, Azure, and other cloud providers
- **Container-Native**: Built on Kubernetes with first-class container support
- **Developer-Friendly**: Simple Python SDK and REST API
- **Cost-Effective**: Pay only for compute time used, with intelligent resource pooling

### Chart Components

This Helm chart deploys a complete Beta9 cluster on Kubernetes with the following components:

#### Core Services
- **Gateway**: Main API server, control plane, and web interface
- **Worker Pools**: Auto-scaled compute nodes for executing workloads (deployed on-demand)
- **Scheduler**: Intelligent workload scheduling and resource allocation

#### Data Layer (Optional - can use external services)
- **PostgreSQL**: Metadata storage, job history, and user management
- **Redis**: Task queuing, caching, and real-time communication  
- **JuiceFS Redis**: Distributed filesystem metadata store
- **MinIO**: S3-compatible object storage for files and container images

#### Monitoring & Observability (Optional)
- **Grafana**: Dashboards and visualization
- **Victoria Metrics**: Time-series metrics collection and storage
- **Fluent Bit**: Log aggregation and forwarding

### Architecture

Beta9 follows a cloud-native architecture designed for scalability and reliability:

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Users/SDKs    │───▶│     Gateway      │───▶│  Worker Pools   │
│                 │    │  (API/Control)   │    │   (Compute)     │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                │                        │
                                ▼                        ▼
                       ┌──────────────────┐    ┌─────────────────┐
                       │   Data Layer     │    │   File Storage  │
                       │ (PostgreSQL,     │    │  (S3/MinIO/     │
                       │  Redis)          │    │   JuiceFS)      │
                       └──────────────────┘    └─────────────────┘
```

## Prerequisites

### Kubernetes Cluster Requirements

- **Kubernetes Version**: 1.23+ (recommended: 1.28+)
- **Helm Version**: 3.8.0+ (recommended: 3.12+)
- **Node Resources**: Minimum 4 CPU cores and 8GB RAM for the control plane
- **Storage**: Dynamic PV provisioner with support for ReadWriteOnce volumes
- **Network**: LoadBalancer or Ingress controller for external access

### GPU Support (Optional but Recommended)

For GPU workloads, ensure your cluster has:
- GPU-enabled nodes
- NVIDIA Device Plugin or GPU Operator installed
- Appropriate GPU drivers on worker nodes

```bash
# Install NVIDIA Device Plugin
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.3/nvidia-device-plugin.yml
```

### Storage Requirements

- **Persistent Volumes**: At least 50GB for data storage (configurable)
- **Container Images**: Additional storage for container registry (if using bundled MinIO)
- **Workspace Data**: Storage for user workspaces and temporary files

### Networking Requirements

- **External Access**: LoadBalancer service or Ingress controller
- **Internal Communication**: Pod-to-pod networking for distributed workloads
- **Internet Access**: For downloading container images and dependencies (unless using private registries)

### Recommended Cluster Setup

For production deployments:

```bash
# Example node configuration
Control Plane Nodes: 3 nodes, 4 CPU, 8GB RAM each
Worker Nodes (CPU): 3+ nodes, 8 CPU, 16GB RAM each  
Worker Nodes (GPU): 1+ nodes, 8 CPU, 32GB RAM, 1+ GPUs each
```


## Configuration and installation details


### External data layers

For production deployments, you may want to use external managed services instead of deploying data stores within your Kubernetes cluster. This approach offers better scalability, availability, and security with managed backups, automatic scaling, and compliance certifications.

#### Supported External Services

**Databases:** Amazon RDS, Google Cloud SQL, Azure Database, DigitalOcean Managed Databases  
**Caching:** ElastiCache, Memorystore, Azure Cache for Redis, Redis Cloud  
**Storage:** Amazon S3, Google Cloud Storage, DigitalOcean Spaces, Cloudflare R2

#### Configuration with Secure Secrets

```yaml
# Disable bundled data stores
postgresql:
  enabled: false
redis:
  enabled: false
juicefs-redis:
  enabled: false
minio:
  enabled: false

# External database with secret reference / Postgres
externalDatabase:
  host: "beta9-db.cluster-xyz.us-east-1.rds.amazonaws.com"
  port: 5432
  user: "beta9"
  database: "beta9_prod"
  existingSecret: "beta9-database-secret"
  existingSecretPasswordKey: "password"

# External Redis with secret reference
externalRedis:
  host: "beta9-cache.xyz.cache.amazonaws.com"
  port: 6379
  existingSecret: "beta9-redis-secret"
  existingSecretPasswordKey: "password"

# External S3 storage (see Cloud-Native Authentication below for IRSA/Pod Identity)
config:
  storage:
    juicefs:
      awsS3Bucket: "https://s3.amazonaws.com/beta9-storage-prod"
      awsAccessKey: "AKIA..."  # Or omit for IRSA/Pod Identity
      awsSecretKey: "secret"   # Or omit for IRSA/Pod Identity
  imageService:
    registries:
      s3:
        primary:
          bucketName: "beta9-images-prod"
          region: "us-east-1"
          endpoint: "https://s3.amazonaws.com"
  workspaceStorage:
    defaultBucketPrefix: "beta9-workspaces"
    defaultEndpointUrl: "https://s3.amazonaws.com"
    defaultRegion: "us-east-1"
```

**Create the secrets:**
```bash
kubectl create secret generic beta9-database-secret \
  --from-literal=password="your-secure-db-password" \
  --namespace=beta9

kubectl create secret generic beta9-redis-secret \
  --from-literal=password="your-secure-redis-password" \
  --namespace=beta9
```

#### Cloud-Native Authentication (IRSA/Pod Identity)

For the highest security, use cloud-native authentication instead of access keys:

##### **AWS IRSA (IAM Roles for Service Accounts)**

```bash
# 1. Create IAM role with S3 permissions
aws iam create-role --role-name Beta9S3Role --assume-role-policy-document '{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/oidc.eks.REGION.amazonaws.com/id/OIDC_ID"},
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "oidc.eks.REGION.amazonaws.com/id/OIDC_ID:sub": "system:serviceaccount:beta9:beta9"
      }
    }
  }]
}'

# 2. Attach S3 permissions
aws iam attach-role-policy \
  --role-name Beta9S3Role \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
```

```yaml
# Helm values for IRSA
serviceAccount:
  create: true
  annotations:
    eks.amazonaws.com/role-arn: "arn:aws:iam::123456789012:role/Beta9S3Role"

minio:
  enabled: false

config:
  storage:
    juicefs:
      awsS3Bucket: "https://s3.amazonaws.com/your-beta9-bucket"
      # Remove access keys - IRSA handles authentication
  fileService:
    endpointUrl: "https://s3.amazonaws.com"
    bucketName: "your-beta9-storage"
    # Remove access keys - IRSA handles authentication  
  imageService:
    registries:
      s3:
        primary:
          bucketName: "your-beta9-images"
          endpoint: "https://s3.amazonaws.com"
          # Remove access keys - IRSA handles authentication
```


##### **Google Cloud Workload Identity**

```bash
# Create service account
gcloud iam service-accounts create beta9-gcs-sa

# Grant storage permissions  
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member "serviceAccount:beta9-gcs-sa@PROJECT_ID.iam.gserviceaccount.com" \
  --role "roles/storage.admin"

# Bind to Kubernetes service account
gcloud iam service-accounts add-iam-policy-binding \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:PROJECT_ID.svc.id.goog[beta9/beta9]" \
  beta9-gcs-sa@PROJECT_ID.iam.gserviceaccount.com
```

```yaml
# Helm values for GCP
serviceAccount:
  create: true
  annotations:
    iam.gke.io/gcp-service-account: "beta9-gcs-sa@PROJECT_ID.iam.gserviceaccount.com"

config:
  storage:
    juicefs:
      awsS3Bucket: "https://storage.googleapis.com/your-gcs-bucket"
      # Remove access keys - Workload Identity handles authentication
```

> **Security Note**: For production deployments, use Kubernetes secrets to store sensitive credentials instead of putting them directly in values files. You can reference existing secrets using the `existingSecret` parameters.

### Ingress

This chart provides support for Ingress resources and cloud-native load balancers. Beta9 can be exposed through various methods depending on your cloud provider and requirements.

#### Ingress vs Service LoadBalancer

**Use Ingress when:**
- You need path-based routing, SSL termination, or multiple domains
- You have an existing ingress controller (nginx, contour, ALB, etc.)
- You want to consolidate multiple services behind one load balancer

**Use Service LoadBalancer when:**
- You need direct L4 access (especially for gRPC)
- You want cloud provider's native load balancer features
- You have simple single-service exposure requirements

#### Beta9 Routing Modes

Beta9 supports two routing modes via `config.gateway.invokeURLType`:

- **Path-based** (`path`): `https://beta9.example.com/function/my-endpoint`
- **Subdomain** (`subdomain`): `https://my-endpoint.beta9.example.com`

Choose subdomain routing for better isolation and path-based for simpler DNS management.

#### Generic Ingress Controller Setup

For standard ingress controllers like nginx or contour:

```yaml
ingress:
  enabled: true
  hostname: "beta9.yourdomain.com"
  ingressClassName: "nginx"  # or "contour"
  annotations:
    # For cert-manager automatic certificate provisioning
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    # For nginx ingress controller
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
    # For gRPC support
    nginx.ingress.kubernetes.io/grpc-backend: "true"
  tls: true

config:
  gateway:
    http:
      externalHost: "beta9.yourdomain.com"
      externalPort: 443
      tls: true
    grpc:
      externalHost: "beta9.yourdomain.com"
      externalPort: 443
      tls: true
```

#### AWS Application Load Balancer (ALB)

For AWS EKS clusters, use the AWS Load Balancer Controller with ALB:

**Prerequisites:**
```bash
# Install AWS Load Balancer Controller
helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=your-cluster-name \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

**Configuration:**
```yaml
# Option 1: ALB Ingress (Recommended for HTTP/HTTPS)
ingress:
  enabled: true
  hostname: "beta9.yourdomain.com"
  ingressClassName: "alb"
  annotations:
    # ALB Configuration
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/load-balancer-name: beta9-alb
    
    # SSL Configuration
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: '443'
    alb.ingress.kubernetes.io/certificate-arn: "arn:aws:acm:region:account:certificate/cert-id"
    
    # Health checks
    alb.ingress.kubernetes.io/healthcheck-path: "/api/v1/health"
    alb.ingress.kubernetes.io/healthcheck-interval-seconds: '30'
    alb.ingress.kubernetes.io/healthcheck-timeout-seconds: '5'
    
    # Performance
    alb.ingress.kubernetes.io/load-balancer-attributes: |
      deletion_protection.enabled=false,
      idle_timeout.timeout_seconds=60,
      access_logs.s3.enabled=true,
      access_logs.s3.bucket=your-alb-logs-bucket
  tls: true

# Option 2: Network Load Balancer (NLB) for gRPC
service:
  type: LoadBalancer
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
    service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
    # For TLS termination at NLB
    service.beta.kubernetes.io/aws-load-balancer-ssl-cert: "arn:aws:acm:region:account:certificate/cert-id"
    service.beta.kubernetes.io/aws-load-balancer-ssl-ports: "https,grpc-tls"

config:
  gateway:
    http:
      externalHost: "beta9.yourdomain.com"
      externalPort: 443
      tls: true
    grpc:
      externalHost: "beta9.yourdomain.com"  
      externalPort: 443
      tls: true
```

#### Google Cloud Load Balancer (GCP)

For GKE clusters, use Google Cloud Load Balancer integration:

**Prerequisites:**
```bash
# Ensure GKE cluster has HTTP(S) load balancing enabled
gcloud container clusters update your-cluster-name \
  --enable-ip-alias \
  --zone=your-zone
```

**Configuration:**
```yaml
# Option 1: GCE Ingress (L7 HTTP/HTTPS Load Balancer)
ingress:
  enabled: true
  hostname: "beta9.yourdomain.com"
  ingressClassName: "gce"
  annotations:
    # GCE Ingress Configuration
    kubernetes.io/ingress.class: "gce"
    kubernetes.io/ingress.global-static-ip-name: "beta9-static-ip"
    
    # SSL Configuration
    ingress.gcp.kubernetes.io/managed-certificates: "beta9-ssl-cert"
    kubernetes.io/ingress.allow-http: "false"
    
    # Backend Configuration
    cloud.google.com/backend-config: '{"default": "beta9-backend-config"}'
    
    # CDN and performance
    kubernetes.io/ingress.class: "gce"
    ingress.gcp.kubernetes.io/frontend-config: "beta9-frontend-config"
  tls: true

# Create managed certificate
apiVersion: networking.gke.io/v1
kind: ManagedCertificate
metadata:
  name: beta9-ssl-cert
spec:
  domains:
    - beta9.yourdomain.com
    - "*.beta9.yourdomain.com"  # For subdomain routing

---
# Backend configuration for health checks and timeouts
apiVersion: cloud.google.com/v1
kind: BackendConfig
metadata:
  name: beta9-backend-config
spec:
  healthCheck:
    checkIntervalSec: 30
    timeoutSec: 5
    healthyThreshold: 1
    unhealthyThreshold: 3
    type: HTTP
    requestPath: /api/v1/health
  timeoutSec: 60
  connectionDraining:
    drainingTimeoutSec: 60

# Option 2: Internal Load Balancer for gRPC
service:
  type: LoadBalancer
  annotations:
    cloud.google.com/load-balancer-type: "External"
    # For internal load balancer, use:
    # cloud.google.com/load-balancer-type: "Internal"
    
config:
  gateway:
    http:
      externalHost: "beta9.yourdomain.com"
      externalPort: 443
      tls: true
    grpc:
      externalHost: "beta9.yourdomain.com"
      externalPort: 443
      tls: true
```

#### Subdomain Routing Configuration

For subdomain-based routing (`*.beta9.yourdomain.com`):

```yaml
ingress:
  enabled: true
  hostname: "beta9.yourdomain.com"
  extraHosts:
    - name: "*.beta9.yourdomain.com"
      path: /
  annotations:
    # Ensure wildcard support
    nginx.ingress.kubernetes.io/server-alias: "*.beta9.yourdomain.com"
    # For ALB
    alb.ingress.kubernetes.io/actions.ssl-redirect: |
      {"Type": "redirect", "RedirectConfig": {"Protocol": "HTTPS", "Port": "443", "StatusCode": "HTTP_301"}}

config:
  gateway:
    invokeURLType: subdomain  # Enable subdomain routing
    http:
      externalHost: "beta9.yourdomain.com"
```

#### Multiple Host Configuration

For serving Beta9 on multiple domains:

```yaml
ingress:
  enabled: true
  hostname: "beta9.primary.com"
  extraHosts:
    - name: "beta9.secondary.com"
      path: /
    - name: "api.company.com"
      path: /beta9
  extraTls:
    - hosts:
        - beta9.secondary.com
      secretName: beta9-secondary-tls
    - hosts:
        - api.company.com
      secretName: company-api-tls
  tls: true
```

#### Securing traffic using TLS

Beta9 supports TLS encryption for secure communication. You can enable TLS through the ingress configuration or by configuring the gateway directly.

##### TLS via Ingress (Recommended)

The easiest way to enable TLS is through ingress with automatic certificate management:

```yaml
ingress:
  enabled: true
  hostname: "beta9.yourdomain.com"
  tls: true
  annotations:
    # For cert-manager automatic certificate provisioning
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    # For nginx ingress controller
    kubernetes.io/ingress.class: "nginx"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
```

##### Manual TLS Certificate Management

For custom certificates, create a TLS secret and reference it in the ingress:

```bash
# Create TLS secret with your certificates
kubectl create secret tls beta9-tls-secret \
  --cert=path/to/tls.crt \
  --key=path/to/tls.key \
  --namespace=beta9
```

```yaml
ingress:
  enabled: true
  hostname: "beta9.yourdomain.com"
  tls: true
  secrets:
    - name: beta9-tls-secret
      certificate: |-
        -----BEGIN CERTIFICATE-----
        ...your certificate...
        -----END CERTIFICATE-----
      key: |-
        -----BEGIN PRIVATE KEY-----
        ...your private key...
        -----END PRIVATE KEY-----
```

##### Gateway TLS Configuration

You can also configure TLS directly on the Beta9 gateway:

```yaml
config:
  gateway:
    grpc:
      tls: true
      externalPort: 443
    http:
      tls: true  
      externalPort: 443
```

#### Troubleshooting Ingress

**Common Issues:**

1. **gRPC not working through HTTP ingress**: Use a dedicated gRPC-aware load balancer or enable gRPC backend annotations
2. **Large file uploads failing**: Increase `proxy-body-size` annotations
3. **WebSocket connections dropping**: Enable WebSocket support in your ingress controller
4. **SSL certificate issues**: Verify cert-manager is properly configured and DNS is pointing to your load balancer

**Health Check Endpoints:**
- HTTP Health: `GET /api/v1/health`
- gRPC Health: Standard gRPC health service (`grpc.health.v1.Health`)
- Metrics: `GET /metrics` (if metrics enabled)

The most common scenario is to have one host name mapped to the deployment. In this case, the `ingress.hostname` property can be used to set the host name. The `ingress.tls` parameter can be used to add the TLS configuration for this host.

However, it is also possible to have more than one host. To facilitate this, the `ingress.extraHosts` parameter can be set with the host names specified as an array. The `ingress.extraTLS` parameter can also be used to add the TLS configuration for extra hosts.

> NOTE: For each host specified in the `ingress.extraHosts` parameter, it is necessary to set a name, path, and any annotations that the Ingress controller should know about. Not all annotations are supported by all Ingress controllers, but [this annotation reference document](https://github.com/kubernetes/ingress-nginx/blob/master/docs/user-guide/nginx-configuration/annotations.md) lists the annotations supported by many popular Ingress controllers.

Adding the TLS parameter will cause the chart to generate HTTPS URLs, and the application will be available on port 443. The actual TLS secrets do not have to be generated by this chart. However, if TLS is enabled, the Ingress record will not work until the TLS secret exists.

[Learn more about Ingress controllers](https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/).

### GPU Support

Beta9 is designed for GPU workloads. Ensure your Kubernetes cluster has GPU nodes available and the appropriate device plugins installed (such as the NVIDIA device plugin for NVIDIA GPUs).

### Additional environment variables

In case you want to add extra environment variables (useful for advanced operations like custom init scripts), you can use the `extraEnvVars` property.

```yaml
gateway:
  extraEnvVars:
    - name: LOG_LEVEL
      value: debug
```

Alternatively, you can use a ConfigMap or a Secret with the environment variables. To do so, use the `extraEnvVarsCM` or the `extraEnvVarsSecret` values.

### Sidecars

If additional containers are needed in the same pod as Beta9 (such as additional metrics or logging exporters), they can be defined using the `sidecars` parameter.

```yaml
gateway:
  sidecars:
  - name: your-image-name
    image: your-image
    imagePullPolicy: Always
    ports:
    - name: portname
      containerPort: 1234
```

If these sidecars export extra ports, extra port definitions can be added using the `service.extraPorts` parameter (where available), as shown in the example below:

```yaml
service:
  extraPorts:
  - name: extraPort
    port: 11311
    targetPort: 11311
```

> NOTE: This Helm chart already includes sidecar containers for the Prometheus exporters (where applicable). These can be activated by adding the `--enable-metrics=true` parameter at deployment time. The `sidecars` parameter should therefore only be used for any extra sidecar containers.

If additional init containers are needed in the same pod, they can be defined using the `initContainers` parameter. Here is an example:

```yaml
gateway:
  initContainers:
    - name: your-image-name
      image: your-image
      imagePullPolicy: Always
      ports:
        - name: portname
          containerPort: 1234
```

Learn more about [sidecar containers](https://kubernetes.io/docs/concepts/workloads/pods/) and [init containers](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/).

### Pod affinity

This chart allows you to set your custom affinity using the `affinity` parameter. Find more information about Pod affinity in the [kubernetes documentation](https://kubernetes.io/docs/concepts/configuration/assign-pod-node/#affinity-and-anti-affinity).

As an alternative, use one of the preset configurations for pod affinity, pod anti-affinity, and node affinity available at the [bitnami/common](https://github.com/bitnami/charts/tree/main/bitnami/common#affinities) chart. To do so, set the `podAffinityPreset`, `podAntiAffinityPreset`, or `nodeAffinityPreset` parameters.

### Prometheus metrics

This chart can be integrated with Prometheus by setting `metrics.enabled` to `true`. The Gateway service exposes metrics on port 9090 that can be scraped by Prometheus. It will have the necessary annotations to be automatically scraped by Prometheus.

#### Prometheus requirements

It is necessary to have a working installation of Prometheus or Prometheus Operator for the integration to work. Install the [Bitnami Prometheus helm chart](https://github.com/bitnami/charts/tree/main/bitnami/prometheus) or the [Bitnami Kube Prometheus helm chart](https://github.com/bitnami/charts/tree/main/bitnami/kube-prometheus) to easily have a working Prometheus in your cluster.

#### Integration with Prometheus Operator

The chart can deploy `ServiceMonitor` objects for integration with Prometheus Operator installations. To do so, set the value `metrics.serviceMonitor.enabled=true`. Ensure that the Prometheus Operator `CustomResourceDefinitions` are installed in the cluster or it will fail with the following error:

```text
no matches for kind "ServiceMonitor" in version "monitoring.coreos.com/v1"
```

Install the [Bitnami Kube Prometheus helm chart](https://github.com/bitnami/charts/tree/main/bitnami/kube-prometheus) for having the necessary CRDs and the Prometheus Operator.

### Backup and restore

To back up and restore Helm chart deployments on Kubernetes, you need to back up the persistent volumes from the source deployment and attach them to a new deployment using [Velero](https://velero.io/), a Kubernetes backup/restore tool. Find the instructions for using Velero in [this guide](https://techdocs.broadcom.com/us/en/vmware-tanzu/application-catalog/tanzu-application-catalog/services/tac-doc/apps-tutorials-backup-restore-deployments-velero-index.html).

## Persistence

The [Beta9](https://github.com/beam-cloud/beta9) deployment stores data at the `/data` path of the container. Persistent Volume Claims are used to keep the data across deployments.

If you encounter errors when working with persistent volumes, refer to our [troubleshooting guide for persistent volumes](https://docs.bitnami.com/kubernetes/faq/troubleshooting/troubleshooting-persistence-volumes/).

## Parameters

See <https://github.com/bitnami/readme-generator-for-helm> to create the table

The above parameters map to the env variables defined in [Beta9](https://github.com/beam-cloud/beta9). For more information please refer to the [Beta9](https://github.com/beam-cloud/beta9) documentation.

Specify each parameter using the `--set key=value[,key=value]` argument to `helm install`. For example,

```console
helm install my-release \
  --set gateway.image.tag=latest \
  --set postgresql.auth.password=secretpassword \
    oci://REGISTRY_NAME/REPOSITORY_NAME/beta9
```

> Note: You need to substitute the placeholders `REGISTRY_NAME` and `REPOSITORY_NAME` with a reference to your Helm chart registry and repository.

The above command sets the Beta9 Gateway image tag to `latest` and the PostgreSQL password to `secretpassword`.

> NOTE: Once this chart is deployed, it is not possible to change the application's access credentials, such as usernames or passwords, using Helm. To change these application credentials after deployment, delete any persistent volumes (PVs) used by the chart and re-deploy it, or use the application's built-in administrative tools if available.

Alternatively, a YAML file that specifies the values for the above parameters can be provided while installing the chart. For example,

```console
helm install my-release -f values.yaml oci://REGISTRY_NAME/REPOSITORY_NAME/beta9
```

> Note: You need to substitute the placeholders `REGISTRY_NAME` and `REPOSITORY_NAME` with a reference to your Helm chart registry and repository.
> **Tip**: You can use the default [values.yaml](https://github.com/beam-cloud/beta9/blob/main/deploy/charts/beta9/values.yaml)

