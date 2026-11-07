# Lab 5. Azure Policy & Tag Governance: Allowed Locations, Required Tags

🇺🇸 English | [🇰🇷 한국어](README.md) | [← Home](../../README.en.md) | [← Lab 4](../04-rbac-entra/README.en.md)

⏱ 20 min · 💸 Free · 🎯 **Watch non-compliant resource creation get rejected.**
📌 This lab is standalone (separate resource group). You need permission to assign policies (e.g. Owner).

## Concept first

- **RBAC** = *who* may do what / **Policy** = how resources *must look* (even an Owner must follow the rules).
- **Policy effects**: `Deny` (reject creation), `Audit` (record only), `Modify` (auto-fix), `DeployIfNotExists` …
- **Tags**: labels such as `costCenter=lab`, used for cost analysis, ownership and automation.

In this lab you assign **two built-in policies** with `Deny` on one resource group.

| Policy | Definition ID | Effect |
|--------|---------------|--------|
| Allowed locations | `e56962a6-4747-49cd-b67b-bf8b01975c4c` | Deny resources outside allowed regions |
| Require a tag on resources | `871b6d14-10aa-478d-b590-94f262ecfa99` | Deny resources without the `costCenter` tag |

## 1. Create a resource group for the lab

```bash
source scripts/env.sh
az group create -n $POLICY_RG -l $LOCATION --tags $LAB_TAG -o none
SCOPE=$(az group show -n $POLICY_RG --query id -o tsv)
```

## 2. Assign the policies

```bash
# ① Allowed locations: Korea Central/South only
az policy assignment create --name allowed-locations \
  --display-name "Allowed locations (lab)" \
  --scope $SCOPE \
  --policy e56962a6-4747-49cd-b67b-bf8b01975c4c \
  --params '{"listOfAllowedLocations":{"value":["koreacentral","koreasouth"]}}' -o none

# ② Required tag: costCenter
az policy assignment create --name require-costcenter-tag \
  --display-name "Require costCenter tag (lab)" \
  --scope $SCOPE \
  --policy 871b6d14-10aa-478d-b590-94f262ecfa99 \
  --params '{"tagName":{"value":"costCenter"}}' -o none

az policy assignment list --scope $SCOPE --query "[].displayName" -o tsv
```

> ⏳ A new assignment **usually takes a few minutes (up to ~30)** to take effect. If step 3 (a)/(b) *creates* an account instead of denying it, delete only that account with `az storage account delete -g $POLICY_RG -n <created-account-name> --yes`, wait a few minutes, and retry. Keep the resource group containing the policy assignments.

## 3. Try to create violating resources 💥

We use storage accounts (lowercase letters and digits only), with a different name for each case to avoid collisions if propagation delays allow an earlier creation.

**(a) Disallowed region** (tag present)

```bash
az storage account create -g $POLICY_RG -n stloc$LAB_SUFFIX -l eastus --sku Standard_LRS \
  --tags costCenter=lab -o none
```

→ `RequestDisallowedByPolicy ... Allowed locations (lab)` ✅

**(b) Missing required tag** (allowed region)

```bash
az storage account create -g $POLICY_RG -n sttag$LAB_SUFFIX -l koreacentral --sku Standard_LRS -o none
```

→ `RequestDisallowedByPolicy ... Require costCenter tag (lab)` ✅

**(c) Compliant**

```bash
az storage account create -g $POLICY_RG -n stpol$LAB_SUFFIX -l koreacentral --sku Standard_LRS \
  --tags costCenter=lab -o none && echo "✅ created"
```

Get used to reading **which policy assignment blocked you** (`policyAssignmentName`) in the error. The denial happens in Azure Resource Manager *before* the resource is created.

## 4. Check compliance

```bash
az policy state trigger-scan -g $POLICY_RG --no-wait
az policy state list -g $POLICY_RG \
  --query "[].{resource:resourceId, policy:policyAssignmentName, state:complianceState}" -o table
```

Evaluation takes a few minutes. You can also see charts in the portal: **Policy → Compliance**.

## 5. Challenges

1. **Switch to Audit:** *Allowed locations* supports an `effect` parameter. **Update the existing `allowed-locations` assignment using the same name.** Adding an Audit assignment with a new name leaves the original Deny in force. After propagation, violations are only *recorded as non-compliant* instead of denied.

   ```bash
   az policy assignment create --name allowed-locations --display-name "Allowed locations - Audit (lab)" \
     --scope $SCOPE --policy e56962a6-4747-49cd-b67b-bf8b01975c4c \
     --params '{"listOfAllowedLocations":{"value":["koreacentral"]},"effect":{"value":"Audit"}}' -o none

   # After propagation: creation outside the allowed region succeeds (required-tag policy remains)
   az storage account create -g $POLICY_RG -n staud$LAB_SUFFIX -l eastus --sku Standard_LRS \
     --tags costCenter=lab -o none
   az policy state trigger-scan -g $POLICY_RG --no-wait
   ```

2. **Auto-fill tags:** the built-in *Inherit a tag from the resource group* (`cd3aa116-8754-49c9-a813-ad46512ece54`) uses `Modify` to **copy the resource group's tag onto resources automatically** (Modify needs a managed identity, i.e. `--location`/`--mi-system-assigned` on the assignment). Governance isn't only denial.
3. **Widen the scope:** assign the same policy at subscription/management group level and it's inherited by everything below (same scope idea as Lab 4).

## ❓ Quiz

1. Why was (a) denied even though you're an Owner? (RBAC ≠ Policy)
2. Does a `Deny` policy delete existing non-compliant resources? (No, they're just flagged)
3. Which is safer when first introducing a rule: `Deny` or `Audit`?

## 🛠 Troubleshooting

| Symptom | Fix |
|---------|-----|
| (a)/(b) were created instead of denied | Policy propagation delay. Delete the resource, wait a few minutes, retry |
| `AuthorizationFailed` when assigning | Needs `Microsoft.Authorization/policyAssignments/write` (Owner or Resource Policy Contributor) |
| `MissingSubscriptionRegistration` (PolicyInsights) | Re-run `bash scripts/00-setup.sh` |
| Storage name already taken | Change the name suffix and retry |

🧹 **Final cleanup:** `bash scripts/cleanup.sh`

🎉 Well done! You've walked the full loop: PaaS deployment → secrets → access control → governance.
