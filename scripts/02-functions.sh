#!/usr/bin/env bash
# Deploy Flex Consumption with private storage and managed identity, without storage keys.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
source scripts/env.sh
source scripts/private-network.sh

az group create -n "$RG" -l "$LOCATION" --tags "$LAB_TAG" -o none
az storage account create -g "$RG" -n "$FUNC_STORAGE" -l "$LOCATION" --sku Standard_LRS \
  --allow-blob-public-access false --allow-shared-key-access false \
  --public-network-access Disabled --min-tls-version TLS1_2 -o none
STORAGE_ID=$(az storage account show -g "$RG" -n "$FUNC_STORAGE" --query id -o tsv)
az storage container-rm create -g "$RG" --storage-account "$FUNC_STORAGE" -n deployments -o none
az identity create -g "$RG" -n "$FUNC_IDENTITY" -l "$LOCATION" --tags "$LAB_TAG" -o none
IDENTITY_ID=$(az identity show -g "$RG" -n "$FUNC_IDENTITY" --query id -o tsv)
IDENTITY_PID=$(az identity show -g "$RG" -n "$FUNC_IDENTITY" --query principalId -o tsv)
IDENTITY_CLIENT_ID=$(az identity show -g "$RG" -n "$FUNC_IDENTITY" --query clientId -o tsv)
az role assignment create --assignee-object-id "$IDENTITY_PID" --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Owner" --scope "$STORAGE_ID" -o none

ensure_lab_network
ensure_lab_private_endpoint "$STORAGE_ID" blob privatelink.blob.core.windows.net
existing=$(az functionapp list -g "$RG" --query "[?name=='$FUNCAPP'].name" -o tsv)
if [ -z "$existing" ]; then
  az functionapp create -g "$RG" -n "$FUNCAPP" --storage-account "$FUNC_STORAGE" \
    --flexconsumption-location "$LOCATION" --runtime python --runtime-version 3.12 \
    --assign-identity "$IDENTITY_ID" --deployment-storage-name "$FUNC_STORAGE" \
    --deployment-storage-container-name deployments --deployment-storage-auth-type UserAssignedIdentity \
    --deployment-storage-auth-value "$IDENTITY_ID" --vnet "$VNET" --subnet functions \
    --https-only true --disable-app-insights true --tags "$LAB_TAG" -o none
fi
az functionapp deployment config set -g "$RG" -n "$FUNCAPP" \
  --deployment-storage-name "$FUNC_STORAGE" --deployment-storage-container-name deployments \
  --deployment-storage-auth-type UserAssignedIdentity --deployment-storage-auth-value "$IDENTITY_ID" -o none
az functionapp config appsettings delete -g "$RG" -n "$FUNCAPP" \
  --setting-names AzureWebJobsStorage -o none
az functionapp config appsettings set -g "$RG" -n "$FUNCAPP" -o none --settings \
  "AzureWebJobsStorage__accountName=$FUNC_STORAGE" \
  AzureWebJobsStorage__credential=managedidentity "AzureWebJobsStorage__clientId=$IDENTITY_CLIENT_ID"

package_dir=$(mktemp -d)
package="$package_dir/function.zip"
trap 'rm -f "$package"; rmdir "$package_dir"' EXIT
(cd src/function && zip -qr "$package" . \
  -x "__pycache__/*" "local.settings.json" ".venv/*" ".python_packages/*")
az functionapp deployment source config-zip -g "$RG" -n "$FUNCAPP" \
  --src "$package" --build-remote true --timeout 600 -o none
az functionapp show -g "$RG" -n "$FUNCAPP" \
  --query "{host:properties.defaultHostName || defaultHostName,subnet:properties.virtualNetworkSubnetId || virtualNetworkSubnetId}" -o json
echo "Next: follow lab 2 to call /api/hello with and without the function key."
