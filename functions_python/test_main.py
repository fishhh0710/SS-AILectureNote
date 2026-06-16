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

    def test_realtime_agent_has_no_tools(self):
        self.assertEqual(realtime_agent.realtime_agent.tools, [])

    def test_realtime_prompt_includes_all_page_summaries(self):
        prompt = realtime_agent.build_realtime_prompt(
            page_summaries={2: "Second page", 1: "First page"},
            recent_segments=["older"],
            latest_segment="latest",
            last_teacher_page=2,
        )
        self.assertIn('"page_number": 1', prompt)
        self.assertIn('"canonical_slide_summary": "First page"', prompt)
        self.assertIn('"page_number": 2', prompt)
        self.assertIn('"canonical_slide_summary": "Second page"', prompt)
        self.assertIn('"last_teacher_page": 2', prompt)

    def test_realtime_prompt_uses_only_canonical_slide_summary(self):
        prompt = realtime_agent.build_realtime_prompt(
            page_summaries={
                36: (
                    "# Page 36: Execution for Branch Instruction\n\n"
                    "## Main Idea\nBranch instruction content.\n\n"
                    "### Professor Additions\n"
                    "- Cache and Multiplexer content from page 19.\n\n"
                    "### Professor Questions\n"
                    "- What differs between page 21 and 24?"
                )
            },
            recent_segments=[],
            latest_segment="latest",
            last_teacher_page=36,
        )
        self.assertIn("Branch instruction content", prompt)
        self.assertNotIn("Professor Additions", prompt)
        self.assertNotIn("Cache and Multiplexer", prompt)
        self.assertNotIn("Professor Questions", prompt)

    def test_realtime_instructions_prioritize_recent_transcript_and_page_mentions(self):
        instructions = realtime_agent.REALTIME_AGENT_INSTRUCTIONS
        self.assertIn("latest_segment is the newest", instructions)
        self.assertIn("refer back to a page", instructions)
        self.assertIn("canonical slide content", instructions)

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

    def test_attention_gate_waits_twenty_five_seconds_in_foreground(self):
        now = datetime(2026, 6, 15, tzinfo=timezone.utc)
        gate = attention_agent.attention_gate(
            student_state={
                "currentPage": 1,
                "currentPageDurationSeconds": 20,
                "appLifecycle": "foreground",
                "sessionStartedAt": (now - timedelta(seconds=20)).isoformat(),
            },
            teacher_page=3,
            session_state={},
            now=now,
        )
        self.assertFalse(gate["should_run"])
        self.assertFalse(gate["interval_ready"])
        self.assertEqual(gate["check_interval_seconds"], 25)

    def test_attention_gate_uses_twenty_five_seconds_in_background(self):
        now = datetime(2026, 6, 15, tzinfo=timezone.utc)
        gate = attention_agent.attention_gate(
            student_state={
                "currentPage": 1,
                "currentPageDurationSeconds": 16,
                "appLifecycle": "background",
                "backgroundedAt": (now - timedelta(seconds=16)).isoformat(),
                "sessionStartedAt": (now - timedelta(seconds=11)).isoformat(),
            },
            teacher_page=3,
            session_state={},
            now=now,
        )
        self.assertFalse(gate["should_run"])
        self.assertEqual(gate["check_interval_seconds"], 25)
        self.assertTrue(gate["signals"]["behind_signal"])

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
            teacher_page=3,
            session_state={
                "lastAttentionCheckedAt": (now - timedelta(seconds=31)),
                "teacherPageAtLastCheck": 2,
            },
            now=now,
        )
        self.assertTrue(gate["should_run"])
        self.assertTrue(gate["signals"]["teacher_moved"])

    def test_attention_agent_exposes_action_tools(self):
        self.assertEqual(
            [tool.name for tool in attention_agent.attention_agent.tools],
            [
                "evaluate_attention_gate",
                "get_attention_evidence",
                "remember_learning_state",
                "send_distraction_notification",
                "save_attention_result",
                "save_attention_event",
            ],
        )

    def test_notification_cooldown_is_one_hundred_eighty_seconds(self):
        now = datetime(2026, 6, 15, tzinfo=timezone.utc)
        self.assertFalse(
            attention_agent._notification_ready(
                {"lastNotificationAt": now - timedelta(seconds=179)}, now
            )
        )
        self.assertTrue(
            attention_agent._notification_ready(
                {"lastNotificationAt": now - timedelta(seconds=180)}, now
            )
        )

    def test_notification_requires_evidence_token_and_completed_cooldown(self):
        now = datetime(2026, 6, 15, tzinfo=timezone.utc)
        student_state = {
            "currentPage": 1,
            "currentPageDurationSeconds": 16,
            "appLifecycle": "background",
            "backgroundedAt": (now - timedelta(seconds=16)).isoformat(),
            "sessionStartedAt": (now - timedelta(seconds=20)).isoformat(),
        }
        gate = attention_agent.attention_gate(
            student_state=student_state,
            teacher_page=3,
            session_state={},
            now=now,
        )
        context = attention_agent.AttentionContext(
            uid="user-1",
            session_id="session-1",
            course_id="course-1",
            lecture_id="lecture-1",
            notification_token="token",
            teacher_page=3,
            page_summaries={},
            transcript_segments=[],
            student_state=student_state,
            now=now,
            database=None,
            session_state={},
            gate=gate,
        )
        self.assertEqual(
            attention_agent._notification_decision(context, "distracted"),
            (False, "attention_evidence_required"),
        )

        context.evidence_loaded = True
        self.assertEqual(
            attention_agent._notification_decision(context, "distracted"),
            (True, "ready"),
        )

        context.notification_token = ""
        self.assertEqual(
            attention_agent._notification_decision(context, "distracted"),
            (False, "missing_notification_token"),
        )

    def test_memory_preference_id_is_stable_across_content_changes(self):
        first = memory_service.MemoryWrite(
            content="The user wants summaries written as bullet points.",
            preference_key="summary.format",
        )
        second = memory_service.MemoryWrite(
            content="The user wants summaries written as concise numbered points.",
            preference_key="summary.format",
        )
        self.assertEqual(
            memory_service.memory_document_id("user-1", first),
            memory_service.memory_document_id("user-1", second),
        )

    def test_memory_learning_id_normalizes_text(self):
        first = memory_service.MemoryWrite(
            content="  Binary   Search ",
        )
        second = memory_service.MemoryWrite(
            content="binary search",
        )
        self.assertEqual(
            memory_service.memory_document_id("user-1", first),
            memory_service.memory_document_id("user-1", second),
        )

    def test_memory_scope_requires_identifiers(self):
        with self.assertRaisesRegex(ValueError, "course_id"):
            memory_service.MemoryWrite(
                content="Recursion",
                scope="course",
            )

    def test_memory_schema_has_no_removed_fields(self):
        self.assertNotIn("domain", memory_service.MemoryWrite.model_fields)
        self.assertNotIn("confidence", memory_service.MemoryWrite.model_fields)
        self.assertNotIn("kind", memory_service.MemoryWrite.model_fields)
        self.assertNotIn("importance", memory_service.MemoryWrite.model_fields)
        self.assertNotIn("explicit", memory_service.MemoryWrite.model_fields)
        self.assertNotIn("metadata", memory_service.MemoryWrite.model_fields)
        self.assertNotIn("confidence", attention_agent.AttentionAgentOutput.model_fields)

    def test_memory_service_ensures_parent_user_document(self):
        database = Mock()
        service = memory_service.MemoryService(database=database)

        service._ensure_user_document("user-1")

        user_document = database.collection.return_value.document.return_value
        database.collection.assert_called_once_with("users")
        database.collection.return_value.document.assert_called_once_with("user-1")
        user_document.set.assert_called_once()
        data, = user_document.set.call_args.args
        self.assertTrue(data["hasMemory"])
        self.assertIn("updatedAt", data)
        self.assertTrue(user_document.set.call_args.kwargs["merge"])

    def test_memory_serialization_hides_removed_canonical_fields(self):
        result = memory_service.MemorySearchResult(
            memory_id="memory-1",
            data={
                "content": "The user wants explanations with concrete examples.",
                "preferenceKey": "explanation.examples",
                "scope": "global",
                "kind": "legacy_kind",
                "importance": 0.8,
                "explicit": True,
                "lastSource": "chat_agent",
                "updatedAt": datetime(2026, 6, 15, tzinfo=timezone.utc),
            },
        ).to_dict()
        self.assertEqual(
            result,
            {
                "memory_id": "memory-1",
                "content": "The user wants explanations with concrete examples.",
                "preferenceKey": "explanation.examples",
                "scope": "global",
            },
        )
        self.assertNotIn("kind", result)
        self.assertNotIn("importance", result)
        self.assertNotIn("explicit", result)
        self.assertNotIn("lastSource", result)
        self.assertNotIn("updatedAt", result)

    def test_attention_output_has_no_confused_summary_field(self):
        self.assertNotIn(
            "confused_summary", attention_agent.AttentionAgentOutput.model_fields
        )

    def test_legacy_candidate_preference_is_effectively_active(self):
        service = memory_service.MemoryService.__new__(memory_service.MemoryService)
        self.assertTrue(
            service._matches(
                {
                    "status": "candidate",
                    "preferenceKey": "summary.language",
                    "scope": "global",
                },
                statuses={"active"},
                course_id="course-1",
                lecture_id="lecture-1",
            )
        )

    def test_attention_output_only_creates_missed_content_memory(self):
        output = attention_agent.AttentionAgentOutput(
            status="behind",
            page_relevance="same_topic",
            reasoning_summary="Student stayed on a relevant concept.",
            missed_content=["The base case stops recursion."],
        )
        writes = attention_agent.attention_memory_writes(
            output,
            course_id="course-1",
            lecture_id="lecture-1",
        )
        self.assertEqual(
            [item.content for item in writes],
            ["The student likely missed: The base case stops recursion."],
        )
        self.assertTrue(all(item.scope == "lecture" for item in writes))

    def test_chat_prompt_includes_memory_and_course_context(self):
        prompt = chat_agent.build_chat_prompt(
            notes="Recursion notes",
            transcript="Teacher transcript",
            history="user: explain this",
            question="Use examples when explaining",
            memories=[
                {
                    "preferenceKey": "explanation.examples",
                    "content": "The user wants explanations with concrete examples.",
                    "scope": "global",
                }
            ],
        )
        self.assertIn("The user wants explanations with concrete examples.", prompt)
        self.assertIn("preference: explanation.examples", prompt)
        self.assertIn("Recursion notes", prompt)
        self.assertIn("Use examples when explaining", prompt)
        self.assertNotIn('"preferenceKey"', prompt)

    def test_memory_serialization_keeps_only_public_fields(self):
        result = memory_service.MemorySearchResult(
            memory_id="memory-1",
            data={
                "content": "The user wants explanations with concrete examples.",
                "updatedAt": datetime(2026, 6, 15, tzinfo=timezone.utc),
            },
        ).to_dict()
        self.assertEqual(
            result,
            {
                "memory_id": "memory-1",
                "content": "The user wants explanations with concrete examples.",
            },
        )

    def test_pdf_prompt_applies_memory_without_overriding_source(self):
        prompt = lecture_ai._pdf_notes_prompt(
            [
                {
                    "preferenceKey": "summary.format",
                    "content": "The user wants summaries written as concise numbered points.",
                },
                {
                    "content": "The student struggles with recursion base cases.",
                },
            ]
        )
        self.assertIn("Preferences:", prompt)
        self.assertIn("The user wants summaries written as concise numbered points.", prompt)
        self.assertIn("Learning context:", prompt)
        self.assertIn("recursion base cases", prompt)
        self.assertIn("Memory never overrides the PDF", prompt)
        self.assertNotIn('"preferenceKey"', prompt)

    def test_pdf_batch_prompt_preserves_original_page_numbers_in_heading(self):
        prompt = lecture_ai._pdf_notes_prompt(start_page=6, end_page=10)

        self.assertIn("The first page in this batch is Page 6, not Page 1", prompt)
        self.assertIn('page_number 6 and its Markdown must begin with "# Page 6:"', prompt)
        self.assertIn("Never restart page numbering at 1", prompt)
        self.assertIn(
            "The page number in the Markdown H1 must exactly match",
            prompt,
        )

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
