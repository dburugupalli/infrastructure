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
  bucket        = "${var.bucket_name}"
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
  name = "EC2-CSYE6225"

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
  name        = "WebAppS3"
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
                "arn:aws:s3:::${var.bucket_name}",
                "arn:aws:s3:::${var.bucket_name}/*",
                "arn:aws:s3:::codedeploy.${var.aws_profile}.${var.dns_record}",
                "arn:aws:s3:::codedeploy.${var.aws_profile}.${var.dns_record}/*"
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

resource "aws_iam_role_policy_attachment" "CloudWatchAgentPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  role       = "${aws_iam_role.role.name}"
}


resource "aws_iam_role_policy_attachment" "AmazonSSMManagedInstanceCore" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = "${aws_iam_role.role.name}"
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

  tags = {
    Name = "cicd"
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

resource "aws_iam_role" "code_deploy_role" {
  name               = "CodeDeployServiceRole"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "codedeploy.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_policy" "gh-ec2-ami" {
  name = "gh-ec2-ami"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "ec2:AttachVolume",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:CopyImage",
      "ec2:CreateImage",
      "ec2:CreateKeypair",
      "ec2:CreateSecurityGroup",
      "ec2:CreateSnapshot",
      "ec2:CreateTags",
      "ec2:CreateVolume",
      "ec2:DeleteKeyPair",
      "ec2:DeleteSecurityGroup",
      "ec2:DeleteSnapshot",
      "ec2:DeleteVolume",
      "ec2:DeregisterImage",
      "ec2:DescribeImageAttribute",
      "ec2:DescribeImages",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceStatus",
      "ec2:DescribeRegions",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSnapshots",
      "ec2:DescribeSubnets",
      "ec2:DescribeTags",
      "ec2:DescribeVolumes",
      "ec2:DetachVolume",
      "ec2:GetPasswordData",
      "ec2:ModifyImageAttribute",
      "ec2:ModifyInstanceAttribute",
      "ec2:ModifySnapshotAttribute",
      "ec2:RegisterImage",
      "ec2:RunInstances",
      "ec2:StopInstances",
      "ec2:TerminateInstances"
    ],
    "Resource" : "*"
  }]
}
EOF
}


resource "aws_iam_policy" "GH-Upload-To-S3" {
  name   = "GH_s3_policy"
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
                "arn:aws:s3:::codedeploy.${var.aws_profile}.${var.dns_record}",
                "arn:aws:s3:::codedeploy.${var.aws_profile}.${var.dns_record}/*"
            ]
        }
    ]
}
EOF
}

resource "aws_iam_policy" "GH-Code-Deploy" {
  name   = "GH_codedeploy_policy"
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "codedeploy:RegisterApplicationRevision",
                "codedeploy:GetApplicationRevision"
            ],
            "Resource": [
                "arn:aws:codedeploy:${var.aws_region}:${var.aws_account_id}:application:${aws_codedeploy_app.code_deploy_app.name}"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "codedeploy:CreateDeployment",
                "codedeploy:GetDeployment"
            ],
            "Resource": [
"arn:aws:codedeploy:${var.aws_region}:${var.aws_account_id}:deploymentgroup:${aws_codedeploy_app.code_deploy_app.name}/${aws_codedeploy_deployment_group.code_deploy_deployment_group.deployment_group_name}"            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "codedeploy:GetDeploymentConfig"
            ],
            "Resource": [
                "arn:aws:codedeploy:${var.aws_region}:${var.aws_account_id}:deploymentconfig:CodeDeployDefault.OneAtATime",
                "arn:aws:codedeploy:${var.aws_region}:${var.aws_account_id}:deploymentconfig:CodeDeployDefault.HalfAtATime",
                "arn:aws:codedeploy:${var.aws_region}:${var.aws_account_id}:deploymentconfig:CodeDeployDefault.AllAtOnce"
            ]
        }
    ]
}
EOF
}

resource "aws_iam_user_policy_attachment" "GH_ec2_policy_attach" {
  user       = "ghactions"
  policy_arn = "${aws_iam_policy.gh-ec2-ami.arn}"
}

resource "aws_iam_user_policy_attachment" "GH_s3_policy_attach" {
  user       = "ghactions"
  policy_arn = "${aws_iam_policy.GH-Upload-To-S3.arn}"
}

resource "aws_iam_user_policy_attachment" "GH_codedeploy_policy_attach" {
  user       = "ghactions"
  policy_arn = "${aws_iam_policy.GH-Code-Deploy.arn}"
}


resource "aws_iam_role_policy_attachment" "AWSCodeDeployRole" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
  role       = "${aws_iam_role.code_deploy_role.name}"
}

resource "aws_codedeploy_app" "code_deploy_app" {
  compute_platform = "Server"
  name             = "csye6225-webapp"
}

resource "aws_codedeploy_deployment_group" "code_deploy_deployment_group" {
  app_name               = "${aws_codedeploy_app.code_deploy_app.name}"
  deployment_group_name  = "csye6225-webapp-deployment"
  deployment_config_name = "CodeDeployDefault.AllAtOnce"
  service_role_arn       = "${aws_iam_role.code_deploy_role.arn}"

  ec2_tag_filter {
    key   = "Name"
    type  = "KEY_AND_VALUE"
    value = "cicd"
  }

  deployment_style {
    deployment_option = "WITHOUT_TRAFFIC_CONTROL"
    deployment_type   = "IN_PLACE"
  }

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }

  depends_on = [aws_codedeploy_app.code_deploy_app]
}


data "aws_route53_zone" "selected" {
  name         = "${var.aws_profile}.${var.dns_record}"
  private_zone = false
}

resource "aws_route53_record" "dms-ec2" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = "api.${data.aws_route53_zone.selected.name}"
  type    = "A"
  ttl     = "60"
  records = ["${aws_instance.example.public_ip}"]
}