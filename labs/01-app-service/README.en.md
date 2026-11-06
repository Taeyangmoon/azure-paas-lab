# Lab 1. Azure App Service: Deploy a Sample Web App

🇺🇸 English | [🇰🇷 한국어](README.md) | [← Home](../../README.en.md) | [Next: Lab 2 →](../02-functions/README.en.md)

⏱ 20 min · 💸 Free (F1) · 🎯 **Feel what PaaS manages for you compared with a VM.**

## Concept first

On a VM you install and patch the OS, install the runtime, configure the web server, certificates, firewall and monitoring. **App Service (PaaS)** does that for you: you just upload code.

| Item | VM (IaaS) | App Service (PaaS) |
|------|-----------|--------------------|
| OS patching / security updates | 👤 You | ☁️ Azure |
| Runtime (Python…) install & update | 👤 You | ☁️ Azure (you pick a version) |
| Web server / load balancer / HTTPS termination | 👤 You | ☁️ Azure |
| App code, app settings, access control | 👤 You | 👤 You |
| Scale out | Build VM replication yourself | A slider / one command |

> Shared responsibility: even on PaaS, **your code, data and identities/access** remain your responsibility. That leads into the rest of the labs (3–5).

## What you'll build

```text
Resource group ─┬─ App Service plan (F1, Linux)
                └─ Web App (Python 3.12 / Flask)
```

## 1. Set variables

Run from the repo root.

```bash
source scripts/env.sh
```

## 2. Try it locally first (optional)

```bash
cd src/webapp
python app.py
```

Open port `8000` in the Codespaces **Ports** tab. Press `Ctrl+C` when done and return to the root (`cd ../..`).

## 3. Create the resources

```bash
# Resource group (shared by labs 1-4)
az group create -n $RG -l $LOCATION --tags $LAB_TAG -o none

# App Service plan: the size/spec of the "server pool" your app runs on
az appservice plan create -g $RG -n $PLAN --is-linux --sku $WEBAPP_SKU -o none

# Web app (you only choose the Python 3.12 runtime)
az webapp create -g $RG -p $PLAN -n $WEBAPP --runtime "PYTHON:3.12" -o none
```

Apply secure defaults, the startup command and the build option:

```bash
az webapp update -g $RG -n $WEBAPP --https-only true -o none
az webapp config set -g $RG -n $WEBAPP \
  --min-tls-version 1.2 --ftps-state Disabled \
  --startup-file "gunicorn --bind=0.0.0.0 --timeout 600 app:app" -o none
az webapp config appsettings set -g $RG -n $WEBAPP \
  --settings SCM_DO_BUILD_DURING_DEPLOYMENT=true -o none
```

> 💡 `SCM_DO_BUILD_DURING_DEPLOYMENT=true` makes Azure build your code (`pip install`) on its side.

## 4. Deploy the code

```bash
(cd src/webapp && zip -qr ../../webapp.zip . -x "__pycache__/*")
az webapp deploy -g $RG -n $WEBAPP --src-path webapp.zip --type zip
```

## 5. Verify

```bash
URL="https://$(az webapp show -g $RG -n $WEBAPP --query defaultHostName -o tsv)"
echo $URL
curl -s $URL/info
```

Open `$URL` in a browser too. **`/info`** shows values *the platform injected* (`WEBSITE_SITE_NAME`…), the Python version and the OS: things you never installed. That's PaaS.

> The first request can take 30+ seconds while the app wakes up. F1 sleeps when idle.

## 6. Experience it

1. **What about plain HTTP?** `curl -i http://${URL#https://}` → redirected (301) to HTTPS thanks to the HTTPS-only setting.
2. **View logs:** `az webapp log config -g $RG -n $WEBAPP --application-logging filesystem --level information -o none && az webapp log tail -g $RG -n $WEBAPP` (`Ctrl+C` to stop)
3. **Change and redeploy:** edit the `/` response in `src/webapp/app.py` and repeat step 4. No SSH into any server.
4. **Scale out (paid SKUs only):** `az appservice plan update -g $RG -n $PLAN --number-of-workers 2` (not on F1; just note the concept)

## ❓ Quiz

1. Who patched the **OS** in this lab? → Azure
2. Who is responsible for vulnerabilities in the app code? → You
3. What happens if you turn `--https-only` off? Why keep it on?

## 🛠 Troubleshooting

| Symptom | Fix |
|---------|-----|
| `Operation cannot be completed without additional quota` (F1/Linux) | `export WEBAPP_SKU=B1` and recreate the plan (or try another region, e.g. `export LOCATION=japaneast`) |
| `The webapp name is already in use` | `rm .lab-env && source scripts/env.sh` for a new suffix |
| Site shows `Application Error` | `az webapp log tail -g $RG -n $WEBAPP`; check the startup command (`app:app`) and `requirements.txt` |
| `zip: command not found` | `sudo apt-get update && sudo apt-get install -y zip` |

➡️ Next: [Lab 2. Azure Functions](../02-functions/README.en.md) (keep the web app; Lab 3 reuses it)
