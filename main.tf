##########
# ECS AMI
##########
data "aws_ami" "ecs" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["amazon"]
}

###################################
# ECS IAM Instance Role and Policy
###################################
resource "aws_iam_role" "ecs_instance_role" {
  count              = local.create_ecs_instance_profile
  name_prefix        = "ec2-role-${local.name_prefix}-"
  assume_role_policy = var.ecs_instance_role_assume_role_policy
}

resource "aws_iam_role_policy" "ecs_instance_role_policy" {
  count       = local.create_ecs_instance_profile
  name_prefix = "ec2-role-policy-${local.name_prefix}-"
  role        = element(concat(aws_iam_role.ecs_instance_role.*.id, [""]), 0)
  policy      = var.ecs_instance_role_policy
}

resource "aws_iam_instance_profile" "ecs_instance_profile" {
  count       = local.create_ecs_instance_profile
  name_prefix = "ec2-profile-${local.name_prefix}-"
  path        = "/"
  role        = element(concat(aws_iam_role.ecs_instance_role.*.name, [""]), 0)
  provisioner "local-exec" {
    command = "sleep 10"
  }
}

#######################
# Launch configuration
#######################
data "template_file" "ecs_user_data" {
  template = file("${path.module}/default-user-data.sh")
  vars = {
    ecs_cluster_name      = var.ecs_cluster_name
    ecs_custom_attrs_json = jsonencode(var.ecs_custom_attrs)
  }
}

resource "aws_launch_configuration" "this" {
  count = var.create_lc ? 1 : 0

  name_prefix                 = "${local.name_prefix}-"
  image_id                    = local.image_id
  instance_type               = var.instance_type
  iam_instance_profile        = local.iam_instance_profile
  key_name                    = var.key_name
  security_groups             = var.security_groups
  associate_public_ip_address = var.associate_public_ip_address
  user_data                   = local.user_data
  enable_monitoring           = var.enable_monitoring
  spot_price                  = var.spot_price
  placement_tenancy           = var.spot_price == "" ? var.placement_tenancy : ""
  ebs_optimized               = var.ebs_optimized
  dynamic "ebs_block_device" {
    for_each = var.ebs_block_device
    content {
      # TF-UPGRADE-TODO: The automatic upgrade tool can't predict
      # which keys might be set in maps assigned here, so it has
      # produced a comprehensive set here. Consider simplifying
      # this after confirming which keys can be set in practice.

      delete_on_termination = lookup(ebs_block_device.value, "delete_on_termination", null)
      device_name           = ebs_block_device.value.device_name
      encrypted             = lookup(ebs_block_device.value, "encrypted", null)
      iops                  = lookup(ebs_block_device.value, "iops", null)
      no_device             = lookup(ebs_block_device.value, "no_device", null)
      snapshot_id           = lookup(ebs_block_device.value, "snapshot_id", null)
      volume_size           = lookup(ebs_block_device.value, "volume_size", null)
      volume_type           = lookup(ebs_block_device.value, "volume_type", null)
    }
  }
  dynamic "ephemeral_block_device" {
    for_each = var.ephemeral_block_device
    content {
      # TF-UPGRADE-TODO: The automatic upgrade tool can't predict
      # which keys might be set in maps assigned here, so it has
      # produced a comprehensive set here. Consider simplifying
      # this after confirming which keys can be set in practice.

      device_name  = ephemeral_block_device.value.device_name
      virtual_name = ephemeral_block_device.value.virtual_name
    }
  }
  dynamic "root_block_device" {
    for_each = var.root_block_device
    content {
      # TF-UPGRADE-TODO: The automatic upgrade tool can't predict
      # which keys might be set in maps assigned here, so it has
      # produced a comprehensive set here. Consider simplifying
      # this after confirming which keys can be set in practice.

      delete_on_termination = lookup(root_block_device.value, "delete_on_termination", null)
      iops                  = lookup(root_block_device.value, "iops", null)
      volume_size           = lookup(root_block_device.value, "volume_size", null)
      volume_type           = lookup(root_block_device.value, "volume_type", null)
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

####################
# Autoscaling group
####################
resource "aws_autoscaling_group" "this" {
  count = var.create_asg && false == var.create_asg_with_initial_lifecycle_hook ? 1 : 0

  name_prefix = "${join(
    "-",
    compact(
      [
        local.name_prefix,
        var.recreate_asg_when_lc_changes ? element(concat(random_pet.asg_name.*.id, [""]), 0) : "",
      ],
    ),
  )}-"
  launch_configuration = var.create_lc ? element(concat(aws_launch_configuration.this.*.name, [""]), 0) : var.launch_configuration
  vpc_zone_identifier  = var.vpc_zone_identifier
  max_size             = var.max_size
  min_size             = var.min_size
  desired_capacity     = var.desired_capacity

  load_balancers            = var.load_balancers
  health_check_grace_period = var.health_check_grace_period
  health_check_type         = var.health_check_type

  min_elb_capacity          = var.min_elb_capacity
  wait_for_elb_capacity     = var.wait_for_elb_capacity ? 1 : 0
  target_group_arns         = var.target_group_arns
  default_cooldown          = var.default_cooldown
  force_delete              = var.force_delete
  termination_policies      = var.termination_policies
  suspended_processes       = var.suspended_processes
  placement_group           = var.placement_group
  enabled_metrics           = var.enabled_metrics
  metrics_granularity       = var.metrics_granularity
  wait_for_capacity_timeout = var.wait_for_capacity_timeout
  protect_from_scale_in     = var.protect_from_scale_in

  # TF-UPGRADE-TODO: In Terraform v0.10 and earlier, it was sometimes necessary to
  # force an interpolation expression to be interpreted as a list by wrapping it
  # in an extra set of list brackets. That form was supported for compatibilty in
  # v0.11, but is no longer supported in Terraform v0.12.
  #
  # If the expression in the following list itself returns a list, remove the
  # brackets to avoid interpretation as a list of lists. If the expression
  # returns a single list item then leave it as-is and remove this TODO comment.
  tags = flatten([
          {
            "key"                 = "Name"
            "value"               = var.name
            "propagate_at_launch" = true
          },
          local.tags_asg_format,
        ]
  )


  lifecycle {
    create_before_destroy = true
  }
}

################################################
# Autoscaling group with initial lifecycle hook
################################################
resource "aws_autoscaling_group" "this_with_initial_lifecycle_hook" {
  count = var.create_asg && var.create_asg_with_initial_lifecycle_hook ? 1 : 0

  name_prefix = "${join(
    "-",
    compact(
      [
        local.name_prefix,
        var.recreate_asg_when_lc_changes ? element(concat(random_pet.asg_name.*.id, [""]), 0) : "",
      ],
    ),
  )}-"
  launch_configuration = var.create_lc ? element(aws_launch_configuration.this.*.name, 0) : var.launch_configuration
  vpc_zone_identifier  = var.vpc_zone_identifier
  max_size             = var.max_size
  min_size             = var.min_size
  desired_capacity     = var.desired_capacity

  load_balancers            = var.load_balancers
  health_check_grace_period = var.health_check_grace_period
  health_check_type         = var.health_check_type

  min_elb_capacity          = var.min_elb_capacity
  wait_for_elb_capacity     = var.wait_for_elb_capacity ? 1 : 0
  target_group_arns         = var.target_group_arns
  default_cooldown          = var.default_cooldown
  force_delete              = var.force_delete
  termination_policies      = var.termination_policies
  suspended_processes       = var.suspended_processes
  placement_group           = var.placement_group
  enabled_metrics           = var.enabled_metrics
  metrics_granularity       = var.metrics_granularity
  wait_for_capacity_timeout = var.wait_for_capacity_timeout
  protect_from_scale_in     = var.protect_from_scale_in

  initial_lifecycle_hook {
    name                    = var.initial_lifecycle_hook_name
    lifecycle_transition    = var.initial_lifecycle_hook_lifecycle_transition
    notification_metadata   = var.initial_lifecycle_hook_notification_metadata
    heartbeat_timeout       = var.initial_lifecycle_hook_heartbeat_timeout
    notification_target_arn = var.initial_lifecycle_hook_notification_target_arn
    role_arn                = var.initial_lifecycle_hook_role_arn
    default_result          = var.initial_lifecycle_hook_default_result
  }

  # TF-UPGRADE-TODO: In Terraform v0.10 and earlier, it was sometimes necessary to
  # force an interpolation expression to be interpreted as a list by wrapping it
  # in an extra set of list brackets. That form was supported for compatibilty in
  # v0.11, but is no longer supported in Terraform v0.12.
  #
  # If the expression in the following list itself returns a list, remove the
  # brackets to avoid interpretation as a list of lists. If the expression
  # returns a single list item then leave it as-is and remove this TODO comment.
  tags = [
    concat(
      [
        {
          "key"                 = "Name"
          "value"               = var.name
          "propagate_at_launch" = true
        },
      ],
      var.tags,
      local.tags_asg_format,
    ),
  ]

  lifecycle {
    create_before_destroy = true
  }
}

resource "random_pet" "asg_name" {
  count = var.recreate_asg_when_lc_changes ? 1 : 0

  separator = "-"
  length    = 2

  keepers = {
    # Generate a new pet name each time we switch launch configuration
    lc_name = var.create_lc ? element(concat(aws_launch_configuration.this.*.name, [""]), 0) : var.launch_configuration
  }
}

