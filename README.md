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

