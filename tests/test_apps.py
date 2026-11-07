import json
import os
import unittest
from unittest.mock import Mock, patch

import azure.functions as func
from azure.core.exceptions import ClientAuthenticationError, HttpResponseError

from src.function import function_app
from src.webapp import app as webapp


class FunctionTests(unittest.TestCase):
    def request(self, body=None, params=None):
        return func.HttpRequest(
            method="POST" if body is not None else "GET",
            url="http://localhost/api/hello",
            headers={"Content-Type": "application/json"},
            params=params or {},
            body=json.dumps(body).encode() if body is not None else b"",
        )

    def test_hello_rejects_non_object_json_and_non_string_names(self):
        for body in ([1], "Azure", 123, {"name": 123}, {"name": ["Azure"]}, {"name": " "}):
            with self.subTest(body=body):
                self.assertEqual(function_app.hello(self.request(body)).status_code, 400)

    def test_hello_accepts_query_and_json_names(self):
        for request in (self.request(params={"name": "Azure"}), self.request({"name": "Azure"})):
            with self.subTest(method=request.method):
                response = function_app.hello(request)
                self.assertEqual(response.status_code, 200)
                self.assertIn("Azure", response.get_body().decode())

    def test_secret_reports_configuration_errors_with_http_errors(self):
        for value, status, code in (("", "not-configured", 404), ("@Microsoft.KeyVault(test)", "unresolved", 502)):
            with self.subTest(status=status), patch.dict(os.environ, {"SECRET_FROM_REFERENCE": value}):
                response = function_app.secret(self.request())
                self.assertEqual(response.status_code, code)
                self.assertEqual(json.loads(response.get_body())["status"], status)


class WebAppTests(unittest.TestCase):
    def test_sdk_preserves_key_vault_denial_status(self):
        for status in (401, 403, 404):
            with self.subTest(status=status):
                error = HttpResponseError(message="Key Vault request failed")
                error.status_code = status
                client = Mock()
                client.get_secret.side_effect = error
                with patch.dict(os.environ, {"KEY_VAULT_URL": "https://example.vault.azure.net/"}):
                    with patch("azure.keyvault.secrets.SecretClient", return_value=client):
                        with patch("azure.identity.DefaultAzureCredential"):
                            with self.assertLogs(webapp.app.logger, level="WARNING"):
                                response = webapp.app.test_client().get("/secret/sdk")
                self.assertEqual(response.status_code, status)
                self.assertEqual(response.json["status"], "error")

    def test_sdk_credential_failure_remains_a_gateway_error(self):
        client = Mock()
        client.get_secret.side_effect = ClientAuthenticationError(message="No credential available")
        with patch.dict(os.environ, {"KEY_VAULT_URL": "https://example.vault.azure.net/"}):
            with patch("azure.keyvault.secrets.SecretClient", return_value=client):
                with patch("azure.identity.DefaultAzureCredential"):
                    with self.assertLogs(webapp.app.logger, level="WARNING"):
                        response = webapp.app.test_client().get("/secret/sdk")
        self.assertEqual(response.status_code, 502)
        self.assertEqual(response.json["type"], "ClientAuthenticationError")


if __name__ == "__main__":
    unittest.main()
