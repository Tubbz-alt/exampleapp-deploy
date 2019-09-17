variable "app_identifier" {}
variable "ecs_cluster_id" {}
variable "ecs_cluster_name" {}
variable "ecs_service_name" {}
variable "ecs_task_execution_role_arn" {}
variable "vpc_id" {}
variable "public_subnet_ids" {}
variable "private_subnet_ids" {}
variable "alb_external_port" {}
variable "container_name" {}
variable "container_port" {}
variable "container_definitions" {}
variable "task_cpu" {
  default = "256"
}
variable "task_memory" {
  default = "0.5GB"
}
variable "health_check_path" {
  default = "/"
}
variable "autoscale_min_capacity" {
  default = 1
}
variable "autoscale_max_capacity" {
  default = 6
}
variable "tags" {
  type = map
}

# Security groups to limit access to our ALB and ECS tasks
# ALB Security Group: Edit this to restrict access to the application
resource "aws_security_group" "alb" {
  name        = "${var.app_identifier}-alb-security-group"
  description = "controls access to the ALB"
  vpc_id      = var.vpc_id

  ingress {
    protocol    = "tcp"
    from_port   = var.alb_external_port
    to_port     = var.alb_external_port
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

# Traffic to the ECS cluster should only come from the ALB
resource "aws_security_group" "ecs_tasks" {
  name        = "${var.app_identifier}-ecs-tasks-security-group"
  description = "allow inbound access from the ALB only"
  vpc_id      = var.vpc_id

  ingress {
    protocol        = "tcp"
    from_port       = var.container_port
    to_port         = var.container_port
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}


# Now the ALB to balance traffic between instances of our app
resource "aws_alb" "main" {
  name            = "${var.app_identifier}-alb"
  subnets         = var.public_subnet_ids
  security_groups = [aws_security_group.alb.id]
  tags            = var.tags
}

resource "aws_alb_target_group" "app" {
  name        = "${var.app_identifier}-alb-target-group"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    healthy_threshold   = "3"
    interval            = "30"
    protocol            = "HTTP"
    matcher             = "200"
    timeout             = "3"
    path                = var.health_check_path
    unhealthy_threshold = "2"
  }
}

# Redirect all traffic from the ALB to the target group
resource "aws_alb_listener" "front_end" {
  load_balancer_arn = aws_alb.main.id
  port              = var.alb_external_port
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_alb_target_group.app.id
    type             = "forward"
  }
}


# autoscaling policies etc to make sure sufficient instances of the task
# are running
resource "aws_appautoscaling_target" "target" {
  service_namespace  = "ecs"
  resource_id        = "service/${var.ecs_cluster_name}/${aws_ecs_service.thisapp_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  #role_arn           = "${aws_iam_role.ecs_autoscale_role.arn}"
  min_capacity = var.autoscale_min_capacity
  max_capacity = var.autoscale_max_capacity
}

# Automatically scale capacity up by one
resource "aws_appautoscaling_policy" "up" {
  name               = "cb_scale_up"
  service_namespace  = "ecs"
  resource_id        = "service/${var.ecs_cluster_name}/${aws_ecs_service.thisapp_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = 1
    }
  }

  depends_on = ["aws_appautoscaling_target.target"]
}

# Automatically scale capacity down by one
resource "aws_appautoscaling_policy" "down" {
  name               = "cb_scale_down"
  service_namespace  = "ecs"
  resource_id        = "service/${var.ecs_cluster_name}/${aws_ecs_service.thisapp_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = -1
    }
  }

  depends_on = ["aws_appautoscaling_target.target"]
}

# Cloudwatch alarm that triggers the autoscaling up policy
resource "aws_cloudwatch_metric_alarm" "service_cpu_high" {
  alarm_name          = "cb_cpu_utilization_high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = "85"

  dimensions = {
    ClusterName = "${var.ecs_cluster_name}"
    ServiceName = "${aws_ecs_service.thisapp_service.name}"
  }

  alarm_actions = ["${aws_appautoscaling_policy.up.arn}"]
}

# Cloudwatch alarm that triggers the autoscaling down policy
resource "aws_cloudwatch_metric_alarm" "service_cpu_low" {
  alarm_name          = "cb_cpu_utilization_low"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = "10"

  dimensions = {
    ClusterName = "${var.ecs_cluster_name}"
    ServiceName = "${aws_ecs_service.thisapp_service.name}"
  }

  alarm_actions = ["${aws_appautoscaling_policy.down.arn}"]
}


# finally, the ECS definitions
# the cluster ID must be passed in from the calling code

resource "aws_ecs_task_definition" "thisapp_task" {

  family                   = var.app_identifier
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = var.ecs_task_execution_role_arn
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  container_definitions    = var.container_definitions
}

resource "aws_ecs_service" "thisapp_service" {
  depends_on = [
    aws_alb_listener.front_end
  ]
  launch_type     = "FARGATE"
  name            = var.ecs_service_name
  cluster         = var.ecs_cluster_id
  desired_count   = 1
  task_definition = aws_ecs_task_definition.thisapp_task.arn
  tags            = var.tags

  network_configuration {
    security_groups = [aws_security_group.ecs_tasks.id]
    subnets         = var.private_subnet_ids
  }

  load_balancer {
    target_group_arn = aws_alb_target_group.app.id
    container_name   = var.container_name
    container_port   = var.container_port
  }
}

output "alb_dns_name" {
  value = aws_alb.main.dns_name
}

output "aws_ecs_service_id" {
  value = aws_ecs_service.thisapp_service.id
}

output "ecs_tasks_sg_id" {
  value = aws_security_group.ecs_tasks.id
}
