"""Tests for logger module, focusing on sensitive data filtering."""

import pytest

from bcbench.logger import SensitiveDataFilter


class TestSensitiveDataFilter:
    @pytest.fixture
    def filter_instance(self):
        """Create a SensitiveDataFilter instance for testing."""
        return SensitiveDataFilter()

    def test_redact_value_with_password(self, filter_instance):
        input_value = "password=secret123"
        result = filter_instance._redact_value(input_value)
        assert "secret123" not in result
        assert "******" in result

    def test_redact_value_with_bearer_token(self, filter_instance):
        input_value = "Authorization: Bearer abc123def456"
        result = filter_instance._redact_value(input_value)
        assert "abc123def456" not in result
        assert "******" in result

    def test_redact_value_with_non_string(self, filter_instance):
        assert filter_instance._redact_value(42) == 42

        assert filter_instance._redact_value(None) is None

        test_list = [1, 2, 3]
        assert filter_instance._redact_value(test_list) == test_list

    def test_redact_value_with_clean_string(self, filter_instance):
        clean_string = "This is a normal log message"
        result = filter_instance._redact_value(clean_string)
        assert result == clean_string

    def test_redact_value_with_powershell_password(self, filter_instance):
        input_value = "$password = ConvertTo-SecureString 'MySecret123' -AsPlainText -Force"
        result = filter_instance._redact_value(input_value)
        assert "MySecret123" not in result
        assert "******" in result
        assert "-AsPlainText -Force" in result  # Command flags should remain
