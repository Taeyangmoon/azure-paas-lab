# 실습 10. Azure Policy와 태그 거버넌스: 허용 지역 제한, 필수 태그

[🇺🇸 English](README.en.md) | 🇰🇷 한국어 | [← 처음으로](../../README.md) | [← 실습 9](../09-rbac-entra/README.md)

⏱ 20분 · 💸 무료 · 🎯 **규칙을 어긴 리소스 생성이 거부되는 장면**을 직접 봅니다.
📌 이 실습은 독립적입니다 (별도 리소스 그룹 사용). 구독에 정책을 할당할 수 있는 권한(Owner 등)이 필요합니다.

## 개념 먼저

- **RBAC** = *누가* 무엇을 할 수 있나 / **Policy** = 리소스가 *어떤 모습이어야* 하나 (권한이 있는 Owner라도 규칙은 따라야 합니다).
- **정책 효과(Effect)**: `Deny`(생성 거부), `Audit`(기록만), `Modify`(자동 수정), `DeployIfNotExists` …
- **태그**: `costCenter=lab` 같은 이름표. 비용 분석, 소유자 식별, 자동화에 사용합니다.

이 실습에서는 리소스 그룹 하나에 **내장(Built-in) 정책 2개**를 `Deny` 로 할당합니다.

| 정책 | 정의 ID | 효과 |
|------|---------|------|
| Allowed locations | `e56962a6-4747-49cd-b67b-bf8b01975c4c` | 허용 지역 밖에는 리소스 생성 거부 |
| Require a tag on resources | `871b6d14-10aa-478d-b590-94f262ecfa99` | `costCenter` 태그 없으면 생성 거부 |

## 1. 실습용 리소스 그룹 만들기

```bash
source scripts/env.sh
az group create -n $POLICY_RG -l $LOCATION --tags $LAB_TAG -o none
SCOPE=$(az group show -n $POLICY_RG --query id -o tsv)
```

## 2. 정책 할당

```bash
# ① 허용 지역: 한국 중부/남부만
az policy assignment create --name allowed-locations \
  --display-name "Allowed locations (lab)" \
  --scope $SCOPE \
  --policy e56962a6-4747-49cd-b67b-bf8b01975c4c \
  --params '{"listOfAllowedLocations":{"value":["koreacentral","koreasouth"]}}' -o none

# ② 필수 태그: costCenter
az policy assignment create --name require-costcenter-tag \
  --display-name "Require costCenter tag (lab)" \
  --scope $SCOPE \
  --policy 871b6d14-10aa-478d-b590-94f262ecfa99 \
  --params '{"tagName":{"value":"costCenter"}}' -o none

az policy assignment list --scope $SCOPE --query "[].displayName" -o tsv
```

> ⏳ 새 정책 할당이 실제로 적용되기까지 **보통 몇 분(최대 약 30분)** 걸립니다. 그 사이 3단계를 시도하면 거부되지 않고 *생성될 수도* 있습니다. 그 경우 `az resource delete`/리소스 그룹째 삭제 후 다시 시도하세요.

## 3. 위반 리소스 만들어 보기 💥

스토리지 계정으로 시험합니다 (이름은 소문자/숫자만).

**(a) 허용되지 않은 지역** (태그는 있음)

```bash
az storage account create -g $POLICY_RG -n stpol$LAB_SUFFIX -l eastus --sku Standard_LRS \
  --tags costCenter=lab -o none
```

→ `RequestDisallowedByPolicy ... Allowed locations (lab)` 오류 ✅

**(b) 필수 태그 누락** (지역은 허용)

```bash
az storage account create -g $POLICY_RG -n stpol$LAB_SUFFIX -l koreacentral --sku Standard_LRS -o none
```

→ `RequestDisallowedByPolicy ... Require costCenter tag (lab)` 오류 ✅

**(c) 규칙을 지킨 경우**

```bash
az storage account create -g $POLICY_RG -n stpol$LAB_SUFFIX -l koreacentral --sku Standard_LRS \
  --tags costCenter=lab -o none && echo "✅ 생성 성공"
```

오류 메시지에서 **어떤 정책 할당이 막았는지**(`policyAssignmentName`)를 읽는 습관을 들이세요. 거부는 *리소스가 만들어지기 전*에 Azure Resource Manager가 수행합니다.

## 4. 준수 상태(Compliance) 확인

```bash
az policy state trigger-scan -g $POLICY_RG --no-wait
az policy state list -g $POLICY_RG \
  --query "[].{리소스:resourceId, 정책:policyAssignmentName, 준수:complianceState}" -o table
```

평가에 몇 분 걸립니다. 포털 → **Policy → 규정 준수**에서 그래프로도 볼 수 있습니다.

## 5. 도전 과제

1. **Audit 로 바꾸기:** *Allowed locations* 는 `effect` 파라미터를 지원합니다. 할당을 `Audit` 으로 다시 만들어 보세요. 거부 대신 *비준수로 기록*만 됩니다. 처음 도입할 때 안전한 방법입니다.

   ```bash
   az policy assignment create --name allowed-locations-audit --display-name "Allowed locations - Audit (lab)" \
     --scope $SCOPE --policy e56962a6-4747-49cd-b67b-bf8b01975c4c \
     --params '{"listOfAllowedLocations":{"value":["koreacentral"]},"effect":{"value":"Audit"}}' -o none
   ```

2. **태그 자동 채우기:** 내장 정책 *Inherit a tag from the resource group*(`cd3aa116-8754-49c9-a813-ad46512ece54`)은 `Modify` 효과로 리소스 그룹의 태그를 리소스에 **자동으로 복사**합니다(수정 효과는 관리 ID와 `--location`/`--mi-system-assigned` 옵션이 필요합니다). 거부만이 거버넌스가 아닙니다.
3. **범위 넓히기:** 같은 정책을 구독/관리 그룹에 할당하면 하위 전체에 상속됩니다. (실습 9의 범위 개념과 같습니다)

## ❓ 점검 퀴즈

1. Owner 권한이 있는데도 (a)가 거부된 이유는? (RBAC ≠ Policy)
2. 이미 존재하는 비준수 리소스는 `Deny` 정책이 삭제해 줄까요? (아니요. 비준수로 표시될 뿐)
3. `Deny` 와 `Audit` 중 신규 도입에 안전한 것은?

## 🛠 문제 해결

| 증상 | 해결 |
|------|------|
| (a)/(b) 가 거부되지 않고 생성됨 | 정책 적용 지연. 몇 분 후 리소스 삭제 후 재시도 |
| `AuthorizationFailed` (정책 할당 시) | `Microsoft.Authorization/policyAssignments/write` 권한 필요 (Owner 또는 Resource Policy Contributor) |
| `MissingSubscriptionRegistration` (PolicyInsights) | `bash scripts/00-setup.sh` 재실행 |
| 스토리지 이름 중복 | 이름 접미사를 바꿔 재시도 |

🧹 **마지막 정리:** `bash scripts/cleanup.sh`

🎉 수고하셨습니다! 이제 PaaS 배포 → 비밀 관리 → 접근 제어 → 거버넌스의 흐름을 한 바퀴 돌았습니다.
