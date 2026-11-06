import os
import platform
import sys
from datetime import datetime, timezone

from flask import Flask, jsonify

app = Flask(__name__)
app.json.ensure_ascii = False  # JSON 응답에서 한글이 \uXXXX 로 깨지지 않게

# App Service(PaaS)가 자동으로 넣어 주는 값만 골라서 보여 줍니다. (전체 환경변수를 출력하지 않습니다!)
# Only a safe allow-list of env vars is shown. Never dump all environment variables.
PLATFORM_VARS = ["WEBSITE_SITE_NAME", "WEBSITE_INSTANCE_ID", "WEBSITE_SKU", "REGION_NAME"]


def mask(value: str) -> str:
    """비밀 값은 화면에 그대로 노출하지 않고 앞 2글자만 보여 줍니다 / show only the first 2 chars."""
    return f"{value[:2]}{'*' * max(len(value) - 2, 0)} (length={len(value)})"


@app.get("/")
def index():
    site = os.getenv("WEBSITE_SITE_NAME")
    where = "Azure App Service (PaaS)" if site else "로컬 / Local (Codespaces)"
    return (
        "<h1>☁️ Azure PaaS Lab</h1>"
        f"<p>실행 위치 / Running on: <b>{where}</b></p>"
        "<ul>"
        "<li><a href='/info'>/info</a> – 플랫폼이 알려 주는 정보 / what the platform tells us</li>"
        "<li><a href='/secret/reference'>/secret/reference</a> – 실습 8: Key Vault 참조 / Key Vault reference</li>"
        "<li><a href='/secret/sdk'>/secret/sdk</a> – 실습 8: SDK + 관리 ID / SDK + managed identity</li>"
        "<li><a href='/healthz'>/healthz</a></li>"
        "</ul>"
    )


@app.get("/healthz")
def healthz():
    return jsonify(status="ok")


@app.get("/info")
def info():
    return jsonify(
        time_utc=datetime.now(timezone.utc).isoformat(),
        python=sys.version.split()[0],
        os=platform.platform(),
        platform_vars={k: os.getenv(k) for k in PLATFORM_VARS if os.getenv(k)},
        managed_identity_enabled=bool(os.getenv("IDENTITY_ENDPOINT")),
    )


@app.get("/secret/reference")
def secret_from_reference():
    """앱 설정 SECRET_FROM_REFERENCE 는 Key Vault 참조이며, 코드는 평범한 환경변수로 읽기만 합니다.
    The code just reads a normal env var; App Service resolves the Key Vault reference."""
    value = os.getenv("SECRET_FROM_REFERENCE")
    if not value:
        return jsonify(status="not-configured", hint="앱 설정 SECRET_FROM_REFERENCE 가 없습니다 / setting missing"), 404
    if value.startswith("@Microsoft.KeyVault("):
        return jsonify(
            status="unresolved",
            hint="Key Vault 참조가 아직 해석되지 않았습니다. 역할 부여 후 앱을 재시작하고 1~2분 기다려 보세요. "
            "/ Reference not resolved yet: check the role assignment, restart the app, wait 1-2 min.",
        ), 502
    return jsonify(status="ok", secret=mask(value))


@app.get("/secret/sdk")
def secret_from_sdk():
    """Azure SDK 의 DefaultAzureCredential 이 환경에 맞는 자격 증명을 알아서 고릅니다.
    Azure 위에서는 관리 ID, Codespaces 에서는 `az login` 계정을 사용합니다. 코드에 비밀번호가 없습니다.
    DefaultAzureCredential picks managed identity on Azure and `az login` locally. No password in code."""
    vault_url = os.getenv("KEY_VAULT_URL")
    name = os.getenv("KEY_VAULT_SECRET_NAME", "demo-secret")
    if not vault_url:
        return jsonify(status="not-configured", hint="앱 설정 KEY_VAULT_URL 이 없습니다 / setting missing"), 404
    try:
        from azure.identity import DefaultAzureCredential
        from azure.keyvault.secrets import SecretClient

        client = SecretClient(vault_url=vault_url, credential=DefaultAzureCredential())
        return jsonify(status="ok", secret=mask(client.get_secret(name).value))
    except Exception as exc:  # 실습용: 오류 종류와 첫 줄만 보여 줍니다 / lab only: show error type + first line
        return jsonify(status="error", type=type(exc).__name__, message=str(exc).splitlines()[0][:300]), 502


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8000")))
