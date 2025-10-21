resource "aws_instance" "ansible_server" {
  ami           = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name

  associate_public_ip_address = true

  tags = {
    Name = "Ansible-EC2"
  }

  vpc_security_group_ids = [aws_security_group.allow_ssh.id] # Add this to control SSH access
}

resource "aws_security_group" "allow_ssh" {
  name        = "allow_ssh"
  description = "Allow SSH inbound traffic"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # For testing; restrict to your Jenkins IP in production
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
