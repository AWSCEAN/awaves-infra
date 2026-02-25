variable "domain_name" {
  description = "Root domain name for the certificate (e.g. awaves.net). A wildcard SAN (*.awaves.net) is added automatically."
  type        = string
}

variable "zone_id" {
  description = "Route 53 hosted zone ID for DNS validation records"
  type        = string
}
