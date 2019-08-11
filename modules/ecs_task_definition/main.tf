resource "aws_ecs_task_definition" "this" {
  count = var.create ? 1 : 0

  family        = "${var.name}"
  task_role_arn = "${var.ecs_taskrole_arn}"

  # Execution role ARN can be needed inside FARGATE
  execution_role_arn = "${var.ecs_task_execution_role_arn}"

  # Used for Fargate
  cpu    = "${var.cpu}"
  memory = "${var.memory}"

  dynamic volume {
    for_each = var.host_path_volumes
    content {
      name = lookup(var.docker_volume, "name", "")
      docker_volume_configuration {
        autoprovision = lookup(var.docker_volume, "autoprovision", false)
        scope         = lookup(var.docker_volume, "scope", "shared")
        driver        = lookup(var.docker_volume, "driver", "")
        driver_opts   = lookup(var.docker_volume, "driver_opts", "")
      }
    }
  }

  container_definitions = "${var.container_definitions}"

  requires_compatibilities = ["${var.launch_type}"]
}
