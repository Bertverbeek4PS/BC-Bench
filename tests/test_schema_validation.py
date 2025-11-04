import json
from pathlib import Path

import pytest
from jsonschema import ValidationError, validate

from bcbench.dataset.dataset_entry import DatasetEntry


class TestDatasetEntrySchemaValidation:
    @pytest.fixture
    def schema(self) -> dict:
        schema_path = Path(__file__).parent.parent / "dataset" / "schema.json"
        with schema_path.open("r", encoding="utf-8") as f:
            return json.load(f)

    def test_valid_complete_entry_passes_schema_validation(self, schema):
        entry = DatasetEntry(
            repo="microsoftInternal/NAV",
            instance_id="microsoftInternal__NAV-12345",
            patch="diff --git a/file.al b/file.al\n+new line",
            base_commit="a" * 40,  # 40-char SHA
            hints_text="This is a hint",
            created_at="2025-01-15",
            test_patch="diff --git a/test.al b/test.al\n+test line",
            problem_statement="Bug: Something is broken",
            environment_setup_version="25.1",
            fail_to_pass=[{"codeunitID": 12345, "functionName": ["Test1"]}],
            pass_to_pass=[],
            project_paths=["src/app1"],
        )

        # Should not raise ValidationError
        validate(instance=entry.to_dict(), schema=schema)

    def test_invalid_instance_id_fails_schema_validation(self, schema):
        entry = DatasetEntry(
            instance_id="invalid_format",  # Missing proper format
            repo="owner/repo",
            base_commit="a" * 40,
            created_at="2025-01-15",
            environment_setup_version="25.1",
            fail_to_pass=[{"codeunitID": 123, "functionName": ["Test1"]}],
            pass_to_pass=[],
            project_paths=["src/app"],
        )

        with pytest.raises(ValidationError) as exc_info:
            validate(instance=entry.to_dict(), schema=schema)

        assert "instance_id" in str(exc_info.value).lower()

    def test_invalid_base_commit_fails_schema_validation(self, schema):
        entry = DatasetEntry(
            instance_id="owner__repo-123",
            repo="owner/repo",
            base_commit="tooshort",  # Should be 40 hex chars
            created_at="2025-01-15",
            environment_setup_version="25.1",
            fail_to_pass=[{"codeunitID": 123, "functionName": ["Test1"]}],
            pass_to_pass=[],
            project_paths=["src/app"],
        )

        with pytest.raises(ValidationError) as exc_info:
            validate(instance=entry.to_dict(), schema=schema)

        assert "base_commit" in str(exc_info.value).lower()

    def test_invalid_environment_version_fails_schema_validation(self, schema):
        entry = DatasetEntry(
            instance_id="owner__repo-456",
            repo="owner/repo",
            base_commit="a" * 40,
            created_at="2025-01-15",
            environment_setup_version="25.10.5",  # Should be XX.X format
            fail_to_pass=[{"codeunitID": 123, "functionName": ["Test1"]}],
            pass_to_pass=[],
            project_paths=["src/app"],
        )

        with pytest.raises(ValidationError) as exc_info:
            validate(instance=entry.to_dict(), schema=schema)

        assert "environment_setup_version" in str(exc_info.value).lower()

    def test_missing_required_fields_fails_schema_validation(self, schema):
        entry = DatasetEntry(
            instance_id="owner__repo-789",
            # Missing many required fields
        )

        with pytest.raises(ValidationError) as exc_info:
            validate(instance=entry.to_dict(), schema=schema)

        # Should complain about missing required fields
        error_message = str(exc_info.value).lower()
        # The schema requires project_paths to have at least 1 item
        assert "required" in error_message or "minitems" in error_message

    def test_empty_function_name_fails_schema_validation(self, schema):
        entry = DatasetEntry(
            instance_id="owner__repo-999",
            repo="owner/repo",
            base_commit="a" * 40,
            created_at="2025-01-15",
            environment_setup_version="25.1",
            fail_to_pass=[{"codeunitID": 123, "functionName": []}],  # Empty array
            pass_to_pass=[],
            project_paths=["src/app"],
        )

        with pytest.raises(ValidationError) as exc_info:
            validate(instance=entry.to_dict(), schema=schema)

        # Schema requires minItems: 1 for functionName
        assert "minitems" in str(exc_info.value).lower()

    def test_invalid_repo_format_fails_schema_validation(self, schema):
        entry = DatasetEntry(
            instance_id="owner__repo-111",
            repo="invalid repo with spaces",  # Should be owner/repo format
            base_commit="a" * 40,
            created_at="2025-01-15",
            environment_setup_version="25.1",
            fail_to_pass=[{"codeunitID": 123, "functionName": ["Test1"]}],
            pass_to_pass=[],
            project_paths=["src/app"],
        )

        with pytest.raises(ValidationError) as exc_info:
            validate(instance=entry.to_dict(), schema=schema)

        assert "repo" in str(exc_info.value).lower()

    def test_missing_fail_to_pass_fails_schema_validation(self, schema):
        entry = DatasetEntry(
            repo="microsoftInternal/NAV",
            instance_id="microsoftInternal__NAV-12345",
            patch="diff --git a/file.al b/file.al\n+new line",
            base_commit="a" * 40,  # 40-char SHA
            hints_text="This is a hint",
            created_at="2025-01-15",
            test_patch="diff --git a/test.al b/test.al\n+test line",
            problem_statement="Bug: Something is broken",
            environment_setup_version="25.1",
            fail_to_pass=[],  # at least one required
            pass_to_pass=[{"codeunitID": 67890, "functionName": ["Test2"]}],
            project_paths=["src/app1"],
        )
        with pytest.raises(ValidationError) as exc_info:
            validate(instance=entry.to_dict(), schema=schema)

        assert "fail_to_pass" in str(exc_info.value).lower()

    def test_duplicated_tests_fails_schema_validation(self, schema):
        entry = DatasetEntry(
            repo="microsoftInternal/NAV",
            instance_id="microsoftInternal__NAV-12345",
            patch="diff --git a/file.al b/file.al\n+new line",
            base_commit="a" * 40,  # 40-char SHA
            hints_text="This is a hint",
            created_at="2025-01-15",
            test_patch="diff --git a/test.al b/test.al\n+test line",
            problem_statement="Bug: Something is broken",
            environment_setup_version="25.1",
            fail_to_pass=[
                {"codeunitID": 12345, "functionName": ["TestFunction1", "TestFunction1"]},  # Duplicated test function
            ],
            pass_to_pass=[],
            project_paths=["src/app1"],
        )

        with pytest.raises(ValidationError) as exc_info:
            validate(instance=entry.to_dict(), schema=schema)

        assert "fail_to_pass" in str(exc_info.value).lower()
