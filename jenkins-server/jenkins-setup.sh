#!/bin/bash
# ============================================================
# Jenkins Master Setup Script - Terraform + Ansible + Maven + GitHub SSH
# Region: ap-southeast-1
# Purpose: Prepare Jenkins EC2 for full DevOps pipeline
# ============================================================

set -e  # Exit on any error

echo "---- [1] Updating System ----"
sudo apt update -y
sudo apt upgrade -y

echo "---- [2] Installing Java 21, Maven, Git, curl, unzip ----"
sudo apt install -y openjdk-21-jdk maven git curl unzip

echo "---- [3] Installing Terraform ----"
if ! command -v terraform &>/dev/null; then
  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
    sudo tee /etc/apt/sources.list.d/hashicorp.list
  sudo apt update -y
  sudo apt install -y terraform
else
  echo "Terraform already installed"
fi

echo "---- [4] Installing Ansible ----"
sudo apt install -y ansible

echo "---- [5] Installing AWS CLI v2 ----"
if ! command -v aws &>/dev/null; then
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
  unzip -q /tmp/awscliv2.zip -d /tmp
  sudo /tmp/aws/install
else
  echo "AWS CLI already installed"
fi

echo "---- [6A] Configuring Jenkins PEM Key ----"
JENKINS_KEY_NAME="Jenkins-singapore.pem"
if [ -f "/home/ubuntu/$JENKINS_KEY_NAME" ]; then
  echo "Found private key in /home/ubuntu/$JENKINS_KEY_NAME"
  sudo mkdir -p /var/lib/jenkins/.ssh
  sudo cp /home/ubuntu/$JENKINS_KEY_NAME /var/lib/jenkins/.ssh/id_rsa
  sudo chmod 700 /var/lib/jenkins/.ssh
  sudo chmod 400 /var/lib/jenkins/.ssh/id_rsa
  sudo chown -R jenkins:jenkins /var/lib/jenkins/.ssh
else
  echo "ERROR: Private key not found at /home/ubuntu/$JENKINS_KEY_NAME"
  echo "Upload your Jenkins PEM key first!"
  exit 1
fi

echo "---- [6B] Generating GitHub SSH key for Jenkins ----"
sudo -u jenkins bash <<'EOF'
mkdir -p ~/.ssh
cd ~/.ssh

# If key doesn't exist, generate one
if [ ! -f id_rsa ]; then
  echo "Generating new SSH key for GitHub..."
  ssh-keygen -t rsa -b 4096 -C "jenkins@server" -f ~/.ssh/id_rsa -N ""
else
  echo "GitHub SSH key already exists."
fi

chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_rsa
chmod 644 ~/.ssh/id_rsa.pub
EOF

echo "---- [7] Verifying Installations ----"
echo ">>> Java Version"
java -version
echo ">>> Maven Version"
mvn -v
echo ">>> Terraform Version"
terraform -v
echo ">>> Ansible Version"
ansible --version
echo ">>> AWS CLI Version"
aws --version

echo "---- [8] Checking access for Jenkins user ----"
sudo su - jenkins -s /bin/bash -c "
  echo 'Verifying Jenkins environment...'
  java -version
  mvn -v
  terraform -v
  ansible --version
  aws --version
"

echo "---- [9] Display Jenkins GitHub Public Key ----"
echo ""
echo ">>> Copy the below SSH public key and add it to your GitHub account:"
echo "-----------------------------------------------------------"
sudo cat /var/lib/jenkins/.ssh/id_rsa.pub
echo "-----------------------------------------------------------"
echo "👉 Go to GitHub → Settings → SSH and GPG Keys → New SSH key"
echo "   Title: Jenkins Server (Singapore)"
echo "   Paste the above key and Save"
echo ""
echo "---- [10] Setup Complete ----"
echo "✅ Jenkins master environment ready for:"
echo "   - Terraform provisioning"
echo "   - Ansible deployments"
echo "   - Maven build for Java 21 apps"
echo "   - AWS CLI access"
echo "   - GitHub SSH access"
echo "-----------------------------------------------------------"
