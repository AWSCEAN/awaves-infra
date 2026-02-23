output "sampling_rule_arn" {
  description = "ARN of the X-Ray sampling rule"
  value       = aws_xray_sampling_rule.awaves.arn
}

output "group_arn" {
  description = "ARN of the X-Ray group"
  value       = aws_xray_group.awaves.arn
}
