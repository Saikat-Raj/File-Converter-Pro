# Configure the AWS Provider
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Variables
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "file-converter"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

# Data sources
data "aws_caller_identity" "current" {}

# S3 Buckets
resource "aws_s3_bucket" "website_bucket" {
  bucket = "${var.project_name}-website-${random_string.bucket_suffix.result}"

  tags = {
    Name        = "${var.project_name}-website"
    Environment = var.environment
  }
}

resource "aws_s3_bucket" "uploads_bucket" {
  bucket = "${var.project_name}-uploads-${random_string.bucket_suffix.result}"

  tags = {
    Name        = "${var.project_name}-uploads"
    Environment = var.environment
  }
}

resource "aws_s3_bucket" "converted_bucket" {
  bucket = "${var.project_name}-converted-${random_string.bucket_suffix.result}"

  tags = {
    Name        = "${var.project_name}-converted"
    Environment = var.environment
  }
}

resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# S3 Bucket Configurations
resource "aws_s3_bucket_website_configuration" "website_bucket" {
  bucket = aws_s3_bucket.website_bucket.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

resource "aws_s3_bucket_public_access_block" "website_bucket" {
  bucket = aws_s3_bucket.website_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "website_bucket" {
  bucket = aws_s3_bucket.website_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.website_bucket.arn}/*"
      },
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.website_bucket]
}

# CORS configuration for uploads bucket
resource "aws_s3_bucket_cors_configuration" "uploads_bucket" {
  bucket = aws_s3_bucket.uploads_bucket.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "POST", "PUT", "DELETE"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# DynamoDB table for tracking conversions
resource "aws_dynamodb_table" "conversions" {
  name         = "${var.project_name}-conversions"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "conversion_id"

  attribute {
    name = "conversion_id"
    type = "S"
  }

  attribute {
    name = "user_session"
    type = "S"
  }

  global_secondary_index {
    name            = "UserSessionIndex"
    hash_key        = "user_session"
    projection_type = "ALL"
  }

  tags = {
    Name        = "${var.project_name}-conversions"
    Environment = var.environment
  }
}

# IAM Role for Lambda functions
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project_name}-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "${aws_s3_bucket.uploads_bucket.arn}/*",
          "${aws_s3_bucket.converted_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query"
        ]
        Resource = [
          aws_dynamodb_table.conversions.arn,
          "${aws_dynamodb_table.conversions.arn}/index/*"
        ]
      }
    ]
  })
}

# Lambda Layer for dependencies
resource "aws_lambda_layer_version" "conversion_layer" {
  filename         = "conversion_layer.zip"
  layer_name       = "${var.project_name}-conversion-layer"
  source_code_hash = data.archive_file.conversion_layer.output_base64sha256

  compatible_runtimes = ["python3.9"]
  description         = "Layer containing libraries for file conversion"
}

data "archive_file" "conversion_layer" {
  type        = "zip"
  output_path = "conversion_layer.zip"
  source_dir  = "${path.module}/layer"
}

# File Upload Lambda
resource "aws_lambda_function" "file_upload" {
  filename         = "file_upload.zip"
  function_name    = "${var.project_name}-file-upload"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  source_code_hash = data.archive_file.file_upload.output_base64sha256
  runtime          = "python3.9"
  timeout          = 30

  environment {
    variables = {
      UPLOADS_BUCKET = aws_s3_bucket.uploads_bucket.bucket
      DYNAMODB_TABLE = aws_dynamodb_table.conversions.name
    }
  }

  tags = {
    Name        = "${var.project_name}-file-upload"
    Environment = var.environment
  }
}

data "archive_file" "file_upload" {
  type        = "zip"
  output_path = "file_upload.zip"
  source {
    content  = <<EOF
import json
import boto3
import uuid
import base64
from datetime import datetime

s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

def handler(event, context):
    try:
        table = dynamodb.Table(os.environ['DYNAMODB_TABLE'])
        uploads_bucket = os.environ['UPLOADS_BUCKET']
        
        body = json.loads(event['body'])
        file_data = base64.b64decode(body['file_data'])
        file_name = body['file_name']
        user_session = body.get('user_session', str(uuid.uuid4()))
        
        conversion_id = str(uuid.uuid4())
        s3_key = f"{user_session}/{conversion_id}/{file_name}"
        
        # Upload to S3
        s3.put_object(
            Bucket=uploads_bucket,
            Key=s3_key,
            Body=file_data,
            ContentType=body.get('content_type', 'application/octet-stream')
        )
        
        # Record in DynamoDB
        table.put_item(
            Item={
                'conversion_id': conversion_id,
                'user_session': user_session,
                'original_file': s3_key,
                'file_name': file_name,
                'status': 'uploaded',
                'created_at': datetime.utcnow().isoformat()
            }
        )
        
        return {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'POST, OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type'
            },
            'body': json.dumps({
                'conversion_id': conversion_id,
                'user_session': user_session,
                'message': 'File uploaded successfully'
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': str(e)})
        }
EOF
    filename = "index.py"
  }
}

# File Conversion Lambda
resource "aws_lambda_function" "file_converter" {
  filename         = "file_converter.zip"
  function_name    = "${var.project_name}-file-converter"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  source_code_hash = data.archive_file.file_converter.output_base64sha256
  runtime          = "python3.9"
  timeout          = 300
  memory_size      = 1024

  layers = [aws_lambda_layer_version.conversion_layer.arn]

  environment {
    variables = {
      UPLOADS_BUCKET   = aws_s3_bucket.uploads_bucket.bucket
      CONVERTED_BUCKET = aws_s3_bucket.converted_bucket.bucket
      DYNAMODB_TABLE   = aws_dynamodb_table.conversions.name
    }
  }

  tags = {
    Name        = "${var.project_name}-file-converter"
    Environment = var.environment
  }
}

data "archive_file" "file_converter" {
  type        = "zip"
  output_path = "file_converter.zip"
  source {
    content  = <<EOF
import json
import boto3
import os
import tempfile
from PIL import Image
import io

s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

def handler(event, context):
    try:
        table = dynamodb.Table(os.environ['DYNAMODB_TABLE'])
        uploads_bucket = os.environ['UPLOADS_BUCKET']
        converted_bucket = os.environ['CONVERTED_BUCKET']
        
        body = json.loads(event['body'])
        conversion_id = body['conversion_id']
        target_format = body['target_format'].lower()
        
        # Get conversion record
        response = table.get_item(Key={'conversion_id': conversion_id})
        if 'Item' not in response:
            raise Exception('Conversion not found')
        
        item = response['Item']
        original_s3_key = item['original_file']
        
        # Download file from S3
        obj = s3.get_object(Bucket=uploads_bucket, Key=original_s3_key)
        file_content = obj['Body'].read()
        
        # Determine conversion type
        original_ext = original_s3_key.split('.')[-1].lower()
        
        if is_image_format(original_ext) and is_image_format(target_format):
            converted_content = convert_image(file_content, target_format)
        else:
            raise Exception(f'Unsupported conversion: {original_ext} to {target_format}')
        
        # Upload converted file
        converted_key = original_s3_key.replace(f'.{original_ext}', f'.{target_format}')
        converted_key = converted_key.replace(uploads_bucket, converted_bucket)
        
        s3.put_object(
            Bucket=converted_bucket,
            Key=converted_key,
            Body=converted_content,
            ContentType=get_content_type(target_format)
        )
        
        # Update DynamoDB
        table.update_item(
            Key={'conversion_id': conversion_id},
            UpdateExpression='SET #status = :status, converted_file = :file',
            ExpressionAttributeNames={'#status': 'status'},
            ExpressionAttributeValues={
                ':status': 'completed',
                ':file': converted_key
            }
        )
        
        # Generate presigned URL
        download_url = s3.generate_presigned_url(
            'get_object',
            Params={'Bucket': converted_bucket, 'Key': converted_key},
            ExpiresIn=3600
        )
        
        return {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'POST, OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type'
            },
            'body': json.dumps({
                'conversion_id': conversion_id,
                'download_url': download_url,
                'message': 'File converted successfully'
            })
        }
        
    except Exception as e:
        # Update status to failed
        try:
            table.update_item(
                Key={'conversion_id': conversion_id},
                UpdateExpression='SET #status = :status, error_message = :error',
                ExpressionAttributeNames={'#status': 'status'},
                ExpressionAttributeValues={
                    ':status': 'failed',
                    ':error': str(e)
                }
            )
        except:
            pass
            
        return {
            'statusCode': 500,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'error': str(e)})
        }

def is_image_format(ext):
    return ext in ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'tiff', 'webp']

def convert_image(file_content, target_format):
    img = Image.open(io.BytesIO(file_content))
    
    # Convert RGBA to RGB for formats that don't support transparency
    if target_format.upper() in ['JPEG', 'JPG'] and img.mode in ['RGBA', 'LA']:
        background = Image.new('RGB', img.size, (255, 255, 255))
        if img.mode == 'RGBA':
            background.paste(img, mask=img.split()[-1])
        else:
            background.paste(img)
        img = background
    
    output = io.BytesIO()
    format_map = {'jpg': 'JPEG', 'jpeg': 'JPEG'}
    save_format = format_map.get(target_format, target_format.upper())
    
    img.save(output, format=save_format)
    return output.getvalue()

def get_content_type(ext):
    types = {
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'png': 'image/png',
        'gif': 'image/gif',
        'bmp': 'image/bmp',
        'tiff': 'image/tiff',
        'webp': 'image/webp'
    }
    return types.get(ext, 'application/octet-stream')
EOF
    filename = "index.py"
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.project_name}-api"
  description = "API for file conversion service"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# API Gateway Resources
resource "aws_api_gateway_resource" "upload" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "upload"
}

resource "aws_api_gateway_resource" "convert" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "convert"
}

# API Gateway Methods
resource "aws_api_gateway_method" "upload_post" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.upload.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "upload_options" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.upload.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "convert_post" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.convert.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "convert_options" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.convert.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

# API Gateway Integrations
resource "aws_api_gateway_integration" "upload_lambda" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.upload.id
  http_method = aws_api_gateway_method.upload_post.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.file_upload.invoke_arn
}

resource "aws_api_gateway_integration" "convert_lambda" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.convert.id
  http_method = aws_api_gateway_method.convert_post.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.file_converter.invoke_arn
}

# CORS Integrations
resource "aws_api_gateway_integration" "upload_options" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.upload.id
  http_method = aws_api_gateway_method.upload_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_integration" "convert_options" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.convert.id
  http_method = aws_api_gateway_method.convert_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

# Method Responses
resource "aws_api_gateway_method_response" "upload_options" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.upload.id
  http_method = aws_api_gateway_method.upload_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_method_response" "convert_options" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.convert.id
  http_method = aws_api_gateway_method.convert_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

# Integration Responses
resource "aws_api_gateway_integration_response" "upload_options" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.upload.id
  http_method = aws_api_gateway_method.upload_options.http_method
  status_code = aws_api_gateway_method_response.upload_options.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

resource "aws_api_gateway_integration_response" "convert_options" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.convert.id
  http_method = aws_api_gateway_method.convert_options.http_method
  status_code = aws_api_gateway_method_response.convert_options.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# Lambda Permissions
resource "aws_lambda_permission" "api_gateway_upload" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.file_upload.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "api_gateway_convert" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.file_converter.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "main" {
  depends_on = [
    aws_api_gateway_integration.upload_lambda,
    aws_api_gateway_integration.convert_lambda,
    aws_api_gateway_integration.upload_options,
    aws_api_gateway_integration.convert_options
  ]

  rest_api_id = aws_api_gateway_rest_api.main.id
  stage_name  = var.environment

  lifecycle {
    create_before_destroy = true
  }
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "website" {
  origin {
    domain_name = aws_s3_bucket.website_bucket.bucket_regional_domain_name
    origin_id   = "S3-${aws_s3_bucket.website_bucket.bucket}"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${aws_s3_bucket.website_bucket.bucket}"
    compress               = true
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name        = "${var.project_name}-cdn"
    Environment = var.environment
  }
}

# Outputs
output "website_url" {
  description = "Website URL"
  value       = "https://${aws_cloudfront_distribution.website.domain_name}"
}

output "api_url" {
  description = "API Gateway URL"
  value       = "https://${aws_api_gateway_rest_api.main.id}.execute-api.${var.aws_region}.amazonaws.com/${var.environment}"
}

output "s3_website_bucket" {
  description = "S3 bucket name for website"
  value       = aws_s3_bucket.website_bucket.bucket
}

output "uploads_bucket" {
  description = "S3 bucket name for uploads"
  value       = aws_s3_bucket.uploads_bucket.bucket
}

output "converted_bucket" {
  description = "S3 bucket name for converted files"
  value       = aws_s3_bucket.converted_bucket.bucket
}
