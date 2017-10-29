provider "aws" {
  region = "eu-west-1"
}

variable "server_port" {
  description = "The port for the server"
  default = "8080"
}

output "elb_dns_name" {
  value = "${aws_elb.terraform-example.dns_name}"
}

terraform {
  backend "s3" {
    bucket = "terraform-remote-state-sandbox"
    key    = "terraform.tfstate"
    region = "eu-west-1"
  }
}

resource "aws_security_group" "instance" {
  name = "terraform-example-instance"

  ingress {
    from_port = "${var.server_port}"
    to_port = "${var.server_port}"
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "elb" {
  name = "terraform-example-elb"

  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_launch_configuration" "terraform-example" {
  image_id = "ami-785db401"
  instance_type = "t2.micro"

  user_data = <<-EOF
              #!/bin/bash
              echo "Hello, World" > index.html
              nohup busybox httpd -f -p "${var.server_port}" &
              EOF

  security_groups = ["${aws_security_group.instance.id}"]

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_availability_zones" "all" {}

resource "aws_autoscaling_group" "terraform-example" {
  launch_configuration = "${aws_launch_configuration.terraform-example.id}"
  availability_zones = ["${data.aws_availability_zones.all.names}"]

  min_size = 2
  max_size = 4

  load_balancers = ["${aws_elb.terraform-example.name}"]
  health_check_type = "ELB"

  tag {
    key = "Name"
    value = "terraform-asg-example"
    propagate_at_launch = true
  }
}

resource "aws_elb" "terraform-example" {
  name = "terraform-asg-example"
  security_groups = ["${aws_security_group.elb.id}"]
  availability_zones = ["${data.aws_availability_zones.all.names}"]

  listener {
    lb_port = 80
    lb_protocol = "http"
    instance_port = "${var.server_port}"
    instance_protocol = "http"
  }

  health_check {
    healthy_threshold = 2
    unhealthy_threshold = 2
    timeout = 3
    interval = 30
    target = "HTTP:${var.server_port}/"
  }
}
