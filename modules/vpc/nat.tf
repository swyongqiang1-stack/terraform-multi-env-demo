resource "aws_eip" "lb" {
  count = 3
  domain   = "vpc"
}


resource "aws_nat_gateway" "nat" {
  count = 3
  allocation_id = aws_eip.lb[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "gw NAT${count.index}"
  }

  # To ensure proper ordering, it is recommended to add an explicit dependency
  # on the Internet Gateway for the VPC.
  depends_on = [aws_internet_gateway.gw]
}

