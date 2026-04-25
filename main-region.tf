# =============================================================
# MAIN-REGION.TF
# =============================================================
# This file builds your MAIN production environment in Cape Town
# This is where your business runs every day
# Web tier + App tier + Networking
# =============================================================

# =============================================================
# NETWORKING — VPC
# =============================================================
# VPC = Virtual Private Cloud
# Think of it like building a fence around your AWS resources
# Your EC2 and RDS live INSIDE this fence
# Only traffic you allow can get in or out

resource "aws_vpc" "main" {
  # No provider needed here — defaults to main region (Cape Town)
  cidr_block           = "10.0.0.0/16"
  # cidr_block is your IP address range for everything inside this VPC
  # 10.0.0.0/16 means you have 65,536 IP addresses available
  # From your CCNA — you know this is a private IP range

  enable_dns_hostnames = true
  # This lets your resources have DNS names like
  # ec2-10-0-1-5.af-south-1.compute.internal

  tags = {
    Name        = "${var.app_name}-main-vpc"
    Environment = var.environment
    # var.app_name pulls the value from variables.tf
    # So this becomes "sabc-news-main-vpc"
  }
}

# PUBLIC SUBNET — Web Tier
# This subnet is accessible from the internet
# Your load balancer and web servers live here
resource "aws_subnet" "main_public_1" {
  vpc_id            = aws_vpc.main.id
  # This subnet belongs to the VPC we just created above
  # See how we reference it — aws_vpc.main.id

  cidr_block        = "10.0.1.0/24"
  # This subnet gets IP addresses from 10.0.1.0 to 10.0.1.255
  # 256 IP addresses for this subnet

  availability_zone = "af-south-1a"
  # This subnet lives in AZ 1 of Cape Town
  # From your learning — AZ = separate data center building

  map_public_ip_on_launch = true
  # Any EC2 launched here gets a public IP automatically

  tags = {
    Name = "${var.app_name}-main-public-1"
    Tier = "web"
  }
}

# Second public subnet in different AZ — for high availability
# Multi AZ = two subnets in two different buildings
# If one building loses power — other subnet still running
resource "aws_subnet" "main_public_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "af-south-1b"   # Different AZ from subnet 1
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.app_name}-main-public-2"
    Tier = "web"
  }
}

# PRIVATE SUBNET — App Tier and Database Tier
# These subnets are NOT accessible from internet
# Only your web tier can talk to app tier
# Only your app tier can talk to database tier
resource "aws_subnet" "main_private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "af-south-1a"

  tags = {
    Name = "${var.app_name}-main-private-1"
    Tier = "app-and-database"
  }
}

resource "aws_subnet" "main_private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "af-south-1b"

  tags = {
    Name = "${var.app_name}-main-private-2"
    Tier = "app-and-database"
  }
}

# INTERNET GATEWAY
# This is the door between your VPC and the internet
# Without this — nothing in your VPC can reach the internet
# Think of it like the router connecting your office to the internet
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.app_name}-main-igw"
  }
}

# ROUTE TABLE
# Tells traffic where to go
# From your CCNA — this is like a routing table on a router
# This rule says: any traffic going to 0.0.0.0/0 (internet)
# send it through the internet gateway
resource "aws_route_table" "main_public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"          # All internet traffic
    gateway_id = aws_internet_gateway.main.id   # Goes through IGW
  }

  tags = {
    Name = "${var.app_name}-main-public-rt"
  }
}

# Associate route table with public subnets
# This connects the routing rules to the subnets
resource "aws_route_table_association" "main_public_1" {
  subnet_id      = aws_subnet.main_public_1.id
  route_table_id = aws_route_table.main_public.id
}

resource "aws_route_table_association" "main_public_2" {
  subnet_id      = aws_subnet.main_public_2.id
  route_table_id = aws_route_table.main_public.id
}

# =============================================================
# SECURITY GROUPS
# =============================================================
# Security groups are like firewalls for your resources
# They control what traffic is allowed IN and OUT
# From your networking background — like ACLs on a switch

# Security group for the Load Balancer
# Only allows HTTP and HTTPS from internet
resource "aws_security_group" "main_alb" {
  name        = "${var.app_name}-main-alb-sg"
  description = "Security group for main region load balancer"
  vpc_id      = aws_vpc.main.id

  # INBOUND RULES — what traffic is allowed IN
  ingress {
    from_port   = 80      # HTTP port
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]   # From anywhere on internet
    description = "Allow HTTP from internet"
  }

  ingress {
    from_port   = 443     # HTTPS port
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]   # From anywhere on internet
    description = "Allow HTTPS from internet"
  }

  # OUTBOUND RULES — what traffic is allowed OUT
  egress {
    from_port   = 0       # All ports
    to_port     = 0
    protocol    = "-1"    # All protocols
    cidr_blocks = ["0.0.0.0/0"]   # To anywhere
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${var.app_name}-main-alb-sg"
  }
}

# Security group for EC2 instances
# Only allows traffic FROM the load balancer — not directly from internet
# This is the security layer — internet hits load balancer first
# Load balancer then talks to EC2
resource "aws_security_group" "main_ec2" {
  name        = "${var.app_name}-main-ec2-sg"
  description = "Security group for main region EC2 instances"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.main_alb.id]
    # Only allow traffic FROM the ALB security group
    # Not from internet directly
    description     = "Allow HTTP only from load balancer"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.app_name}-main-ec2-sg"
  }
}

# =============================================================
# LOAD BALANCER
# =============================================================
# ALB = Application Load Balancer
# Receives all traffic from internet
# Spreads it across multiple EC2 instances
# If one EC2 is unhealthy — stops sending traffic to it

resource "aws_lb" "main" {
  name               = "${var.app_name}-main-alb"
  internal           = false        # false = public facing internet
  load_balancer_type = "application"
  security_groups    = [aws_security_group.main_alb.id]

  subnets = [
    aws_subnet.main_public_1.id,
    aws_subnet.main_public_2.id
    # Load balancer spans BOTH public subnets
    # This is Multi AZ for the load balancer itself
  ]

  tags = {
    Name = "${var.app_name}-main-alb"
  }
}

# TARGET GROUP
# The load balancer needs to know WHERE to send traffic
# Target group defines the destination — your EC2 instances
# It also does health checks — is each EC2 healthy?
resource "aws_lb_target_group" "main" {
  name     = "${var.app_name}-main-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    path                = "/health"
    # Load balancer calls /health on each EC2 every 30 seconds
    # EC2 must respond with HTTP 200 to be considered healthy
    healthy_threshold   = 2     # 2 successful checks = healthy
    unhealthy_threshold = 3     # 3 failed checks = unhealthy
    interval            = 30    # Check every 30 seconds
  }

  tags = {
    Name = "${var.app_name}-main-tg"
  }
}

# LISTENER
# Tells the load balancer — when traffic comes in on port 80
# forward it to the target group
resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}

# =============================================================
# AUTO SCALING GROUP — MAIN REGION
# =============================================================
# Launch Template — the blueprint for each EC2 instance
# When Auto Scaling needs to add a new instance
# it uses this template to know how to build it

resource "aws_launch_template" "main" {
  name_prefix   = "${var.app_name}-main-"
  image_id      = var.main_ami_id        # Which AMI to use
  instance_type = var.main_instance_type # What size instance

  # User data — the startup script
  # Remember our early discussion about user data?
  # This runs on first boot and fetches the application code
  user_data = base64encode(<<-EOF
    #!/bin/bash
    # Update the server
    yum update -y

    # Install web server
    yum install -y httpd

    # Install git to fetch code
    yum install -y git

    # Fetch application code from GitHub
    git clone https://github.com/sabc-news/website.git /var/www/html/

    # Install AWS CLI to talk to S3 and other AWS services
    yum install -y aws-cli

    # Start web server
    systemctl start httpd

    # Make web server start automatically on reboot
    systemctl enable httpd

    # Create health check endpoint
    # Load balancer calls /health to check if this EC2 is alive
    echo "healthy" > /var/www/html/health
  EOF
  )
  # base64encode converts the script to base64 format
  # This is required by AWS for user data

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.main_ec2.id]
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.app_name}-main-ec2"
      Environment = var.environment
    }
  }
}

# AUTO SCALING GROUP
# Manages a fleet of EC2 instances
# Adds instances when traffic is high
# Removes instances when traffic is low
# Replaces unhealthy instances automatically
resource "aws_autoscaling_group" "main" {
  name                = "${var.app_name}-main-asg"
  min_size            = var.main_min_instances   # At least 2 always running
  max_size            = var.main_max_instances   # Never more than 10
  desired_capacity    = var.main_min_instances   # Start with minimum

  vpc_zone_identifier = [
    aws_subnet.main_public_1.id,
    aws_subnet.main_public_2.id
    # Spread instances across both AZs
    # High availability — if one AZ fails other has instances
  ]

  target_group_arns = [aws_lb_target_group.main.arn]
  # Connect ASG to load balancer
  # New instances automatically register with load balancer

  health_check_type         = "ELB"
  # Use load balancer health checks to determine if instance is healthy
  # If load balancer marks instance unhealthy — ASG replaces it

  health_check_grace_period = 300
  # Give new instances 5 minutes to start up before health checking
  # Because user data script takes time to install software

  launch_template {
    id      = aws_launch_template.main.id
    version = "$Latest"   # Always use latest version of template
  }

  tag {
    key                 = "Name"
    value               = "${var.app_name}-main-asg-instance"
    propagate_at_launch = true
    # propagate_at_launch = copy this tag to every EC2 the ASG creates
  }
}

# AUTO SCALING POLICY — Scale UP
# When CPU goes above 70% — add more instances
resource "aws_autoscaling_policy" "main_scale_up" {
  name                   = "${var.app_name}-main-scale-up"
  autoscaling_group_name = aws_autoscaling_group.main.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 2      # Add 2 instances at a time
  cooldown               = 300    # Wait 5 minutes before scaling again
}

# AUTO SCALING POLICY — Scale DOWN  
# When CPU goes below 30% — remove instances to save cost
resource "aws_autoscaling_policy" "main_scale_down" {
  name                   = "${var.app_name}-main-scale-down"
  autoscaling_group_name = aws_autoscaling_group.main.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1     # Remove 1 instance at a time
  cooldown               = 300
}
                                                                                                                                                                  