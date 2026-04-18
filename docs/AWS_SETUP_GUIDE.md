# ChatProxy Platform — AWS Setup Guide
### For People Without a Technical Background

**What you will end up with:**
- A live website at your own domain (e.g. `www.mychatbot.com`)
- All services running 24/7 on Amazon's cloud servers
- Secure HTTPS connection (the padlock in the browser)
- Automatic backups and monitoring

**Estimated time:** 2–3 hours (most of it is waiting for AWS to finish things)  
**Estimated monthly cost:** $50–100 USD (dev/test), $300–500 USD (production)

---

## Security Concepts (Read This First)

Before running setup, understand these 4 concepts:

1. **Identity vs secret**
  - Identity = who can call AWS APIs (IAM user/role)
  - Secret = sensitive value (password, JWT key, DB URL)
  - Identities should be short-lived (roles when possible), secrets should be stored in **AWS Secrets Manager** only.

2. **Source of truth**
  - `terraform.tfvars` and `.env.example` are templates.
  - Real secrets should only live in Secrets Manager paths like:
    - `/chatproxy/dev/jwt`
    - `/chatproxy/dev/db/accounting`
    - `/chatproxy/dev/mongodb/auth`
    - `/chatproxy/dev/mongodb/proxy`
    - `/chatproxy/dev/ses`

3. **Rotation**
  - Rotation means creating a new secret value, updating running services, and invalidating old credentials.
  - Rotation should happen after any exposure and on a schedule (for example every 30-90 days).

4. **Blast radius**
  - If one secret leaks, impact should be limited.
  - Use different passwords for each system (Mongo auth user, Mongo proxy user, Postgres user, admin user).

---

## Before You Start — What You Will Need

| What | Why |
|------|-----|
| An AWS account | Where everything runs |
| A credit card | AWS charges you monthly |
| An email address | For notifications and account creation |
| This computer with internet access | To run the setup commands |

---

## Part 1 — Create Your AWS Account

> **Already have an AWS account?** Skip to Part 2.

1. Open your web browser and go to: **https://aws.amazon.com**
2. Click the orange **"Create an AWS Account"** button (top right)
3. Fill in:
   - **Email address** — use a real one, you will get important alerts here
   - **Password** — make it strong
   - **AWS account name** — e.g. `MyChatProxy` (this is just a label for you)
4. Click **"Verify email address"** — check your inbox and enter the code
5. Choose **"Personal"** account type
6. Enter your name, phone number, and address
7. Enter your **credit card** — AWS won't charge you unless you use resources
8. Verify your phone number (they will call or SMS you a code)
9. Choose the **"Free tier"** support plan (the free one is fine)
10. Click **"Go to the AWS Management Console"**

> **You are now in the AWS Console.** It looks complicated — don't worry, this guide tells you exactly where to click.

---

## Part 2 — Buy Your Domain Name

A domain name is your website's address (like `mychatbot.com`). You can buy one directly from AWS — no need for a separate company.

### Step 2.1 — Search for a domain

1. In the AWS Console, type **"Route 53"** in the search bar at the top and click it
2. In the left menu, click **"Registered domains"**
3. Click the orange **"Register domain"** button
4. In the search box, type the domain name you want — e.g. `mychatbot`
5. Click **"Search"**

### Step 2.2 — Pick a domain

You will see a list of available names with prices:

| Domain ending | Typical price per year |
|---|---|
| `.com` | ~$14/year — most professional |
| `.net` | ~$11/year |
| `.org` | ~$12/year |
| `.io` | ~$39/year — popular for tech apps |
| `.ai` | ~$60–70/year |

> **Tip:** A `.com` domain looks the most professional and is what people expect.

6. Click **"Add to cart"** next to the domain you want
7. Click **"Continue"**

### Step 2.3 — Register the domain

8. Fill in the **Registrant Contact** form:
   - First name, last name
   - Organization (optional — use your school/company or leave blank)
   - Email, phone number
   - Full address
9. Check **"Enable Privacy Protection"** — this hides your personal details from public lookup (recommended ✅)
10. Check the box: **"I have read and agree to the AWS Domain Name Registration Agreement"**
11. Click **"Complete Order"**
12. AWS will send you a **verification email** — click the link in it within 15 days

> ⏱️ **Wait 10–30 minutes** — AWS will register your domain. You will receive an email when it is ready.

### Step 2.4 — Confirm your Hosted Zone was created

After the domain is registered:
1. In Route 53, click **"Hosted zones"** in the left menu
2. You should see your domain listed (e.g. `mychatbot.com`) — this was created automatically ✅
3. Click on it and note the **Hosted Zone ID** (looks like `Z1234ABCDEF`) — you will need it later

---

## Part 3 — Set Up a Secure Certificate (Free HTTPS)

This gives your site the padlock icon and encrypts all traffic. AWS provides this free.

1. In the AWS Console search bar, type **"Certificate Manager"** and click it
2. Make sure the region in the top right says **"US East (N. Virginia)"** — ACM certificates for CloudFront must be in this region
3. Click **"Request a certificate"**
4. Choose **"Request a public certificate"** → click **"Next"**
5. Under **"Fully qualified domain name"**, type: `*.mychatbot.com` (replace with your domain)
   - Click **"Add another name to this certificate"** and also add: `mychatbot.com` (without the `*`)
   - ⚠️ **Both names are required** — `*.mychatbot.com` covers subdomains, `mychatbot.com` covers the bare domain. Missing either one will cause a browser certificate error.
6. Under **"Validation method"**, choose **"DNS validation"**
7. Click **"Request"**
8. You will see status **"Pending validation"** — click on the certificate
9. Click **"Create records in Route 53"** → click **"Create records"**

> ⏱️ **Wait 5–10 minutes** — the status will change from "Pending validation" to "Issued" ✅

10. Once it says **"Issued"**, copy the **Certificate ARN** (looks like `arn:aws:acm:us-east-1:123456789:certificate/abc-123`) — save it in a text file

### Troubleshooting — Still "Pending Validation" after 30+ minutes?

The "Create records in Route 53" button sometimes fails silently. Fix it via CLI:

**Step 1 — Get the required CNAME values:**
```powershell
aws acm describe-certificate --region us-east-1 `
  --certificate-arn YOUR_CERTIFICATE_ARN `
  --query "Certificate.DomainValidationOptions"
```
Note the `Name` and `Value` under `ResourceRecord`.

**Step 2 — Add the CNAME to Route 53 manually:**
```powershell
aws route53 change-resource-record-sets `
  --hosted-zone-id YOUR_HOSTED_ZONE_ID `
  --change-batch '{\"Changes\":[{\"Action\":\"UPSERT\",\"ResourceRecordSet\":{\"Name\":\"CNAME_NAME_HERE.\",\"Type\":\"CNAME\",\"TTL\":300,\"ResourceRecords\":[{\"Value\":\"CNAME_VALUE_HERE.\"}]}}]}'
```
Replace `CNAME_NAME_HERE` and `CNAME_VALUE_HERE` with the values from Step 1.
The certificate will validate within 5–30 minutes after the record is in place.

---

## Part 4 — Install the Required Tools on Your Computer

You need two programs to deploy the platform. Open **PowerShell as Administrator**:

> **How to open PowerShell as Administrator:**
> Press the Windows key, type `powershell`, right-click **"Windows PowerShell"**, click **"Run as administrator"**, click **"Yes"**

Copy and paste these commands one at a time:

### Install AWS CLI (tool to control AWS from your computer)
```powershell
winget install Amazon.AWSCLI
```
After it installs, close and reopen PowerShell, then verify:
```powershell
aws --version
```
You should see something like: `aws-cli/2.15.0`

### Install Terraform (tool to set up cloud infrastructure)
```powershell
winget install Hashicorp.Terraform
```
After it installs, close and reopen PowerShell, then verify:
```powershell
terraform --version
```
You should see something like: `Terraform v1.7.0`

### Install Docker Desktop (tool to build the app containers)
1. Go to: **https://www.docker.com/products/docker-desktop**
2. Download and install it
3. Start Docker Desktop and wait for the green "Running" status

---

## Part 5 — Connect Your Computer to AWS

You need to create a "key" that lets your computer control your AWS account.

### Step 5.1 — Create an access key in AWS

1. In the AWS Console, click your account name (top right) → **"Security credentials"**
2. Scroll down to **"Access keys"** → click **"Create access key"**
3. Choose **"Command Line Interface (CLI)"**
4. Check the confirmation box → click **"Next"** → click **"Create access key"**
5. **IMPORTANT:** Click **"Download .csv file"** and save it somewhere safe — you can only see this key once!

### Step 5.2 — Configure AWS CLI

Open PowerShell and run:
```powershell
aws configure
```

Enter the values when prompted:
```
AWS Access Key ID:     [paste from your CSV file]
AWS Secret Access Key: [paste from your CSV file]
Default region name:   us-east-1
Default output format: json
```

Test it works:
```powershell
aws sts get-caller-identity
```
You should see your account number — this means your computer is connected to AWS ✅

---

## Part 6 — Navigate to the Project Folder

Open PowerShell and go to the platform folder:
```powershell
cd "C:\Users\$env:USERNAME\Documents\ThankGodForJesusChrist\ThankGodForChatProxyPlatform"
```

---

## Part 7 — Set Up Terraform Storage

Terraform needs a place on AWS to save its work. Run these commands in PowerShell:

> Replace `YOUR-NAME` with something unique — e.g. your initials and today's date like `jk20260323`

```powershell
# Create storage bucket (replace YOUR-NAME)
aws s3 mb s3://chatproxy-tfstate-YOUR-NAME --region us-east-1

# Turn on versioning (keeps history of changes)
aws s3api put-bucket-versioning `
  --bucket chatproxy-tfstate-YOUR-NAME `
  --versioning-configuration Status=Enabled

# Create a lock table (prevents two people editing at once)
aws dynamodb create-table `
  --table-name chatproxy-terraform-locks `
  --attribute-definitions AttributeName=LockID,AttributeType=S `
  --key-schema AttributeName=LockID,KeyType=HASH `
  --billing-mode PAY_PER_REQUEST `
  --region us-east-1
```

If all three commands say `OK` or show JSON output without errors — you are done with this step ✅

---

## Part 8 — Create Environment Configuration Files

You need to create two files that tell Terraform where to save its work and what settings to use.

### Step 8.1 — Create the backend config

Create the file `infra/environments/dev/backend.hcl` with this content  
(replace `chatproxy-tfstate-YOUR-NAME` with the bucket name you used above):

```hcl
bucket         = "chatproxy-tfstate-YOUR-NAME"
key            = "dev/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "chatproxy-terraform-locks"
encrypt        = true
```

### Step 8.2 — Create the Terraform variables file

Create the file `infra/environments/dev/terraform.tfvars` and fill in your details:

```hcl
# Project settings
project     = "chatproxy"
env         = "dev"
aws_region  = "us-east-1"

# Your domain (from Part 2)
domain_name     = "mychatbot.com"          # ← replace with your domain
hosted_zone_id  = "Z1234ABCDEF"            # ← your Hosted Zone ID from Part 2
certificate_arn = "arn:aws:acm:..."        # ← your Certificate ARN from Part 3

# Alert email (where AWS sends alarms)
alarm_email = "you@youremail.com"          # ← your email

# Network settings (leave these as-is for dev)
vpc_cidr           = "10.0.0.0/16"
nat_gateway_count  = 1
availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]

# Scaling settings
min_tasks = 1
max_tasks = 2

# Security
enable_execute_command = true    # allows debug access (fine for dev)
```

---

## Part 9 — Set Up Your Databases

For this repository's current AWS deployment, your databases are:
- **PostgreSQL on AWS RDS** (used by accounting-service)
- **MongoDB on AWS EC2** (used by auth-service and flowise-proxy)

MongoDB Atlas is an optional alternative. Use it only if you intentionally want managed MongoDB outside your AWS VPC.

### Which one should I use?

- Use **AWS-native (recommended for this repo)** if you are following the Terraform modules in `infra/`.
- Use **Atlas (optional)** only if you specifically choose external MongoDB.

### Option A — AWS-native MongoDB (Recommended for this setup)

No separate manual database signup is required for MongoDB.
Terraform provisions a MongoDB EC2 instance and writes connection strings into Secrets Manager:
- `/chatproxy/dev/mongodb/auth`
- `/chatproxy/dev/mongodb/proxy`

You only need to ensure your RDS/accounting secret exists before apply:
- `/chatproxy/dev/db/accounting`

### Option B — MongoDB Atlas (Optional)

If you choose Atlas, follow the steps below and then write those Atlas URLs to Secrets Manager.

### Step 9.1 — Create a free MongoDB Atlas account

1. Go to: **https://www.mongodb.com/cloud/atlas/register**
2. Sign up with your email
3. Choose **"Free"** (M0 cluster) → click **"Create"**
4. Pick **"AWS"** as the cloud provider, region **"us-east-1"**
5. Click **"Create Cluster"** — wait ~3 minutes

### Step 9.2 — Create database users

1. In Atlas, click **"Database Access"** in the left menu
2. Click **"Add New Database User"**
3. Create first user:
   - Username: `auth_user`
   - Password: make a strong password and save it
   - Role: **Read and write to any database**
   - Click **"Add User"**
4. Repeat to create a second user:
   - Username: `proxy_user`
   - Password: make a different strong password and save it

### Step 9.3 — Allow connections from AWS

1. Click **"Network Access"** in the left menu
2. Click **"Add IP Address"**
3. Click **"Allow Access from Anywhere"** (for dev — we can restrict this later)
4. Click **"Confirm"**

### Step 9.4 — Get your connection strings

1. Click **"Database"** in the left menu → click **"Connect"** on your cluster
2. Click **"Drivers"**
3. Copy the connection string — it looks like:
   ```
   mongodb+srv://auth_user:<password>@cluster0.xxxxx.mongodb.net/
   ```
4. Replace `<password>` with your actual password
5. Add the database name at the end:
   - For auth service: `.../auth_db?retryWrites=true&w=majority`
   - For proxy service: `.../flowise_proxy?retryWrites=true&w=majority`

Save both connection strings in a text file.

---

## Part 10 — Store Secrets in AWS

Run these commands in PowerShell to store all sensitive passwords in AWS Secrets Manager. Replace the placeholder values with your real ones.

```powershell
# Generate secure JWT secrets automatically
$ACCESS  = [System.Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
$REFRESH = [System.Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32))

# JWT secrets (used by all services — must be the same)
aws secretsmanager put-secret-value `
  --secret-id /chatproxy/dev/jwt `
  --secret-string "{`"JWT_ACCESS_SECRET`":`"$ACCESS`",`"JWT_REFRESH_SECRET`":`"$REFRESH`"}"

# MongoDB for auth-service (replace the URL with yours from Part 9)
aws secretsmanager put-secret-value `
  --secret-id /chatproxy/dev/mongodb/auth `
  --secret-string '{"MONGODB_URI":"mongodb+srv://auth_user:YOUR_PASS@cluster0.xxxxx.mongodb.net/auth_db?retryWrites=true&w=majority"}'

# MongoDB for flowise-proxy (replace the URL with yours from Part 9)
aws secretsmanager put-secret-value `
  --secret-id /chatproxy/dev/mongodb/proxy `
  --secret-string '{"MONGODB_URL":"mongodb+srv://proxy_user:YOUR_PASS@cluster0.xxxxx.mongodb.net/flowise_proxy?retryWrites=true&w=majority"}'

# Database password for accounting service
aws secretsmanager put-secret-value `
  --secret-id /chatproxy/dev/db/accounting `
  --secret-string '{"DB_USER":"accounting_user","DB_PASSWORD":"CHOOSE_A_STRONG_PASSWORD"}'
```

> **How to set up the SES email secret** — see Part 11 first, then come back to run:
> ```powershell
> aws secretsmanager put-secret-value `
>   --secret-id /chatproxy/dev/ses `
>   --secret-string '{"SMTP_USER":"YOUR_SES_USER","SMTP_PASS":"YOUR_SES_PASS"}'
> ```

---

## Part 11 — Set Up Email Sending (Amazon SES)

The platform sends emails for password resets and account verification.

1. In the AWS Console, search for **"Simple Email Service"** (SES) and click it
2. Click **"Verified identities"** → click **"Create identity"**
3. Choose **"Domain"**, type your domain (e.g. `mychatbot.com`), click **"Create identity"**
4. AWS will show you DNS records to add — click **"Publish DNS records to Route 53"** → click **"Publish records"** ✅
5. Wait ~10 minutes for status to change to **"Verified"**

#### Get SMTP credentials:
6. In the SES left menu, click **"SMTP settings"**
7. Click **"Create SMTP credentials"**
8. Click **"Create"** → **Download credentials** — save them!
9. Go back to Part 10 and run the SES secret command with these credentials

#### Move out of the SES sandbox (important!):
By default, SES can only send to verified emails. To send to anyone:
10. Click **"Account dashboard"** in SES
11. Click **"Request production access"**
12. Fill in the form — explain you are running an educational chatbot platform
13. AWS usually approves within 24–48 hours

---

## Part 12 — Deploy the Secrets Module

Now run Terraform for the first time. This creates the secret "containers" in AWS.

```powershell
cd infra

# Download Terraform dependencies
terraform init -backend-config=environments/dev/backend.hcl

# Preview what will be created (nothing is created yet)
terraform plan -var-file=environments/dev/terraform.tfvars

# Create the resources (type "yes" when prompted)
terraform apply -var-file=environments/dev/terraform.tfvars
```

When it finishes, you will see:
```
Apply complete! Resources: X added, 0 changed, 0 destroyed.
```
✅ Secrets are now set up in AWS.

---

## Part 13 — Build and Upload the App Containers

This packages the application code and uploads it to AWS so ECS can run it.

```powershell
cd "C:\Users\$env:USERNAME\Documents\ThankGodForJesusChrist\ThankGodForChatProxyPlatform"

# Get your AWS account number
$ACCOUNT = (aws sts get-caller-identity --query Account --output text)
$REGION  = "us-east-1"
$BASE    = "$ACCOUNT.dkr.ecr.$REGION.amazonaws.com"

# Create container repositories in AWS
aws ecr create-repository --repository-name chatproxy/auth-service       --region $REGION
aws ecr create-repository --repository-name chatproxy/accounting-service  --region $REGION
aws ecr create-repository --repository-name chatproxy/flowise-proxy       --region $REGION
aws ecr create-repository --repository-name chatproxy/bridge              --region $REGION

# Log Docker into AWS
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin "$BASE"

# Build and upload auth-service
cd auth-service
docker build -t "$BASE/chatproxy/auth-service:latest" .
docker push "$BASE/chatproxy/auth-service:latest"

# Build and upload accounting-service
cd ../accounting-service
docker build -t "$BASE/chatproxy/accounting-service:latest" .
docker push "$BASE/chatproxy/accounting-service:latest"

# Build and upload flowise-proxy
cd ../flowise-proxy-service-py
docker build -t "$BASE/chatproxy/flowise-proxy:latest" .
docker push "$BASE/chatproxy/flowise-proxy:latest"

# Build and upload bridge (frontend)
cd ../bridge
docker build -t "$BASE/chatproxy/bridge:latest" .
docker push "$BASE/chatproxy/bridge:latest"

cd ..
```

> ⏱️ Each build takes 3–10 minutes. The total upload time depends on your internet speed.

---

## Part 14 — What Happens Next (Remaining Infrastructure)

Once the containers are uploaded, the remaining infrastructure needs to be deployed:
- **VPC** (the private network your services run in)
- **RDS Aurora** (the PostgreSQL database)
- **ECS Cluster** (where your containers run)
- **Application Load Balancer** (routes web traffic to the right service)

These Terraform modules are being built. When ready, deploying them will be:
```powershell
cd infra
terraform apply -var-file=environments/dev/terraform.tfvars
```
And everything will come up automatically.

---

## Part 15 — Verify Everything Is Working

Once all services are running, open your browser and check:

| URL | What you should see |
|---|---|
| `https://mychatbot.com` | The chat interface |
| `https://mychatbot.com/api/auth/health` | `{"status":"ok"}` |
| `https://mychatbot.com/api/accounting/health` | `{"status":"ok"}` |
| `https://mychatbot.com/api/chat/health` | `{"status":"ok"}` |

### Create your first admin account

Open PowerShell and run:
```powershell
$BASE_URL = "https://mychatbot.com"   # ← replace with your domain

# Generate a strong random admin password (store in your password manager)
$ADMIN_PASSWORD = [System.Web.Security.Membership]::GeneratePassword(24,6)
$ADMIN_PASSWORD

Invoke-RestMethod -Method POST "$BASE_URL/api/auth/register" `
  -ContentType "application/json" `
  -Body (@{ email = "admin@mychatbot.com"; password = $ADMIN_PASSWORD; name = "Admin User" } | ConvertTo-Json)
```

Then log in to the Bridge UI at `https://mychatbot.com` with those credentials.

---

## Secret Exposure Check and Rotation (Production Runbook)

Use this whenever you suspect a leak, or before a fresh relaunch.

### Step A - Identify what may be exposed

Check for these common leak locations:
- docs and old reports (for example copied JWTs, passwords in markdown)
- backup folders (`backup_*`, `config_backup_*`)
- local `.env` files accidentally copied
- shell history and CI logs

If any real secret appears in Git history, treat it as compromised and rotate immediately.

### Step B - Rotate JWT secrets

This invalidates active access/refresh tokens and forces re-login.

```powershell
$ACCESS  = [System.Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
$REFRESH = [System.Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32))

aws secretsmanager put-secret-value `
  --secret-id /chatproxy/dev/jwt `
  --secret-string "{`"JWT_ACCESS_SECRET`":`"$ACCESS`",`"JWT_REFRESH_SECRET`":`"$REFRESH`"}"
```

Redeploy services that consume JWTs:
- `auth-service`
- `accounting-service`
- `flowise-proxy`

### Step C - Rotate database credentials

1. Create new DB users/passwords (Mongo Atlas and RDS).
2. Update corresponding Secrets Manager values.
3. Redeploy affected services.
4. Verify health endpoints.
5. Disable old DB credentials.

### Step D - Rotate admin account password

Preferred method (API, no direct DB edits):
1. Login as admin.
2. Call `POST /api/protected/change-password` with:
  - `currentPassword`
  - `newPassword` (strong random value)
3. Store the new password in your password manager.

If admin login is lost:
1. Create a temporary recovery admin via bootstrap script.
2. Change original admin password.
3. Remove recovery admin.

### Step E - Verify rotation succeeded

1. Old tokens fail with `401`.
2. New login works.
3. Admin pages load.
4. `/api/auth/health`, `/api/accounting/health`, `/api/v1/chat/health` return healthy responses.

---

## Fresh Setup Again (Clean Rebuild Sequence)

If you want to set up from scratch again, follow this order:

1. **Prepare account and tooling**
  - AWS account, domain, certificate, AWS CLI, Terraform, Docker.

2. **Prepare Terraform backend**
  - S3 backend bucket + DynamoDB lock table.

3. **Prepare secrets first**
  - Generate fresh JWT and DB credentials.
  - Store all values in Secrets Manager before deploying workloads.

4. **Deploy base infrastructure**
  - VPC, subnets, security groups, ALB, ECS cluster, RDS.

5. **Build and push images**
  - auth, accounting, flowise-proxy, bridge to ECR.

6. **Deploy application services**
  - ECS services wired to ALB path rules.

7. **Initialize and verify data plane**
  - Confirm accounting DB schema is created.
  - Confirm Mongo connections for auth and proxy.

8. **Create first admin with random password**
  - No default/static admin passwords.

9. **Run smoke tests**
  - Login, admin users, credits, usage, chat endpoints.

10. **Lock down security**
  - Remove temporary/testing routes.
  - Restrict network rules.
  - Set cost alarms and rotation reminders.

---

## Troubleshooting — Common Issues

### "The domain name is already taken"
- Try a different name or a different ending (`.net`, `.org`, `.io`)

### "Certificate status is still Pending"
- Wait longer (up to 30 minutes)
- Make sure your domain registration is verified (check your email)

### "Terraform init fails"
- Check that your AWS CLI is configured correctly: run `aws sts get-caller-identity`
- Make sure the S3 bucket name in `backend.hcl` matches exactly what you created

### "Docker build fails"
- Make sure Docker Desktop is running (look for the whale icon in the taskbar)
- Try running Docker Desktop as Administrator

### "Connection refused" after deployment
- Wait 5–10 minutes — ECS takes time to start the containers
- Check ECS in the AWS Console: `Clusters → chatproxy-dev → Services`
- Click **"Logs"** tab on a service to see error messages

---

## Monthly Cost Summary (Dev Environment)

| AWS Service | Estimated Monthly Cost |
|---|---|
| ECS Fargate (4 services) | ~$20–40 |
| RDS Aurora Serverless v2 | ~$10–20 |
| Application Load Balancer | ~$16 |
| NAT Gateway | ~$5–10 |
| ECR (container storage) | ~$1–3 |
| Route 53 (hosted zone) | ~$0.50 |
| Secrets Manager | ~$2–3 |
| CloudWatch Logs | ~$1–5 |
| **Domain name** | ~$1/month (paid annually) |
| **Total** | **~$56–98/month** |

> MongoDB Atlas free tier (M0) is included at $0/month for dev.

---

## Getting Help

If something goes wrong, the AWS Console shows you error messages:
- **ECS problems** → AWS Console → ECS → Your Cluster → Services → Logs tab
- **Database problems** → AWS Console → RDS → Your cluster → Logs & events
- **DNS problems** → AWS Console → Route 53 → Health checks
- **Build problems** → Check the PowerShell terminal output for red error text

The most important rule: **if you see an error, copy the full text** — it tells you exactly what went wrong.
