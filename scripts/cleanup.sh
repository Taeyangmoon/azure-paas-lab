#!/usr/bin/env bash
# 실습에서 만든 모든 리소스를 삭제합니다 / Delete everything created by the labs.
# 사용법 / Usage:  bash scripts/cleanup.sh        (확인 질문 있음 / asks for confirmation)
#                  bash scripts/cleanup.sh -y     (질문 없이 / no prompt)
set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
if [ ! -f .lab-env ]; then
  echo "❌ .lab-env 없음 / Missing .lab-env: restore the lab state before cleanup." >&2
  exit 1
fi
# shellcheck disable=SC1091
source scripts/env.sh >/dev/null

echo "삭제 대상 / Will delete:"
echo "  - 리소스 그룹 / Resource groups : $RG, $POLICY_RG"
echo "  - Key Vault (soft-delete purge) : $KV"
echo "  - 서비스 주체 / Service principal: $SP_NAME"
if [ "${1:-}" != "-y" ]; then
  read -r -p "계속할까요? / Continue? [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]] || { echo "취소 / Cancelled"; exit 0; }
fi

trap 'rm -rf "$LAB_ROOT/.azure-sp"; rm -f "$LAB_ROOT/webapp.zip"' EXIT

# Key Vault 는 삭제 후에도 7일 동안 이름이 예약(soft-delete)되므로 purge 가 필요합니다.
# A deleted Key Vault keeps its name reserved (soft-delete), so purge it.
for rg in "$RG" "$POLICY_RG"; do
  exists=$(az group exists -n "$rg")
  if [ "$exists" = "true" ]; then
    echo "🗑  삭제 중 / Deleting $rg ..."
    az group delete -n "$rg" --yes --no-wait
  fi
done

echo "⏳ 리소스 그룹 삭제 대기 / Waiting for deletion..."
for rg in "$RG" "$POLICY_RG"; do
  exists=$(az group exists -n "$rg")
  if [ "$exists" = "true" ]; then
    az group wait --deleted -g "$rg"
  fi
done

deleted_vault=$(az keyvault list-deleted --query "[?name=='$KV'].name" -o tsv)
if [ -n "$deleted_vault" ]; then
  echo "🧹 Key Vault purge: $KV"
  az keyvault purge --name "$KV" -o none
fi

app_ids=$(az ad app list --display-name "$SP_NAME" --query "[].id" -o tsv)
for id in $app_ids; do
  echo "🧹 Entra 앱/서비스 주체 삭제 / Deleting Entra app $SP_NAME"
  az ad app delete --id "$id"
done

role_id=$(az role definition list --name "Web App Restarter ($LAB_SUFFIX)" --query "[0].name" -o tsv)
if [ -n "$role_id" ]; then
  az role definition delete --name "$role_id"
fi

echo "✅ 정리 완료 / Cleanup complete. (.lab-env 는 남겨둡니다 / kept: rm .lab-env 로 새 접미사 / for a new suffix)"
