# Tomcat CI/CD Pipeline — README

Complete reference for the repository: what it does, how it works, how to run it, and how to troubleshoot.
Written so a developer, DevOps engineer or reviewer can open this and understand the end-to-end flow: Jenkins → Terraform → EC2 → Ansible → Tomcat → WAR.

## Table of contents

1. Project overview  
2. Project structure  
3. High-level flow  
4. Prerequisites  
5. Jenkins pipeline (how to use it & parameters)  
6. Terraform (what it provisions & how)  
7. Ansible role: `tomcat` (what it does)  
8. Important files & templates (examples)  
9. How to run (examples)  
10. Verification & common checks (post-deploy)  
11. Troubleshooting: common errors & fixes  
12. Security & production recommendations  
13. Change log / notes  
14. FAQ

## 1) Project overview

This project automates the full lifecycle for deploying a Java webapp to Tomcat on AWS:

- Jenkins (CI) builds the WAR using Maven.
- Terraform provisions an EC2 instance (or other infra).
- Jenkins reads the EC2 IP from Terraform outputs.
- Jenkins uses Ansible (role `tomcat`) to:
  - install Java and dependencies,
  - install and configure Tomcat,
  - configure Manager / Host Manager access,
  - deploy the WAR to Tomcat,
  - start Tomcat.
- The Jenkins server also acts as the Ansible controller so the WAR is copied from Jenkins workspace to the target EC2.
- The pipeline supports `create-deploy` and `destroy` flows via a parameter.

## 2) Project structure (typical layout)



├─ Jenkinsfile # Main pipeline (param ACTION: create-deploy|destroy)
├─ terraform-infra/ # Terraform configuration (creates EC2 etc)
│ └─ main.tf
├─ ansible-playbooks/
│ ├─ deploy-tomcat.yaml # Playbook that uses roles/tomcat
│ └─ inventory.ini (created runtime by Jenkins)
│ └─ roles/
│ └─ tomcat/
│ ├─ tasks/main.yaml # Role tasks: install/config Tomcat & deploy WAR
│ ├─ defaults/main.yaml # Role default variables
│ ├─ templates/
│ │ └─ tomcat-users.xml.j2
│ └─ handlers/main.yaml # Restart Tomcat handler
└─ javaapp-tomcat/ # Maven Java webapp (generates target/*.war)
└─ pom.xml
> Note: Jenkins runs on one server that also has CLI tools installed (Terraform, Ansible, Maven, Java, AWS CLI, Python). Jenkins triggers Terraform and Ansible from that machine.

## 3) High-level flow

1. Jenkins `Checkout` stage clones the repo.  
2. `Build WAR with Maven` creates `target/artisantek-app.war`.  
3. `Terraform Init` and `Terraform Apply` create the EC2 (create-deploy) or `Terraform Destroy` tears it down (destroy).  
4. `Wait for EC2 and Fetch IP` extracts `public_ip` from Terraform outputs into `EC2_IP`.  
5. `Deploy Tomcat & WAR using Ansible`:
   - Jenkins creates `inventory.ini` with `EC2_IP` and SSH key path.
   - `ansible-playbook` runs with `--extra-vars` to pass WAR path and destination.
   - The `tomcat` role installs Tomcat, configures manager/host-manager, deploys the WAR, sets ownership, and starts Tomcat.

## 4) Prerequisites

On the Jenkins server (control node):
- Jenkins installed and configured.
- Tools installed and available in PATH:
  - Java (JDK), Maven (`mvn`)
  - Terraform CLI
  - Ansible (with Python 3)
  - awscli
- Jenkins credentials configured:
  - AWS credentials (matching id used in Jenkinsfile)
  - SSH private key for the EC2 keypair (credential id e.g. `Jenkins-singapore`)
- Repository must contain:
  - Terraform code that outputs `public_ip` (`terraform output -raw public_ip`)
  - `ansible-playbooks/deploy-tomcat.yaml` which calls `tomcat` role
  - `javaapp-tomcat/` Maven project

On the target EC2:
- No special tools required (Ansible pushes files from controller).
- SSH access for the remote user (e.g., `ubuntu`) as configured by Terraform.

## 5) Jenkins pipeline (Jenkinsfile) — parameters & usage

**Parameter**:
- `ACTION` (choice): `create-deploy` or `destroy`.

**Behavior**:
- `create-deploy`: build WAR, `terraform apply`, fetch IP, run Ansible deploy.
- `destroy`: run `terraform destroy` only (skips build & deploy).

**Important environment variables / credentials**:
- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` — set via Jenkins credentials.
- `KEY_NAME` — EC2 keypair name Terraform uses.
- `TF_DIR`, `ANSIBLE_DIR`, `JAVA_APP_DIR` — directories in repo.
- `withCredentials([sshUserPrivateKey(...)])` exposes `${SSH_KEY}` to the shell so Jenkins can SSH/create inventory.

**How WAR path is passed to Ansible**:
- Jenkins runs `ansible-playbook` with `--extra-vars` supplying `war_source_path` (absolute path in the Jenkins workspace) and `war_dest_path` (remote destination).

## 6) Terraform (what it does)

- Provisions EC2 (and network resources) as defined in `terraform-infra/`.
- Must output `public_ip` so Jenkins can pick it up:
- 
## 7) Ansible role `tomcat` — what it does (detailed)

**Role purpose**: Install Tomcat 9, configure manager/host-manager, deploy WAR, ensure Tomcat runs under `tomcat` user.

**Important variables (examples in `defaults/main.yml`)**:
- `tomcat_version`: "9.0.110"  
- `tomcat_install_dir`: "/opt/apache-tomcat-{{ tomcat_version }}"  
- `tomcat_tarball_url`: tomcat tarball URL  
- `tomcat_manager_user`: "admin"  
- `tomcat_manager_password`: "changeme"  
- `java_package`: "openjdk-21-jdk"  
- `war_source_path`: default path (overridable by `--extra-vars`)  
- `war_dest_path`: default destination in tomcat webapps  
- `tomcat_user` / `tomcat_group`: tomcat

**Primary tasks (summary)**:
1. Update apt cache (`apt`).
2. Install JDK, python3, python3-apt (`apt`).
3. Create `tomcat` group & user (`group`, `user`).
4. Download Tomcat tarball (`get_url`).
5. Extract Tomcat (`unarchive`).
6. Ensure ownership (`file` with `recurse`).
7. Deploy `tomcat-users.xml` via template (`template`).
8. Replace or comment `RemoteAddrValve` in manager/host-manager `context.xml` to allow access (multiline-safe `replace`).
9. Kill any stale process on 8080 (`shell: fuser -k 8080/tcp || true`).
10. Remove exploded app folder if present (`file: state=absent`).
11. Copy WAR from controller to remote (`copy`).
12. Ensure WAR ownership (`file`).
13. Make startup script executable (`file`).
14. Start Tomcat (`shell` nohup or via handler).
15. Wait for Tomcat to listen on 8080 (`wait_for` delegated to remote).
16. Fix ownership of exploded folder if Tomcat expanded the WAR (`file` recurse).
17. Check `/manager/html` is present (`uri` expecting 200 or 401).

**Handlers**:
- `Restart Tomcat` runs shutdown/startup scripts safely (set -eux, shutdown || true, sleep, startup).

## 8) Important files & templates (examples)

`tomcat-users.xml.j2` template example:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users>
<role rolename="manager-gui"/>
<role rolename="admin-gui"/>
<user username="{{ tomcat_manager_user }}" password="{{ tomcat_manager_password }}" roles="manager-gui,admin-gui"/>
</tomcat-users>
Valve replacement regex (DOTALL-safe) used in Ansible replace:
regexp: '(?s)(<Valve\s+className="org\.apache\.catalina\.valves\.RemoteAddrValve".*?allow=")[^"]*(".*?/>)'
replace: '\1.*\2'

## 9) How to run (examples)

From Jenkins: choose ACTION=create-deploy and run the job.
cd terraform-infra
terraform init
terraform apply -auto-approve -var 'key_name=Jenkins-singapore'

# After apply
export EC2_IP=$(terraform output -raw public_ip)

cd ../ansible-playbooks
echo "${EC2_IP} ansible_user=ubuntu ansible_ssh_private_key_file=/path/to/key.pem ansible_python_interpreter=/usr/bin/python3" > inventory.ini

ansible-playbook -i inventory.ini deploy-tomcat.yaml \
  --extra-vars "war_source_path=/path/to/javaapp-tomcat/target/artisantek-app.war war_dest_path=/opt/apache-tomcat-9.0.110/webapps/artisantek-app.war" \
  --ssh-extra-args='-o StrictHostKeyChecking=no'
10) Verification & common checks

Check Tomcat process & port:
sudo ss -tulpn | grep 8080
ps aux | grep java
Check Tomcat logs:

sudo tail -n 200 /opt/apache-tomcat-9.0.110/logs/catalina.out
Check Manager / Host Manager:

http://<EC2_IP>:8080/manager/html → should prompt for login (401) if reachable.

http://<EC2_IP>:8080/host-manager/html

Check context.xml Valve:

sudo sed -n '/<Context/,/<\/Context>/p' /opt/apache-tomcat-9.0.110/webapps/manager/META-INF/context.xml
Expect to see <Valve ... allow=".*" /> or commented Valve.

Check tomcat-users.xml:

sudo cat /opt/apache-tomcat-9.0.110/conf/tomcat-users.xml

11) Troubleshooting: common errors & fixes

A) "Could not find or access '/path/*.war'" in Ansible copy

Cause: war_source_path wrong or wildcard used; copy does not expand controller-side wildcards.

Fix: Use absolute path or change role to use with_fileglob.

B) Permission denied on /opt/apache-tomcat...

Cause: directory owned by tomcat:tomcat.

Fix: use sudo for inspection or ensure Ansible tasks run with become.

C) 403 Access Denied on /manager/html

Causes:

RemoteAddrValve restricts to localhost.

Missing manager-gui role in tomcat-users.xml.

Fix:

Update context.xml Valve via multiline-safe replace or comment it out.

Ensure tomcat-users.xml contains a user with manager-gui.

D) 404 Not Found on /manager/html

Cause: Manager app missing or not deployed.

Fix:

Ensure /opt/apache-tomcat-<version>/webapps contains manager and host-manager.

Remove creates: in unarchive or delete old dir before extracting.

Inspect catalina.out.

E) Address already in use when starting Tomcat

Fix:

sudo ss -tulpn | grep 8080

Stop process: pkill -f org.apache.catalina.startup.Bootstrap or fuser -k 8080/tcp.

Add idempotent Ansible steps to stop any existing Tomcat before starting.

F) YAML syntax error: "mapping values are not allowed"

Cause: wrong indentation or unescaped : in comments/strings.

Fix:

Keep - name: at consistent indentation.

Quote regex strings and escape dots (\.).

12) Security & production recommendations

Do not leave Manager/Host Manager open to the internet. allow=".*" is OK for short-lived CI VMs only.

Prefer whitelisting Jenkins controller IP and admin IPs in the Valve or use Security Groups to restrict port 8080.

Store secrets in Jenkins credentials or Vault; avoid committing credentials to git.

Use a systemd unit for Tomcat in production instead of nohup.

Configure log rotation and forward logs as needed.

13) Change log / notes

Valve editing uses a DOTALL regex to support multi-line Valve elements.

Ansible role uses backup: yes on replace tasks so original files can be inspected.

14) FAQ

Q: Where is the WAR file taken from?
A: From the Jenkins workspace: javaapp-tomcat/target/artisantek-app.war — path passed to Ansible via --extra-vars.

Q: How does Ansible connect to EC2?
A: Jenkins writes inventory.ini:

<EC2_IP> ansible_user=ubuntu ansible_ssh_private_key_file=<SSH_KEY_PATH> ansible_python_interpreter=/usr/bin/python3


Q: Why does Manager still say 403 after adding user?
A: Because RemoteAddrValve may still restrict to localhost. Update context.xml Valve or whitelist IP.

Q: How to make this safer for production?
A: Use Security Groups, systemd for Tomcat, restrict Manager access to admin IPs only.
