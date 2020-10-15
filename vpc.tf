resource "aws_vpc" "VPC" {
  cidr_block           = var.vpcCIDR
  instance_tenancy     = var.instanceTenancy
  enable_dns_support   = var.dnsSupport
  enable_dns_hostnames = var.dnsHostNames
  tags = {
    Name = "aws-vpc"
  }
}

resource "aws_internet_gateway" "VPC_GW" {
  vpc_id = aws_vpc.VPC.id
  tags = {
    Name = "aws-vpc-igw"
  }
}

resource "aws_route_table" "VPC_route_table" {
  vpc_id = aws_vpc.VPC.id
  tags = {
    Name = "aws-vpc-route-table"
  }
}

resource "aws_route" "VPC_internet_access" {
  route_table_id         = aws_route_table.VPC_route_table.id
  destination_cidr_block = var.destinationCIDR
  gateway_id             = aws_internet_gateway.VPC_GW.id
}

resource "aws_route_table_association" "VPC_association" {
  count          = "${length(var.subnetCIDR)}"
  subnet_id      = "${element(aws_subnet.VPC_Subnet.*.id, count.index)}"
  route_table_id = "${aws_route_table.VPC_route_table.id}"
}
