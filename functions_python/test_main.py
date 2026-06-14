import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import Mock, patch

import attention_agent
import function_common
import realtime_agent
import speech


class FunctionContractTests(unittest.TestCase):
    def test_request_payload_unwraps_data(self):
        request = Mock()
        request.get_json.return_value = {"data": {"question": "test"}}
        self.assertEqual(function_common.request_payload(request), {"question": "test"})

    def test_required_string_rejects_blank(self):
        with self.assertRaisesRegex(ValueError, "question"):
            function_common.required_string({"question": "  "}, "question")

    def test_safe_storage_id_matches_flutter_contract(self):
        self.assertEqual(function_common.safe_storage_id("course/中文 1"), "course____1")

    def test_parse_realtime_context_limits_previous_segments(self):
        segments = [f"segment-{index}" for index in range(12)]
        self.assertEqual(
            realtime_agent.parse_recent_segments(segments),
            segments[-9:],
        )

    def test_normalize_realtime_output_enforces_summary_exclusivity(self):
        output = realtime_agent.RealtimeAgentOutput(
            page_number=3,
            new_points=["- New point", "null"],
            questions=["Why is this true?"],
            targets=[
                realtime_agent.RealtimeTarget(
                    text="diagram",
                    color="orange",
                    description="the central diagram",
                )
            ],
            update_note_at="summary",
        )
        result = realtime_agent.normalize_realtime_output(output)
        self.assertEqual(result["update_note_at"], "summary")
        self.assertEqual(result["new_points"], ["- New point"])
        self.assertEqual(result["targets"], [])

    def test_normalize_realtime_output_rejects_empty_action(self):
        output = realtime_agent.RealtimeAgentOutput(
            page_number=3,
            update_note_at="slides",
        )
        result = realtime_agent.normalize_realtime_output(output)
        self.assertEqual(result["update_note_at"], "none")
        self.assertEqual(result["page_number"], 3)

    def test_attention_gate_waits_thirty_seconds(self):
        now = datetime(2026, 6, 15, tzinfo=timezone.utc)
        gate = attention_agent.attention_gate(
            student_state={
                "currentPage": 1,
                "currentPageDurationSeconds": 20,
                "appLifecycle": "background",
                "sessionStartedAt": (now - timedelta(seconds=20)).isoformat(),
            },
            teacher_page=3,
            session_state={},
            now=now,
        )
        self.assertFalse(gate["should_run"])
        self.assertFalse(gate["interval_ready"])

    def test_attention_gate_runs_for_mismatch_after_interval(self):
        now = datetime(2026, 6, 15, tzinfo=timezone.utc)
        gate = attention_agent.attention_gate(
            student_state={
                "currentPage": 1,
                "currentPageDurationSeconds": 35,
                "appLifecycle": "foreground",
                "sessionStartedAt": (now - timedelta(seconds=35)).isoformat(),
            },
            teacher_page=3,
            session_state={},
            now=now,
        )
        self.assertTrue(gate["should_run"])
        self.assertTrue(gate["signals"]["page_mismatch"])
        self.assertTrue(gate["signals"]["student_stagnant"])

    def test_attention_gate_detects_teacher_movement(self):
        now = datetime(2026, 6, 15, tzinfo=timezone.utc)
        gate = attention_agent.attention_gate(
            student_state={
                "currentPage": 4,
                "currentPageDurationSeconds": 5,
                "appLifecycle": "foreground",
                "sessionStartedAt": (now - timedelta(minutes=2)).isoformat(),
            },
            teacher_page=4,
            session_state={
                "lastAttentionCheckedAt": (now - timedelta(seconds=31)),
                "teacherPageAtLastCheck": 2,
            },
            now=now,
        )
        self.assertTrue(gate["should_run"])
        self.assertTrue(gate["signals"]["teacher_moved"])

    @patch.dict(speech.os.environ, {}, clear=True)
    def test_azure_handler_reports_missing_key(self):
        request = Mock(method="POST")
        with self.assertLogs(level="ERROR"):
            response = speech.azure_token_handler(request)
        self.assertEqual(response.status_code, 500)
        self.assertIn("not configured", response.get_data(as_text=True))


if __name__ == "__main__":
    unittest.main()
