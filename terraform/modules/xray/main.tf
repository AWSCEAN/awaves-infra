# =============================================================================
# X-Ray Sampling Rule
# =============================================================================

resource "aws_xray_sampling_rule" "awaves" {
  rule_name      = "${var.name}-sampling"
  priority       = 9000
  reservoir_size = 1
  fixed_rate     = 0.05 # 5% sampling
  host           = "*"
  http_method    = "*"
  resource_arn   = "*"
  service_name   = "*"
  service_type   = "*"
  url_path       = "*"
  version        = 1

  attributes = {
    Project = var.name
  }
}

# =============================================================================
# X-Ray Group
# =============================================================================

resource "aws_xray_group" "awaves" {
  group_name        = var.name
  filter_expression = "annotation.Project = \"${var.name}\""

  insights_configuration {
    insights_enabled      = false
    notifications_enabled = false
  }
}
