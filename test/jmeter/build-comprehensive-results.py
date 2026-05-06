"""Build a single CSV that combines JMeter, metrics, logs, and traces exports."""

from __future__ import annotations

import argparse
import csv
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

CSV_HEADERS = [
    "timestamp",
    "data_type",
    "service",
    "metric_name",
    "metric_value",
    "unit",
    "log_level",
    "log_message",
    "trace_id",
    "span_id",
    "span_name",
    "span_duration_ms",
    "span_service",
    "error_message",
    "notes",
]


def epoch_ms_to_iso(value: str) -> str:
    try:
        return datetime.fromtimestamp(int(value) / 1000, tz=timezone.utc).isoformat().replace("+00:00", "Z")
    except Exception:
        return value


def epoch_seconds_to_iso(value: float | int | str) -> str:
    try:
        return datetime.fromtimestamp(float(value), tz=timezone.utc).isoformat().replace("+00:00", "Z")
    except Exception:
        return str(value)


def clean_text(value: Any) -> str:
    if value is None:
        return ""
    return str(value).replace("\n", " ").replace("\r", " ").strip()


def iter_rows(path: Path) -> Iterable[list[str]]:
    with path.open(newline="", encoding="utf-8", errors="replace") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            yield row


def write_row(writer: csv.writer, row: list[Any]) -> None:
    writer.writerow([clean_text(value) for value in row])


def parse_jmeter(csv_path: Path, writer: csv.writer) -> None:
    if not csv_path.exists():
        return

    for row in iter_rows(csv_path):
        timestamp = epoch_ms_to_iso(row.get("timeStamp", ""))
        success = clean_text(row.get("success", "false")).lower() == "true"
        failure_message = clean_text(row.get("failureMessage", ""))
        notes = (
            f"responseCode={clean_text(row.get('responseCode', ''))}; "
            f"responseMessage={clean_text(row.get('responseMessage', ''))}; "
            f"threadName={clean_text(row.get('threadName', ''))}; "
            f"url={clean_text(row.get('URL', ''))}; "
            f"latency={clean_text(row.get('Latency', ''))}; "
            f"success={clean_text(row.get('success', ''))}; "
            f"failureMessage={failure_message}"
        )
        write_row(
            writer,
            [
                timestamp,
                "jmeter",
                clean_text(row.get("label", "api")),
                "response_time_ms",
                clean_text(row.get("elapsed", "")),
                "ms",
                "info" if success else "error",
                clean_text(row.get("responseMessage", "")),
                "",
                "",
                "",
                "",
                "",
                failure_message,
                notes,
            ],
        )


def parse_prometheus_query_range(json_path: Path, writer: csv.writer) -> None:
    if not json_path.exists():
        return

    try:
        payload = json.loads(json_path.read_text(encoding="utf-8", errors="replace"))
    except Exception as exc:
        write_row(
            writer,
            [
                datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
                "prometheus_raw",
                "system",
                json_path.name,
                "",
                "",
                "warning",
                f"Could not parse JSON: {exc}",
                "",
                "",
                "",
                "",
                "",
                "",
                f"source_file={json_path.name}",
            ],
        )
        return

    result = payload.get("data", {}).get("result", [])
    for series in result:
        metric = series.get("metric", {})
        labels = "; ".join(f"{key}={value}" for key, value in metric.items())
        service = metric.get("service") or metric.get("container_label_com_docker_compose_service") or metric.get("job") or "system"
        metric_name = json_path.stem
        values = series.get("values") or []
        for sample in values:
            if not isinstance(sample, list) or len(sample) < 2:
                continue
            ts, value = sample[0], sample[1]
            write_row(
                writer,
                [
                    epoch_seconds_to_iso(ts),
                    "prometheus",
                    service,
                    metric_name,
                    value,
                    "sample",
                    "info",
                    labels,
                    "",
                    "",
                    "",
                    "",
                    "",
                    "",
                    f"source_file={json_path.name}",
                ],
            )


def parse_loki_json(json_path: Path, writer: csv.writer) -> None:
    if not json_path.exists():
        return

    try:
        payload = json.loads(json_path.read_text(encoding="utf-8", errors="replace"))
    except Exception as exc:
        write_row(
            writer,
            [
                datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
                "loki_raw",
                "system",
                json_path.name,
                "",
                "",
                "warning",
                f"Could not parse JSON: {exc}",
                "",
                "",
                "",
                "",
                "",
                "",
                f"source_file={json_path.name}",
            ],
        )
        return

    for stream in payload.get("data", {}).get("result", []):
        labels = stream.get("stream", {})
        service = labels.get("container", labels.get("service_name", labels.get("job", "system")))
        label_text = "; ".join(f"{key}={value}" for key, value in labels.items())
        for sample in stream.get("values", []):
            if not isinstance(sample, list) or len(sample) < 2:
                continue
            ts, line = sample[0], sample[1]
            lower_line = str(line).lower()
            log_level = "error" if any(token in lower_line for token in ["error", "exception", "failed", "panic", "fatal", "oom"]) else "warning" if any(token in lower_line for token in ["warn", "timeout", "slow"]) else "info"
            write_row(
                writer,
                [
                    epoch_seconds_to_iso(int(ts) / 1_000_000_000 if str(ts).isdigit() else ts),
                    "loki",
                    service,
                    "log_entry",
                    "1",
                    "count",
                    log_level,
                    line,
                    "",
                    "",
                    "",
                    "",
                    "",
                    "",
                    f"source_file={json_path.name}; labels={label_text}",
                ],
            )


def parse_tempo_json(json_path: Path, writer: csv.writer) -> None:
    if not json_path.exists():
        return

    try:
        payload = json.loads(json_path.read_text(encoding="utf-8", errors="replace"))
    except Exception as exc:
        write_row(
            writer,
            [
                datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
                "tempo_raw",
                "system",
                json_path.name,
                "",
                "",
                "warning",
                f"Could not parse JSON: {exc}",
                "",
                "",
                "",
                "",
                "",
                "",
                f"source_file={json_path.name}",
            ],
        )
        return

    traces = payload if isinstance(payload, list) else payload.get("traces")
    if isinstance(traces, list):
        for trace in traces:
            trace_id = clean_text(trace.get("traceID") or trace.get("traceId") or trace.get("trace_id"))
            service = clean_text(trace.get("rootServiceName") or trace.get("serviceName") or trace.get("service")) or "tempo"
            duration = trace.get("durationMs") or trace.get("duration_ms") or trace.get("duration") or ""
            write_row(
                writer,
                [
                    datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
                    "tempo",
                    service,
                    "trace_search_result",
                    duration,
                    "ms",
                    "info",
                    clean_text(trace.get("name") or trace.get("spanName") or trace.get("operationName") or trace.get("rootServiceName")),
                    trace_id,
                    clean_text(trace.get("spanID") or trace.get("spanId") or trace.get("span_id")),
                    clean_text(trace.get("name") or trace.get("spanName") or trace.get("operationName")),
                    clean_text(duration),
                    service,
                    "",
                    f"source_file={json_path.name}",
                ],
            )
        return

    compact = json.dumps(payload, separators=(",", ":"))
    write_row(
        writer,
        [
            datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "tempo_raw",
            "tempo",
            json_path.name,
            "",
            "",
            "info",
            compact[:5000],
            "",
            "",
            "",
            "",
            "tempo",
            "",
            f"source_file={json_path.name}",
        ],
    )


def parse_log_file(log_path: Path, writer: csv.writer) -> None:
    if not log_path.exists():
        return

    service = log_path.stem
    with log_path.open(encoding="utf-8", errors="replace") as handle:
        for line in handle:
            line = line.rstrip("\n")
            lower_line = line.lower()
            log_level = "error" if any(token in lower_line for token in ["error", "exception", "failed", "panic", "fatal", "oom"]) else "warning" if any(token in lower_line for token in ["warn", "timeout", "slow"]) else "info"
            write_row(
                writer,
                [
                    datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
                    "application_log",
                    service,
                    "log_entry",
                    "1",
                    "count",
                    log_level,
                    line,
                    "",
                    "",
                    "",
                    "",
                    "",
                    "",
                    f"source_file={log_path.name}",
                ],
            )


def build_csv(results_dir: Path, anomaly_id: str, run_id: str, output_path: Path) -> None:
    # New layout: results_dir IS the run dir, observability/ sits directly inside it
    if (results_dir / "observability").exists():
        export_root = results_dir / "observability"
    else:
        # Legacy layout: results_dir is the base dir, subfolder named {id}-{run_id}-observability
        export_root = results_dir / f"{anomaly_id}-{run_id}-observability"
        if not export_root.exists():
            matches = sorted(results_dir.glob(f"{anomaly_id}-*-observability"))
            if not matches:
                raise FileNotFoundError(f"Observability export folder not found: {export_root}")
            export_root = matches[-1]
            run_id = export_root.name[len(f"{anomaly_id}-") : -len("-observability")]

    with output_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(CSV_HEADERS)

        metadata_path = export_root / "export-metadata.json"
        if metadata_path.exists():
            metadata = json.loads(metadata_path.read_text(encoding="utf-8", errors="replace"))
            write_row(
                writer,
                [
                    metadata.get("expanded_window_start", ""),
                    "summary",
                    "system",
                    "expanded_window_start",
                    metadata.get("expanded_window_start_epoch", ""),
                    "epoch",
                    "info",
                    "Expanded export start",
                    "",
                    "",
                    "",
                    "",
                    "",
                    "",
                    f"source_file={metadata_path.name}",
                ],
            )
            write_row(
                writer,
                [
                    metadata.get("expanded_window_end", ""),
                    "summary",
                    "system",
                    "expanded_window_end",
                    metadata.get("expanded_window_end_epoch", ""),
                    "epoch",
                    "info",
                    "Expanded export end",
                    "",
                    "",
                    "",
                    "",
                    "",
                    "",
                    f"source_file={metadata_path.name}",
                ],
            )

        parse_jmeter(results_dir / f"{anomaly_id}-results.csv", writer)

        metrics_dir = export_root / "metrics"
        for path in sorted(metrics_dir.glob("*.json")):
            parse_prometheus_query_range(path, writer)

        logs_dir = export_root / "logs"
        for path in sorted(logs_dir.glob("*.log")):
            parse_log_file(path, writer)
        loki_json = logs_dir / "loki-query-range.json"
        if loki_json.exists():
            parse_loki_json(loki_json, writer)

        traces_dir = export_root / "traces"
        for path in sorted(traces_dir.glob("*.json")):
            parse_tempo_json(path, writer)


def main() -> int:
    parser = argparse.ArgumentParser(description="Build comprehensive CSV from anomaly run artifacts")
    parser.add_argument("--results-dir", required=True)
    parser.add_argument("--anomaly-id", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    build_csv(Path(args.results_dir), args.anomaly_id, args.run_id, Path(args.output))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
