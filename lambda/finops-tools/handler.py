"""The 3 FinOps MCP tools, backing the Gateway target in 04-MCP.tf.

boto3 ships with the Lambda Python runtime, so there's nothing to package.

Event/context format confirmed against AWS docs (Gateway > Lambda targets >
Lambda function input format): `event` is a flat dict of the tool's input
arguments, and the tool name arrives on `context.client_context.custom`
prefixed with the target name (e.g. "finops-tools___cost_by_service_period"),
not in `event` itself.
https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-add-target-lambda.html
"""

import datetime

import boto3

ce_client = boto3.client("ce")
ec2_client = boto3.client("ec2")
cloudwatch_client = boto3.client("cloudwatch")

# Current + recent-past GPU instance family prefixes. AWS adds new GPU
# families over time (this list was accurate as of early 2026) — extend it
# if a newer family isn't showing up.
GPU_INSTANCE_TYPE_PREFIXES = (
    "p2.", "p3.", "p4d.", "p4de.", "p5.", "p5e.", "p5en.",
    "g3.", "g3s.", "g4dn.", "g4ad.", "g5.", "g5g.", "g6.", "g6e.",
    "trn1.", "trn1n.", "trn2.", "inf1.", "inf2.", "dl1.", "dl2q.",
)


def cost_by_service_period(start_date, end_date, service=None):
    kwargs = {
        "TimePeriod": {"Start": start_date, "End": end_date},
        "Granularity": "DAILY",
        "Metrics": ["UnblendedCost"],
        "GroupBy": [{"Type": "DIMENSION", "Key": "SERVICE"}],
    }
    if service:
        kwargs["Filter"] = {"Dimensions": {"Key": "SERVICE", "Values": [service]}}

    response = ce_client.get_cost_and_usage(**kwargs)

    costs_by_service = {}
    for day in response.get("ResultsByTime", []):
        for group in day.get("Groups", []):
            service_name = group["Keys"][0]
            amount = float(group["Metrics"]["UnblendedCost"]["Amount"])
            costs_by_service[service_name] = costs_by_service.get(service_name, 0.0) + amount

    return {
        "start_date": start_date,
        "end_date": end_date,
        "unit": "USD",
        "costs_by_service": costs_by_service,
    }


def active_gpu_instances():
    paginator = ec2_client.get_paginator("describe_instances")
    instances = []
    for page in paginator.paginate(Filters=[{"Name": "instance-state-name", "Values": ["running"]}]):
        for reservation in page["Reservations"]:
            for instance in reservation["Instances"]:
                instance_type = instance["InstanceType"]
                if instance_type.startswith(GPU_INSTANCE_TYPE_PREFIXES):
                    instances.append({
                        "instance_id": instance["InstanceId"],
                        "instance_type": instance_type,
                        "launch_time": instance["LaunchTime"].isoformat(),
                    })
    return instances


def gpu_utilization_rate(instance_id, period_hours=24):
    end_time = datetime.datetime.utcnow()
    start_time = end_time - datetime.timedelta(hours=period_hours)

    # NOTE: EC2/CloudWatch has no built-in GPU metric. This assumes the
    # CloudWatch agent (or NVIDIA DCGM exporter) on the instance publishes
    # GPU utilization under this namespace/metric name — adjust to match
    # whatever's actually configured if it differs.
    response = cloudwatch_client.get_metric_statistics(
        Namespace="CWAgent",
        MetricName="nvidia_smi_utilization_gpu",
        Dimensions=[{"Name": "InstanceId", "Value": instance_id}],
        StartTime=start_time,
        EndTime=end_time,
        Period=3600,
        Statistics=["Average"],
    )

    datapoints = sorted(response.get("Datapoints", []), key=lambda d: d["Timestamp"])
    average = sum(d["Average"] for d in datapoints) / len(datapoints) if datapoints else None

    return {
        "instance_id": instance_id,
        "period_hours": period_hours,
        "average_gpu_utilization_percent": average,
        "datapoint_count": len(datapoints),
    }


TOOLS = {
    "cost_by_service_period": cost_by_service_period,
    "active_gpu_instances": active_gpu_instances,
    "gpu_utilization_rate": gpu_utilization_rate,
}


TOOL_NAME_DELIMITER = "___"


def _strip_target_prefix(qualified_tool_name):
    """"finops-tools___cost_by_service_period" -> "cost_by_service_period"."""
    if TOOL_NAME_DELIMITER in qualified_tool_name:
        return qualified_tool_name.split(TOOL_NAME_DELIMITER, 1)[1]
    return qualified_tool_name


def handler(event, context):
    qualified_tool_name = context.client_context.custom["bedrockAgentCoreToolName"]
    tool_name = _strip_target_prefix(qualified_tool_name)
    arguments = event  # event *is* the arguments dict, not a wrapper around it

    tool = TOOLS.get(tool_name)
    if tool is None:
        return {"error": f"Unknown tool '{tool_name}'"}

    try:
        return tool(**arguments)
    except Exception as exc:  # surface tool errors to the agent instead of a raw Lambda failure
        return {"error": f"'{tool_name}' failed: {exc}"}
