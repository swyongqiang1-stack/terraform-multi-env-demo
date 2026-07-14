variable "cidr_block" {
    type = string
}

variable "public_subnet_id" {
    type = string
}

variable "private_subnet_id" {
    type = list(string)
}

