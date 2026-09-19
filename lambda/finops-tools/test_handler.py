"""Unit tests for handler.py, boto3 clients mocked — no AWS account needed.

Run with: .venv/bin/pytest lambda/finops-tools/test_handler.py
"""

import datetime
from types import SimpleNamespace
from unittest.mock import MagicMock

import handler


def _fake_context(tool_name):
    return SimpleNamespace(
        client_context=SimpleNamespace(custom={"bedrockAgentCoreToolName": tool_name})
    )


class TestStripTargetPrefix:
    def test_strips_target_name_prefix(self):
        assert handler._strip_target_prefix("finops-tools___cost_by_service_period") == "cost_by_service_period"

    def test_leaves_unprefixed_name_untouched(self):
        assert handler._strip_target_prefix("cost_by_service_period") == "cost_by_service_period"


class TestCostByServicePeriod:
    def test_aggregates_cost_by_service_across_days(self, monkeypatch):
        fake_response = {
            "ResultsByTime": [
                {"Groups": [{"Keys": ["EC2"], "Metrics": {"UnblendedCost": {"Amount": "1.5"}}}]},
                {"Groups": [{"Keys": ["EC2"], "Metrics": {"UnblendedCost": {"Amount": "2.5"}}}]},
            ]
        }
        mock_ce = MagicMock()
        mock_ce.get_cost_and_usage.return_value = fake_response
        monkeypatch.setattr(handler, "ce_client", mock_ce)

        result = handler.cost_by_service_period("2026-01-01", "2026-01-03")

        assert result["costs_by_service"] == {"EC2": 4.0}
        assert result["unit"] == "USD"
        call_kwargs = mock_ce.get_cost_and_usage.call_args.kwargs
        assert "Filter" not in call_kwargs

    def test_passes_service_filter_when_given(self, monkeypatch):
        mock_ce = MagicMock()
        mock_ce.get_cost_and_usage.return_value = {"ResultsByTime": []}
        monkeypatch.setattr(handler, "ce_client", mock_ce)

        handler.cost_by_service_period("2026-01-01", "2026-01-03", service="Amazon EC2")

        call_kwargs = mock_ce.get_cost_and_usage.call_args.kwargs
        assert call_kwargs["Filter"] == {"Dimensions": {"Key": "SERVICE", "Values": ["Amazon EC2"]}}


class TestActiveGpuInstances:
    def test_filters_to_gpu_instance_types_only(self, monkeypatch):
        launch_time = datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc)
        page = {
            "Reservations": [
                {
                    "Instances": [
                        {"InstanceId": "i-gpu1", "InstanceType": "g5.xlarge", "LaunchTime": launch_time},
                        {"InstanceId": "i-cpu1", "InstanceType": "t3.micro", "LaunchTime": launch_time},
                    ]
                }
            ]
        }
        mock_paginator = MagicMock()
        mock_paginator.paginate.return_value = [page]
        mock_ec2 = MagicMock()
        mock_ec2.get_paginator.return_value = mock_paginator
        monkeypatch.setattr(handler, "ec2_client", mock_ec2)

        result = handler.active_gpu_instances()

        assert len(result) == 1
        assert result[0]["instance_id"] == "i-gpu1"
        assert result[0]["instance_type"] == "g5.xlarge"


class TestGpuUtilizationRate:
    def test_averages_datapoints(self, monkeypatch):
        mock_cw = MagicMock()
        mock_cw.get_metric_statistics.return_value = {
            "Datapoints": [
                {"Timestamp": datetime.datetime(2026, 1, 1, 1), "Average": 40.0},
                {"Timestamp": datetime.datetime(2026, 1, 1, 0), "Average": 20.0},
            ]
        }
        monkeypatch.setattr(handler, "cloudwatch_client", mock_cw)

        result = handler.gpu_utilization_rate("i-0123456789abcdef0", period_hours=12)

        assert result["average_gpu_utilization_percent"] == 30.0
        assert result["datapoint_count"] == 2

    def test_returns_none_average_when_no_datapoints(self, monkeypatch):
        mock_cw = MagicMock()
        mock_cw.get_metric_statistics.return_value = {"Datapoints": []}
        monkeypatch.setattr(handler, "cloudwatch_client", mock_cw)

        result = handler.gpu_utilization_rate("i-0123456789abcdef0")

        assert result["average_gpu_utilization_percent"] is None
        assert result["datapoint_count"] == 0


class TestHandlerDispatch:
    def test_strips_target_prefix_and_dispatches_with_event_as_arguments(self, monkeypatch):
        fake_tool = MagicMock(return_value={"ok": True})
        monkeypatch.setitem(handler.TOOLS, "active_gpu_instances", fake_tool)

        event = {}
        context = _fake_context("finops-tools___active_gpu_instances")

        result = handler.handler(event, context)

        fake_tool.assert_called_once_with()
        assert result == {"ok": True}

    def test_passes_event_fields_as_keyword_arguments(self, monkeypatch):
        fake_tool = MagicMock(return_value={"ok": True})
        monkeypatch.setitem(handler.TOOLS, "gpu_utilization_rate", fake_tool)

        event = {"instance_id": "i-abc", "period_hours": 6}
        context = _fake_context("finops-tools___gpu_utilization_rate")

        handler.handler(event, context)

        fake_tool.assert_called_once_with(instance_id="i-abc", period_hours=6)

    def test_unknown_tool_name_returns_an_error(self):
        event = {}
        context = _fake_context("finops-tools___does_not_exist")

        result = handler.handler(event, context)

        assert "error" in result
        assert "does_not_exist" in result["error"]

    def test_tool_exception_is_caught_and_returned_as_error(self, monkeypatch):
        failing_tool = MagicMock(side_effect=RuntimeError("boom"))
        monkeypatch.setitem(handler.TOOLS, "active_gpu_instances", failing_tool)

        event = {}
        context = _fake_context("finops-tools___active_gpu_instances")

        result = handler.handler(event, context)

        assert result == {"error": "'active_gpu_instances' failed: boom"}
