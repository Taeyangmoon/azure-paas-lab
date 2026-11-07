# 실습 2. Azure Functions: HTTP 트리거 함수

[🇺🇸 English](README.en.md) | 🇰🇷 한국어 | [← 처음으로](../../README.md) | [← 실습 1](../01-app-service/README.md) | [다음: 실습 3 →](../03-key-vault/README.md)

⏱ 20~30분 · 💸 호출 기반 + Private Endpoint 시간당 과금 · 🎯 **서버리스를 가장 짧은 코드로 체험합니다.**

## 개념 먼저

- **서버리스**: 서버가 없는 게 아니라 *서버를 내가 신경 쓰지 않는* 것입니다. 요청이 오면 실행되고, 없으면 비용이 거의 들지 않습니다.
- **트리거**: 함수를 깨우는 이벤트(HTTP 요청, 타이머, 큐 메시지 …). 이 실습은 **HTTP 트리거**입니다.
- 이 실습은 **Flex Consumption** 요금제를 사용합니다. 사용량 기반이며 새 함수 앱에 권장되는 서버리스 호스팅입니다.
- 스토리지는 **공용 접근과 키 인증을 끈 상태**로 사용합니다. 함수가 **관리 ID + Private Endpoint**로 접근하므로 현재 관리형 구독의 정책을 해제할 필요가 없습니다.

| | App Service (실습 1) | Functions (실습 2) |
|---|---|---|
| 단위 | 앱 전체 | 함수(작은 코드 조각) |
| 실행 | 항상 켜져 있음(플랜) | 요청 시 실행 |
| 과금 | 플랜 시간 기준 | 실행 횟수·시간 기준 |

## 코드는 이게 전부입니다

`src/function/function_app.py` 중 핵심:

```python
@app.route(route="hello", methods=["GET", "POST"])
def hello(req: func.HttpRequest) -> func.HttpResponse:
    name = req.params.get("name")
    return func.HttpResponse(f"안녕하세요, {name}!")
```

## 1. 로컬에서 실행

```bash
source scripts/env.sh
cd src/function
func start
```

새 터미널(`+` 버튼)에서 호출해 봅니다.

```bash
curl "http://localhost:7071/api/hello?name=Azure"
curl -i "http://localhost:7071/api/hello"        # 400: name 누락
```

확인 후 `Ctrl+C` 로 종료하고 `cd ../..` 로 루트에 돌아옵니다.

로컬 런타임은 기본적으로 함수 키를 검사하지 않습니다. 다음 Azure 단계에서 실제 401/200을 비교합니다.

## 2. Azure 준비와 배포 — 명령 한 줄

저장소 루트에서 실행합니다. 첫 네트워크 준비·배포는 몇 분 걸립니다.

```bash
bash scripts/02-functions.sh
```

스크립트가 스토리지, 관리 ID, VNet/Private DNS/Private Endpoint, Flex 함수 앱을 만들고 Python 코드를 원격 빌드·배포합니다. Application Insights는 비용과 구성을 줄이기 위해 생략합니다.

```text
내 요청 ── HTTPS + 함수 키 ──▶ Functions (Flex Consumption)
                                  │ 관리 ID (스토리지 비밀번호 없음)
                                  ▼ VNet + Private Endpoint
                             비공개 Blob 스토리지
```

필수 이해는 두 가지입니다. **함수 키**는 *호출자 → 함수*를 보호하고, **관리 ID + RBAC**는 *함수 → 스토리지*를 보호합니다. `Storage Blob Data Owner`는 함수 호스트의 상태·키·배포 패키지 관리를 위해 **이 스토리지 계정 범위에만** 부여합니다.

코드를 수정한 뒤 같은 명령을 다시 실행하면 재배포됩니다. 이름·네트워크는 재사용합니다.

## 3. 호출해 보기: 함수 키

이 함수는 `AuthLevel.FUNCTION` 입니다. **키 없이는 호출할 수 없습니다.** 첫 번째 보안 개념입니다.

```bash
source scripts/env.sh
HOST=$(az functionapp show -g $RG -n $FUNCAPP --query "properties.defaultHostName || defaultHostName" -o tsv)

# 키 없이 → 401 Unauthorized
curl -i "https://$HOST/api/hello?name=Azure"

# 키와 함께 → 200 OK
KEY=$(az functionapp keys list -g $RG -n $FUNCAPP --query functionKeys.default -o tsv)
curl -i "https://$HOST/api/hello?name=Azure" -H "x-functions-key: $KEY"

# JSON 본문도 가능 → 200; name이 없거나 문자열이 아니면 → 400
curl -i "https://$HOST/api/hello" -H "x-functions-key: $KEY" \
  -H "Content-Type: application/json" --data '{"name":"Azure"}'
unset KEY
```

> 🔐 키는 URL(`?code=`)보다 **헤더**로 보내는 편이 로그에 덜 남습니다. 그리고 키는 *약한 보호 수단*입니다. 실제 서비스에서는 Microsoft Entra 인증(Easy Auth)을 함께 고려하세요.

## 4. 정책을 지킨 상태 확인

```bash
az storage account show -g $RG -n $FUNC_STORAGE \
  --query '{publicNetworkAccess:publicNetworkAccess,allowSharedKeyAccess:allowSharedKeyAccess}' -o json
az functionapp show -g $RG -n $FUNCAPP --query "properties.virtualNetworkSubnetId || virtualNetworkSubnetId" -o tsv
```

`Disabled`, `false`, 그리고 서브넷 ID가 나오면 정상입니다. **공용 스토리지나 스토리지 키 없이도 함수가 실제로 동작**한 것입니다.

- **Cold start:** 한동안 호출하지 않다가 호출하면 첫 응답이 조금 느립니다. `time curl ...` 로 비교해 보세요.
- **비용:** 함수 실행은 호출 기반이지만 **Private Endpoint는 호출이 없어도 시간당 과금**됩니다. 실습이 끝나면 전체 정리하세요.

## ❓ 점검 퀴즈

1. 서버리스에서 "서버가 없다"는 말은 정확한 표현일까요?
2. 같은 기능을 App Service로 만들었다면 트래픽이 0일 때 비용은?
3. 함수 키가 유출되면 어떻게 해야 하나요? (`az functionapp keys set` / 포털에서 키 갱신)

## 🛠 문제 해결

| 증상 | 해결 |
|------|------|
| `func: command not found` | Codespace 를 재빌드(`Rebuild Container`)하거나 `.devcontainer` 를 확인 |
| 배포 직후 404/503 또는 빈 함수 키 | 호스트 기동·RBAC/DNS 전파에 1~2분이 걸릴 수 있습니다. 잠시 후 키 조회와 호출을 재시도 |
| `functionKeys.default` 가 비어 있음 | 함수 호스트가 아직 시작 전입니다. 1~2분 후 재시도하거나 포털 *앱 키* 에서 확인 |
| `Key based authentication is not permitted` | 예전 수동 생성 명령 대신 `bash scripts/02-functions.sh`를 사용하세요. 공용 접근/키 인증을 켜지 않습니다 |
| 지원하지 않는 지역 | 시작 전에 `az functionapp list-flexconsumption-locations -o table`로 확인. 지역 변경은 기존 랩을 정리한 뒤 모든 실습을 같은 지역에서 다시 시작 |
| 스토리지 계정 이름 중복 | `rm .lab-env && source scripts/env.sh` 로 새 접미사 생성 (기존 리소스 정리 후) |

➡️ 다음: [실습 3. Key Vault + 관리 ID](../03-key-vault/README.md)
