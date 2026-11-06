# 실습 4. Azure RBAC와 Microsoft Entra ID: 역할 할당, 최소 권한

[🇺🇸 English](README.en.md) | 🇰🇷 한국어 | [← 처음으로](../../README.md) | [← 실습 3](../03-key-vault/README.md) | [다음: 실습 5 →](../05-policy-governance/README.md)

⏱ 25분 · 💸 무료 · 🎯 실습 3에서 쓴 권한 부여 원리를 **일반화**합니다.
📌 사전 조건: [실습 3](../03-key-vault/README.md) 완료

## 개념 먼저

**Microsoft Entra ID** 는 "**누구**인가"(인증)를, **Azure RBAC** 는 "**무엇을 해도 되는가**"(권한 부여)를 담당합니다.

```text
역할 할당 (Role Assignment) =  누가(보안 주체)  +  무슨 역할(역할 정의)  +  어디서(범위)
```

| 구성 요소 | 예시 |
|-----------|------|
| 보안 주체 | 사용자, 그룹, 서비스 주체, **관리 ID** (실습 3의 웹앱!) |
| 역할 정의 | Reader, Contributor, Owner, Key Vault Secrets User … (직접 만들 수도 있음) |
| 범위 | 관리 그룹 ⊃ 구독 ⊃ 리소스 그룹 ⊃ 리소스 (**아래로 상속**) |

> **최소 권한 원칙**: 필요한 *역할*을 필요한 *범위*에 필요한 *기간*만 부여합니다.

## 1. 내 환경 살펴보기

```bash
source scripts/env.sh
RG_ID=$(az group show -n $RG --query id -o tsv)
KV_ID=$(az keyvault show -g $RG -n $KV --query id -o tsv)
PRINCIPAL_ID=$(az webapp identity show -g $RG -n $WEBAPP --query principalId -o tsv)

# Entra ID 에서의 나
az ad signed-in-user show --query "{이름:displayName, 계정:userPrincipalName, 객체ID:id}" -o table

# 웹앱의 관리 ID 도 Entra ID 에 "서비스 주체"로 존재합니다
az ad sp show --id $PRINCIPAL_ID --query "{이름:displayName, 유형:servicePrincipalType, 객체ID:id}" -o table

# 이 관리 ID가 가진 권한 (실습 3에서 부여한 것)
az role assignment list --assignee $PRINCIPAL_ID --all -o table
```

## 2. 역할 안에는 무엇이 있을까?

```bash
az role definition list --name "Reader" --query "[0].permissions[0].actions" -o tsv
az role definition list --name "Key Vault Secrets User" --query "[0].permissions[0].{actions:actions, dataActions:dataActions}" -o json
```

- `actions`: **관리 평면** (리소스 생성/삭제/설정)
- `dataActions`: **데이터 평면** (비밀 읽기, Blob 읽기 …). 실습 3에서 Owner가 비밀을 못 읽은 이유입니다.

## 3. 최소 권한 실험: "읽기 전용" 사용자 만들기

실습용 **서비스 주체**(앱용 계정)를 만들어 `Reader` 역할을 **리소스 그룹 범위**로만 부여합니다.

```bash
SP=$(az ad sp create-for-rbac --name $SP_NAME --role Reader --scopes $RG_ID -o json)
SP_APP_ID=$(echo "$SP" | jq -r .appId)
SP_PASSWORD=$(echo "$SP" | jq -r .password)
SP_TENANT=$(echo "$SP" | jq -r .tenant)
SP_OBJECT_ID=$(az ad sp show --id $SP_APP_ID --query id -o tsv)
```

> 🔐 `$SP_PASSWORD` 는 지금 이 터미널에만 있습니다. 파일·Git에 저장하지 마세요. (정리 때 삭제됩니다.) 실무에서는 비밀번호가 필요 없는 **관리 ID** 를 우선하세요. 이 랩에서는 "다른 사람의 시점"을 흉내 내려고 사용합니다.

이 계정으로 **별도 로그인 세션**을 만들어 시험합니다(내 `az login` 은 그대로 유지).

```bash
as_sp() { AZURE_CONFIG_DIR="$LAB_ROOT/.azure-sp" "$@"; }
as_sp az login --service-principal -u $SP_APP_ID -p "$SP_PASSWORD" --tenant $SP_TENANT -o none

# ✅ 읽기: 성공
as_sp az group show -n $RG --query name -o tsv
as_sp az webapp list -g $RG --query "[].name" -o tsv

# ❌ 쓰기: AuthorizationFailed
as_sp az storage account create -g $RG -n st9$LAB_SUFFIX -l $LOCATION --sku Standard_LRS -o none

# ❌ 비밀 읽기: Reader 는 관리 평면만 → Forbidden (데이터 평면은 별도!)
as_sp az keyvault secret show --vault-name $KV -n demo-secret
```

### 필요한 것만 추가하기

"스토리지 계정을 만들 수 있어야 한다"는 요구가 생겼다고 합시다. `Contributor`(거의 전부)가 아니라 **딱 맞는 역할**을 **같은 범위**에 부여합니다.

```bash
az role assignment create --assignee-object-id $SP_OBJECT_ID --assignee-principal-type ServicePrincipal \
  --role "Storage Account Contributor" --scope $RG_ID -o none

for i in $(seq 1 10); do
  as_sp az storage account create -g $RG -n st9$LAB_SUFFIX -l $LOCATION --sku Standard_LRS -o none 2>/dev/null \
    && { echo "✅ 스토리지 생성 성공"; break; }
  echo "⏳ 권한 전파 대기 ($i/10)..."; sleep 20
done

# ❌ 하지만 웹앱을 멈추는 것은 여전히 불가 (Microsoft.Web 권한 없음)
as_sp az webapp stop -g $RG -n $WEBAPP
```

확인: `az role assignment list --assignee $SP_OBJECT_ID --all -o table`

> 포털에서도 확인해 보세요: 리소스 그룹 → **액세스 제어(IAM)** → **액세스 확인** 에서 위 주체를 검색하면 *유효 권한*이 보입니다. 관리자가 "이 신원이 뭘 할 수 있지?"를 확인하는 방법입니다.

## 4. 도전 과제: 사용자 지정 역할

"웹앱 **재시작만** 가능한" 역할을 만들어 봅니다.

```bash
cat > /tmp/role.json <<EOF
{
  "Name": "Web App Restarter ($LAB_SUFFIX)",
  "Description": "Can view and restart web apps only.",
  "Actions": ["Microsoft.Web/sites/read", "Microsoft.Web/sites/restart/action"],
  "NotActions": [],
  "AssignableScopes": ["$RG_ID"]
}
EOF
az role definition create --role-definition @/tmp/role.json -o none

az role assignment create --assignee-object-id $SP_OBJECT_ID --assignee-principal-type ServicePrincipal \
  --role "Web App Restarter ($LAB_SUFFIX)" --scope $RG_ID -o none

# 1~3분 후
as_sp az webapp restart -g $RG -n $WEBAPP      # ✅
as_sp az webapp stop -g $RG -n $WEBAPP         # ❌ 여전히 거부
```

## ❓ 점검 퀴즈

1. Reader 역할로 Key Vault 비밀을 읽을 수 있었나요? 왜?
2. 역할을 **구독** 범위가 아닌 **리소스 그룹**에 준 이점은?
3. 사람이 아닌 앱에 권한을 줄 때 비밀번호가 필요 없는 방법은? (실습 3: 관리 ID)

## 🛠 문제 해결

| 증상 | 해결 |
|------|------|
| `az ad sp create-for-rbac` → `Insufficient privileges` | 테넌트가 앱 등록을 막은 경우입니다. 3·4단계를 건너뛰고 1~2단계 + 포털 **IAM → 액세스 확인** 으로 진행하세요 |
| `as_sp az login` 후 구독이 없다고 나옴 | 역할 전파를 1~2분 기다린 뒤 재시도 |
| 역할 부여 직후에도 `AuthorizationFailed` | 정상입니다. 전파에 최대 몇 분 걸립니다 |
| `jq: command not found` | `sudo apt-get install -y jq` |

> 🧹 서비스 주체·사용자 지정 역할은 `bash scripts/cleanup.sh` 가 삭제합니다.

➡️ 다음: [실습 5. Azure Policy & 태그 거버넌스](../05-policy-governance/README.md)
