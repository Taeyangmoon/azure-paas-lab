#!/usr/bin/env bash
# Connect the web app to a private Key Vault without opening public network access.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
source scripts/env.sh
source scripts/private-network.sh

if [ "${1:-}" != "--allow-paid" ]; then
  echo "This lab needs paid App Service B1 (or higher) and Private Endpoints." >&2
  echo "Run: bash scripts/03-key-vault.sh --allow-paid; clean up afterwards." >&2
  exit 2
fi
az webapp show -g "$RG" -n "$WEBAPP" -o none
tier=$(az appservice plan show -g "$RG" -n "$PLAN" --query sku.tier -o tsv)
if [ "$tier" = Free ] || [ "$tier" = Shared ]; then
  echo "Upgrading the lab plan to paid B1 for VNet integration."
  az appservice plan update -g "$RG" -n "$PLAN" --sku B1 -o none
fi
ensure_lab_network
existing=$(az keyvault list -g "$RG" --query "[?name=='$KV'].name" -o tsv)
if [ -z "$existing" ]; then
  az keyvault create -g "$RG" -n "$KV" -l "$LOCATION" --enable-rbac-authorization true \
    --public-network-access Disabled --tags "$LAB_TAG" -o none
else
  az keyvault update -g "$RG" -n "$KV" --enable-rbac-authorization true \
    --public-network-access Disabled -o none
fi
KV_ID=$(az keyvault show -g "$RG" -n "$KV" --query id -o tsv)
ensure_lab_private_endpoint "$KV_ID" vault privatelink.vaultcore.azure.net

# ARM provisions only a public demo value. Data-plane reads still require network access and RBAC.
az rest --method put --url "https://management.azure.com$KV_ID/secrets/demo-secret?api-version=2023-07-01" \
  --body '{"properties":{"value":"my-super-secret-value"}}' -o none
PRINCIPAL_ID=$(az webapp identity assign -g "$RG" -n "$WEBAPP" --query principalId -o tsv)
az role assignment create --assignee-object-id "$PRINCIPAL_ID" --assignee-principal-type ServicePrincipal \
  --role "Key Vault Secrets User" --scope "$KV_ID" -o none
az webapp vnet-integration add -g "$RG" -n "$WEBAPP" --vnet "$VNET" --subnet webapp -o none
az webapp config set -g "$RG" -n "$WEBAPP" --generic-configurations '{"vnetRouteAllEnabled":true}' -o none
az webapp config appsettings set -g "$RG" -n "$WEBAPP" -o none --settings \
  "SECRET_FROM_REFERENCE=@Microsoft.KeyVault(VaultName=$KV;SecretName=demo-secret)" \
  "KEY_VAULT_URL=https://$KV.vault.azure.net/" KEY_VAULT_SECRET_NAME=demo-secret
az webapp restart -g "$RG" -n "$WEBAPP"
URL="https://$(az webapp show -g "$RG" -n "$WEBAPP" --query defaultHostName -o tsv)"
curl --fail --show-error --silent --retry 12 --retry-delay 10 --max-time 60 "$URL/healthz"
az keyvault show -g "$RG" -n "$KV" --query "{vault:name,publicNetworkAccess:properties.publicNetworkAccess}" -o json
echo "Next: follow lab 3 to verify both /secret/reference and /secret/sdk."
