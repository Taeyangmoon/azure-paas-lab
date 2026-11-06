# 실습 6. Azure App Service: 샘플 웹앱 배포

[🇺🇸 English](README.en.md) | 🇰🇷 한국어 | [← 처음으로](../../README.md) | [다음: 실습 7 →](../07-functions/README.md)

⏱ 20분 · 💸 무료(F1) · 🎯 **PaaS가 VM 대비 무엇을 대신 관리해 주는지 체감합니다.**

## 개념 먼저

VM에 웹앱을 올리려면 OS 설치·패치, 런타임 설치, 웹서버 설정, 인증서, 방화벽, 모니터링을 직접 해야 합니다. **App Service(PaaS)** 는 코드만 올리면 이를 대신합니다.

| 항목 | VM (IaaS) | App Service (PaaS) |
|------|-----------|--------------------|
| OS 패치/보안 업데이트 | 👤 내가 | ☁️ Azure |
| 런타임(Python 등) 설치·업데이트 | 👤 내가 | ☁️ Azure (버전만 선택) |
| 웹서버/로드밸런서/HTTPS 종단 | 👤 내가 | ☁️ Azure |
| 앱 코드·앱 설정·접근 제어 | 👤 내가 | 👤 내가 |
| 스케일 아웃 | VM 복제 직접 구성 | 슬라이더/명령 한 줄 |

> 공동 책임 모델: PaaS에서도 **내 코드, 데이터, ID/접근 권한**은 여전히 내 책임입니다. 이것이 이 랩의 나머지 실습(8~10)으로 이어집니다.

## 만들 것

```text
리소스 그룹 ─┬─ App Service 플랜 (F1, Linux)
             └─ Web App (Python 3.12 / Flask)
```

## 1. 변수 준비

저장소 루트에서 실행합니다.

```bash
source scripts/env.sh
```

## 2. 로컬에서 먼저 실행해 보기 (선택)

```bash
cd src/webapp
python app.py
```

Codespaces 하단 **포트** 탭의 `8000` 포트를 열면 앱이 보입니다. 확인했으면 `Ctrl+C` 로 종료하고 루트로 돌아옵니다(`cd ../..`).

## 3. 리소스 만들기

```bash
# 리소스 그룹 (실습 6~9 공용)
az group create -n $RG -l $LOCATION --tags $LAB_TAG -o none

# App Service 플랜: 앱이 실행되는 "서버 묶음"의 사양
az appservice plan create -g $RG -n $PLAN --is-linux --sku $WEBAPP_SKU -o none

# 웹앱 (Python 3.12 런타임을 선택만 하면 됩니다)
az webapp create -g $RG -p $PLAN -n $WEBAPP --runtime "PYTHON:3.12" -o none
```

보안 기본값을 설정하고 시작 명령/빌드 옵션을 지정합니다.

```bash
az webapp update -g $RG -n $WEBAPP --https-only true -o none
az webapp config set -g $RG -n $WEBAPP \
  --min-tls-version 1.2 --ftps-state Disabled \
  --startup-file "gunicorn --bind=0.0.0.0 --timeout 600 app:app" -o none
az webapp config appsettings set -g $RG -n $WEBAPP \
  --settings SCM_DO_BUILD_DURING_DEPLOYMENT=true -o none
```

> 💡 `SCM_DO_BUILD_DURING_DEPLOYMENT=true` 는 업로드한 코드를 Azure가 대신 빌드(`pip install`)하게 합니다.

## 4. 코드 배포

```bash
(cd src/webapp && zip -qr ../../webapp.zip . -x "__pycache__/*")
az webapp deploy -g $RG -n $WEBAPP --src-path webapp.zip --type zip
```

## 5. 확인

```bash
URL="https://$(az webapp show -g $RG -n $WEBAPP --query defaultHostName -o tsv)"
echo $URL
curl -s $URL/info
```

브라우저로 `$URL` 도 열어 보세요. **`/info`** 에서 `WEBSITE_SITE_NAME` 등 *플랫폼이 넣어 준 값*과 Python 버전, OS를 볼 수 있습니다. 내가 설치한 적 없는 것들입니다. 이게 PaaS입니다.

> 첫 요청은 앱이 깨어나느라 30초 이상 걸릴 수 있습니다. F1은 유휴 시 잠듭니다.

## 6. 직접 체감해 보기

1. **HTTP로 접속하면?** `curl -i http://${URL#https://}` → HTTPS로 리다이렉트(301)됩니다. HTTPS 전용 설정 덕분입니다.
2. **로그 보기:** `az webapp log config -g $RG -n $WEBAPP --application-logging filesystem --level information -o none && az webapp log tail -g $RG -n $WEBAPP` (`Ctrl+C`로 종료)
3. **코드 수정 후 재배포:** `src/webapp/app.py` 의 `/` 응답 문구를 바꾸고 4단계를 다시 실행해 보세요. 서버 접속(SSH) 없이 끝납니다.
4. **스케일 아웃(유료 SKU 전용):** `az appservice plan update -g $RG -n $PLAN --number-of-workers 2` (F1은 불가. 개념만 확인하세요)

## ❓ 점검 퀴즈

1. 이 실습에서 **OS 패치**는 누가 했나요? → Azure
2. 앱 코드의 보안 취약점은 누구 책임인가요? → 나
3. `--https-only true` 를 끄면 어떻게 되나요? 왜 켜 두어야 할까요?

## 🛠 문제 해결

| 증상 | 해결 |
|------|------|
| `Operation cannot be completed without additional quota` (F1/Linux) | `export WEBAPP_SKU=B1` 후 플랜부터 다시 생성 (다른 지역 `export LOCATION=japaneast` 도 가능) |
| `The webapp name is already in use` | `rm .lab-env && source scripts/env.sh` 로 새 접미사 생성 |
| 사이트가 `Application Error` | `az webapp log tail -g $RG -n $WEBAPP` 로 로그 확인. 시작 명령(`app:app`)과 `requirements.txt` 확인 |
| `zip: command not found` | `sudo apt-get update && sudo apt-get install -y zip` |

➡️ 다음: [실습 7. Azure Functions](../07-functions/README.md) (웹앱은 지우지 마세요. 실습 8에서 계속 씁니다)
