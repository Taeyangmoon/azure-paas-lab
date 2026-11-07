#!/usr/bin/env bash
# 모든 실습이 공유하는 변수 / Shared variables for all labs
# 사용법 / Usage:  source scripts/env.sh   (저장소 루트에서 / from the repo root)
#
# 처음 실행하면 무작위 6자리 접미사(LAB_SUFFIX)를 만들어 .lab-env 에 저장합니다.
# 터미널을 새로 열어도 같은 이름을 재사용하므로 다시 source 하기만 하면 됩니다.
# On first run a random 6-char suffix is saved to .lab-env and reused afterwards.

LAB_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
export LAB_ROOT
LAB_ENV_FILE="$LAB_ROOT/.lab-env"

if [ ! -f "$LAB_ENV_FILE" ]; then
  echo "LAB_SUFFIX=$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 6)" > "$LAB_ENV_FILE"
fi
# shellcheck disable=SC1090
. "$LAB_ENV_FILE"

export LOCATION="${LOCATION:-koreacentral}"     # 지역 / region
export WEBAPP_SKU="${WEBAPP_SKU:-F1}"           # F1 = 무료 / free. 할당량 오류 시 / on quota error: B1

export RG="rg-paaslab-$LAB_SUFFIX"              # 실습 1~4 / labs 1-4
export PLAN="plan-paaslab-$LAB_SUFFIX"
export WEBAPP="app-paaslab-$LAB_SUFFIX"
export FUNC_STORAGE="stfunc$LAB_SUFFIX"
export FUNCAPP="func-paaslab-$LAB_SUFFIX"
export FUNC_IDENTITY="id-func-$LAB_SUFFIX"
export VNET="vnet-paaslab-$LAB_SUFFIX"
export KV="kv-paaslab-$LAB_SUFFIX"
export SP_NAME="sp-paaslab-$LAB_SUFFIX"         # 실습 4 / lab 4
export POLICY_RG="rg-paaslab-policy-$LAB_SUFFIX" # 실습 5 / lab 5
export LAB_TAG="lab=azure-paas-lab"

echo "LAB_SUFFIX=$LAB_SUFFIX  LOCATION=$LOCATION  RG=$RG"
