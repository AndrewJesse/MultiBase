variable "region_a" {
  type    = string
  default = "us-east-1"
}

variable "region_b" {
  type    = string
  default = "eu-west-1"
}

variable "instance_type" {
  type    = string
  default = "t4g.medium"
}

variable "volume_gb" {
  type    = number
  default = 30
}

variable "instance_profile" {
  type    = string
  default = "multibase-node"
}
