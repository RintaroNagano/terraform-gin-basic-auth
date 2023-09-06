provider "aws" {
  region = "ap-northeast-1"
  version = "v2.70.0"
}

# AWSのvpcをterraform内でmainという名前にして作成
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
	Name = "gin-basic-auth"
  }
}

# Subnet
# https://www.terraform.io/docs/providers/aws/r/subnet.html
resource "aws_subnet" "public_1a" {
  # 先程作成したVPCを参照し、そのVPC内にSubnetを立てる
  vpc_id = "${aws_vpc.main.id}"

  # Subnetを作成するAZ
  availability_zone = "ap-northeast-1a"
  cidr_block        = "10.0.1.0/24"

  tags = {
    Name = "gin-basic-auth-public-1a"
  }
}

resource "aws_subnet" "public_1c" {
  # 先程作成したVPCを参照し、そのVPC内にSubnetを立てる
  vpc_id = "${aws_vpc.main.id}"

  # Subnetを作成するAZ
  availability_zone = "ap-northeast-1c"
  cidr_block        = "10.0.2.0/24"

  tags = {
    Name = "gin-basic-auth-public-1c"
  }
}

# Private Subnets
resource "aws_subnet" "private_1a" {
  vpc_id = "${aws_vpc.main.id}"

  availability_zone = "ap-northeast-1a"
  cidr_block        = "10.0.10.0/24"

  tags = {
    Name = "gin-basic-auth-private-1a"
  }
}

resource "aws_subnet" "private_1c" {
  vpc_id = "${aws_vpc.main.id}"

  availability_zone = "ap-northeast-1c"
  cidr_block        = "10.0.11.0/24"

  tags = {
    Name = "gin-basic-auth-private-1c"
  }
}

# Internet Gateway
# https://www.terraform.io/docs/providers/aws/r/internet_gateway.html
resource "aws_internet_gateway" "main" {
  vpc_id = "${aws_vpc.main.id}"

  tags = {
    Name = "gin-basic-auth"
  }
}

# Route Table
# https://www.terraform.io/docs/providers/aws/r/route_table.html
resource "aws_route_table" "public" {
  vpc_id = "${aws_vpc.main.id}"

  tags = {
    Name = "gin-basic-auth"
  }
}

# Route
# https://www.terraform.io/docs/providers/aws/r/route.html
resource "aws_route" "public" {
  destination_cidr_block = "0.0.0.0/0"
  route_table_id         = "${aws_route_table.public.id}"
  gateway_id             = "${aws_internet_gateway.main.id}"
}

# Association
# https://www.terraform.io/docs/providers/aws/r/route_table_association.html
resource "aws_route_table_association" "public_1a" {
  subnet_id      = "${aws_subnet.public_1a.id}"
  route_table_id = "${aws_route_table.public.id}"
}

# SecurityGroup
# https://www.terraform.io/docs/providers/aws/r/security_group.html
resource "aws_security_group" "alb" {
  name        = "gin-basic-auth-alb"
  description = "gin basic auth alb"
  vpc_id      = "${aws_vpc.main.id}"

  # セキュリティグループ内のリソースからインターネットへのアクセスを許可する
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "gin-basic-auth-alb"
  }
}

# SecurityGroup Rule
# https://www.terraform.io/docs/providers/aws/r/security_group.html
resource "aws_security_group_rule" "alb_http" {
  security_group_id = "${aws_security_group.alb.id}"

  # セキュリティグループ内のリソースへインターネットからのアクセスを許可する
  type = "ingress"

  from_port = 80
  to_port   = 80
  protocol  = "tcp"

  cidr_blocks = ["0.0.0.0/0"]
}

# ELB
# https://www.terraform.io/docs/providers/aws/d/lb.html
resource "aws_lb" "main" {
  load_balancer_type = "application"
  name               = "gin-basic-auth"

  security_groups = ["${aws_security_group.alb.id}"]
  subnets         = ["${aws_subnet.public_1a.id}", "${aws_subnet.public_1c.id}"]
}

# Listener
# https://www.terraform.io/docs/providers/aws/r/lb_listener.html
resource "aws_lb_listener" "main" {
  # HTTPでのアクセスを受け付ける
  port              = "80"
  protocol          = "HTTP"

  # ELBのarnを指定します。
  #XXX: arnはAmazon Resource Names の略で、その名の通りリソースを特定するための一意な名前(id)です。
  load_balancer_arn = "${aws_lb.main.arn}"

  # "ok" という固定レスポンスを設定する
  default_action {
    type             = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      status_code  = "200"
      message_body = "ok"
    }
  }
}

resource "aws_cloudwatch_log_group" "log_group" {
  name = "/ecs/gin-basic-auth"
}

# ECSタスク定義関連の変数
variable "aws_account_id" {
  description = "The id of the aws"
  type        = "string"
}

# Task Definition
# https://www.terraform.io/docs/providers/aws/r/ecs_task_definition.html
resource "aws_ecs_task_definition" "main" {
  family = "gin-basic-auth"

  # データプレーンの選択
  requires_compatibilities = ["FARGATE"]

  # ECSタスクが使用可能なリソースの上限
  # タスク内のコンテナはこの上限内に使用するリソースを収める必要があり、メモリが上限に達した場合OOM Killer にタスクがキルされる
  cpu    = "256"
  memory = "512"

  # ECSタスクのネットワークドライバ
  # Fargateを使用する場合は"awsvpc"決め打ち
  network_mode = "awsvpc"

  # タスクロール(s3などの参照をするときの権限)，タスク実行ロール(ECRからのpullするときの権限)の設定
  task_role_arn            = "arn:aws:iam::${var.aws_account_id}:role/ecsTaskExecutionRole"
  execution_role_arn       = "arn:aws:iam::${var.aws_account_id}:role/ecsTaskExecutionRole"

  # 起動するコンテナの定義
  # ファイルの設定を参照。
  container_definitions = "${file("./task-definitions/app.json")}" 
}

# ECS Cluster
# https://www.terraform.io/docs/providers/aws/r/ecs_cluster.html
resource "aws_ecs_cluster" "main" {
  name = "gin-basic-auth"
}

# ALB Target Group
# https://www.terraform.io/docs/providers/aws/r/lb_target_group.html
resource "aws_lb_target_group" "main" {
  name = "gin-basic-auth"

  # ターゲットグループを作成するVPC
  vpc_id = "${aws_vpc.main.id}"

  # ALBからECSタスクのコンテナへトラフィックを振り分ける設定
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"

  # コンテナへの死活監視設定
  health_check = {
    port = 80
    path = "/"
  }
}

# ALB Listener Rule
# https://www.terraform.io/docs/providers/aws/r/lb_listener_rule.html
resource "aws_lb_listener_rule" "main" {
  # ルールを追加するリスナー
  listener_arn = "${aws_lb_listener.main.arn}"

  # 受け取ったトラフィックをターゲットグループへ受け渡す
  action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.main.id}"
  }

  # ターゲットグループへ受け渡すトラフィックの条件
  condition {
    field  = "path-pattern"
    values = ["*"]
  }
}

# SecurityGroup
# https://www.terraform.io/docs/providers/aws/r/security_group.html
resource "aws_security_group" "ecs" {
  name        = "gin-basic-auth-ecs"
  description = "gin basic auth ecs"

  # セキュリティグループを配置するVPC
  vpc_id      = "${aws_vpc.main.id}"

  # セキュリティグループ内のリソースからインターネットへのアクセス許可設定
  # 今回の場合DockerHubへのPullに使用する。
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "gin-basic-auth-ecs"
  }
}

# SecurityGroup Rule
# https://www.terraform.io/docs/providers/aws/r/security_group.html
resource "aws_security_group_rule" "ecs" {
  security_group_id = "${aws_security_group.ecs.id}"

  # インターネットからセキュリティグループ内のリソースへのアクセス許可設定
  type = "ingress"

  # TCPでの80ポートへのアクセスを許可する
  from_port = 80
  to_port   = 80
  protocol  = "tcp"

  # 同一VPC内からのアクセスのみ許可
  cidr_blocks = ["10.0.0.0/16"]
}

# ECS Service
# https://www.terraform.io/docs/providers/aws/r/ecs_service.html
resource "aws_ecs_service" "main" {
  name = "gin-basic-auth"

  # 依存関係の記述。
  # "aws_lb_listener_rule.main" リソースの作成が完了するのを待ってから当該リソースの作成を開始する。
  # "depends_on" は "aws_ecs_service" リソース専用のプロパティではなく、Terraformのシンタックスのため他の"resource"でも使用可能
  depends_on = ["aws_lb_listener_rule.main"]

  # 当該ECSサービスを配置するECSクラスターの指定
  cluster = "${aws_ecs_cluster.main.name}"

  # データプレーンとしてFargateを使用する
  launch_type = "FARGATE"

  # ECSタスクの起動数を定義
  desired_count = "1"

  # 起動するECSタスクのタスク定義
  task_definition = "${aws_ecs_task_definition.main.arn}"

  # ECSタスクへ設定するネットワークの設定
  network_configuration = {
    # タスクの起動を許可するサブネット
    subnets         = ["${aws_subnet.public_1a.id}"]
    # タスクに紐付けるセキュリティグループ
    security_groups = ["${aws_security_group.ecs.id}"]
    # 公開IPの自動割り当て
    assign_public_ip = "true"
  }

  # ECSタスクの起動後に紐付けるELBターゲットグループ
  load_balancer = [
    {
      target_group_arn = "${aws_lb_target_group.main.arn}"
      container_name   = "app"
      container_port   = "80"
    },
  ]
}

# DB関連の変数
variable "database_name" {
  description = "The name of the database"
  type        = "string"
}

variable "database_username" {
  description = "The username for the database"
  type        = "string"
}

variable "database_password" {
  description = "The password for the database"
  type        = "string"
}


# SecurityGroup (RDS) 
resource "aws_security_group" "rds" {
  name        = "gin-basic-auth-db"
  description = "gin basic auth db"

  # セキュリティグループを配置するVPC
  vpc_id      = "${aws_vpc.main.id}"

  # DBへのアクセス許可設定
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # セキュリティグループ内のリソースからインターネットへのアクセス許可設定
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "gin-basic-auth-db"
  }
}

# RDS SubnetGroup
resource "aws_db_subnet_group" "rds" {
  name        = "gin-basic-auth-rds"
  description = "gin-basic-auth-rds"
  subnet_ids  = [
    "${aws_subnet.private_1a.id}","${aws_subnet.private_1c.id}",
  ]

  tags = {
    Name = "gin-basic-auth-rds"
  }
}

# RDS
resource "aws_db_instance" "rds" {
  identifier          = "gin-basic-auth-db"
  engine              = "mysql"
  engine_version      = "8.0.33"
  instance_class      = "db.t2.micro"
  allocated_storage   = 20
  storage_type        = "gp2"
  name                = "${var.database_name}"
  username            = "${var.database_username}"
  password            = "${var.database_password}"
  port                = 3306
  multi_az            = true
  skip_final_snapshot = true

  vpc_security_group_ids = ["${aws_security_group.rds.id}"]
  db_subnet_group_name   = "${aws_db_subnet_group.rds.name}"
}

# ECR
resource "aws_ecr_repository" "ecr" {
  name                 = "gin-basic-auth"
  # 同じタグでプッシュされたときに，上書きせずに残す
  image_tag_mutability = "MUTABLE"

  # プッシュされたときに脆弱性をスキャン
  image_scanning_configuration {
    scan_on_push = true
  }
}

# ECRライフサイクルポリシー
resource "aws_ecr_lifecycle_policy" "ecr-lp" {
  repository = "${aws_ecr_repository.ecr.name}"

  # イメージが500超えたら削除
  policy = <<EOF
  {
    "rules": [
      {
        "rulePriority": 1,
        "description": "Delete images when count is more than 500",
        "selection": {
          "tagStatus": "any",
          "countType": "imageCountMoreThan",
          "countNumber": 500
        },
        "action": {
          "type": "expire"
        }
      }
    ]
  }
EOF
}

