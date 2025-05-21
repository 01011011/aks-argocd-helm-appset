provider "azurerm" {
  features {}
  subscription_id = "e930349d-9137-4a7f-af1c-d1cb2221555b"
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
variable "location" { default = "westus" }
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
    vm_size    = "Standard_D2ads_v6"
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
  version    = "5.52.0"
  create_namespace = true
  values = [file("${path.module}/argocd-values.yaml")]
  depends_on = [null_resource.kubeconfig]
}

resource "random_integer" "suffix" {
  min = 10000
  max = 99999
}

resource "azurerm_container_registry" "acr" {
  name                = "tqlacr${random_integer.suffix.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = false
}

resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
}

resource "kubernetes_config_map" "argo_runtime_config" {
  metadata {
    name      = "argo-runtime-config"
    namespace = "default"
  }
  data = {
    client_id    = "1111-aaaa-bbbb-2222"
    vault_name   = "my-test-vault"
    registry_url = azurerm_container_registry.acr.login_server
  }
  depends_on = [helm_release.argocd]
}
