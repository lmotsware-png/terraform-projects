# =============================================================
# PROVIDERS.TF
# =============================================================
# A provider tells Terraform WHICH cloud and WHICH region to
# build in. Think of it like telling a contractor:
# "I want you to build in Cape Town AND in Ireland."
# We need TWO providers because we are building in TWO regions.
# =============================================================

# This is your MAIN region — where your business runs normally
provider "aws" {
  region = "af-south-1"   # Cape Town — South Africa
}

# This is your DR region — your warm standby
# alias = "dr" means we give it a nickname
# When we want to build something in Ireland we say provider = aws.dr
provider "aws" {
  alias  = "dr"
  region = "eu-west-1"    # Ireland — far away from South Africa
}

# Why Ireland? Because if South Africa has a massive disaster
# Ireland is thousands of kilometers away and completely unaffected
