# =============================================================
# LAMBDA.TF
# =============================================================
# This file creates the Lambda function that processes order files
#
# Remember our Lambda discussion:
# Lambda = serverless function
# You upload code — AWS runs it when triggered
# You do not manage any servers
# You only pay when the function actually runs
#
# This Lambda:
# - Gets triggered the MOMENT a file lands in S3
# - Reads the order file
# - Validates and processes the order
# - Saves to database
# - Runs INSIDE our VPC so it can reach RDS
# =============================================================

# =============================================================
# LAMBDA FUNCTION CODE
# =============================================================
# Lambda needs actual code to run
# We write the code inline here as a Python script
# In real production you would have a separate .py file
# and zip it up — but for learning we write it inline

# First create the Python code as a local file
resource "local_file" "lambda_code" {
  filename = "${path.module}/lambda/order_processor.py"
  # path.module = the folder where this Terraform file lives
  # We create a lambda/ subfolder with the Python code

  content = <<-PYTHON
import json
import boto3
import csv
import logging
import os

# Set up logging — this writes to CloudWatch
# Like print() but goes to AWS CloudWatch logs
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Create AWS clients — these let Python talk to AWS services
s3_client = boto3.client('s3')
# boto3 = the Python library for AWS
# boto3.client('s3') = create a connection to S3

def lambda_handler(event, context):
    """
    This is the MAIN function — Lambda calls this when triggered
    
    event = information about what triggered Lambda
    For S3 trigger: event contains bucket name and file name
    
    context = information about the Lambda execution itself
    (timeout remaining, function name, etc.)
    """
    
    logger.info(f"Order processor triggered. Event: {json.dumps(event)}")
    # Log that we were triggered — visible in CloudWatch
    
    # =========================================================
    # STEP 1 — Get the file details from the trigger event
    # =========================================================
    # When S3 triggers Lambda — it sends event data
    # Event contains: which bucket, which file, when it happened
    
    try:
        # Get bucket name and file key from the event
        bucket_name = event['Records'][0]['s3']['bucket']['name']
        # event['Records'][0] = first record (there might be multiple)
        # ['s3']['bucket']['name'] = drill down to bucket name
        
        file_key = event['Records'][0]['s3']['object']['key']
        # ['s3']['object']['key'] = the file path inside the bucket
        # Example: uploads/order_20260425_143022.csv
        
        logger.info(f"Processing file: s3://{bucket_name}/{file_key}")
        
    except KeyError as e:
        logger.error(f"Could not extract S3 details from event: {e}")
        raise
    
    # =========================================================
    # STEP 2 — Download and read the file from S3
    # =========================================================
    
    try:
        # Download the file from S3
        response = s3_client.get_object(Bucket=bucket_name, Key=file_key)
        # get_object = download a file from S3
        # Bucket = which bucket
        # Key = which file (the path)
        
        # Read the file content
        file_content = response['Body'].read().decode('utf-8')
        # response['Body'] = the file data
        # .read() = read all bytes
        # .decode('utf-8') = convert bytes to readable text
        
        logger.info(f"Successfully downloaded file. Size: {len(file_content)} characters")
        
    except Exception as e:
        logger.error(f"Failed to download file from S3: {e}")
        raise
    
    # =========================================================
    # STEP 3 — Parse the CSV order file
    # =========================================================
    # The ERP sends CSV (Comma Separated Values) files
    # Example file content:
    # OrderID,StoreCode,Product,Quantity,Price
    # ORD001,WW-SOWETO,Bread,500,15.99
    # ORD001,WW-SOWETO,Milk,200,8.50
    
    orders = []
    
    try:
        import io
        csv_reader = csv.DictReader(io.StringIO(file_content))
        # csv.DictReader = reads CSV where first row is headers
        # Each row becomes a dictionary
        # Example: {'OrderID': 'ORD001', 'Product': 'Bread', ...}
        
        for row in csv_reader:
            orders.append(row)
            # Add each order line to our list
        
        logger.info(f"Parsed {len(orders)} order lines from CSV")
        
    except Exception as e:
        logger.error(f"Failed to parse CSV file: {e}")
        raise
    
    # =========================================================
    # STEP 4 — Validate the orders
    # =========================================================
    # Check that required fields are present
    # Check that quantities and prices are valid numbers
    
    valid_orders = []
    invalid_orders = []
    
    required_fields = ['OrderID', 'StoreCode', 'Product', 'Quantity', 'Price']
    
    for order in orders:
        is_valid = True
        
        # Check all required fields exist
        for field in required_fields:
            if field not in order or not order[field]:
                logger.warning(f"Order missing required field '{field}': {order}")
                is_valid = False
                break
        
        # Check quantity is a number
        if is_valid:
            try:
                int(order['Quantity'])
            except ValueError:
                logger.warning(f"Invalid quantity in order: {order}")
                is_valid = False
        
        if is_valid:
            valid_orders.append(order)
        else:
            invalid_orders.append(order)
    
    logger.info(f"Validation complete. Valid: {len(valid_orders)}, Invalid: {len(invalid_orders)}")
    
    # =========================================================
    # STEP 5 — Process valid orders
    # =========================================================
    # In real production — save to RDS database here
    # For this example we log the orders and simulate processing
    
    processed_count = 0
    
    for order in valid_orders:
        try:
            # In real production this would be:
            # db_connection.execute("INSERT INTO orders VALUES ...")
            
            logger.info(f"Processing order: {order['OrderID']} - "
                       f"{order['Product']} x{order['Quantity']} "
                       f"for store {order['StoreCode']}")
            
            processed_count += 1
            
        except Exception as e:
            logger.error(f"Failed to process order {order.get('OrderID', 'UNKNOWN')}: {e}")
    
    # =========================================================
    # STEP 6 — Return result
    # =========================================================
    
    result = {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Order file processed successfully',
            'file': file_key,
            'total_orders': len(orders),
            'valid_orders': len(valid_orders),
            'invalid_orders': len(invalid_orders),
            'processed': processed_count
        })
    }
    
    logger.info(f"Processing complete: {result}")
    return result

PYTHON
}

# Zip the Lambda code — AWS requires Lambda code in a zip file
data "archive_file" "lambda_zip" {
  type        = "zip"
  # type = zip = compress into a zip file

  source_dir  = "${path.module}/lambda"
  # source_dir = the folder containing our Python code

  output_path = "${path.module}/lambda.zip"
  # output_path = where to save the zip file
  # Terraform creates this zip automatically

  depends_on = [local_file.lambda_code]
  # Create the code file BEFORE trying to zip it
}

# =============================================================
# LAMBDA FUNCTION RESOURCE
# =============================================================

resource "aws_lambda_function" "order_processor" {
  function_name = "${var.project_name}-order-processor"
  # function_name = what the Lambda function is called in AWS

  filename      = data.archive_file.lambda_zip.output_path
  # filename = where is the zip file with our code
  # Terraform uploads this zip to Lambda automatically

  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  # source_code_hash = a fingerprint of the zip file
  # If the code changes — this hash changes
  # Terraform sees the hash changed and knows to redeploy Lambda
  # Without this — Terraform would not update Lambda when code changes

  role    = aws_iam_role.lambda.arn
  # role = which IAM role Lambda uses
  # This gives Lambda permissions to read S3, write logs, etc.

  handler = "order_processor.lambda_handler"
  # handler = which function to call when Lambda is triggered
  # Format: FILENAME.FUNCTION_NAME
  # order_processor = the Python file name (order_processor.py)
  # lambda_handler = the function name inside the file

  runtime = "python3.11"
  # runtime = which programming language and version
  # python3.11 = Python version 3.11
  # Other options: nodejs18.x, java11, dotnet6, ruby3.2

  timeout = var.lambda_timeout
  # timeout = maximum seconds Lambda can run
  # From variables.tf — default is 300 seconds (5 minutes)
  # If it runs longer — Lambda automatically stops it

  memory_size = var.lambda_memory
  # memory_size = how much RAM to give Lambda
  # From variables.tf — default is 512 MB
  # More memory = faster execution = slightly more cost

  # =============================================================
  # VPC CONFIGURATION — Run Lambda inside our private VPC
  # =============================================================
  # Lambda needs to run inside our VPC to:
  # - Reach our RDS database (which is in private subnet)
  # - Access internal resources
  # - Not expose data processing to internet

  vpc_config {
    subnet_ids = [
      aws_subnet.private_az1.id,
      aws_subnet.private_az2.id
    ]
    # subnet_ids = which subnets Lambda can run in
    # We give it both private subnets for high availability
    # Lambda will run in whichever AZ has capacity

    security_group_ids = [aws_security_group.lambda.id]
    # security_group_ids = firewall rules for Lambda
    # Our Lambda security group allows outbound to reach S3 and RDS
  }

  # =============================================================
  # ENVIRONMENT VARIABLES
  # =============================================================
  # Environment variables = settings passed to the Lambda function
  # The Python code can read these with os.environ['VARIABLE_NAME']
  # Good for passing configuration without hardcoding in code

  environment {
    variables = {
      BUCKET_NAME   = aws_s3_bucket.orders.id
      # The Lambda code can read this to know which bucket to use
      # Instead of hardcoding bucket name in Python code

      ENVIRONMENT   = var.environment
      # Which environment — production, staging, dev
      # Lambda can log this to know where it is running

      PROJECT_NAME  = var.project_name
      # Project name — used for logging and parameter store paths

      LOG_LEVEL     = "INFO"
      # How much logging detail
      # INFO = normal operation logs
      # DEBUG = very detailed — use only when troubleshooting
    }
  }

  # =============================================================
  # RESERVED CONCURRENCY
  # =============================================================
  # Concurrency = how many Lambda instances can run simultaneously
  # If 10 files arrive at the same time — 10 Lambda instances run
  # reserved_concurrent_executions limits this

  reserved_concurrent_executions = 10
  # Maximum 10 Lambda instances running at the same time
  # Protects database from being overwhelmed
  # If 100 files arrive at once — only 10 process simultaneously
  # Others wait in queue — processed as capacity becomes available

  depends_on = [
    aws_iam_role_policy_attachment.lambda_vpc,
    aws_iam_role_policy.lambda_s3,
    aws_cloudwatch_log_group.lambda
    # Make sure IAM roles and log group exist before creating Lambda
  ]

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-order-processor"
    Purpose = "Processes order files immediately after SFTP upload"
    Runtime = "python3.11"
  })
}

# =============================================================
# LAMBDA PERMISSION — Allow S3 to invoke Lambda
# =============================================================
# S3 needs permission to call Lambda
# Without this — S3 cannot trigger our Lambda function
# Even if the notification is set up — it would be rejected

resource "aws_lambda_permission" "s3_invoke" {
  statement_id  = "AllowS3ToInvokeLambda"
  # statement_id = unique label for this permission

  action        = "lambda:InvokeFunction"
  # action = what S3 is allowed to do
  # lambda:InvokeFunction = S3 is allowed to trigger/run Lambda

  function_name = aws_lambda_function.order_processor.function_name
  # function_name = which Lambda function S3 can invoke

  principal     = "s3.amazonaws.com"
  # principal = WHO gets this permission
  # s3.amazonaws.com = the S3 service itself

  source_arn    = aws_s3_bucket.orders.arn
  # source_arn = which specific S3 bucket can invoke Lambda
  # ONLY our orders bucket — not any other S3 bucket
  # Security — even if another bucket tried to invoke Lambda — blocked
}
