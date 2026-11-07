# Lab 4. Azure RBAC and Microsoft Entra ID: Role Assignments & Least Privilege

🇺🇸 English | [🇰🇷 한국어](README.md) | [← Home](../../README.en.md) | [← Lab 3](../03-key-vault/README.en.md) | [Next: Lab 5 →](../05-policy-governance/README.en.md)

⏱ 25 min · 💸 Free · 🎯 **Generalize** the authorization mechanism you used in Lab 3.
📌 Prerequisite: [Lab 3](../03-key-vault/README.en.md) completed

## Concept first

**Microsoft Entra ID** answers "**who** are you?" (authentication). **Azure RBAC** answers "**what may you do?**" (authorization).

```text
Role assignment =  who (security principal)  +  which role (role definition)  +  where (scope)
```

| Component | Examples |
|-----------|----------|
| Security principal | User, group, service principal, **managed identity** (the web app from Lab 3!) |
| Role definition | Reader, Contributor, Owner, Key Vault Secrets User … (or your own custom role) |
| Scope | Management group ⊃ subscription ⊃ resource group ⊃ resource (**inherited downward**) |

> **Least privilege**: grant the needed *role* at the needed *scope* for only the needed *time*.

## 1. Explore your environment

```bash
source scripts/env.sh
RG_ID=$(az group show -n $RG --query id -o tsv)
KV_ID=$(az keyvault show -g $RG -n $KV --query id -o tsv)
PRINCIPAL_ID=$(az webapp identity show -g $RG -n $WEBAPP --query principalId -o tsv)

# Me, in Entra ID
az ad signed-in-user show --query "{name:displayName, account:userPrincipalName, objectId:id}" -o table

# The web app's managed identity also exists in Entra ID as a "service principal"
az ad sp show --id $PRINCIPAL_ID --query "{name:displayName, type:servicePrincipalType, objectId:id}" -o table

# What this managed identity may do (granted in Lab 3)
az role assignment list --assignee $PRINCIPAL_ID --all -o table
```

## 2. What's inside a role?

```bash
az role definition list --name "Reader" --query "[0].permissions[0].actions" -o tsv
az role definition list --name "Key Vault Secrets User" --query "[0].permissions[0].{actions:actions, dataActions:dataActions}" -o json
```

- `actions`: **management plane** (create/delete/configure resources)
- `dataActions`: **data plane** (read secrets, read blobs …). That's why the Owner couldn't read secrets in Lab 3.

## 3. Least-privilege experiment: a "read-only" user

Create a lab **service principal** (an app account) and give it `Reader` at **resource group scope** only.

```bash
SP=$(az ad sp create-for-rbac --name $SP_NAME --role Reader --scopes $RG_ID -o json)
SP_APP_ID=$(echo "$SP" | jq -r .appId)
SP_PASSWORD=$(echo "$SP" | jq -r .password)
SP_TENANT=$(echo "$SP" | jq -r .tenant)
SP_OBJECT_ID=$(az ad sp show --id $SP_APP_ID --query id -o tsv)
```

> 🔐 `$SP_PASSWORD` lives only in this terminal. Never save it to a file or Git (cleanup removes the principal). In real projects prefer **managed identities**, which need no password. Here we use it only to impersonate "someone else".

Use a **separate login session** so your own `az login` stays intact:

```bash
as_sp() { AZURE_CONFIG_DIR="$LAB_ROOT/.azure-sp" "$@"; }
as_sp bash scripts/retry.sh az login --service-principal -u $SP_APP_ID --password="$SP_PASSWORD" --tenant $SP_TENANT -o none

# ✅ Read: works
as_sp az group show -n $RG --query name -o tsv
as_sp az webapp list -g $RG --query "[].name" -o tsv

# ❌ Write: AuthorizationFailed
as_sp az storage account create -g $RG -n st9$LAB_SUFFIX -l $LOCATION --sku Standard_LRS -o none

# ❌ Read secret: Reader is management plane only → Forbidden (data plane is separate!)
as_sp az keyvault secret show --vault-name $KV -n demo-secret
```

### Add only what's needed

Suppose this principal must now create storage accounts. Don't hand out `Contributor` (almost everything); grant the **exactly fitting role** at the **same scope**.

```bash
az role assignment create --assignee-object-id $SP_OBJECT_ID --assignee-principal-type ServicePrincipal \
  --role "Storage Account Contributor" --scope $RG_ID -o none

as_sp bash scripts/retry.sh az storage account create -g $RG -n st9$LAB_SUFFIX \
  -l $LOCATION --sku Standard_LRS -o none && echo "✅ storage account created"

# ❌ Still can't stop the web app (no Microsoft.Web permission)
as_sp az webapp stop -g $RG -n $WEBAPP
```

Verify: `az role assignment list --assignee $SP_OBJECT_ID --all -o table`

> Also check in the portal: resource group → **Access control (IAM)** → **Check access** and search for the principal to see its *effective permissions*. This is how admins answer "what can this identity do?".

## 4. Challenge: a custom role

Create a role that can **only restart** web apps.

```bash
cat > /tmp/role.json <<EOF
{
  "Name": "Web App Restarter ($LAB_SUFFIX)",
  "Description": "Can view and restart web apps only.",
  "Actions": ["Microsoft.Web/sites/read", "Microsoft.Web/sites/restart/action"],
  "NotActions": [],
  "AssignableScopes": ["$RG_ID"]
}
EOF
ROLE_ID=$(az role definition create --role-definition @/tmp/role.json --query name -o tsv)

# Use the returned role ID to avoid propagation delays in name lookup
bash scripts/retry.sh az role assignment create --assignee-object-id $SP_OBJECT_ID \
  --assignee-principal-type ServicePrincipal --role "$ROLE_ID" --scope $RG_ID -o none

# Retry role assignment propagation errors within a fixed limit
as_sp bash scripts/retry.sh az webapp restart -g $RG -n $WEBAPP  # ✅
as_sp az webapp stop -g $RG -n $WEBAPP         # ❌ still denied
```

## ❓ Quiz

1. Could Reader read the Key Vault secret? Why (not)?
2. What's the benefit of assigning at **resource group** instead of **subscription** scope?
3. How can an app get permissions without any password? (Lab 3: managed identity)

## 🛠 Troubleshooting

| Symptom | Fix |
|---------|-----|
| `az ad sp create-for-rbac` → `Insufficient privileges` | Your tenant blocks app registrations. Skip steps 3-4; do steps 1-2 plus portal **IAM → Check access** |
| No subscription after `as_sp az login` | Wait 1-2 minutes for propagation and retry |
| `AuthorizationFailed` right after granting a role | Expected; propagation can take a few minutes |
| `jq: command not found` | `sudo apt-get install -y jq` |

> 🧹 `bash scripts/cleanup.sh` removes the service principal and the custom role.

➡️ Next: [Lab 5. Azure Policy & tag governance](../05-policy-governance/README.en.md)
