#!/bin/bash
echo ECS_CLUSTER=${ecs_cluster_name} > /etc/ecs/ecs.config
%{ if ecs_custom_attrs_json != "{}" ~}
echo 'ECS_INSTANCE_ATTRIBUTES=${ecs_custom_attrs_json}' >> /etc/ecs/ecs.config
%{ endif ~}
