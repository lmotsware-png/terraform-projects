# =============================================================
# ROUTE53.TF
# =============================================================
# Route 53 is AWS DNS service
# DNS = translates domain names to IP addresses
# From your CCNA — you know how DNS works
#
# Route 53 is the BRAIN of disaster recovery
# It watches both regions continuously
# When Cape Town goes down — it automatically switches
# all traffic to Ireland
# Users type the same URL — Route 53 sends them to Ireland
# Users do not even know a disaster happened
# =============================================================

# HOSTED ZONE
# This is where your domain records live
# Think of it like the phone book for your domain
resource "aws_route53_zone" "main" {
  name = var.domain_name   # sabcnews.co.za
  # Route 53 is global — no provider needed
  # It works across all regions automatically

  tags = {
    Name        = "${var.app_name}-hosted-zone"
    Environment = var.environment
  }
}

# =============================================================
# HEALTH CHECKS
# =============================================================
# Route 53 health checks continuously test your endpoints
# Every 30 seconds it sends a request to your load balancer
# If it gets no response — marks it as unhealthy
# Then automatically redirects traffic to DR region

# Health check for MAIN region (Cape Town)
resource "aws_route53_health_check" "main" {
  fqdn              = aws_lb.main.dns_name
  # fqdn = the DNS name of your main load balancer
  # Route 53 sends requests to this address every 30 seconds

  port              = 80
  type              = "HTTP"
  resource_path     = "/health"
  # Checks the /health endpoint we created in user data
  # If /health returns 200 — healthy
  # If no response or error — unhealthy

  failure_threshold = "3"
  # Must fail 3 times in a row before marking unhealthy
  # Prevents false alarms from temporary blips

  request_interval  = "30"
  # Check every 30 seconds

  tags = {
    Name    = "${var.app_name}-main-health-check"
    Region  = "Cape Town"
  }
}

# Health check for DR region (Ireland)
resource "aws_route53_health_check" "dr" {
  fqdn              = aws_lb.dr.dns_name
  port              = 80
  type              = "HTTP"
  resource_path     = "/health"
  failure_threshold = "3"
  request_interval  = "30"

  tags = {
    Name   = "${var.app_name}-dr-health-check"
    Region = "Ireland"
  }
}

# =============================================================
# DNS RECORDS WITH FAILOVER ROUTING
# =============================================================
# This is where the disaster recovery magic happens
# We create TWO DNS records for the same domain
# One points to Cape Town (PRIMARY)
# One points to Ireland (SECONDARY)
#
# Route 53 Failover Routing:
# - Always send traffic to PRIMARY (Cape Town)
# - If PRIMARY health check fails — automatically send to SECONDARY (Ireland)
# - When PRIMARY recovers — automatically switch back

# PRIMARY DNS RECORD — Points to Cape Town load balancer
resource "aws_route53_record" "main_primary" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.domain_name   # sabcnews.co.za
  type    = "A"
  # A record = maps domain name to IP address

  # Alias record points to load balancer
  # Load balancer IP can change — alias always follows it
  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }

  failover_routing_policy {
    type = "PRIMARY"   # This is the main record — use this first
  }

  set_identifier  = "main-primary"
  health_check_id = aws_route53_health_check.main.id
  # Link health check to this record
  # If health check fails — stop using this record
  # Automatically switch to SECONDARY record below
}

# SECONDARY DNS RECORD — Points to Ireland load balancer
# This record is ONLY used when PRIMARY is unhealthy
resource "aws_route53_record" "dr_secondary" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.domain_name   # Same domain name
  type    = "A"

  alias {
    name                   = aws_lb.dr.dns_name    # Points to Ireland ALB
    zone_id                = aws_lb.dr.zone_id
    evaluate_target_health = true
  }

  failover_routing_policy {
    type = "SECONDARY"   # Only use this when PRIMARY is down
  }

  set_identifier  = "dr-secondary"
  health_check_id = aws_route53_health_check.dr.id
}

# =============================================================
# WHAT HAPPENS DURING DISASTER — TIMELINE
# =============================================================
#
# SECOND 0:    Cape Town region goes down
#
# SECOND 30:   Route 53 health check sends request to Cape Town
#              No response received
#
# SECOND 60:   Second health check fails
#
# SECOND 90:   Third health check fails
#              Failure threshold reached (3 failures)
#              Route 53 marks Cape Town as UNHEALTHY
#
# SECOND 91:   Route 53 stops sending traffic to Cape Town
#              Starts sending ALL traffic to Ireland
#
# SECOND 91+:  Users in South Africa type sabcnews.co.za
#              Route 53 returns Ireland load balancer address
#              Traffic flows to Ireland warm standby
#              Ireland Auto Scaling Group starts scaling up
#
# MINUTE 5:    Ireland has scaled up to handle full traffic
#              Business running normally from Ireland
#              Users notice nothing — same URL works fine
#
# =============================================================
