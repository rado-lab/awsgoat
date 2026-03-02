terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# VPC Config for public access
resource "aws_vpc" "lab-vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name      = "AWS_GOAT_VPC"
    yor_trace = "1cb76da0-41af-41bc-b036-6f42609da000"
  }
}
resource "aws_subnet" "lab-subnet-public-1" {
  vpc_id                  = aws_vpc.lab-vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]
  tags = {
    yor_trace = "fe539ae7-fd7f-4112-9644-bfdf183b7154"
  }
}
resource "aws_internet_gateway" "my_vpc_igw" {
  vpc_id = aws_vpc.lab-vpc.id
  tags = {
    Name      = "My VPC - Internet Gateway"
    yor_trace = "a40e0c88-3d9c-4444-a4e5-746cd8836fa3"
  }
}
resource "aws_route_table" "my_vpc_us_east_1_public_rt" {
  vpc_id = aws_vpc.lab-vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my_vpc_igw.id
  }

  tags = {
    Name      = "Public Subnet Route Table."
    yor_trace = "ed6674d3-8a3b-4574-b603-58f37d1a9cfb"
  }
}

resource "aws_route_table_association" "my_vpc_us_east_1a_public" {
  subnet_id      = aws_subnet.lab-subnet-public-1.id
  route_table_id = aws_route_table.my_vpc_us_east_1_public_rt.id
}
resource "aws_subnet" "lab-subnet-public-1b" {
  vpc_id                  = aws_vpc.lab-vpc.id
  cidr_block              = "10.0.128.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true
  tags = {
    yor_trace = "feb8ee99-9e36-4943-9d42-60f58adbb843"
  }
}
resource "aws_route_table_association" "my_vpc_us_east_1b_public" {
  subnet_id      = aws_subnet.lab-subnet-public-1b.id
  route_table_id = aws_route_table.my_vpc_us_east_1_public_rt.id
}

resource "aws_security_group" "ecs_sg" {
  name        = "ECS-SG"
  description = "SG for cluster created from terraform"
  vpc_id      = aws_vpc.lab-vpc.id

  ingress {
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.load_balancer_security_group.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    yor_trace = "1a04c6d1-daa3-405a-80a9-17d9aa8d874a"
  }
}

# Create Database Subnet Group
# terraform aws db subnet group
resource "aws_db_subnet_group" "database-subnet-group" {
  name        = "database subnets"
  subnet_ids  = [aws_subnet.lab-subnet-public-1.id, aws_subnet.lab-subnet-public-1b.id]
  description = "Subnets for Database Instance"

  tags = {
    Name      = "Database Subnets"
    yor_trace = "0895eb16-3dca-414e-96b6-f4f5e885d1e9"
  }
}

# Create Security Group for the Database
# terraform aws create security group

resource "aws_security_group" "database-security-group" {
  name        = "Database Security Group"
  description = "Enable MYSQL Aurora access on Port 3306"
  vpc_id      = aws_vpc.lab-vpc.id

  ingress {
    description     = "MYSQL/Aurora Access"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = ["${aws_security_group.ecs_sg.id}"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name      = "rds-db-sg"
    yor_trace = "6a237af7-543c-4dd8-8dd1-cb56dd2d2302"
  }

}

# Create Database Instance Restored from DB Snapshots
# terraform aws db instance
resource "aws_db_instance" "database-instance" {
  identifier             = "aws-goat-db"
  allocated_storage      = 10
  instance_class         = "db.t3.micro"
  engine                 = "mysql"
  engine_version         = "8.0"
  username               = "root"
  password               = "T2kVB3zgeN3YbrKS"
  parameter_group_name   = "default.mysql8.0"
  skip_final_snapshot    = true
  availability_zone      = "us-east-1a"
  db_subnet_group_name   = aws_db_subnet_group.database-subnet-group.name
  vpc_security_group_ids = [aws_security_group.database-security-group.id]
  tags = {
    yor_trace = "24cacfff-85d2-4cb2-aec6-98623f1bbc70"
  }
}



resource "aws_security_group" "load_balancer_security_group" {
  name        = "Load-Balancer-SG"
  description = "SG for load balancer created from terraform"
  vpc_id      = aws_vpc.lab-vpc.id

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
    Name      = "aws-goat-m2-sg"
    yor_trace = "43e46c5f-d82a-4e0e-8b19-fe2c36d0a56e"
  }
}



resource "aws_iam_role" "ecs-instance-role" {
  name                 = "ecs-instance-role"
  path                 = "/"
  permissions_boundary = aws_iam_policy.instance_boundary_policy.arn
  assume_role_policy = jsonencode({
    "Version" : "2008-10-17",
    "Statement" : [
      {
        "Sid" : "",
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "ec2.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })
  tags = {
    yor_trace = "4fe74ed9-cfd1-4dda-a762-c07b5610d9b9"
  }
}


resource "aws_iam_role_policy_attachment" "ecs-instance-role-attachment-1" {
  role       = aws_iam_role.ecs-instance-role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}
resource "aws_iam_role_policy_attachment" "ecs-instance-role-attachment-2" {
  role       = aws_iam_role.ecs-instance-role.name
  policy_arn = "arn:aws:iam::aws:policy/IAMFullAccess"
}

resource "aws_iam_role_policy_attachment" "ecs-instance-role-attachment-3" {
  role       = aws_iam_role.ecs-instance-role.name
  policy_arn = aws_iam_policy.ecs_instance_policy.arn
}

resource "aws_iam_policy" "ecs_instance_policy" {
  name = "aws-goat-instance-policy"
  policy = jsonencode({
    "Statement" : [
      {
        "Action" : [
          "ssm:*",
          "ssmmessages:*",
          "ec2:RunInstances",
          "ec2:Describe*"
        ],
        "Effect" : "Allow",
        "Resource" : "*",
        "Sid" : "Pol1"
      }
    ],
    "Version" : "2012-10-17"
  })
  tags = {
    yor_trace = "1d4cd99f-ed7e-4966-851f-ad579afeeeb8"
  }
}

resource "aws_iam_policy" "instance_boundary_policy" {
  name = "aws-goat-instance-boundary-policy"
  policy = jsonencode({
    "Statement" : [
      {
        "Action" : [
          "iam:List*",
          "iam:Get*",
          "iam:PassRole",
          "iam:PutRole*",
          "ssm:*",
          "ssmmessages:*",
          "ec2:RunInstances",
          "ec2:Describe*",
          "ecs:*",
          "ecr:*",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Effect" : "Allow",
        "Resource" : "*",
        "Sid" : "Pol1"
      }
    ],
    "Version" : "2012-10-17"
  })
  tags = {
    yor_trace = "6ea410b7-ff7b-4dac-9daa-c2513cb93454"
  }
}

resource "aws_iam_instance_profile" "ec2-deployer-profile" {
  name = "ec2Deployer"
  path = "/"
  role = aws_iam_role.ec2-deployer-role.id
  tags = {
    yor_trace = "4150b741-efff-4b2b-b10b-8d68f4672550"
  }
}
resource "aws_iam_role" "ec2-deployer-role" {
  name = "ec2Deployer-role"
  path = "/"
  assume_role_policy = jsonencode({
    "Version" : "2008-10-17",
    "Statement" : [
      {
        "Sid" : "",
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "ec2.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })
  tags = {
    yor_trace = "ba297db6-5e6a-411b-bc93-9a486fd087e8"
  }
}

resource "aws_iam_policy" "ec2_deployer_admin_policy" {
  name = "ec2DeployerAdmin-policy"
  policy = jsonencode({
    "Statement" : [
      {
        "Action" : [
          "*"
        ],
        "Effect" : "Allow",
        "Resource" : "*",
        "Sid" : "Policy1"
      }
    ],
    "Version" : "2012-10-17"
  })
  tags = {
    yor_trace = "c603ee5d-2f89-4257-9591-0639c2d84119"
  }
}

resource "aws_iam_role_policy_attachment" "ec2-deployer-role-attachment" {
  role       = aws_iam_role.ec2-deployer-role.name
  policy_arn = aws_iam_policy.ec2_deployer_admin_policy.arn
}

resource "aws_iam_instance_profile" "ecs-instance-profile" {
  name = "ecs-instance-profile"
  path = "/"
  role = aws_iam_role.ecs-instance-role.id
  tags = {
    yor_trace = "b0071cec-fb1c-4f0d-9765-388a56be51e6"
  }
}
resource "aws_iam_role" "ecs-task-role" {
  name = "ecs-task-role"
  path = "/"
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "",
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "ecs-tasks.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
    }
  )
  tags = {
    yor_trace = "fbf1fa13-bb05-4b1e-a0a3-15a7e70215a1"
  }
}

resource "aws_iam_role_policy_attachment" "ecs-task-role-attachment" {
  role       = aws_iam_role.ecs-task-role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
resource "aws_iam_role_policy_attachment" "ecs-task-role-attachment-2" {
  role       = aws_iam_role.ecs-task-role.name
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
}

resource "aws_iam_role_policy_attachment" "ecs-instance-role-attachment-ssm" {
  role       = aws_iam_role.ecs-instance-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}


data "aws_ami" "ecs_optimized_ami" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-2.0.202*-x86_64-ebs"]
  }
}


resource "aws_launch_template" "ecs_launch_template" {
  name_prefix   = "ecs-launch-template-"
  image_id      = data.aws_ami.ecs_optimized_ami.id
  instance_type = "t2.micro"

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs-instance-profile.name
  }

  vpc_security_group_ids = [aws_security_group.ecs_sg.id]
  user_data              = base64encode(data.template_file.user_data.rendered)
  tags = {
    yor_trace = "37b5c7f9-f33c-4536-a9b0-52e3557faf83"
  }
}

resource "aws_autoscaling_group" "ecs_asg" {
  name                = "ECS-lab-asg"
  vpc_zone_identifier = [aws_subnet.lab-subnet-public-1.id]
  desired_capacity    = 1
  min_size            = 0
  max_size            = 1

  launch_template {
    id      = aws_launch_template.ecs_launch_template.id
    version = "$Latest"
  }
}


resource "aws_ecs_cluster" "cluster" {
  name = "ecs-lab-cluster"

  tags = {
    name      = "ecs-cluster-name"
    yor_trace = "58bcff11-e42c-4247-8a11-18034d29d014"
  }
}

data "template_file" "user_data" {
  template = file("${path.module}/resources/ecs/user_data.tpl")
}

resource "aws_ecs_task_definition" "task_definition" {
  container_definitions    = data.template_file.task_definition_json.rendered
  family                   = "ECS-Lab-Task-definition"
  network_mode             = "bridge"
  memory                   = "512"
  cpu                      = "512"
  requires_compatibilities = ["EC2"]
  task_role_arn            = aws_iam_role.ecs-task-role.arn

  pid_mode = "host"
  volume {
    name      = "modules"
    host_path = "/lib/modules"
  }
  volume {
    name      = "kernels"
    host_path = "/usr/src/kernels"
  }
  tags = {
    yor_trace = "b38eb65e-b63b-42b7-985b-fdb3a3df090f"
  }
}

data "template_file" "task_definition_json" {
  template = file("${path.module}/resources/ecs/task_definition.json")
  depends_on = [
    null_resource.rds_endpoint
  ]
}



resource "aws_ecs_service" "worker" {
  name                              = "ecs_service_worker"
  cluster                           = aws_ecs_cluster.cluster.id
  task_definition                   = aws_ecs_task_definition.task_definition.arn
  desired_count                     = 1
  health_check_grace_period_seconds = 2147483647

  load_balancer {
    target_group_arn = aws_lb_target_group.target_group.arn
    container_name   = "aws-goat-m2"
    container_port   = 80
  }
  depends_on = [aws_lb_listener.listener]
  tags = {
    yor_trace = "b10c81c1-f7ea-499e-9352-69e10478c18b"
  }
}

resource "aws_alb" "application_load_balancer" {
  name               = "aws-goat-m2-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = [aws_subnet.lab-subnet-public-1.id, aws_subnet.lab-subnet-public-1b.id]
  security_groups    = [aws_security_group.load_balancer_security_group.id]

  tags = {
    Name      = "aws-goat-m2-alb"
    yor_trace = "6658b22e-8a21-499b-85b8-7fbbab72a279"
  }
}

resource "aws_lb_target_group" "target_group" {
  name        = "aws-goat-m2-tg"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.lab-vpc.id

  tags = {
    Name      = "aws-goat-m2-tg"
    yor_trace = "bbbff612-67e8-46ec-8ebc-9971c268886a"
  }
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_alb.application_load_balancer.id
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target_group.id
  }
}


resource "aws_secretsmanager_secret" "rds_creds" {
  name                    = "RDS_CREDS"
  recovery_window_in_days = 0
  tags = {
    yor_trace = "d43399ed-65b2-4399-aef9-49a12ce2352a"
  }
}

resource "aws_secretsmanager_secret_version" "secret_version" {
  secret_id     = aws_secretsmanager_secret.rds_creds.id
  secret_string = <<EOF
   {
    "username": "root",
    "password": "T2kVB3zgeN3YbrKS"
   }
EOF
}

resource "null_resource" "rds_endpoint" {
  provisioner "local-exec" {
    command     = <<EOF
RDS_URL="${aws_db_instance.database-instance.endpoint}"
RDS_URL=$${RDS_URL::-5}
sed -i "s,RDS_ENDPOINT_VALUE,$RDS_URL,g" ${path.module}/resources/ecs/task_definition.json
EOF
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [
    aws_db_instance.database-instance
  ]
}

resource "null_resource" "cleanup" {
  provisioner "local-exec" {
    command     = <<EOF
RDS_URL="${aws_db_instance.database-instance.endpoint}"
RDS_URL=$${RDS_URL::-5}
sed -i "s,$RDS_URL,RDS_ENDPOINT_VALUE,g" ${path.module}/resources/ecs/task_definition.json
EOF
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [
    null_resource.rds_endpoint, aws_ecs_task_definition.task_definition
  ]
}


/* Creating a S3 Bucket for Terraform state file upload. */
resource "aws_s3_bucket" "bucket_tf_files" {
  bucket        = "do-not-delete-awsgoat-state-files-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags = {
    Name        = "Do not delete Bucket"
    Environment = "Dev"
    yor_trace   = "083bf7f5-cfbf-4dca-9154-fbf28e841c88"
  }
}

output "ad_Target_URL" {
  value = "${aws_alb.application_load_balancer.dns_name}:80/login.php"
}
