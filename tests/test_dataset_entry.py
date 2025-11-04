import json
from pathlib import Path

import pytest

from bcbench.dataset.dataset_entry import DatasetEntry
from bcbench.exceptions import InvalidEntryFormatError


class TestDatasetEntryValidation:
    def test_from_json_catches_invalid_test_entry_missing_codeunit_id(self):
        payload = {
            "instance_id": "test__repo-123",
            "FAIL_TO_PASS": [
                {
                    "functionName": ["TestFunction1"]
                    # Missing codeunitID
                }
            ],
        }

        with pytest.raises(InvalidEntryFormatError) as exc_info:
            DatasetEntry.from_json(payload)

        assert "test__repo-123" in str(exc_info.value)
        assert "codeunitID" in str(exc_info.value)

    def test_from_json_catches_invalid_test_entry_missing_function_name(self):
        payload = {
            "instance_id": "test__repo-456",
            "FAIL_TO_PASS": [
                {
                    "codeunitID": 12345
                    # Missing functionName
                }
            ],
        }

        with pytest.raises(InvalidEntryFormatError) as exc_info:
            DatasetEntry.from_json(payload)

        assert "test__repo-456" in str(exc_info.value)
        assert "functionName" in str(exc_info.value)

    def test_from_json_catches_invalid_test_entry_wrong_type(self):
        payload = {
            "instance_id": "test__repo-789",
            "PASS_TO_PASS": [
                {
                    "codeunitID": "not_an_integer",  # Should be int
                    "functionName": ["TestFunction1"],
                }
            ],
        }

        with pytest.raises(InvalidEntryFormatError) as exc_info:
            DatasetEntry.from_json(payload)

        assert "test__repo-789" in str(exc_info.value)


class TestDatasetEntryRoundTrip:
    def test_round_trip_with_complete_entry(self):
        original_data = {
            "repo": "microsoftInternal/NAV",
            "instance_id": "microsoftInternal__NAV-12345",
            "patch": "diff --git a/file.al b/file.al\n+new line",
            "base_commit": "a" * 40,  # 40-char SHA
            "hints_text": "This is a hint about the issue",
            "created_at": "2025-01-15",
            "test_patch": "diff --git a/test.al b/test.al\n+test line",
            "problem_statement": "Bug: Something is broken\n\nSteps to reproduce...",
            "environment_setup_version": "25.1",
            "FAIL_TO_PASS": [
                {
                    "codeunitID": 12345,
                    "functionName": ["TestFunction1", "TestFunction2"],
                }
            ],
            "PASS_TO_PASS": [
                {
                    "codeunitID": 67890,
                    "functionName": ["TestFunction3"],
                }
            ],
            "project_paths": ["src/app1", "src/app2"],
        }

        # Round trip: dict -> DatasetEntry -> dict
        entry = DatasetEntry.from_json(original_data)
        result_data = entry.to_dict()

        # Verify all fields are preserved
        assert result_data["repo"] == original_data["repo"]
        assert result_data["instance_id"] == original_data["instance_id"]
        assert result_data["patch"] == original_data["patch"]
        assert result_data["base_commit"] == original_data["base_commit"]
        assert result_data["hints_text"] == original_data["hints_text"]
        assert result_data["created_at"] == original_data["created_at"]
        assert result_data["test_patch"] == original_data["test_patch"]
        assert result_data["problem_statement"] == original_data["problem_statement"]
        assert result_data["environment_setup_version"] == original_data["environment_setup_version"]
        assert result_data["FAIL_TO_PASS"] == original_data["FAIL_TO_PASS"]
        assert result_data["PASS_TO_PASS"] == original_data["PASS_TO_PASS"]
        assert result_data["project_paths"] == original_data["project_paths"]

    def test_get_task_includes_problem_statement(self):
        entry = DatasetEntry(
            instance_id="test__task-1",
            problem_statement="Fix the bug in module X",
        )

        task = entry.get_task()
        assert "Fix the bug in module X" in task

    def test_get_task_includes_hints_when_present(self):
        entry = DatasetEntry(
            instance_id="test__task-2",
            problem_statement="Fix the bug",
            hints_text="Look at file Y",
        )

        task = entry.get_task()
        assert "Fix the bug" in task
        assert "Additional Hints" in task
        assert "Look at file Y" in task

    def test_get_task_without_hints(self):
        entry = DatasetEntry(
            instance_id="test__task-3",
            problem_statement="Just the problem",
            hints_text="",
        )

        task = entry.get_task()
        assert task == "Just the problem"
        assert "Additional Hints" not in task

    def test_save_to_file_creates_jsonl(self, tmp_path: Path):
        entry = DatasetEntry(
            instance_id="test__save-1",
            repo="test/repo",
            problem_statement="Test problem",
            fail_to_pass=[{"codeunitID": 100, "functionName": ["Test1"]}],
        )

        file_path = tmp_path / "test_output.jsonl"
        entry.save_to_file(file_path)

        assert file_path.exists()

        with file_path.open("r", encoding="utf-8") as f:
            line = f.readline()
            loaded_data = json.loads(line)

        assert loaded_data["instance_id"] == "test__save-1"
        assert loaded_data["repo"] == "test/repo"
        assert loaded_data["problem_statement"] == "Test problem"

    def test_save_to_file_appends_multiple_entries(self, tmp_path: Path):
        file_path = tmp_path / "test_append.jsonl"

        entry1 = DatasetEntry(instance_id="test__append-1")
        entry2 = DatasetEntry(instance_id="test__append-2")

        entry1.save_to_file(file_path)
        entry2.save_to_file(file_path)

        # Read both lines
        with file_path.open("r", encoding="utf-8") as f:
            lines = f.readlines()

        assert len(lines) == 2
        data1 = json.loads(lines[0])
        data2 = json.loads(lines[1])
        assert data1["instance_id"] == "test__append-1"
        assert data2["instance_id"] == "test__append-2"
