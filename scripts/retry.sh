#!/usr/bin/env bash
# RBAC 전파 오류만 제한적으로 재시도합니다 / Retry only RBAC propagation errors.
# 사용법 / Usage: bash scripts/retry.sh az <command> ...
set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "Usage: bash scripts/retry.sh <command> [arguments...]" >&2
  exit 2
fi

error_file=$(mktemp)
trap 'rm -f "$error_file"' EXIT

for attempt in $(seq 1 10); do
  if "$@" 2>"$error_file"; then
    cat "$error_file" >&2
    exit 0
  else
    status=$?
  fi
  cat "$error_file" >&2
  if ! grep -Eq "ForbiddenByRbac|AuthorizationFailed|Role .*does(n.t| not) exist|No subscriptions found" "$error_file"; then
    exit "$status"
  fi
  if [ "$attempt" -eq 10 ]; then
    echo "❌ 재시도 한도 초과 / Retry limit reached (10 attempts)." >&2
    exit "$status"
  fi
  echo "⏳ RBAC 전파 대기 / Waiting for RBAC propagation ($attempt/10)..." >&2
  sleep 15
done
