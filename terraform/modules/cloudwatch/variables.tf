variable "name" {
  description = "Name prefix for resources"
  type        = string
}

variable "sns_alerts_topic_arn" {
  description = "ARN of the SNS alerts topic"
  type        = string
}

variable "step_functions_state_machine_arn" {
  description = "ARN of the Step Functions state machine"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}
