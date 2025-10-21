variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-southeast-1"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.medium"
}

variable "ami_id" {
  description = "AMI ID for EC2 instance"
  type        = string
  default     = "ami-0933f1385008d33c4"
}

variable "key_name" {
  description = "Name of the existing SSH key pair"
  type        = string
  default     = "Jenkins-singapore"
}

