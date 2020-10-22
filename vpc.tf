resource "aws_vpc" "VPC" {
  cidr_block           = var.vpcCIDR
  instance_tenancy     = var.instanceTenancy
  enable_dns_support   = var.dnsSupport
  enable_dns_hostnames = var.dnsHostNames
  tags = {
    Name = "aws-vpc"
  }
}

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

resource "aws_db_subnet_group" "db-subnet" {
  name       = "test-group"
  subnet_ids = "${aws_subnet.VPC_Subnet.*.id}"
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

data "aws_ami" "ami" {
  most_recent = true
  owners      = ["${var.id}"]
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

resource "aws_s3_bucket" "my_s3_bucket_resource" {
  bucket        = "webapp.dinakarasaisantosh.burugupalli"
  force_destroy = true
  acl           = "private"
  versioning {
    enabled = true
  }
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "aws:kms"
      }
    }
  }
  lifecycle_rule {
    enabled = true
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }
}

resource "aws_iam_role" "role" {
  name = "test-role"

  assume_role_policy = <<-EOF
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Action": "sts:AssumeRole",
          "Principal": {
            "Service": "ec2.amazonaws.com"
          },
          "Effect": "Allow",
          "Sid": ""
        }
      ]
    }
EOF
}

resource "aws_iam_policy" "policy" {
  name        = "test-policy"
  description = "A test policy"

  policy = <<EOF
{
  "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
               "s3:Get*",
        "s3:List*",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:DeleteObjectVersion"
            ],
            "Effect": "Allow",
            "Resource": [
                "arn:aws:s3:::webapp.dinakarasaisantosh.burugupalli",
                "arn:aws:s3:::webapp.dinakarasaisantosh.burugupalli/*"
            ]
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "test-attach" {
  role       = aws_iam_role.role.name
  policy_arn = aws_iam_policy.policy.arn
}

resource "aws_iam_instance_profile" "test_profile" {
  name = "test_profile"
  role = aws_iam_role.role.name
}

resource "aws_security_group" "My_VPC_Security_Group" {
  vpc_id      = aws_vpc.VPC.id
  name        = "My VPC Security Group"
  description = "My VPC Security Group"
  # allow ingress of port 22
  ingress {
    cidr_blocks = var.ingressCIDR
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
  }

  ingress {
    cidr_blocks = var.ingressCIDR
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
  }

  ingress {
    cidr_blocks = var.ingressCIDR
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
  }

  ingress {
    cidr_blocks = var.ingressCIDR
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
  }

  # allow egress of all ports
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
} # end resource


# Database security group
resource "aws_security_group" "database" {
  name   = "database_security_group"
  vpc_id = aws_vpc.VPC.id
  tags = {
    Name        = "Database Security Group"
    Environment = "${var.aws_profile}"
  }
}

resource "aws_security_group_rule" "database" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = "${aws_security_group.My_VPC_Security_Group.id}"
  security_group_id        = "${aws_security_group.database.id}"
}

resource "aws_db_instance" "db" {
  allocated_storage      = "20"
  storage_type           = "gp2"
  engine                 = "mysql"
  engine_version         = "5.7.22"
  instance_class         = "db.t2.micro"
  name                   = "${var.rdsDBName}"
  username               = "${var.dbusername}"
  password               = "${var.dbpassword}"
  skip_final_snapshot    = true
  db_subnet_group_name   = "${aws_db_subnet_group.db-subnet.name}"
  vpc_security_group_ids = ["${aws_security_group.database.id}"]
}

resource "aws_instance" "example" {
  ami                    = data.aws_ami.ami.id
  instance_type          = "t2.micro"
  vpc_security_group_ids = ["${aws_security_group.My_VPC_Security_Group.id}"]
  subnet_id              = "${aws_subnet.VPC_Subnet[0].id}"
  key_name               = "${var.ec2_key}"
  iam_instance_profile   = "${aws_iam_instance_profile.test_profile.name}"
  user_data              = <<-EOF
               #!/bin/bash
               sudo echo export "Bucketname=${aws_s3_bucket.my_s3_bucket_resource.bucket}" >> /etc/environment
               sudo echo export "DBhost=${aws_db_instance.db.address}" >> /etc/environment
               sudo echo export "DBendpoint=${aws_db_instance.db.endpoint}" >> /etc/environment
               sudo echo export "DBname=${var.rdsDBName}" >> /etc/environment
               sudo echo export "DBusername=${aws_db_instance.db.username}" >> /etc/environment
               sudo echo export "DBpassword=${aws_db_instance.db.password}" >> /etc/environment
               sudo echo export "Region=${var.aws_region}" >> /etc/environment 
               EOF
  root_block_device {
    volume_type           = "gp2"
    volume_size           = 20
    delete_on_termination = true
  }
}

resource "aws_dynamodb_table" "dynamodb-table" {
  name           = "csye6225"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }
  tags = {
    Name = "csye6225"
  }
}
