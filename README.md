# End-to-End DevSecOps Pipeline on AWS

This project demonstrates the creation of a complete, modern DevSecOps pipeline. The system is designed to automatically build, scan, and deploy a containerized Python Flask application to a Kubernetes cluster on AWS. The entire workflow is orchestrated by GitHub Actions and defined using Infrastructure as Code.

---

## Table of Contents
1.  [Project Overview](#project-overview)
2.  [Core Technologies Used](#core-technologies-used)
3.  [How the Pipeline Works](#how-the-pipeline-works)
4.  [How to Build This Project: A Step-by-Step Guide](#how-to-build-this-project-a-step-by-step-guide)
    *   [Phase 0: Prerequisites and Initial Setup](#phase-0-prerequisites-and-initial-setup)
    *   [Phase 1: Build the Kubernetes Cluster](#phase-1-build-the-kubernetes-cluster)
    *   [Phase 2: Prepare the Application](#phase-2-prepare-the-application)
    *   [Phase 3: Secure and Encrypt Secrets](#phase-3-secure-and-encrypt-secrets)
    *   [Phase 4: Configure GitHub Actions](#phase-4-configure-github-actions)
    *   [Phase 5: Push and Verify](#phase-5-push-and-verify)
5.  [Key Challenges & Lessons Learned](#key-challenges--lessons-learned)

---

## Project Overview

The goal of this project was to implement a fully automated CI/CD (Continuous Integration/Continuous Deployment) pipeline with security integrated at every step (DevSecOps). When a developer pushes new code to the GitHub repository, a series of automated jobs are triggered to ensure the code is secure and functional before deploying it to a live environment.

This project showcases a progression from a basic, AWS-native pipeline (Task 1, now decommissioned) to this more advanced, flexible, and industry-standard workflow using GitHub Actions.

## Core Technologies Used

*   **Cloud Provider:** Amazon Web Services (AWS)
*   **CI/CD Orchestrator:** GitHub Actions
*   **Infrastructure as Code (IaC):** Terraform
*   **Containerization:** Docker & Docker Hub
*   **Container Orchestration:** Amazon EKS (Kubernetes)
*   **IaC Security Scanning:** `tfsec`
*   **Container Security Scanning:** `Trivy`
*   **Secret Management:** Kubernetes Sealed Secrets
*   **Application:** Python (Flask)

## How the Pipeline Works

1.  **Trigger:** A developer pushes a code change to the `main` branch of the GitHub repository.
2.  **Scan Infrastructure:** GitHub Actions starts. The first job uses `tfsec` to scan the Terraform code for any security misconfigurations.
3.  **Build & Scan Container:** The next job builds the Python application into a Docker container. `Trivy` then scans this container for any known vulnerabilities in the OS or its packages.
4.  **Push to Registry:** If the container is deemed secure, it is pushed to a Docker Hub repository.
5.  **Deploy to Kubernetes:** The final job connects to the Amazon EKS cluster. It applies the encrypted secret (which the Sealed Secrets controller decrypts) and then updates the Kubernetes deployment manifest with the new container image, triggering a rolling update of the live application.
6.  **Go Live:** An AWS Load Balancer automatically routes traffic to the newly updated application pods.

---

## How to Build This Project: A Step-by-Step Guide

### Phase 0: Prerequisites and Initial Setup

1.  **Accounts:**
    *   Create an **AWS account** and configure your AWS CLI locally (`aws configure`).
    *   Create a **GitHub account**.
    *   Create a **Docker Hub account** and a new public repository (e.g., `devsecops-app`).

2.  **Install Tools on your local machine (e.g., WSL/Ubuntu):**
    *   Terraform
    *   Docker
    *   `kubectl`
    *   `eksctl`
    *   `kubeseal`

3.  **Clone This Repository:**
    ```bash
    git clone https://github.com/prerna408/devsecops-project.git
    cd devsecops-project
    ```

### Phase 1: Build the Kubernetes Cluster

The application will run on a Kubernetes cluster hosted on AWS EKS.

1.  **Create the EKS Cluster:** Run the following command. This process will take 15-20 minutes. We use `t3.medium` instances to ensure there is enough space for all the Kubernetes components and our application.
    ```bash
    eksctl create cluster \
    --name devsecops-cluster \
    --region <your-aws-region> \
    --nodegroup-name standard-workers \
    --node-type t3.medium \
    --nodes 2
    ```
    *Note: `eksctl` will automatically configure your local `kubectl` to connect to this new cluster.*

2.  **Verify Connection:** Check that you can connect to your new cluster.
    ```bash
    kubectl get nodes
    ```

### Phase 2: Prepare the Application

This involves creating the `Dockerfile` to containerize the app and the Kubernetes manifests to describe how it should run.

1.  **Review the `Dockerfile`:** This file defines how to build the application container. It uses a secure, modern Python base image.
2.  **Review the `k8s/deployment.yaml`:** This file tells Kubernetes how to run your app, including which container image to use (with a placeholder), how many copies to run, and how to expose it to the internet with a Load Balancer.

### Phase 3: Secure and Encrypt Secrets

We will use Sealed Secrets to safely manage the application's password.

1.  **Install the Sealed Secrets Controller:** This one-time command installs the "manager" program into your cluster that can decrypt secrets.
    ```bash
    kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.25.0/controller.yaml
    ```
2.  **Wait and Verify:** Wait a minute for the controller to start, then check that it is running.
    ```bash
    kubectl get pods -n kube-system
    ```
    *(Look for a pod named `sealed-secrets-controller-...` in the `Running` state.)*

3.  **Create and Seal Your Secret:**
    *   First, create a temporary, unencrypted secret file.
        ```bash
        kubectl create secret generic my-app-secret --from-literal=MY_SECRET_PASSWORD='YourSecretPassword123!' --dry-run=client -o yaml > temp-secret.yaml
        ```
    *   Next, use `kubeseal` to encrypt it.
        ```bash
        kubeseal < temp-secret.yaml > k8s/sealed-secret.yaml
        ```
    *   Finally, delete the temporary, unsafe file.
        ```bash
        rm temp-secret.yaml
        ```
    The `k8s/sealed-secret.yaml` file is now safe to commit to GitHub.

### Phase 4: Configure GitHub Actions

The pipeline needs credentials to access AWS and Docker Hub.

1.  **Create a Docker Hub Access Token:**
    *   Go to Docker Hub -> Account Settings -> Security -> New Access Token.
    *   Give it `Read, Write, Delete` permissions.
    *   Copy the token and save it.

2.  **Add Secrets to Your GitHub Repository:**
    *   In your GitHub repo, go to **Settings > Secrets and variables > Actions**.
    *   Click **New repository secret** for each of the following:
        *   `AWS_ACCESS_KEY_ID`: Your AWS access key.
        *   `AWS_SECRET_ACCESS_KEY`: Your AWS secret key.
        *   `AWS_REGION`: The region of your EKS cluster (e.g., `eu-north-1`).
        *   `EKS_CLUSTER_NAME`: The name of your cluster (`devsecops-cluster`).
        *   `DOCKERHUB_USERNAME`: Your Docker Hub username.
        *   `DOCKERHUB_TOKEN`: The Docker Hub access token you just created.

### Phase 5: Push and Verify

Now that everything is set up, you are ready to trigger the pipeline.

1.  **Commit and Push Your Code:**
    ```bash
    git add .
    git commit -m "Initial project setup and configuration"
    git push
    ```

2.  **Watch the Pipeline:**
    *   In your GitHub repository, go to the **"Actions"** tab. You will see your pipeline running.
    *   You can click on the workflow to see each job (`tfsec-scan`, `build-and-push-image`, `deploy-to-eks`) execute in real-time.

3.  **Verify the Live Application:**
    *   After the workflow succeeds, wait a minute or two for the AWS Load Balancer to be created.
    *   Get the public URL of your application with this command:
        ```bash
        kubectl get service devsecops-app-service
        ```
    *   Copy the long DNS name from the `EXTERNAL-IP` column and paste it into your web browser. You should see your running application!

---

## Key Challenges & Lessons Learned

This project was a deep dive into real-world cloud engineering, where the most valuable lessons came from debugging complex failures.

*   **The Server Log is the Ultimate Truth:** Early pipeline failures gave misleading "permissions" errors. The breakthrough came from using SSH to log into the EC2 instance and reading the CodeDeploy logs, which revealed the true, simple error: a mismatch in OS usernames.
*   **Resource Sizing is Critical:** The Kubernetes setup was initially blocked because the `t3.micro` instances were too small to even schedule the necessary tools. Diagnosing this with `kubectl describe pod` and upgrading to `t3.medium` was a critical fix.
*   **CI/CD Workflows are Code:** A persistent deployment bug was traced to the GitHub Actions workflow itself, where a variable was not being passed correctly between jobs. Refactoring the workflow to be more robust (by reconstructing the variable in the final job) solved the issue and highlighted the importance of treating the pipeline itself as a piece of software.

This project was a fantastic experience in building, securing, and debugging a complete, modern software delivery system.