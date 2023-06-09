provider "aws" {
  region = "us-east-1"
}

data "aws_availability_zones" "working" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_ami" "latest_amazon_linux" {
  owners      = ["137112412989"]
  most_recent = true
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}
data "aws_vpc" "default" {
  filter {
    name   = "tag:Name"
    values = ["3-tier-vpc"]
  }
}

data "aws_subnet" "subnet1" {
  filter {
    name   = "tag:Name"
    values = ["subnet1"]
  }
}

data "aws_subnet" "subnet2" {
  filter {
    name   = "tag:Name"
    values = ["subnet2"]
  }
}

################################################################################################################

# Instance Creation

# resource "aws_instance" "my_ubuntu" {
#   ami                    = "ami-03c7d01cf4dedc891"
#   instance_type          = "t2.micro"
#   key_name               = "test-key"
#   vpc_security_group_ids = [aws_security_group.web.id]
#   user_data              = file("user_data.sh")

#   tags = {
#     Name    = "test server-2"
#     Owner   = "Mobi"
#     project = "Phoenix"
#   }
# }

################################################################################################################

# Security Group Creation

resource "aws_security_group" "web" {
  name        = "WebServer-SG-1"
  description = "Security Group for my WebServer"
  vpc_id      = data.aws_vpc.default.id # This need to be added since AWS Provider v4.29+ to set VPC id

  ingress {
    description = "Allow port HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow port HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  ingress {
    description = "Allow port SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow ALL ports"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }


  tags = {
    Name  = "WebServer SG by Terraform"
    Owner = "Mobi"
  }
}

################################################################################################################

#VPC Section


data "aws_vpcs" "vpcs" {}

data "aws_vpc" "test" {
  tags = {
    Name = "3-tier-vpc"
  }
}

# resource "aws_subnet" "subnet1" {
#   vpc_id            = data.aws_vpc.test.id
#   availability_zone = data.aws_availability_zones.working.names[0]
#   cidr_block        = "10.0.0.192/26"

#   tags = {
#     Name = "NewSubnet"
#     Info = "AZ: ${data.aws_availability_zones.working.names[0]} in Region: ${data.aws_region.current.description}"
#   }
# }

################################################################################################################

#ASG Creation

# data "aws_subnet" "subnet1" {
#   filter {
#     name = "tag:Name"
#     values = ["NewSubnet"]
#   }
# }

resource "aws_launch_template" "web" {
  name                   = "WebServer-Highly-Available-LT"
  image_id               = data.aws_ami.latest_amazon_linux.id
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.web.id]
  user_data              = filebase64("user_data.sh")
}

resource "aws_autoscaling_group" "web" {
  name             = "WebServer-Highly-Available-ASG-Ver-${aws_launch_template.web.latest_version}"
  min_size         = 2
  max_size         = 4
  desired_capacity = 3
  # min_elb_capacity    = 2
  health_check_type         = "EC2"
  wait_for_capacity_timeout = 0
  health_check_grace_period = 300
  vpc_zone_identifier       = [data.aws_subnet.subnet1.id, data.aws_subnet.subnet2.id]
  target_group_arns         = [aws_lb_target_group.web.arn]

  launch_template {
    id      = aws_launch_template.web.id
    version = aws_launch_template.web.latest_version
  }

  dynamic "tag" {
    for_each = {
      Name   = "WebServer in ASG"
      TAGKEY = "TAGVALUE"
    }
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
  lifecycle {
    create_before_destroy = true
  }
}

################################################################################################################

#Load Balancer Creation

resource "aws_lb" "web" {
  name               = "WebServer-HighlyAvailable-ALB"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web.id]
  subnets            = [data.aws_subnet.subnet1.id, data.aws_subnet.subnet2.id]
}

resource "aws_lb_target_group" "web" {
  name                 = "WebServer-HighlyAvailable-TG"
  vpc_id               = data.aws_vpc.default.id
  port                 = 80
  protocol             = "HTTP"
  deregistration_delay = 10 # seconds
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

#-------------------------------------------------------------------------------
output "web_loadbalancer_url" {
  value = aws_lb.web.dns_name
}