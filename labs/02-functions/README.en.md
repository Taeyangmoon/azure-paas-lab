# Lab 2. Azure Functions: HTTP-triggered Function

🇺🇸 English | [🇰🇷 한국어](README.md) | [← Home](../../README.en.md) | [← Lab 1](../01-app-service/README.en.md) | [Next: Lab 3 →](../03-key-vault/README.en.md)

⏱ 20 min · 💸 Nearly free (usage-based) · 🎯 **See serverless with the shortest possible code.**

## Concept first

- **Serverless** doesn't mean "no servers"; it means *you don't think about servers*. It runs when a request arrives and costs almost nothing when idle.
- **Trigger**: the event that wakes a function (HTTP request, timer, queue message…). This lab uses an **HTTP trigger**.
- This lab uses the **Flex Consumption** plan: usage-based, and the recommended serverless hosting for new function apps.

| | App Service (Lab 1) | Functions (Lab 2) |
|---|---|---|
| Unit | The whole app | A function (small piece of code) |
| Execution | Always on (plan) | On demand |
| Billing | Plan hours | Executions and run time |

## This is all the code

Core of `src/function/function_app.py`:

```python
@app.route(route="hello", methods=["GET", "POST"])
def hello(req: func.HttpRequest) -> func.HttpResponse:
    name = req.params.get("name")
    return func.HttpResponse(f"Hello, {name}!")
```

## 1. Run it locally

```bash
source scripts/env.sh
cd src/function
func start
```

In a new terminal (`+` button):

```bash
curl "http://localhost:7071/api/hello?name=Azure"
curl -i "http://localhost:7071/api/hello"        # 400: name missing
```

Press `Ctrl+C` when done and `cd ../..` back to the root.

## 2. Create the Azure resources

```bash
source scripts/env.sh
az group create -n $RG -l $LOCATION --tags $LAB_TAG -o none

# Storage account where the Functions runtime keeps its state
az storage account create -g $RG -n $FUNC_STORAGE -l $LOCATION \
  --sku Standard_LRS --allow-blob-public-access false --min-tls-version TLS1_2 -o none

# Function app (Flex Consumption)
az functionapp create -g $RG -n $FUNCAPP --storage-account $FUNC_STORAGE \
  --flexconsumption-location $LOCATION --runtime python --runtime-version 3.12 -o none
```

> If you get an error that Flex Consumption isn't supported in `koreacentral`, run `az functionapp list-flexconsumption-locations -o table`, pick a supported region with `export LOCATION=<region>`, and create the storage account and function app there (the resource group may stay in its original region).

## 3. Deploy

```bash
(cd src/function && func azure functionapp publish $FUNCAPP)
```

The output ends with the list of function URLs.

## 4. Call it: function keys

This function uses `AuthLevel.FUNCTION`, so it **can't be called without a key**. That's your first security concept.

```bash
HOST=$(az functionapp show -g $RG -n $FUNCAPP --query defaultHostName -o tsv)

# Without a key → 401 Unauthorized
curl -i "https://$HOST/api/hello?name=Azure"

# With the key → 200 OK
KEY=$(az functionapp keys list -g $RG -n $FUNCAPP --query functionKeys.default -o tsv)
curl "https://$HOST/api/hello?name=Azure" -H "x-functions-key: $KEY"
```

> 🔐 Sending the key in a **header** leaves fewer traces in logs than `?code=` in the URL. Keys are also a *weak* protection; for real services consider Microsoft Entra authentication (Easy Auth).

## 5. Feel the serverless model

- **Cold start:** the first call after an idle period is a bit slower. Compare with `time curl ...`.
- **Logs:** Azure portal → function app → **Log stream**.
- **Cost:** portal → function app → *Monitoring* to see execution counts. No calls, no execution cost.

## ❓ Quiz

1. Is "serverless has no servers" an accurate statement?
2. What would the same feature cost on App Service at zero traffic?
3. What do you do if a function key leaks? (`az functionapp keys set` / regenerate in the portal)

## 🛠 Troubleshooting

| Symptom | Fix |
|---------|-----|
| `func: command not found` | Rebuild the Codespace (`Rebuild Container`) and check `.devcontainer` |
| 401/404 right after deploy | Wait 1-2 minutes and retry; confirm the publish output listed the functions |
| `functionKeys.default` is empty | The host hasn't started yet. Retry after 1-2 minutes or read it from *App keys* in the portal |
| `storage account ... has networking restrictions` (creating the function app) or `Key based authentication is not permitted` (deploying) | An organization policy forces public network access / key authentication off on storage accounts (e.g. corporate-managed subscriptions). Run this lab in a **personal lab subscription** without such policies |
| Storage account name already taken | `rm .lab-env && source scripts/env.sh` for a new suffix (after cleaning up old resources) |

➡️ Next: [Lab 3. Key Vault + Managed Identity](../03-key-vault/README.en.md)
