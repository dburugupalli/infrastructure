
variable "aws_region" {
  type = string
}

variable "aws_profile" {
  type = string
}

variable "ingressCIDR" {
  type = list
}
variable "egressCIDR" {
  type = list
}
variable "mapPublicIP" {
  default = true
}

variable "azs" {
  type = list
}
variable "instanceTenancy" {
  default = "default"
}
variable "dnsSupport" {
  default = true
}
variable "dnsHostNames" {
  default = true
}
variable "vpcCIDR" {
  type = string
}
variable "subnetCIDR" {
  type = list
}
variable "destinationCIDR" {
  type = string
}

variable "rdsDBName" {
  type = string
}

variable "id" {
  type = string
}

variable "dbusername" {
  type = string
}

variable "dbpassword" {
  type = string
}

variable "ec2_key" {
  type = string
}

variable "dns_record" {
  type = string
}

variable "aws_account_id" {
  type = string
}

variable "bucket_name" {
  type = string
}