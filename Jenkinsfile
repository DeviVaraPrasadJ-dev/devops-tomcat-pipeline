pipeline {
    agent any

    environment {
        AWS_ACCESS_KEY_ID     = credentials('aws-access-key-id')
        AWS_SECRET_ACCESS_KEY = credentials('aws-secret-access-key')
        KEY_NAME              = 'Jenkins-singapore'
        TF_DIR                = 'terraform-infra'
        ANSIBLE_DIR           = 'ansible-playbooks'
        JAVA_APP_DIR          = 'javaapp-tomcat'
    }

    stages {
        stage('Checkout') {
            steps {
                git branch: 'main', url: 'git@github.com:DeviVaraPrasadJ-dev/devops-tomcat-pipeline.git'
            }
        }

        stage('Build WAR with Maven') {
            steps {
                dir(JAVA_APP_DIR) {
                    sh 'mvn clean package'
                }
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

        stage('Wait for EC2 and Fetch IP') {
            steps {
                dir(TF_DIR) {
                    script {
                        env.EC2_IP = sh(
                            script: "terraform output -raw public_ip",
                            returnStdout: true
                        ).trim()
                        echo "EC2 Public IP: ${env.EC2_IP}"
                    }
                }
            }
        }

        stage('Deploy Tomcat & WAR using Ansible') {
            steps {
                sshagent(['jenkins-singapore']) {  // <-- Use SSH Agent with your credential ID here
                    dir(ANSIBLE_DIR) {
                        sh """
                            ansible-playbook -i ${EC2_IP}, -u ubuntu deploy-tomcat.yml
                        """
                    }
                }
            }
        }
    }

    post {
        always {
            echo ' Pipeline execution complete.'
        }
    }
}
