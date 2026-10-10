variable "primary_region" {
  type    = string
  default = "us-east-1"
}

variable "budget_email" {
  type = string
}

variable "monthly_budget_usd" {
  type    = number
  default = 20
}

variable "roles_anywhere_ca_pem" {
  description = "PEM of a self-managed CA for the home node; empty disables Roles Anywhere."
  type        = string
  default     = ""
}

variable "github_repo" {
  description = "owner/name allowed to assume the CI role via OIDC"
  type        = string
  default     = "QuietCode-Dev/MultiBase"
}
