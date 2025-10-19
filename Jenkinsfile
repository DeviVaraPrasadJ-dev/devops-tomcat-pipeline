pipeline {
    agent any

    environment {
        AWS_ACCESS_KEY_ID     = credentials('aws-access-key-id')
        AWS_SECRET_ACCESS_KEY = credentials('aws-secret-access-key')
        KEY_NAME              = 'Jenkins-singapore'   // Your AWS key pair
        PRIVATE_KEY_PATH      = '/var/lib/jenkins/.ssh/id_rsa'
        TF_DIR                = 'terraform-infra'
        ANSIBLE_DIR           = 'ansible-playbooks'
    }

    stages {
        stage('Checkout') {
            steps {
                git branch: 'main', url: 'git@github.com:DeviVaraPrasadJ-dev/devops-tomcat-pipeline.git'
            }
        }

        stage('Terraform Init') {
            steps {
                dir(TF_DIR) {
                    sh 'terraform init'
                }
            }
        }

        stage('Terraform Apply') {
            steps {
                dir(TF_DIR) {
                    sh """
                        terraform apply -auto-approve \
                            -var 'key_name=${KEY_NAME}'
                    """
                }
            }
        }

        stage('Wait for EC2') {
            steps {
                dir(TF_DIR) {
                    script {
                        // Capture public IP from Terraform output
                        env.EC2_IP = sh(
                            script: "terraform output -raw public_ip",
                            returnStdout: true
                        ).trim()
                        echo "EC2 Public IP: ${env.EC2_IP}"
                    }
                }
            }
        }

        stage('Deploy Tomcat using Ansible') {
            steps {
                dir(ANSIBLE_DIR) {
                    sh """
                        ansible-playbook -i ${EC2_IP}, -u ubuntu --private-key ${PRIVATE_KEY_PATH} deploy-tomcat.yml
                    """
                }
            }
        }
    }

    post {
        always {
            echo 'Pipeline finished.'
        }
    }
}
