# =============================================================
# DR-REGION.TF
# =============================================================
# This file builds your WARM STANDBY in Ireland
# Notice every resource has: provider = aws.dr
# This tells Terraform — build this in Ireland not Cape Town
#
# Key difference from main-region.tf:
# - Smaller instance sizes (scaled DOWN but fully functional)
# - Minimum 1 instance only (not 2)
# - Same structure — web tier, app tier, networking all present
# =============================================================

# =============================================================
# NETWORKING — VPC in Ireland
# =============================================================

resource "aws_vpc" "dr" {
  provider             = aws.dr    # BUILD THIS IN IRELAND
  cidr_block           = "10.1.0.0/16"
  # Different CIDR from main (10.0.0.0/16)
  # They must be different if you ever connect them via VPC Peering

  enable_dns_hostnames = true

  tags = {
    Name        = "${var.app_name}-dr-vpc"
    Environment = var.environment
    Purpose     = "disaster-recovery"
  }
}

resource "aws_subnet" "dr_public_1" {
  provider          = aws.dr
  vpc_id            = aws_vpc.dr.id
  cidr_block        = "10.1.1.0/24"
  availability_zone = "eu-west-1a"    # Ireland AZ 1
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.app_name}-dr-public-1"
    Tier = "web"
  }
}

resource "aws_subnet" "dr_public_2" {
  provider          = aws.dr
  vpc_id            = aws_vpc.dr.id
  cidr_block        = "10.1.2.0/24"
  availability_zone = "eu-west-1b"    # Ireland AZ 2
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.app_name}-dr-public-2"
    Tier = "web"
  }
}

resource "aws_subnet" "dr_private_1" {
  provider          = aws.dr
  vpc_id            = aws_vpc.dr.id
  cidr_block        = "10.1.3.0/24"
  availability_zone = "eu-west-1a"

  tags = {
    Name = "${var.app_name}-dr-private-1"
    Tier = "app-and-database"
  }
}

resource "aws_subnet" "dr_private_2" {
  provider          = aws.dr
  vpc_id            = aws_vpc.dr.id
  cidr_block        = "10.1.4.0/24"
  availability_zone = "eu-west-1b"

  tags = {
    Name = "${var.app_name}-dr-private-2"
    Tier = "app-and-database"
  }
}

resource "aws_internet_gateway" "dr" {
  provider = aws.dr
  vpc_id   = aws_vpc.dr.id

  tags = {
    Name = "${var.app_name}-dr-igw"
  }
}

resource "aws_route_table" "dr_public" {
  provider = aws.dr
  vpc_id   = aws_vpc.dr.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.dr.id
  }

  tags = {
    Name = "${var.app_name}-dr-public-rt"
  }
}

resource "aws_route_table_association" "dr_public_1" {
  provider       = aws.dr
  subnet_id      = aws_subnet.dr_public_1.id
  route_table_id = aws_route_table.dr_public.id
}

resource "aws_route_table_association" "dr_public_2" {
  provider       = aws.dr
  subnet_id      = aws_subnet.dr_public_2.id
  route_table_id = aws_route_table.dr_public.id
}

# =============================================================
# SECURITY GROUPS — Ireland
# =============================================================

resource "aws_security_group" "dr_alb" {
  provider    = aws.dr
  name        = "${var.app_name}-dr-alb-sg"
  description = "Security group for DR region load balancer"
  vpc_id      = aws_vpc.dr.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.app_name}-dr-alb-sg"
  }
}

resource "aws_security_group" "dr_ec2" {
  provider    = aws.dr
  name        = "${var.app_name}-dr-ec2-sg"
  description = "Security group for DR region EC2 instances"
  vpc_id      = aws_vpc.dr.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.dr_alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.app_name}-dr-ec2-sg"
  }
}

# =============================================================
# LOAD BALANCER — Ireland
# =============================================================
# Same structure as main region
# But this one sits in Ireland ready for when disaster hits

resource "aws_lb" "dr" {
  provider           = aws.dr
  name               = "${var.app_name}-dr-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.dr_alb.id]

  subnets = [
    aws_subnet.dr_public_1.id,
    aws_subnet.dr_public_2.id
  ]

  tags = {
    Name    = "${var.app_name}-dr-alb"
    Purpose = "disaster-recovery"
  }
}

resource "aws_lb_target_group" "dr" {
  provider = aws.dr
  name     = "${var.app_name}-dr-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.dr.id

  health_check {
    enabled             = true
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = {
    Name = "${var.app_name}-dr-tg"
  }
}

resource "aws_lb_listener" "dr" {
  provider          = aws.dr
  load_balancer_arn = aws_lb.dr.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dr.arn
  }
}

# =============================================================
# AUTO SCALING GROUP — Ireland (Warm Standby)
# =============================================================
# THIS IS THE KEY DIFFERENCE FROM MAIN REGION
#
# Main region:   min=2  max=10  instance=m5.large
# DR region:     min=1  max=10  instance=t3.small
#
# DR is SCALED DOWN but fully functional
# When disaster hits — min scales up to match production
# max stays the same so it CAN handle full traffic

resource "aws_launch_template" "dr" {
  provider      = aws.dr
  name_prefix   = "${var.app_name}-dr-"
  image_id      = var.dr_ami_id           # Ireland AMI ID
  instance_type = var.dr_instance_type    # t3.small — smaller than main

  user_data = base64encode(<<-EOF
    #!/bin/bash
    # Same startup script as main region
    # Same application fetched from same GitHub repo
    # This ensures DR environment runs IDENTICAL application
    yum update -y
    yum install -y httpd
    yum install -y git

    # Fetch SAME application code from GitHub
    git clone https://github.com/sabc-news/website.git /var/www/html/

    yum install -y aws-cli
    systemctl start httpd
    systemctl enable httpd
    echo "healthy" > /var/www/html/health
  EOF
  )

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.dr_ec2.id]
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.app_name}-dr-ec2"
      Environment = var.environment
      Purpose     = "warm-standby"
    }
  }
}

resource "aws_autoscaling_group" "dr" {
  provider            = aws.dr
  name                = "${var.app_name}-dr-asg"
  min_size            = var.dr_min_instances    # Only 1 instance normally
  max_size            = var.dr_max_instances    # Can scale to 10 if needed
  desired_capacity    = var.dr_min_instances    # Start with 1

  vpc_zone_identifier = [
    aws_subnet.dr_public_1.id,
    aws_subnet.dr_public_2.id
  ]

  target_group_arns         = [aws_lb_target_group.dr.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.dr.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.app_name}-dr-asg-instance"
    propagate_at_launch = true
  }
}

# Scale up policy for DR
# When disaster hits and traffic floods DR region
# This policy scales up automatically
resource "aws_autoscaling_policy" "dr_scale_up" {
  provider               = aws.dr
  name                   = "${var.app_name}-dr-scale-up"
  autoscaling_group_name = aws_autoscaling_group.dr.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 3      # Add 3 instances at a time during disaster
  cooldown               = 120    # Shorter cooldown — disaster needs fast scaling
}
