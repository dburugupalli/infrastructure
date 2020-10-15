# Infrastructure

### AWS Networking Setup

#### Pre-requisite

```
1. Configure aws-cli
```

```
1. Create Virtual Private Cloud (VPC) (Links to an external site.)

2. Create subnets (Links to an external site.) in your VPC. You must create 3 subnets, each in different availability zone in the same region in the same VPC

3. Create Internet Gateway (Links to an external site.) resource and attach the Internet Gateway to the VPC

4. Create a public route table (Links to an external site.). Attach all subnets created above to the route table.

5. Create a public route in the public route table created above with destination CIDR block 0.0.0.0/0 and internet gateway created above as the target.
```

### Terraform

Use Infrastructure as Code to provision and manage any cloud, infrastructure, or service

```
Create networking resources using terraform apply command

Cleanup of networking resources using terraform destroy command.
```

