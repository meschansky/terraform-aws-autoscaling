locals {
  tags_asg_format = ["${null_resource.tags_as_list_of_maps.*.triggers}"]
  name_prefix = "${coalesce(var.lc_name, var.name)}"
  create_ecs_instance_profile = "${var.ecs_cluster_name != "" && var.iam_instance_profile == "" ? "1" : "0"}"
  iam_instance_profile = "${local.create_ecs_instance_profile ? element(concat(aws_iam_instance_profile.ecs_instance_profile.*.name, list("")), 0) : var.iam_instance_profile}"
  ecs_user_data = "#!/bin/bash\necho \"ECS_CLUSTER=${var.ecs_cluster_name}\" > /etc/ecs/ecs.config"
  user_data = "${var.ecs_cluster_name != "" ? join("\n", list(local.ecs_user_data, var.user_data)) : var.user_data}"
}

resource "null_resource" "tags_as_list_of_maps" {
  count = "${length(keys(var.tags_as_map))}"

  triggers = "${map(
    "key", "${element(keys(var.tags_as_map), count.index)}",
    "value", "${element(values(var.tags_as_map), count.index)}",
    "propagate_at_launch", "true"
  )}"
}
