# 🚀 AKS + ArgoCD + Helm + GitHub + ApplicationSets: Full Solution

This guide will help you provision an AKS cluster, install ArgoCD, connect it to your GitHub repo, and deploy a sample Helm app using ApplicationSets. All steps are copy-paste ready!

---

## 1️⃣ Terraform: Provision AKS & Install ArgoCD

Create a file named `main.tf` in your project root with the following content:

```hcl
provider "azurerm" {
  features {}
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

variable "resource_group" { default = "tql-aks-rg" }
variable "location" { default = "eastus" }
variable "aks_name" { default = "tql-aks" }

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group
  location = var.location
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.aks_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "argocdtest"

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_DS2_v2"
  }

  identity {
    type = "SystemAssigned"
  }
}

data "azurerm_kubernetes_cluster" "cluster" {
  name                = azurerm_kubernetes_cluster.aks.name
  resource_group_name = azurerm_kubernetes_cluster.aks.resource_group_name
}

resource "null_resource" "kubeconfig" {
  provisioner "local-exec" {
    command = "az aks get-credentials --resource-group ${azurerm_resource_group.rg.name} --name ${azurerm_kubernetes_cluster.aks.name} --overwrite-existing"
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "5.46.0"
  create_namespace = true
  values = [file("${path.module}/argocd-values.yaml")]
  depends_on = [null_resource.kubeconfig]
}

resource "kubernetes_config_map" "argo_runtime_config" {
  metadata {
    name      = "argo-runtime-config"
    namespace = "default"
  }
  data = {
    client_id    = "1111-aaaa-bbbb-2222"
    vault_name   = "my-test-vault"
    registry_url = "myregistry.azurecr.io"
  }
  depends_on = [helm_release.argocd]
}
```

> **Note:** Create a minimal `argocd-values.yaml` in the same directory (can be empty or use ArgoCD defaults).

---

## 2️⃣ Initialize & Apply Terraform

```sh
# Log in to Azure if not already
az login

# Initialize and apply Terraform
terraform init
terraform apply -auto-approve
```

---

## 3️⃣ Get AKS Credentials (if not done automatically)

```sh
az aks get-credentials --resource-group tql-aks-rg --name tql-aks --overwrite-existing
```

---

## 4️⃣ Access ArgoCD UI

```sh
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

- Open [https://localhost:8080](https://localhost:8080) in your browser.
- Get the ArgoCD admin password:

```sh
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

---

## 5️⃣ Connect ArgoCD to Your GitHub Repo

```sh
argocd repo add https://github.com/01011011/aks-argocd-helm-appset.git \
  --username 01011011 --password <YOUR_GITHUB_PAT>
```

---

## 6️⃣ Sample Helm App Structure

```
apps/
  ├── myapp/
  │   ├── Chart.yaml
  │   ├── templates/
  │   │   └── deployment.yaml
  │   ├── values-dev.yaml
  │   └── values-prod.yaml
  └── appset.yaml
```

- `apps/myapp/Chart.yaml`:

```yaml
apiVersion: v2
name: myapp
description: A sample Helm chart for Kubernetes
version: 0.1.0
appVersion: "1.0.0"
```

- `apps/myapp/templates/deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 1
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
        - name: myapp
          image: nginx:latest
          ports:
            - containerPort: 80
          env:
            - name: CLIENT_ID
              value: {{ (lookup "v1" "ConfigMap" "default" "argo-runtime-config").data.client_id }}
            - name: VAULT_NAME
              value: {{ (lookup "v1" "ConfigMap" "default" "argo-runtime-config").data.vault_name }}
            - name: REGISTRY_URL
              value: {{ (lookup "v1" "ConfigMap" "default" "argo-runtime-config").data.registry_url }}
```

- `apps/myapp/values-dev.yaml`:

```yaml
replicaCount: 1
image:
  repository: nginx
  tag: latest
```

- `apps/myapp/values-prod.yaml`:

```yaml
replicaCount: 2
image:
  repository: nginx
  tag: stable
```

---

## 7️⃣ ApplicationSet Example

- `apps/appset.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: myapps
spec:
  generators:
    - list:
        elements:
          - name: dev
            valuesFile: values-dev.yaml
          - name: prod
            valuesFile: values-prod.yaml
  template:
    metadata:
      name: '{{name}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/01011011/aks-argocd-helm-appset.git
        targetRevision: HEAD
        path: apps/myapp
        helm:
          valueFiles:
            - '{{valuesFile}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: default
      syncPolicy:
        automated:
          selfHeal: true
          prune: true
```

---

## 8️⃣ Deploy & Test

```sh
# Commit and push all files to your GitHub repo
# (Make sure your repo matches the structure above)
git add .
git commit -m "Initial AKS/ArgoCD/Helm sample app setup"
git push origin main
```

- In ArgoCD UI, create an ApplicationSet using `apps/appset.yaml` or let ArgoCD auto-sync.
- Watch your app deploy to AKS!

---

## 9️⃣ Monitor & Manage

- Use the ArgoCD UI to monitor and manage deployments.
- Use `kubectl` to check resources:

```sh
kubectl get pods -A
kubectl get svc -A
```

---

## ℹ️ Notes

- For more details, see comments in the Terraform and YAML files.
- Adjust resource names, locations, and values as needed for your environment.
- For production, review security and scaling settings.
