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
                    withEnv([
                        "AWS_ACCESS_KEY_ID=${env.AWS_ACCESS_KEY_ID}",
                        "AWS_SECRET_ACCESS_KEY=${env.AWS_SECRET_ACCESS_KEY}"
                    ]) {
                        sh 'terraform init'
                    }
                }
            }
        }

        stage('Terraform Apply') {
            steps {
                dir(TF_DIR) {
                    withEnv([
                        "AWS_ACCESS_KEY_ID=${env.AWS_ACCESS_KEY_ID}",
                        "AWS_SECRET_ACCESS_KEY=${env.AWS_SECRET_ACCESS_KEY}"
                    ]) {
                        sh """
                            terraform apply -auto-approve \
                                -var 'key_name=${KEY_NAME}'
                        """
                    }
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
    withCredentials([sshUserPrivateKey(credentialsId: 'Jenkins-singapore', keyFileVariable: 'SSH_KEY', usernameVariable: 'SSH_USER')]) {
      dir("${ANSIBLE_DIR}") {
        sh '''
          set -eux

          # Make key private
          chmod 600 ${SSH_KEY}

          # Wait until SSH is accepting connections (loop until ssh works)
          until ssh -o StrictHostKeyChecking=no -o BatchMode=yes -i ${SSH_KEY} ubuntu@${EC2_IP} 'echo ok' 2>/dev/null; do
            echo "Waiting for SSH on ${EC2_IP}..."
            sleep 5
          done

          # Create inventory in the ansible directory (so playbook relative paths work)
          echo "${EC2_IP} ansible_user=ubuntu ansible_ssh_private_key_file=${SSH_KEY} ansible_python_interpreter=/usr/bin/python3" > inventory.ini

          # Run the playbook
          ansible-playbook -i inventory.ini deploy-tomcat.yml --ssh-extra-args='-o StrictHostKeyChecking=no'
        '''
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
