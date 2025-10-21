resource "aws_instance" "ansible_server" {
  ami           = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name

  tags = {
    Name = "Ansible-EC2"
  }

  # Optional: provisioner to install Ansible immediately
  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update -y",        # For Ubuntu AMI
      "sudo apt-get install -y ansible"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"           # depends on AMI
      private_key = file("~/.ssh/id_rsa")
      host        = self.public_ip
    }
  }
}
