#!/usr/bin/env bash
# 실습에서 만든 모든 리소스를 삭제합니다 / Delete everything created by the labs.
# 사용법 / Usage:  bash scripts/cleanup.sh        (확인 질문 있음 / asks for confirmation)
#                  bash scripts/cleanup.sh -y     (질문 없이 / no prompt)
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
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

# Key Vault 는 삭제 후에도 7일 동안 이름이 예약(soft-delete)되므로 purge 가 필요합니다.
# A deleted Key Vault keeps its name reserved (soft-delete), so purge it.
for rg in "$RG" "$POLICY_RG"; do
  if [ "$(az group exists -n "$rg")" = "true" ]; then
    echo "🗑  삭제 중 / Deleting $rg ..."
    az group delete -n "$rg" --yes --no-wait
  fi
done

echo "⏳ 리소스 그룹 삭제 대기 / Waiting for deletion..."
for rg in "$RG" "$POLICY_RG"; do
  az group wait --deleted -g "$rg" 2>/dev/null || true
done

if az keyvault list-deleted --query "[?name=='$KV'].name" -o tsv 2>/dev/null | grep -q .; then
  echo "🧹 Key Vault purge: $KV"
  az keyvault purge --name "$KV" >/dev/null || echo "   (purge protection 이 켜져 있으면 자동 만료를 기다려야 합니다 / wait for auto-expiry if purge protection is on)"
fi

app_ids=$(az ad app list --display-name "$SP_NAME" --query "[].id" -o tsv 2>/dev/null || true)
for id in $app_ids; do
  echo "🧹 Entra 앱/서비스 주체 삭제 / Deleting Entra app $SP_NAME"
  az ad app delete --id "$id" || true
done

az role definition delete --name "Web App Restarter ($LAB_SUFFIX)" >/dev/null 2>&1 || true

rm -rf .azure-sp webapp.zip
echo "✅ 정리 완료 / Cleanup complete. (.lab-env 는 남겨둡니다 / kept: rm .lab-env 로 새 접미사 / for a new suffix)"
