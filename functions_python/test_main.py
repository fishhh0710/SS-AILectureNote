import unittest
from unittest.mock import Mock, patch

import main


class FunctionContractTests(unittest.TestCase):
    def test_request_payload_unwraps_data(self):
        request = Mock()
        request.get_json.return_value = {"data": {"question": "test"}}
        self.assertEqual(main._request_payload(request), {"question": "test"})

    def test_required_string_rejects_blank(self):
        with self.assertRaisesRegex(ValueError, "question"):
            main._required_string({"question": "  "}, "question")

    def test_safe_storage_id_matches_flutter_contract(self):
        self.assertEqual(main._safe_storage_id("course/中文 1"), "course____1")

    def test_realtime_prompt_contains_summary_and_chunk(self):
        prompt = main._realtime_agent_prompt("Old summary", "New explanation")
        self.assertIn("Old summary", prompt)
        self.assertIn("New explanation", prompt)

    @patch.dict(main.os.environ, {}, clear=True)
    def test_azure_handler_reports_missing_key(self):
        request = Mock(method="POST")
        with self.assertLogs(level="ERROR"):
            response = main._azure_token_handler(request)
        self.assertEqual(response.status_code, 500)
        self.assertIn("not configured", response.get_data(as_text=True))


if __name__ == "__main__":
    unittest.main()
