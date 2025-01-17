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
  //  security_groups=["${aws_security_group.loadBalancer.id}"]
  }

  ingress {
    # cidr_blocks = var.ingressCIDR
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    security_groups=["${aws_security_group.loadBalancer.id}"]

  }

  ingress {
    # cidr_blocks = var.ingressCIDR
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    security_groups=["${aws_security_group.loadBalancer.id}"]
  }

  ingress {
    # cidr_blocks = var.ingressCIDR
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    security_groups=["${aws_security_group.loadBalancer.id}"]

  }

  # allow egress of all ports
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
} # end resource

data "aws_acm_certificate" "ssl_certificate" {
  domain   = "${var.aws_profile}.${var.dns_record}"
  statuses = ["ISSUED"]
}

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
resource "aws_db_parameter_group" "default" {
  name   = "rds-mysql"
  family = "mysql5.7"

  parameter {
    name  = "performance_schema"
    value = true
    apply_method = "pending-reboot"
  }
}

resource "aws_db_instance" "db" {
  allocated_storage      = "20"
  storage_type           = "gp2"
  engine                 = "mysql"
  engine_version         = "5.7.22"
  instance_class         = "db.t2.small"
  name                   = "${var.rdsDBName}"
  username               = "${var.dbusername}"
  password               = "${var.dbpassword}"
  skip_final_snapshot    = true
  db_subnet_group_name   = "${aws_db_subnet_group.db-subnet.name}"
  vpc_security_group_ids = ["${aws_security_group.database.id}"]
  parameter_group_name = "${aws_db_parameter_group.default.name}"
  storage_encrypted = true
}



resource "aws_security_group" "loadBalancer" {
  name   = "lbsecuritygroup"
  vpc_id = "${aws_vpc.VPC.id}"
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
    ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name        = "lbsecuritygroup"
  }
}



resource "aws_launch_configuration" "asg_launch_config" {
  name                   = "asg_launch_config"
   image_id                     = data.aws_ami.ami.id
  instance_type          = "t2.micro"
  security_groups        = ["${aws_security_group.My_VPC_Security_Group.id}"]
  # subnet_id              = "${aws_subnet.test_VPC_Subnet[0].id}"
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
               sudo echo export "sns_topic_arn"="${aws_sns_topic.sns_answer.arn}" >> /etc/environment
               sudo echo export "website_url"="${var.website_url}" >> /etc/environment
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


resource "aws_iam_policy" "ghactions-Lambda" {
  name = "ghactions_s3_policy_lambda"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "lambda:*"
        ],
        
      "Resource": "arn:aws:lambda:${var.aws_region}:${var.aws_account_id}:function:${aws_lambda_function.sns_lambda_email.function_name}"
    }
  ]
}
EOF
}

resource "aws_iam_policy" "sns_iam_policy" {
  name = "ec2_iam_policy"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "SNS:Publish"
      ],
      "Resource": "${aws_sns_topic.sns_answer.arn}"
    }
  ]
}
EOF
}


resource "aws_iam_policy" "lambda_policy" {
  name        = "lambda_policy"
  description = "Policy for cloud watch and code deploy"
  policy      = <<EOF
{
   "Version": "2012-10-17",
   "Statement": [
       {
           "Effect": "Allow",
           "Action": [
               "logs:CreateLogGroup",
               "logs:CreateLogStream",
               "logs:PutLogEvents"
           ],
           "Resource": "*"
       },
       {
         "Sid": "LambdaDynamoDBAccess",
         "Effect": "Allow",
         "Action": [
             "dynamodb:GetItem",
             "dynamodb:PutItem",
             "dynamodb:UpdateItem"
         ],
         "Resource": "arn:aws:dynamodb:${var.aws_region}:${var.aws_account_id}:table/csye6225"
       },
       {
         "Sid": "LambdaSESAccess",
         "Effect": "Allow",
         "Action": [
             "ses:VerifyEmailAddress",
             "ses:SendEmail",
             "ses:SendRawEmail"
         ],
         "Resource": "*"
       }
   ]
}
 EOF
}

resource "aws_iam_role" "iam_for_lambda" {
  name = "iam_for_lambda"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

data "aws_iam_policy_document" "sns-topic-policy" {
  policy_id = "__default_policy_ID"

  statement {
    actions = [
      "SNS:Subscribe",
      "SNS:SetTopicAttributes",
      "SNS:RemovePermission",
      "SNS:Receive",
      "SNS:Publish",
      "SNS:ListSubscriptionsByTopic",
      "SNS:GetTopicAttributes",
      "SNS:DeleteTopic",
      "SNS:AddPermission",
    ]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceOwner"

      values = [
        "${var.aws_account_id}",
      ]
    }

    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    resources = [
      "${aws_sns_topic.sns_answer.arn}",
    ]

    sid = "__default_statement_ID"
  }
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
  autoscaling_groups = ["${aws_autoscaling_group.autoscaling.name}"]
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


resource "aws_autoscaling_group" "autoscaling" {
  name                 = "terraform-aws-autoscaling-group"
  launch_configuration = "${aws_launch_configuration.asg_launch_config.name}"
  min_size             = 3
  max_size             = 5
  default_cooldown     = 60
  desired_capacity     = 3
  vpc_zone_identifier = ["${aws_subnet.VPC_Subnet[0].id}"]
  target_group_arns = ["${aws_lb_target_group.albTargetGroup.arn}"]
  tag {
    key                 = "Name"
    value               = "cicd"
    propagate_at_launch = true
  }
}

resource "aws_lb_target_group" "albTargetGroup" {
  name     = "aLoadBalancerTargetGroup"
  port     = "8080"
  protocol = "HTTP"
  vpc_id   = "${aws_vpc.VPC.id}"
  tags = {
    name = "albTargetGroup"
  }
  health_check {
    healthy_threshold   = 3
    unhealthy_threshold = 5
    timeout             = 5
    interval            = 30
    path                = "/healthstatus"
    port                = "8080"
    matcher             = "200"
  }
}

resource "aws_autoscaling_policy" "WebServerScaleUpPolicy" {
  name                   = "WebServerScaleUpPolicy"
  adjustment_type        = "ChangeInCapacity"
  autoscaling_group_name = "${aws_autoscaling_group.autoscaling.name}"
  cooldown               = 60
  scaling_adjustment     = 1
}

resource "aws_autoscaling_policy" "WebServerScaleDownPolicy" {
  name                   = "WebServerScaleDownPolicy"
  adjustment_type        = "ChangeInCapacity"
  autoscaling_group_name = "${aws_autoscaling_group.autoscaling.name}"
  cooldown               = 60
  scaling_adjustment     = -1
}

resource "aws_cloudwatch_metric_alarm" "CPUAlarmLow" {
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  statistic           = "Average"
  period              = "60"
  evaluation_periods  = "1"
  threshold           = "3"
  alarm_name          = "CPUAlarmLow"
  comparison_operator = "LessThanThreshold"
  dimensions = {
    AutoScalingGroupName = "${aws_autoscaling_group.autoscaling.name}"
  }
  alarm_description = "if (CPU < 3%) for 1 minute then Scale-down"
  alarm_actions     = ["${aws_autoscaling_policy.WebServerScaleDownPolicy.arn}"]
}

resource "aws_cloudwatch_metric_alarm" "CPUAlarmHigh" {
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  statistic           = "Average"
  period              = "60"
  evaluation_periods  = "1"
  threshold           = "5"
  alarm_name          = "CPUAlarmHigh"
  comparison_operator = "GreaterThanThreshold"
  dimensions = {
  AutoScalingGroupName = "${aws_autoscaling_group.autoscaling.name}"
  }
  alarm_description = "if (CPU > 5%) for 1 minute then Scale-up"
  alarm_actions     = ["${aws_autoscaling_policy.WebServerScaleUpPolicy.arn}"]
}

resource "aws_lb" "applicationLoadBalancer" {
  name               = "applicationLoadBalancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = ["${aws_security_group.loadBalancer.id}"]
  # count              = "${length(var.subnetCIDR)}"
  subnets            = "${aws_subnet.VPC_Subnet.*.id}"
  ip_address_type    = "ipv4"
  tags = {
    Name        = "applicationLoadBalancer"
  }
}

resource "aws_lb_listener" "webappListener" {
  load_balancer_arn = "${aws_lb.applicationLoadBalancer.arn}"
  port              = "443"
  protocol          = "HTTPS"
  certificate_arn   = "${data.aws_acm_certificate.ssl_certificate.arn}"

  default_action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.albTargetGroup.arn}"
  }
}

data "aws_route53_zone" "selected" {
  name         = "${var.aws_profile}.${var.dns_record}"
  private_zone = false
}

resource "aws_route53_record" "dms-ec2" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = "${data.aws_route53_zone.selected.name}"
  type    = "A"
  # ttl     = "60"
  # records = ["${aws_instance.example.public_ip}"]
  alias {
    name    = "${aws_lb.applicationLoadBalancer.dns_name}"
    zone_id = "${aws_lb.applicationLoadBalancer.zone_id}"
    evaluate_target_health = true
  }
}

resource "aws_iam_user_policy_attachment" "ghactions_lambda_policy_attach" {
  user = "ghactions"
  policy_arn = "${aws_iam_policy.ghactions-Lambda.arn}"
}


resource "aws_sns_topic" "sns_answer" {
  name = "request_email_answer"
}

resource "aws_sns_topic_policy" "sns_answer_policy" {
  arn = "${aws_sns_topic.sns_answer.arn}"
  policy = "${data.aws_iam_policy_document.sns-topic-policy.json}"
}


resource "aws_iam_role_policy_attachment" "sns_ec2" {
  policy_arn = "${aws_iam_policy.sns_iam_policy.arn}"
  role = "${aws_iam_role.role.name}"
}


data "archive_file" "lambda_zip" {
    type          = "zip"
    source_file   = "index.js"
    output_path   = "lambda_function.zip"
}

resource "aws_lambda_function" "sns_lambda_email" {
  filename      = "lambda_function.zip"
  function_name = "lambda_function_name"
  role          = "${aws_iam_role.iam_for_lambda.arn}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  source_code_hash = "${data.archive_file.lambda_zip.output_base64sha256}"
  environment {
    variables = {
      timeToLive = "300"
    }
  }
}

resource "aws_sns_topic_subscription" "lambda" {
  topic_arn = "${aws_sns_topic.sns_answer.arn}"
  protocol  = "lambda"
  endpoint  = "${aws_lambda_function.sns_lambda_email.arn}"
}

resource "aws_lambda_permission" "lambda_permission_sns" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.sns_lambda_email.function_name}"
  principal     = "sns.amazonaws.com"
  source_arn    = "${aws_sns_topic.sns_answer.arn}"
}


resource "aws_iam_role_policy_attachment" "lambda_role_attachement_policy" {
  role       = "${aws_iam_role.iam_for_lambda.name}"
  policy_arn = "${aws_iam_policy.lambda_policy.arn}"
}