provider "helm" {
  version = ">= 1.1.1"
  kubernetes {
    config_path = var.cluster_config_file
  }
}

locals {
  tmp_dir                = "${path.cwd}/.tmp"
  gitops_dir             = var.gitops_dir != "" ? var.gitops_dir : "${path.cwd}/gitops"
  chart_name             = "service-mesh"
  chart_dir              = "${local.gitops_dir}/${local.chart_name}"
  global_config          = {
    clusterType = var.cluster_type
    olmNamespace = var.olm_namespace
    operatorNamespace = var.operator_namespace
  }
  elasticsearch_config = {
    createInstance = false
  }
  jaeger_config = {
    createInstance = false
  }
  kiali_config = {
    createInstance = false
  }
  service_mesh_config = {
    createInstance = true
  }
}

resource "null_resource" "setup-chart" {
  provisioner "local-exec" {
    command = "mkdir -p ${local.chart_dir} && cp -R ${path.module}/chart/${local.chart_name}/* ${local.chart_dir} && echo ${var.cluster_config_file}"
  }
}

resource "null_resource" "delete-consolelink" {
  count = var.cluster_type == "ocp4" ? 1 : 0

  provisioner "local-exec" {
    command = "kubectl delete consolelink -l grouping=garage-cloud-native-toolkit -l app=${var.name} || exit 0"

    environment = {
      KUBECONFIG = var.cluster_config_file
    }
  }
}

resource "local_file" "service-mesh-values" {
  depends_on = [null_resource.setup-chart, null_resource.delete-consolelink]

  content  = yamlencode({
    global = local.global_config
    elasticsearch-operator = local.elasticsearch_config
    jaeger-operator = local.jaeger_config
    kiali-operator = local.kiali_config
    service-mesh-operator = local.service_mesh_config
  })
  filename = "${local.chart_dir}/values.yaml"
}

resource "null_resource" "print-values" {
  provisioner "local-exec" {
    command = "cat ${local_file.service-mesh-values.filename}"
  }
}

resource "helm_release" "service-mesh" {
  depends_on = [local_file.service-mesh-values]
  count = var.mode != "setup" ? 1 : 0

  name              = var.name
  chart             = local.chart_dir
  namespace         = var.operator_namespace
  timeout           = 1200
  dependency_update = true
  force_update      = true
  replace           = true

  disable_openapi_validation = true
}
