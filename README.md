======================================================================
Tomcat CI/CD Pipeline — README

Complete reference for the repository: what it does, how it works, how to run it, and how to troubleshoot.
Written so a developer, DevOps engineer or reviewer can open this and understand the end-to-end flow: Jenkins -> Terraform -> EC2 -> Ansible -> Tomcat -> WAR.

--Table of contents

Project overview

1. Project structure

2. High-level flow

3. Prerequisites

4. Jenkins pipeline (how to use it & parameters)

5. Terraform (what it provisions & how)

6. Ansible role: tomcat (what it does)

7. Important files & templates (examples)

8. How to run (examples)

9. Verification & common checks (post-deploy)

10. Troubleshooting: common errors & fixes

11. Security & production recommendations

12. Change log / notes

13. FAQ

Project overview
This project automates the full lifecycle for deploying a Java webapp to Tomcat on AWS:

Jenkins (CI) builds the WAR using Maven.

Terraform provisions an EC2 instance (or other infra).

Jenkins reads the EC2 IP from Terraform outputs.

Jenkins uses Ansible (role "tomcat") to:

Install Java and dependencies,

Install and configure Tomcat,

Configure Manager / Host Manager access,

Deploy the WAR to Tomcat,

Start Tomcat.

The Jenkins server also acts as the Ansible controller so the WAR is copied from Jenkins workspace to the target EC2.

The pipeline supports create-deploy and destroy flows via a parameter.

Project structure (typical layout)
.
├─ Jenkinsfile # Main pipeline (param ACTION: create-deploy|destroy)
├─ terraform-infra/ # Terraform configuration (creates EC2 etc)
│ └─ main.tf
├─ ansible-playbooks/
│ ├─ deploy-tomcat.yaml # Playbook that uses roles/tomcat
│ └─ inventory.ini (created at runtime by Jenkins)
│ └─ roles/
│ └─ tomcat/
│ ├─ tasks/main.yaml # Role tasks: install/config Tomcat & deploy WAR
│ ├─ defaults/main.yaml # Role default variables
│ ├─ templates/
│ │ └─ tomcat-users.xml.j2
│ └─ handlers/main.yaml # Restart Tomcat handler
└─ javaapp-tomcat/ # Maven Java webapp (generates target/*.war)
└─ pom.xml

Note: Jenkins runs on one server that also has CLI tools installed (terraform, ansible, maven, java, awscli, python). Jenkins triggers Terraform and Ansible from that machine.

High-level flow

Jenkins "Checkout" stage clones the repo.

"Build WAR with Maven" creates target/artisantek-app.war.

"Terraform Init" and "Terraform Apply" create the EC2 (create-deploy) or "Terraform Destroy" tears it down (destroy).

"Wait for EC2 and Fetch IP" extracts public_ip from Terraform outputs into EC2_IP.

"Deploy Tomcat & WAR using Ansible":

Jenkins creates inventory.ini with EC2_IP and SSH key path.

ansible-playbook is run with --extra-vars to pass the absolute WAR path (war_source_path) and destination (war_dest_path).

The tomcat role installs Tomcat, configures manager/host-manager, deploys the WAR, sets ownership, and starts Tomcat.

Prerequisites
On the Jenkins server (control node):

Jenkins installed and configured.

Tools installed and available in PATH: Java (JDK), Maven (mvn), Terraform CLI, Ansible (with Python 3), awscli.

Jenkins credentials configured:

AWS credentials (matching the ID used in Jenkinsfile)

SSH private key for the EC2 keypair (credential id used: e.g., Jenkins-singapore)

The repository must contain:

Terraform code that outputs public_ip (terraform output -raw public_ip)

ansible-playbooks/deploy-tomcat.yaml which calls the tomcat role

javaapp-tomcat/ Maven project

On the target EC2:

No special tools required (Ansible pushes files from controller).

SSH access for the remote user configured by Terraform (ubuntu or similar).

Jenkins pipeline (Jenkinsfile) — parameters & usage
Parameter:

ACTION (choice): create-deploy or destroy.

Behavior:

create-deploy: build WAR, terraform apply, fetch IP, run Ansible deploy.

destroy: run terraform destroy only (skips build & deploy).

Important environment variables / credentials in the Jenkinsfile:

AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY — set via Jenkins credentials.

KEY_NAME — EC2 keypair name Terraform uses.

TF_DIR, ANSIBLE_DIR, JAVA_APP_DIR — directories in repo for Terraform, Ansible, Java app.

withCredentials([...sshUserPrivateKey...]) exposes SSH private key path (${SSH_KEY}) to the shell, used to write inventory and SSH into EC2.

How the WAR path is passed to Ansible:

Example call in Jenkinsfile:
ansible-playbook -i inventory.ini deploy-tomcat.yaml
--extra-vars "war_source_path=${WORKSPACE}/javaapp-tomcat/target/artisantek-app.war war_dest_path=/opt/apache-tomcat-9.0.110/webapps/artisantek-app.war"

This passes an absolute path of the WAR on the Jenkins controller to Ansible.

Terraform (what it does)

Provisions EC2 (and associated network resources) as defined in terraform-infra/.

Must provide public_ip as an output.

Commands to run manually:
cd terraform-infra
terraform init
terraform apply -auto-approve -var 'key_name=Jenkins-singapore'
terraform destroy -auto-approve -var 'key_name=Jenkins-singapore'

Ansible role "tomcat" — what it does (detailed)
Role purpose: Install Tomcat 9, configure manager/host-manager, deploy WAR, ensure Tomcat runs under tomcat user.

Important variables (defaults/main.yml):

tomcat_version: "9.0.110"

tomcat_install_dir: "/opt/apache-tomcat-{{ tomcat_version }}"

tomcat_tarball_url: URL to tar.gz for that version

tomcat_manager_user: "admin"

tomcat_manager_password: "changeme"

java_package: "openjdk-21-jdk"

war_source_path: default path inside role (overridable)

war_dest_path: default dest inside tomcat_install_dir

tomcat_user: tomcat

tomcat_group: tomcat

Primary tasks summary:

Ensure apt cache up-to-date (apt update)

Install required packages (openjdk, python3, python3-apt)

Create tomcat group (group module)

Create tomcat user (system user, non-login)

Download Tomcat tarball (get_url)

Extract Tomcat to /opt (unarchive)

Ensure tomcat_install_dir owned by tomcat (file with recurse)

Copy tomcat-users.xml (template) to conf/

Replace or comment RemoteAddrValve in manager/host-manager context.xml to allow access (DOTALL-safe replace)

Kill any process using port 8080 (fuser -k)

Remove previously exploded app directory (file state absent) if needed

Deploy WAR from controller using copy

Ensure WAR ownership (file)

Make startup script executable (file mode 0755)

Start Tomcat (nohup startup &)

Wait for port 8080 to be listening (wait_for delegate_to)

Fix ownership of exploded folder if Tomcat expanded the WAR (file recurse)

Check /manager/html is present (uri module accepts status 200 or 401)

Handlers:

Restart Tomcat handler: runs shutdown and startup scripts. Example:
set -eux
{{ tomcat_install_dir }}/bin/shutdown.sh || true
sleep 3
{{ tomcat_install_dir }}/bin/startup.sh

Important files & templates (examples)
tomcat-users.xml.j2 template example:

<?xml version="1.0" encoding="UTF-8"?> <tomcat-users> <role rolename="manager-gui"/> <role rolename="admin-gui"/> <user username="{{ tomcat_manager_user }}" password="{{ tomcat_manager_password }}" roles="manager-gui,admin-gui"/> </tomcat-users>

Valve replacement (DOTALL regex) example used in Ansible replace:
regexp: '(?s)(<Valve\s+className="org.apache.catalina.valves.RemoteAddrValve".?allow=")[^"](".?/>)'
replace: '\1.\2'

How to run (examples)
From Jenkins: choose ACTION=create-deploy and run the job in Jenkins UI.

Manually from controller:

Terraform provision
cd terraform-infra
terraform init
terraform apply -auto-approve -var 'key_name=Jenkins-singapore'

Extract EC2 IP
cd terraform-infra
export EC2_IP=$(terraform output -raw public_ip)

Run Ansible (on controller)
cd ansible-playbooks
echo "${EC2_IP} ansible_user=ubuntu ansible_ssh_private_key_file=/path/to/key.pem ansible_python_interpreter=/usr/bin/python3" > inventory.ini
ansible-playbook -i inventory.ini deploy-tomcat.yaml
--extra-vars "war_source_path=/path/to/javaapp-tomcat/target/artisantek-app.war war_dest_path=/opt/apache-tomcat-9.0.110/webapps/artisantek-app.war"
--ssh-extra-args='-o StrictHostKeyChecking=no'

Verification & common checks
Check Tomcat process & port:
sudo ss -tulpn | grep 8080
ps aux | grep java

Check Tomcat logs:
sudo tail -n 200 /opt/apache-tomcat-9.0.110/logs/catalina.out

Check Manager / Host Manager:
http://<EC2_IP>:8080/manager/html
http://<EC2_IP>:8080/host-manager/html
Expect authentication prompt (401) if reached.

Check context.xml Valve area:
sudo sed -n '/<Context/,/</Context>/p' /opt/apache-tomcat-9.0.110/webapps/manager/META-INF/context.xml
Expect a single Valve line containing allow=".*" or commented Valve.

Check tomcat-users.xml:
sudo cat /opt/apache-tomcat-9.0.110/conf/tomcat-users.xml
Ensure user has manager-gui role.

Troubleshooting: common errors & fixes
A) "Could not find or access '/path/*.war'" in Ansible copy

Cause: war_source_path points to wrong controller path or uses wildcard. "copy" does not expand controller-side wildcards.

Fix: Use absolute path to WAR in --extra-vars or use fileglob in the role.

B) Permission denied inspecting /opt/apache-tomcat...

Cause: Directory owned by tomcat:tomcat.

Fix: Use sudo or chown appropriately. Ansible tasks should run as become to set correct ownership.

C) 403 Access Denied on /manager/html

Causes:

RemoteAddrValve restricts access to localhost in context.xml

Missing or incorrect manager user/roles in tomcat-users.xml

Fix:

Use DOTALL-safe replace to set allow=".*" or comment the Valve

Ensure tomcat-users.xml contains a user with manager-gui role

D) 404 Not Found on /manager/html

Cause: Manager app missing or not deployed

Fix:

Check /opt/apache-tomcat-<version>/webapps contains manager/host-manager

Ensure unarchive task ran or remove creates: to force extraction

Check catalina.out for errors

E) Address already in use: bind on Tomcat startup

Cause: Another process listening on 8080

Fix:

sudo ss -tulpn | grep 8080

stop the process (pkill -f org.apache.catalina.startup.Bootstrap) or fuser -k 8080/tcp

Add idempotent Ansible steps to stop existing Tomcat before starting

F) Ansible YAML syntax error "mapping values are not allowed"

Cause: Wrong indentation or unescaped colon in comments or strings

Fix:

Ensure proper indentation; quote regex strings; place comments cleanly at column 1

Security & production recommendations

Do not leave Manager/Host Manager open to the internet. allow=".*" is OK for short-lived CI test VMs only.

Better: set allow to a safe regex listing Jenkins controller IP and admin IPs, or use Security Groups to restrict access.

Use Jenkins credentials store for secrets; do not commit credentials to git.

Use systemd to manage Tomcat instead of nohup for production.

Configure log rotation and forward logs if needed.

Change log / notes

Valve editing uses a DOTALL regex to handle multi-line Valve blocks.

Ansible role uses backup: yes on replacements so you can inspect original files.

FAQ
Q: Where is the WAR file taken from?
A: From the Jenkins workspace: javaapp-tomcat/target/artisantek-app.war passed to Ansible via --extra-vars.

Q: How does Ansible connect to EC2?
A: Jenkins writes inventory.ini:
<EC2_IP> ansible_user=ubuntu ansible_ssh_private_key_file=<SSH_KEY_PATH> ansible_python_interpreter=/usr/bin/python3

Q: Why does Manager still say 403 after adding user?
A: Because RemoteAddrValve may still restrict access to localhost. Change context.xml Valve or whitelist IP.

Q: How to make this safer for production?
A: Use security groups, systemd for Tomcat, restrict Manager access to admin IPs only.

Contact / Next steps
If you want, the following can be added:

A systemd unit file and Ansible tasks to install it so Tomcat is a proper service.

Replace allow=".*" with templated allowed IPs (pass Jenkins IP and admin IP via vars).

Slack/email notifications in Jenkins pipeline.

Which of these would you like next?

======================================================================
End of plain-text README
