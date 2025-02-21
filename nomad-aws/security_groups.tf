resource "aws_security_group" "nomad_sg" {
  name        = "${var.basename}-nomad_sg"
  description = "SG for CircleCI Server nomad server/client"
  vpc_id      = var.vpc_id

  ingress {
    description = "Nomad RPC Communication"
    from_port   = 4647
    to_port     = 4647
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow CircleCI Retry with SSH Access"
    from_port   = 64535
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_security_group" "ssh_sg" {
  description = "SG for CircleCI Server Nomad SSH access"
  count       = var.ssh_key != null ? 1 : 0
  name        = "${var.basename}-circleci-nomad_ssh"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
