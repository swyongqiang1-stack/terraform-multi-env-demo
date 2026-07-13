variable "cidr_block" {
  type = string
}

variable "subnet" {
  type = list(string)
}

variable "zone" {
  type = list(string)
}

variable "password" {
  type = string
}