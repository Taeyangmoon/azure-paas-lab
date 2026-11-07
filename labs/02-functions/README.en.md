# Lab 2. Azure Functions: HTTP-triggered Function

🇺🇸 English | [🇰🇷 한국어](README.md) | [← Home](../../README.en.md) | [← Lab 1](../01-app-service/README.en.md) | [Next: Lab 3 →](../03-key-vault/README.en.md)

⏱ 20–30 min · 💸 Usage-based + hourly Private Endpoint cost · 🎯 **See serverless with the shortest possible code.**

## Concept first

- **Serverless** doesn't mean "no servers"; it means *you don't think about servers*. It runs when a request arrives and costs almost nothing when idle.
- **Trigger**: the event that wakes a function (HTTP request, timer, queue message…). This lab uses an **HTTP trigger**.
- This lab uses the **Flex Consumption** plan: usage-based, and the recommended serverless hosting for new function apps.
- Storage keeps **public access and key authentication disabled**. The function uses **managed identity + a Private Endpoint**, so managed-subscription policies don't need to be relaxed.

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

The local runtime doesn't check function keys by default. Compare real 401/200 responses in Azure next.

## 2. Prepare and deploy to Azure — one command

Run from the repository root. Initial networking setup and deployment take several minutes.

```bash
bash scripts/02-functions.sh
```

The script creates storage, a managed identity, VNet/Private DNS/Private Endpoint, and the Flex function app, then remotely builds and deploys Python code. Application Insights is omitted to keep cost and setup small.

```text
My request ── HTTPS + function key ──▶ Functions (Flex Consumption)
                                          │ Managed identity (no storage password)
                                          ▼ VNet + Private Endpoint
                                     Private Blob storage
```

Understand two boundaries: the **function key** protects *caller → function*; **managed identity + RBAC** protects *function → storage*. `Storage Blob Data Owner` is granted **only on this storage account** for host state, keys, and deployment packages.

Run the same command after editing code to redeploy. Names and networking are reused.

## 3. Call it: function keys

This function uses `AuthLevel.FUNCTION`, so it **can't be called without a key**. That's your first security concept.

```bash
source scripts/env.sh
HOST=$(az functionapp show -g $RG -n $FUNCAPP --query "properties.defaultHostName || defaultHostName" -o tsv)

# Without a key → 401 Unauthorized
curl -i "https://$HOST/api/hello?name=Azure"

# With the key → 200 OK
KEY=$(az functionapp keys list -g $RG -n $FUNCAPP --query functionKeys.default -o tsv)
curl -i "https://$HOST/api/hello?name=Azure" -H "x-functions-key: $KEY"

# JSON body → 200; missing or non-string name → 400
curl -i "https://$HOST/api/hello" -H "x-functions-key: $KEY" \
  -H "Content-Type: application/json" --data '{"name":"Azure"}'
unset KEY
```

> 🔐 Sending the key in a **header** leaves fewer traces in logs than `?code=` in the URL. Keys are also a *weak* protection; for real services consider Microsoft Entra authentication (Easy Auth).

## 4. Verify policy-compliant settings

```bash
az storage account show -g $RG -n $FUNC_STORAGE \
  --query '{publicNetworkAccess:publicNetworkAccess,allowSharedKeyAccess:allowSharedKeyAccess}' -o json
az functionapp show -g $RG -n $FUNCAPP --query "properties.virtualNetworkSubnetId || virtualNetworkSubnetId" -o tsv
```

Expect `Disabled`, `false`, and a subnet ID. The function worked **without public storage or storage keys**.

- **Cold start:** the first call after an idle period is a bit slower. Compare with `time curl ...`.
- **Cost:** executions are usage-based, but **Private Endpoints incur hourly cost even with no calls**. Clean up everything afterwards.

## ❓ Quiz

1. Is "serverless has no servers" an accurate statement?
2. What would the same feature cost on App Service at zero traffic?
3. What do you do if a function key leaks? (`az functionapp keys set` / regenerate in the portal)

## 🛠 Troubleshooting

| Symptom | Fix |
|---------|-----|
| `func: command not found` | Rebuild the Codespace (`Rebuild Container`) and check `.devcontainer` |
| 404/503 or an empty key right after deploy | Host startup and RBAC/DNS propagation can take 1-2 minutes. Retry the key lookup and requests shortly |
| `functionKeys.default` is empty | The host hasn't started yet. Retry after 1-2 minutes or read it from *App keys* in the portal |
| `Key based authentication is not permitted` | Use `bash scripts/02-functions.sh` instead of the old manual creation commands. Do not turn on public access or key authentication |
| Unsupported region | Check `az functionapp list-flexconsumption-locations -o table` before starting. To change region, clean up and restart all labs in the same supported region |
| Storage account name already taken | `rm .lab-env && source scripts/env.sh` for a new suffix (after cleaning up old resources) |

➡️ Next: [Lab 3. Key Vault + Managed Identity](../03-key-vault/README.en.md)
