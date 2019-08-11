locals {

  envvars_as_list_of_maps = flatten([
     for key in keys(var.container_envvars) : {
       name   = key
       value = var.container_envvars[key]
   }])

  secrets_as_list_of_maps = flatten([
     for key in keys(var.container_secrets) : {
       name   = key
       valueFrom = var.container_secrets[key]
   }])
}


locals {
  port_mappings = {
    with_port = [
      {
        containerPort = "${var.container_port}"
        hostPort      = "${var.host_port}"
        protocol      = "${var.protocol}"
      },
    ]

    without_port = []
  }

  use_port = "${var.container_port == "" ? "without_port" : "with_port" }"

  container_definitions = [{
    name                   = "${var.container_name}"
    image                  = "${var.container_image}"
    memory                 = "${var.container_memory}"
    memoryReservation      = "${var.container_memory_reservation}"
    cpu                    = "${var.container_cpu}"
    essential              = "${var.essential}"
    entryPoint             = "${var.entrypoint}"
    command                = "${var.container_command}"
    workingDirectory       = "${var.working_directory}"
    readonlyRootFilesystem = "${var.readonly_root_filesystem}"
    dockerLabels           = "${local.docker_labels}"

    privileged = "${var.privileged}"

    hostname     = "${var.hostname}"
    environment  = local.envvars_as_list_of_maps
    secrets      = secrets_as_list_of_maps
    mountPoints  = ["${var.mountpoints}"]
    portMappings = "${local.port_mappings[local.use_port]}"
    healthCheck  = "${var.healthcheck}"

    logConfiguration = {
      logDriver = "${var.log_driver}"
      options   = "${var.log_options}"
    }
  }]
}
