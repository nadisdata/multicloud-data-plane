variable "region" {
  type        = string
  description = "Target region (use a GovCloud region in production)."
  default     = "us-west-2"
}

variable "name_prefix" {
  type        = string
  description = "Prefix applied to all resource names."
  default     = "ref-data-plane"
}

variable "sci_dev_principal_arns" {
  type        = list(string)
  description = "Science-development workspace role ARNs allowed governed read-through access."
  default     = []
}
