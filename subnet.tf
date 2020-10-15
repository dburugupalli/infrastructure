#Point 2: Create Subnet 
resource "aws_subnet" "VPC_Subnet" {
  count                   = "${length(var.subnetCIDR)}"
  vpc_id                  = "${aws_vpc.VPC.id}"
  cidr_block              = "${element(var.subnetCIDR, count.index)}"
  map_public_ip_on_launch = var.mapPublicIP
  availability_zone       = "${element(var.azs, count.index)}"
  tags = {
    Name = "aws-subnet-${count.index + 1}"
  }
}