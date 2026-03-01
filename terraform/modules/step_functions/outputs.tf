output "state_machine_arn" {
  description = "ARN of the data collection state machine"
  value       = aws_sfn_state_machine.data_collection.arn
}

output "state_machine_name" {
  description = "Name of the data collection state machine"
  value       = aws_sfn_state_machine.data_collection.name
}

output "role_arn" {
  description = "ARN of the Step Functions IAM role"
  value       = aws_iam_role.step_functions.arn
}

output "inference_state_machine_arn" {
  description = "ARN of the batch inference state machine (re-inference with approved model)"
  value       = aws_sfn_state_machine.batch_inference.arn
}
