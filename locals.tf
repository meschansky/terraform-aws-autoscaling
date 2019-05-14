locals {
  tags_asg_format             = [null_resource.tags_as_list_of_maps.*.triggers]
  name_prefix                 = coalesce(var.lc_name, var.name)
  create_ecs_instance_profile = var.ecs_cluster_name != "" && var.iam_instance_profile == "" ? "1" : "0"
  iam_instance_profile = local.create_ecs_instance_profile ? element(
    concat(aws_iam_instance_profile.ecs_instance_profile.*.name, [""]),
    0,
  ) : var.iam_instance_profile
  ecs_user_data = data.template_file.ecs_user_data.rendered
  user_data     = var.ecs_cluster_name != "" ? join("\n", [local.ecs_user_data, var.user_data]) : var.user_data
  image_id      = var.ecs_cluster_name != "" && var.image_id == "" ? data.aws_ami.ecs.image_id : var.image_id
}

resource "null_resource" "tags_as_list_of_maps" {
  count = length(keys(var.tags_as_map))

  triggers = {
    "key"                 = element(keys(var.tags_as_map), count.index)
    "value"               = element(values(var.tags_as_map), count.index)
    "propagate_at_launch" = "true"
  }
}

resource "null_resource" "ecs_user_data_rendered" {
  triggers = {
    json = data.template_file.ecs_user_data.rendered
  }
}

