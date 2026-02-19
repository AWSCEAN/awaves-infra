variable "name" {
  description = "Name prefix for resources"
  type        = string
}

variable "state_machine_arn" {
  description = "ARN of the Step Functions state machine to trigger"
  type        = string
}
