import unittest
import threading
import time
from datetime import datetime, timedelta, timezone
from tempfile import TemporaryDirectory
from unittest.mock import Mock, patch

from pypdf import PdfWriter

import attention_agent
import chat_agent
import function_common
import lecture_ai
import memory_service
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

    def test_memory_preference_id_is_stable_across_content_changes(self):
        first = memory_service.MemoryWrite(
            domain="preference",
            kind="summary_format",
            content="Use bullet points",
            preference_key="summary.format",
            explicit=True,
        )
        second = memory_service.MemoryWrite(
            domain="preference",
            kind="summary_format",
            content="Use concise numbered points",
            preference_key="summary.format",
            explicit=True,
        )
        self.assertEqual(
            memory_service.memory_document_id("user-1", first),
            memory_service.memory_document_id("user-1", second),
        )

    def test_memory_learning_id_normalizes_text(self):
        first = memory_service.MemoryWrite(
            domain="learning",
            kind="confusion",
            content="  Binary   Search ",
        )
        second = memory_service.MemoryWrite(
            domain="learning",
            kind="confusion",
            content="binary search",
        )
        self.assertEqual(
            memory_service.memory_document_id("user-1", first),
            memory_service.memory_document_id("user-1", second),
        )

    def test_memory_scope_requires_identifiers(self):
        with self.assertRaisesRegex(ValueError, "course_id"):
            memory_service.MemoryWrite(
                domain="learning",
                kind="confusion",
                content="Recursion",
                scope="course",
            )

    def test_memory_schema_has_no_confidence_field(self):
        self.assertNotIn("confidence", memory_service.MemoryWrite.model_fields)
        self.assertNotIn("confidence", attention_agent.AttentionAgentOutput.model_fields)

    def test_legacy_candidate_preference_is_effectively_active(self):
        service = memory_service.MemoryService.__new__(memory_service.MemoryService)
        self.assertTrue(
            service._matches(
                {
                    "status": "candidate",
                    "domain": "preference",
                    "scope": "global",
                },
                domains={"preference"},
                statuses={"active"},
                course_id="course-1",
                lecture_id="lecture-1",
            )
        )

    def test_attention_output_creates_learning_memory_evidence(self):
        output = attention_agent.AttentionAgentOutput(
            status="confused",
            page_relevance="same_topic",
            reasoning_summary="Student stayed on a relevant concept.",
            missed_content=["The base case stops recursion."],
            confused_summary="The student may not understand the recursion base case.",
        )
        writes = attention_agent.attention_memory_writes(
            output,
            course_id="course-1",
            lecture_id="lecture-1",
        )
        self.assertEqual([item.kind for item in writes], ["missed_content", "confusion"])
        self.assertTrue(all(item.scope == "lecture" for item in writes))

    def test_chat_prompt_includes_memory_and_course_context(self):
        prompt = chat_agent.build_chat_prompt(
            notes="Recursion notes",
            transcript="Teacher transcript",
            history="user: explain this",
            question="Use examples when explaining",
            memories=[
                {
                    "domain": "preference",
                    "preferenceKey": "explanation.examples",
                    "content": "Use concrete examples",
                }
            ],
        )
        self.assertIn("Use concrete examples", prompt)
        self.assertIn("Recursion notes", prompt)
        self.assertIn("Use examples when explaining", prompt)

    def test_memory_serialization_converts_firestore_timestamps(self):
        result = memory_service.MemorySearchResult(
            memory_id="memory-1",
            data={
                "content": "Use examples",
                "updatedAt": datetime(2026, 6, 15, tzinfo=timezone.utc),
            },
        ).to_dict()
        self.assertEqual(result["updatedAt"], "2026-06-15T00:00:00+00:00")

    def test_pdf_prompt_applies_memory_without_overriding_source(self):
        prompt = lecture_ai._pdf_notes_prompt(
            [
                {
                    "domain": "preference",
                    "content": "Use concise numbered points",
                },
                {
                    "domain": "learning",
                    "content": "The student struggles with recursion base cases",
                },
            ]
        )
        self.assertIn("Use concise numbered points", prompt)
        self.assertIn("recursion base cases", prompt)
        self.assertIn("Memory never overrides the PDF", prompt)

    def test_pdf_is_split_into_five_page_batches(self):
        with TemporaryDirectory() as temp_dir:
            source_path = f"{temp_dir}/source.pdf"
            writer = PdfWriter()
            for _ in range(12):
                writer.add_blank_page(width=100, height=100)
            with open(source_path, "wb") as source_file:
                writer.write(source_file)

            batches, total_pages = lecture_ai._split_pdf_batches(
                source_path, temp_dir
            )

            self.assertEqual(total_pages, 12)
            self.assertEqual(
                [(item.start_page, item.end_page) for item in batches],
                [(1, 5), (6, 10), (11, 12)],
            )

    def test_batch_pages_are_remapped_to_original_page_numbers(self):
        pages = lecture_ai._normalize_batch_pages(
            {
                "pages": [
                    {"page_number": 1, "markdown": "First"},
                    {"page_number": 2, "markdown": "Second"},
                ]
            },
            start_page=11,
            expected_page_count=2,
        )
        self.assertEqual([page["page_number"] for page in pages], [11, 12])

    def test_pdf_batch_runner_limits_concurrency_to_three(self):
        batches = [
            lecture_ai.PdfBatch(index, index + 1, index + 1, "unused.pdf")
            for index in range(6)
        ]
        lock = threading.Lock()
        active = 0
        maximum_active = 0

        def worker(batch):
            nonlocal active, maximum_active
            with lock:
                active += 1
                maximum_active = max(maximum_active, active)
            time.sleep(0.03)
            with lock:
                active -= 1
            return [{"page_number": batch.start_page, "markdown": "note"}]

        pages = lecture_ai._run_batches_concurrently(batches, worker)

        self.assertEqual(len(pages), 6)
        self.assertLessEqual(maximum_active, 3)
        self.assertGreater(maximum_active, 1)

    @patch.dict(speech.os.environ, {}, clear=True)
    def test_azure_handler_reports_missing_key(self):
        request = Mock(method="POST")
        with self.assertLogs(level="ERROR"):
            response = speech.azure_token_handler(request)
        self.assertEqual(response.status_code, 500)
        self.assertIn("not configured", response.get_data(as_text=True))


if __name__ == "__main__":
    unittest.main()
