output "schedule_arn" {
  description = "ARN of the EventBridge schedule"
  value       = aws_scheduler_schedule.data_collection.arn
}

output "schedule_name" {
  description = "Name of the EventBridge schedule"
  value       = aws_scheduler_schedule.data_collection.name
}
