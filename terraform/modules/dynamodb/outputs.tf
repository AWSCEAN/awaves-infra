output "table_surf_data_name" {
  description = "Name of the surf data DynamoDB table"
  value       = aws_dynamodb_table.surf_data.name
}

output "table_surf_data_arn" {
  description = "ARN of the surf data DynamoDB table"
  value       = aws_dynamodb_table.surf_data.arn
}

output "table_saved_list_name" {
  description = "Name of the saved list DynamoDB table"
  value       = aws_dynamodb_table.saved_list.name
}

output "table_saved_list_arn" {
  description = "ARN of the saved list DynamoDB table"
  value       = aws_dynamodb_table.saved_list.arn
}
