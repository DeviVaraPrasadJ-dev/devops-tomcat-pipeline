pipeline {
    agent any

    // -------------------------
    // Parameters
    // -------------------------
    // - ACTION: choice parameter to control the pipeline behavior.
    //   - create-deploy : create infrastructure with Terraform, build WAR, and deploy with Ansible.
    //   - destroy        : run terraform destroy to tear down infrastructure.
    parameters {
        choice(name: 'ACTION',
               choices: ['create-deploy', 'destroy'],
               description: 'Select create-deploy to provision infra and deploy the app; select destroy to tear down infra.')
    }

    environment {
        // Credentials and folder names used across the pipeline:
        // AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY: Jenkins credentials referenced by id.
        // KEY_NAME: name of keypair used for EC2 created by Terraform.
        // TF_DIR: directory with Terraform code (relative to workspace).
        // ANSIBLE_DIR: directory with Ansible playbooks (relative to workspace).
        // JAVA_APP_DIR: directory containing the Java app (maven project).
        AWS_ACCESS_KEY_ID     = credentials('aws-access-key-id')
        AWS_SECRET_ACCESS_KEY = credentials('aws-secret-access-key')
        KEY_NAME              = 'Jenkins-singapore'
        TF_DIR                = 'terraform-infra'
        ANSIBLE_DIR           = 'ansible-playbooks'
        JAVA_APP_DIR          = 'javaapp-tomcat'
    }

    stages {

        /* =========================================================================
         * Stage: Checkout
         *
         * Purpose:
         *  - Pulls the pipeline, Terraform, Ansible, and Java app code from Git.
         *
         * Key lines:
         *  - git branch: 'main', url: 'git@github.com:...'
         *    -> Clones the repo and checks out the specified branch. Jenkins will
         *       run the rest of the pipeline using files in the workspace.
         * ========================================================================= */
        stage('Checkout') {
            steps {
                // This clones the repo into the Jenkins workspace.
                git branch: 'main', url: 'git@github.com:DeviVaraPrasadJ-dev/devops-tomcat-pipeline.git'
            }
        }

        /* =========================================================================
         * Stage: Build WAR with Maven
         *
         * Purpose:
         *  - Builds the Java webapp producing a WAR that will later be deployed.
         *
         * Condition:
         *  - Only runs when ACTION == 'create-deploy' (we do not build for destroy).
         *
         * Key lines:
         *  - dir(JAVA_APP_DIR) { sh 'mvn clean package' }
         *    -> Changes working directory into the Java project folder and runs
         *       Maven to clean + package (produces target/*.war).
         *
         * Notes:
         *  - ${JAVA_APP_DIR} is defined in environment at the top and points
         *    to the project folder in the workspace.
         * ========================================================================= */
        stage('Build WAR with Maven') {
            when { expression { return params.ACTION == 'create-deploy' } }
            steps {
                dir(JAVA_APP_DIR) {
                    sh 'mvn clean package'
                }
            }
        }

        /* =========================================================================
         * Stage: Terraform Init
         *
         * Purpose:
         *  - Initializes the Terraform workspace (downloads providers, creates state).
         *
         * Condition:
         *  - Required for both create-deploy and destroy because Terraform must
         *    be initialized before apply/destroy.
         *
         * Key lines:
         *  - dir(TF_DIR) { withEnv([...]) { sh 'terraform init' } }
         *    -> Runs terraform init inside the Terraform folder. withEnv injects
         *       AWS credentials into the environment for Terraform to use.
         *
         * Notes:
         *  - You provide AWS creds via Jenkins credentials IDs (see environment).
         * ========================================================================= */
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

        /* =========================================================================
         * Stage: Terraform Apply (Provision)
         *
         * Purpose:
         *  - Creates infrastructure (EC2, VPC, etc.) using terraform apply.
         *
         * Condition:
         *  - Only runs when ACTION == 'create-deploy'.
         *
         * Key lines:
         *  - terraform apply -auto-approve -var 'key_name=${KEY_NAME}'
         *    -> Applies plan immediately (-auto-approve). Passes the AWS key name
         *       variable to Terraform. Remove -auto-approve if you want manual approval.
         * ========================================================================= */
        stage('Terraform Apply') {
            when { expression { return params.ACTION == 'create-deploy' } }
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

        /* =========================================================================
         * Stage: Destroy Infrastructure
         *
         * Purpose:
         *  - Destroys all Terraform-managed infrastructure via terraform destroy.
         *
         * Condition:
         *  - Only runs when ACTION == 'destroy'.
         *
         * Key lines:
         *  - terraform destroy -auto-approve -var 'key_name=${KEY_NAME}'
         *    -> Tears down resources immediately. Use with caution: it's destructive.
         *
         * Notes:
         *  - This stage assumes the same TF_DIR and credential configuration as apply.
         * ========================================================================= */
        stage('Destroy Infrastructure') {
            when { expression { return params.ACTION == 'destroy' } }
            steps {
                dir(TF_DIR) {
                    withEnv([
                        "AWS_ACCESS_KEY_ID=${env.AWS_ACCESS_KEY_ID}",
                        "AWS_SECRET_ACCESS_KEY=${env.AWS_SECRET_ACCESS_KEY}"
                    ]) {
                        sh """
                            terraform destroy -auto-approve \
                                -var 'key_name=${KEY_NAME}'
                        """
                    }
                }
            }
        }

        /* =========================================================================
         * Stage: Wait for EC2 and Fetch IP
         *
         * Purpose:
         *  - After apply, fetch the public IP from Terraform outputs and export it
         *    to the pipeline environment as EC2_IP so subsequent steps can use it.
         *
         * Condition:
         *  - Only makes sense for create-deploy (no EC2 exists in destroy).
         *
         * Key lines:
         *  - env.EC2_IP = sh(script: "terraform output -raw public_ip", returnStdout: true).trim()
         *    -> Runs terraform output to read 'public_ip' from the Terraform state and
         *       stores it in the pipeline environment variable EC2_IP for later use.
         * ========================================================================= */
        stage('Wait for EC2 and Fetch IP') {
            when { expression { return params.ACTION == 'create-deploy' } }
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

        /* =========================================================================
         * Stage: Deploy Tomcat & WAR using Ansible
         *
         * Purpose:
         *  - Uses the Ansible playbook to install Tomcat and deploy the WAR onto the
         *    EC2 instance created by Terraform.
         *
         * Condition:
         *  - Runs only for create-deploy.
         *
         * Key lines explained:
         *  - withCredentials([sshUserPrivateKey(...)]):
         *      -> Fetches SSH private key from Jenkins credentials store and exposes
         *         it in the environment as ${SSH_KEY}. It ensures the pipeline can
         *         SSH into the EC2 instance.
         *
         *  - chmod 600 ${SSH_KEY}
         *      -> Ensures the SSH key file has secure permissions required by SSH.
         *
         *  - until ssh -o StrictHostKeyChecking=no -o BatchMode=yes -i ${SSH_KEY} ubuntu@${EC2_IP} 'echo ok' ...
         *      -> Polls the EC2 instance until SSH is reachable. The flags:
         *         - StrictHostKeyChecking=no avoids interactive host key prompts.
         *         - BatchMode=yes makes SSH fail rather than prompt for passwords.
         *
         *  - echo "... > inventory.ini"
         *      -> Writes a minimal Ansible inventory that points to the EC2 IP and
         *         instructs Ansible to use the provided private key and python3
         *         interpreter on the remote host.
         *
         *  - ansible-playbook -i inventory.ini deploy-tomcat.yaml --extra-vars "war_source_path=... war_dest_path=..." --ssh-extra-args='-o StrictHostKeyChecking=no'
         *      -> Runs the Ansible playbook:
         *         - -i inventory.ini : use our temporary inventory
         *         - --extra-vars : override role/default vars (absolute path to the WAR on the Jenkins agent and destination path on remote)
         *         - --ssh-extra-args : pass extra ssh args to Ansible to avoid host key prompts
         *
         * Notes:
         *  - ${WORKSPACE} refers to the Jenkins workspace for the job; it is used
         *    to point at the built WAR artifact on the controller.
         * ========================================================================= */
        stage('Deploy Tomcat & WAR using Ansible') {
            when { expression { return params.ACTION == 'create-deploy' } }
            steps {
                withCredentials([sshUserPrivateKey(credentialsId: 'Jenkins-singapore', keyFileVariable: 'SSH_KEY', usernameVariable: 'SSH_USER')]) {
                    dir("${ANSIBLE_DIR}") {
                        sh '''
                          set -eux

                          chmod 600 ${SSH_KEY}

                          until ssh -o StrictHostKeyChecking=no -o BatchMode=yes -i ${SSH_KEY} ubuntu@${EC2_IP} 'echo ok' 2>/dev/null; do
                            echo "Waiting for SSH on ${EC2_IP}..."
                            sleep 5
                          done

                          echo "${EC2_IP} ansible_user=ubuntu ansible_ssh_private_key_file=${SSH_KEY} ansible_python_interpreter=/usr/bin/python3" > inventory.ini

                          ansible-playbook -i inventory.ini deploy-tomcat.yaml \
                            --extra-vars "war_source_path=${WORKSPACE}/javaapp-tomcat/target/artisantek-app.war war_dest_path=/opt/apache-tomcat-9.0.110/webapps/artisantek-app.war" \
                            --ssh-extra-args='-o StrictHostKeyChecking=no'
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
