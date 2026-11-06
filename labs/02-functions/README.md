# 실습 2. Azure Functions: HTTP 트리거 함수

[🇺🇸 English](README.en.md) | 🇰🇷 한국어 | [← 처음으로](../../README.md) | [← 실습 1](../01-app-service/README.md) | [다음: 실습 3 →](../03-key-vault/README.md)

⏱ 20분 · 💸 거의 무료(호출 기반) · 🎯 **서버리스를 가장 짧은 코드로 체험합니다.**

## 개념 먼저

- **서버리스**: 서버가 없는 게 아니라 *서버를 내가 신경 쓰지 않는* 것입니다. 요청이 오면 실행되고, 없으면 비용이 거의 들지 않습니다.
- **트리거**: 함수를 깨우는 이벤트(HTTP 요청, 타이머, 큐 메시지 …). 이 실습은 **HTTP 트리거**입니다.
- 이 실습은 **Flex Consumption** 요금제를 사용합니다. 사용량 기반이며 새 함수 앱에 권장되는 서버리스 호스팅입니다.

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

## 2. Azure 리소스 만들기

```bash
source scripts/env.sh
az group create -n $RG -l $LOCATION --tags $LAB_TAG -o none

# 함수 런타임이 상태를 저장하는 스토리지 계정
az storage account create -g $RG -n $FUNC_STORAGE -l $LOCATION \
  --sku Standard_LRS --allow-blob-public-access false --min-tls-version TLS1_2 -o none

# 함수 앱 (Flex Consumption)
az functionapp create -g $RG -n $FUNCAPP --storage-account $FUNC_STORAGE \
  --flexconsumption-location $LOCATION --runtime python --runtime-version 3.12 -o none
```

> `koreacentral` 에서 Flex Consumption 을 지원하지 않는다는 오류가 나면 `az functionapp list-flexconsumption-locations -o table` 로 지원 지역을 확인하고 `export LOCATION=<지역>` 으로 바꾼 뒤, 스토리지 계정과 함수 앱을 그 지역에 만드세요(리소스 그룹은 기존 지역 그대로여도 됩니다).

## 3. 배포

```bash
(cd src/function && func azure functionapp publish $FUNCAPP)
```

완료 메시지에 함수 URL 목록이 표시됩니다.

## 4. 호출해 보기: 함수 키

이 함수는 `AuthLevel.FUNCTION` 입니다. **키 없이는 호출할 수 없습니다.** 첫 번째 보안 개념입니다.

```bash
HOST=$(az functionapp show -g $RG -n $FUNCAPP --query defaultHostName -o tsv)

# 키 없이 → 401 Unauthorized
curl -i "https://$HOST/api/hello?name=Azure"

# 키와 함께 → 200 OK
KEY=$(az functionapp keys list -g $RG -n $FUNCAPP --query functionKeys.default -o tsv)
curl "https://$HOST/api/hello?name=Azure" -H "x-functions-key: $KEY"
```

> 🔐 키는 URL(`?code=`)보다 **헤더**로 보내는 편이 로그에 덜 남습니다. 그리고 키는 *약한 보호 수단*입니다. 실제 서비스에서는 Microsoft Entra 인증(Easy Auth)을 함께 고려하세요.

## 5. 서버리스 체감하기

- **Cold start:** 한동안 호출하지 않다가 호출하면 첫 응답이 조금 느립니다. `time curl ...` 로 비교해 보세요.
- **로그 보기:** Azure 포털 → 함수 앱 → **로그 스트림**
- **비용:** 포털 → 함수 앱 → *Monitoring* 에서 실행 횟수를 확인해 보세요. 호출이 없으면 실행 비용도 없습니다.

## ❓ 점검 퀴즈

1. 서버리스에서 "서버가 없다"는 말은 정확한 표현일까요?
2. 같은 기능을 App Service로 만들었다면 트래픽이 0일 때 비용은?
3. 함수 키가 유출되면 어떻게 해야 하나요? (`az functionapp keys set` / 포털에서 키 갱신)

## 🛠 문제 해결

| 증상 | 해결 |
|------|------|
| `func: command not found` | Codespace 를 재빌드(`Rebuild Container`)하거나 `.devcontainer` 를 확인 |
| 배포 직후 401/404 | 1~2분 기다린 뒤 다시 시도. `func azure functionapp publish` 출력에 함수 목록이 있는지 확인 |
| `functionKeys.default` 가 비어 있음 | 함수 호스트가 아직 시작 전입니다. 1~2분 후 재시도하거나 포털 *앱 키* 에서 확인 |
| 스토리지 계정 이름 중복 | `rm .lab-env && source scripts/env.sh` 로 새 접미사 생성 (기존 리소스 정리 후) |

➡️ 다음: [실습 3. Key Vault + 관리 ID](../03-key-vault/README.md)
