#!/usr/bin/env bash
# 실습 시작 전 점검 + 리소스 공급자 등록 / Pre-flight check + resource provider registration
# 사용법 / Usage:  bash scripts/00-setup.sh
set -euo pipefail

if ! az account show >/dev/null 2>&1; then
  echo "❌ Azure에 로그인되어 있지 않습니다 / Not signed in."
  echo "   az login --use-device-code"
  exit 1
fi

echo "✅ 구독 / Subscription:"
az account show --query "{name:name, id:id, tenant:tenantId, user:user.name}" -o table

echo
echo "⏳ 리소스 공급자 등록 중 (처음 한 번만 오래 걸립니다) / Registering providers (slow only the first time)..."
for ns in Microsoft.Web Microsoft.KeyVault Microsoft.Storage Microsoft.Network Microsoft.PolicyInsights Microsoft.OperationalInsights Microsoft.App; do
  state=$(az provider show --namespace "$ns" --query registrationState -o tsv 2>/dev/null || echo "NotRegistered")
  if [ "$state" != "Registered" ]; then
    echo "   - $ns ($state) -> register"
    az provider register --namespace "$ns" --wait >/dev/null
  else
    echo "   - $ns OK"
  fi
done

echo
echo "🎉 준비 완료 / Ready. 다음 / Next: labs/01-app-service"
