# Remote backend configuration
# Uncomment after creating the S3 bucket and DynamoDB table:
#
#   aws s3api create-bucket --bucket awaves-terraform-state --region us-east-1
#   aws s3api put-bucket-versioning --bucket awaves-terraform-state --versioning-configuration Status=Enabled
#   aws s3api put-bucket-encryption --bucket awaves-terraform-state \
#     --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
#   aws s3api put-public-access-block --bucket awaves-terraform-state \
#     --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
#   aws dynamodb create-table --table-name awaves-terraform-lock \
#     --attribute-definitions AttributeName=LockID,AttributeType=S \
#     --key-schema AttributeName=LockID,KeyType=HASH \
#     --billing-mode PAY_PER_REQUEST --region us-east-1
#
# terraform {
#   backend "s3" {
#     bucket         = "awaves-terraform-state"
#     key            = "dev/terraform.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "awaves-terraform-lock"
#     encrypt        = true
#   }
# }
