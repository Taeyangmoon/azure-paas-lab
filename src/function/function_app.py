import json
import logging
import os

import azure.functions as func

# FUNCTION 레벨: 호출 시 함수 키(x-functions-key)가 필요합니다. 로컬 실행에서는 키를 검사하지 않습니다.
# FUNCTION level: callers must send a function key in Azure. Not enforced when running locally.
app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)


@app.route(route="hello", methods=["GET", "POST"])
def hello(req: func.HttpRequest) -> func.HttpResponse:
    name = req.params.get("name")
    if not name:
        try:
            name = (req.get_json() or {}).get("name")
        except ValueError:
            name = None
    logging.info("hello called (name=%s)", name)
    if not name:
        return func.HttpResponse(
            "name 쿼리 문자열 또는 JSON 본문을 넣어 주세요 / Pass ?name=... or a JSON body.", status_code=400
        )
    return func.HttpResponse(f"안녕하세요, {name}! Hello from Azure Functions 👋")


@app.route(route="secret", methods=["GET"])
def secret(req: func.HttpRequest) -> func.HttpResponse:
    """실습 8(선택): Key Vault 참조로 주입된 앱 설정을 평범한 환경변수로 읽습니다.
    Lab 8 (optional): reads a Key Vault-referenced app setting as a plain env var."""
    value = os.getenv("SECRET_FROM_REFERENCE")
    if not value:
        body = {"status": "not-configured"}
    elif value.startswith("@Microsoft.KeyVault("):
        body = {"status": "unresolved"}
    else:
        body = {"status": "ok", "secret": f"{value[:2]}{'*' * max(len(value) - 2, 0)} (length={len(value)})"}
    return func.HttpResponse(json.dumps(body), mimetype="application/json")
