output "table_surf_info_name" {
  description = "Name of the surf info DynamoDB table"
  value       = aws_dynamodb_table.surf_info.name
}

output "table_surf_info_arn" {
  description = "ARN of the surf info DynamoDB table"
  value       = aws_dynamodb_table.surf_info.arn
}

output "table_saved_list_name" {
  description = "Name of the saved list DynamoDB table"
  value       = aws_dynamodb_table.saved_list.name
}

output "table_saved_list_arn" {
  description = "ARN of the saved list DynamoDB table"
  value       = aws_dynamodb_table.saved_list.arn
}
