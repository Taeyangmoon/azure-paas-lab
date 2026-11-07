#!/usr/bin/env bash
# Shared private networking for labs 2 and 3. Source after scripts/env.sh.

ensure_lab_network() {
  local existing subnet name prefix delegation
  existing=$(az network vnet list -g "$RG" --query "[?name=='$VNET'].name" -o tsv) || return
  if [ -z "$existing" ]; then
    az network vnet create -g "$RG" -n "$VNET" -l "$LOCATION" \
      --address-prefixes 10.42.0.0/16 --tags "$LAB_TAG" -o none || return
  fi
  for subnet in "private-endpoints:10.42.0.0/24:none" \
    "functions:10.42.1.0/24:Microsoft.App/environments" \
    "webapp:10.42.2.0/24:Microsoft.Web/serverFarms"; do
    IFS=: read -r name prefix delegation <<< "$subnet"
    existing=$(az network vnet subnet list -g "$RG" --vnet-name "$VNET" \
      --query "[?name=='$name'].name" -o tsv) || return
    if [ -z "$existing" ]; then
      if [ "$delegation" = none ]; then
        az network vnet subnet create -g "$RG" --vnet-name "$VNET" -n "$name" \
          --address-prefixes "$prefix" --private-endpoint-network-policies Disabled -o none || return
      else
        az network vnet subnet create -g "$RG" --vnet-name "$VNET" -n "$name" \
          --address-prefixes "$prefix" --delegations "$delegation" -o none || return
      fi
    fi
  done
}

ensure_lab_private_endpoint() {
  local resource_id="$1" group="$2" zone="$3"
  local endpoint="pe-$group-$LAB_SUFFIX" existing zone_id vnet_id
  vnet_id=$(az network vnet show -g "$RG" -n "$VNET" --query id -o tsv) || return
  existing=$(az network private-dns zone list -g "$RG" --query "[?name=='$zone'].name" -o tsv) || return
  if [ -z "$existing" ]; then
    az network private-dns zone create -g "$RG" -n "$zone" -o none || return
  fi
  existing=$(az network private-dns link vnet list -g "$RG" --zone-name "$zone" \
    --query "[?name=='$VNET'].name" -o tsv) || return
  if [ -z "$existing" ]; then
    az network private-dns link vnet create -g "$RG" --zone-name "$zone" -n "$VNET" \
      --virtual-network "$vnet_id" --registration-enabled false -o none || return
  fi
  existing=$(az network private-endpoint list -g "$RG" --query "[?name=='$endpoint'].name" -o tsv) || return
  if [ -z "$existing" ]; then
    az network private-endpoint create -g "$RG" -n "$endpoint" -l "$LOCATION" \
      --vnet-name "$VNET" --subnet private-endpoints --private-connection-resource-id "$resource_id" \
      --group-id "$group" --connection-name "$endpoint" --tags "$LAB_TAG" -o none || return
  fi
  zone_id=$(az network private-dns zone show -g "$RG" -n "$zone" --query id -o tsv) || return
  az network private-endpoint dns-zone-group create -g "$RG" --endpoint-name "$endpoint" \
    -n default --private-dns-zone "$zone_id" --zone-name "$group" -o none
}
