#!/usr/bin/env python3
"""
Parse an iTerm2 AI chat wire log into a human-readable summary.

The wire log is what `aiChatRawWireLogging` (advanced setting) produces
in `~/Library/Application Support/iTerm2/AIChatWire/`. Each log file is
a sequence of records of the form:

    === call <UUID> request <ISO8601> ===
    POST <url>
    Headers (N):
    <name>: <value>
    ...
    Body (string, N bytes):
    <body>
    --- end request <UUID> ---

    === call <UUID> stream chunk <ISO8601> (N bytes) ===
    <chunk>
    --- end chunk <UUID> ---

    === call <UUID> response <ISO8601> elapsed=N.NNNs ===
    Body (N bytes):
    <body>
    --- end response <UUID> ---

    === call <UUID> error <ISO8601> elapsed=N.NNNs ===
    <reason>
    --- end error <UUID> ---

The interesting work here is reconstructing Anthropic SSE streams back
into the assembled content blocks (text deltas glued together, tool-use
input_json_delta fragments concatenated and JSON-decoded) so a 50-chunk
streamed turn reads as one block per content block instead of as a
sequence of fragmentary deltas.

Usage:
    parse_ai_wire_log.py [--call UUID] [--raw] [--no-system] [--no-tools]
                         [--max-body BYTES] [path-to-log]

If `path-to-log` is omitted or `-`, reads stdin. Output is plain text
with one section per call in chronological order.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, field
from typing import Optional


HEADER_RE = re.compile(
    r"^=== call (?P<call>[0-9A-Fa-f-]{36}) "
    r"(?P<kind>request|stream chunk|response|error) "
    r"(?P<ts>\S+)"
    r"(?: \((?P<bytes>\d+) bytes\))?"
    r"(?: elapsed=(?P<elapsed>[0-9.]+)s)?"
    r" ===\s*$"
)

END_RE = re.compile(
    r"^--- end (?P<kind>request|chunk|response|error) "
    r"(?P<call>[0-9A-Fa-f-]{36}) ---\s*$"
)


@dataclass
class Record:
    call_id: str
    kind: str            # "request" | "stream chunk" | "response" | "error"
    timestamp: str
    body_lines: list[str] = field(default_factory=list)
    chunk_bytes: Optional[int] = None
    elapsed: Optional[float] = None

    def body(self) -> str:
        return "\n".join(self.body_lines)


@dataclass
class Call:
    call_id: str
    request: Optional[Record] = None
    chunks: list[Record] = field(default_factory=list)
    response: Optional[Record] = None
    error: Optional[Record] = None
    first_seen_idx: int = 0


# --- parsing ---------------------------------------------------------------


def parse_records(text: str) -> list[Record]:
    """Walk the log linearly and group consecutive lines between
    `=== ... ===` and `--- end ... ---` markers into Record objects."""
    records: list[Record] = []
    current: Optional[Record] = None
    for line in text.splitlines():
        if current is None:
            m = HEADER_RE.match(line)
            if m:
                current = Record(
                    call_id=m["call"],
                    kind=m["kind"],
                    timestamp=m["ts"],
                    chunk_bytes=int(m["bytes"]) if m["bytes"] else None,
                    elapsed=float(m["elapsed"]) if m["elapsed"] else None,
                )
            continue
        end = END_RE.match(line)
        if end:
            records.append(current)
            current = None
            continue
        current.body_lines.append(line)
    if current is not None:
        # Log truncated mid-record. Keep what we have.
        records.append(current)
    return records


def group_by_call(records: list[Record]) -> list[Call]:
    by_id: dict[str, Call] = {}
    order: list[str] = []
    for i, rec in enumerate(records):
        call = by_id.get(rec.call_id)
        if call is None:
            call = Call(call_id=rec.call_id, first_seen_idx=i)
            by_id[rec.call_id] = call
            order.append(rec.call_id)
        if rec.kind == "request":
            call.request = rec
        elif rec.kind == "stream chunk":
            call.chunks.append(rec)
        elif rec.kind == "response":
            call.response = rec
        elif rec.kind == "error":
            call.error = rec
    return [by_id[k] for k in order]


# --- HTTP-record helpers ---------------------------------------------------


def split_http_record(body: str) -> tuple[str, dict[str, str], str]:
    """Split a request body record into (start_line, headers, body).
    Start line is `POST <url>`, headers follow `Headers (N):` until the
    `Body (...)` line, and the body is everything after the colon-line."""
    lines = body.splitlines()
    start = lines[0] if lines else ""
    headers: dict[str, str] = {}
    body_start = None
    in_headers = False
    for i, line in enumerate(lines[1:], start=1):
        if not in_headers:
            if line.startswith("Headers ("):
                in_headers = True
                continue
            if line.startswith("Body "):
                body_start = i + 1
                break
            continue
        if line.startswith("Body "):
            body_start = i + 1
            break
        if ":" in line:
            k, v = line.split(":", 1)
            headers[k.strip()] = v.lstrip()
    body_text = "\n".join(lines[body_start:]) if body_start else ""
    return start, headers, body_text


def split_response_record(body: str) -> str:
    """Strip the `Body (N bytes):` header off a response record."""
    lines = body.splitlines()
    for i, line in enumerate(lines):
        if line.startswith("Body "):
            return "\n".join(lines[i + 1 :])
    return body


def mask_headers(headers: dict[str, str]) -> dict[str, str]:
    """Mask credentials in headers for display. The on-disk log keeps
    them verbatim by design; this is just for the prettified output."""
    masked = {}
    sensitive = {"authorization", "x-api-key", "api-key",
                 "x-goog-api-key", "openai-api-key"}
    for k, v in headers.items():
        if k.lower() in sensitive and v:
            # Keep the prefix so vendor / scheme is recognizable.
            prefix = v[:12] if len(v) > 16 else v[:4]
            masked[k] = f"{prefix}…[{len(v)} chars]"
        else:
            masked[k] = v
    return masked


# --- Anthropic SSE reconstruction -----------------------------------------


@dataclass
class SSEEvent:
    event: str
    data: str  # raw text, may be JSON


def parse_sse(text: str) -> list[SSEEvent]:
    """Walk an Anthropic-style SSE stream (one `event:`/`data:` pair per
    block, blocks separated by blank lines). Tolerant of trailing
    whitespace inside `data:` JSON (the Anthropic API pads with spaces)."""
    events: list[SSEEvent] = []
    current_event = ""
    current_data_lines: list[str] = []
    for raw in text.splitlines():
        line = raw.rstrip()
        if not line:
            if current_event or current_data_lines:
                events.append(SSEEvent(event=current_event,
                                        data="\n".join(current_data_lines).strip()))
            current_event = ""
            current_data_lines = []
            continue
        if line.startswith("event:"):
            current_event = line[len("event:"):].strip()
        elif line.startswith("data:"):
            current_data_lines.append(line[len("data:"):].lstrip())
        # Ignore other SSE fields (id:, retry:) — Anthropic doesn't send them.
    if current_event or current_data_lines:
        events.append(SSEEvent(event=current_event,
                                data="\n".join(current_data_lines).strip()))
    return events


@dataclass
class AssembledBlock:
    index: int
    block_type: str               # "text" | "tool_use" | "thinking" | other
    text: str = ""                # for text / thinking
    tool_name: str = ""
    tool_id: str = ""
    tool_input_json: str = ""     # accumulated partial_json
    raw_blocks: list[dict] = field(default_factory=list)  # initial content_block_start payloads


@dataclass
class AssembledResponse:
    model: str = ""
    role: str = ""
    blocks: dict[int, AssembledBlock] = field(default_factory=dict)
    stop_reason: Optional[str] = None
    usage: dict = field(default_factory=dict)
    other_events: list[SSEEvent] = field(default_factory=list)

    def ordered_blocks(self) -> list[AssembledBlock]:
        return [self.blocks[k] for k in sorted(self.blocks.keys())]


def assemble_anthropic_stream(events: list[SSEEvent]) -> AssembledResponse:
    """Walk a sequence of SSE events from an Anthropic streamed response
    and stitch the deltas back into the content blocks the non-streaming
    API would have returned in one shot."""
    out = AssembledResponse()
    for ev in events:
        try:
            payload = json.loads(ev.data) if ev.data else {}
        except json.JSONDecodeError:
            payload = {}
        t = payload.get("type") or ev.event
        if t == "message_start":
            msg = payload.get("message", {})
            out.model = msg.get("model", "")
            out.role = msg.get("role", "")
            usage = msg.get("usage")
            if usage:
                out.usage.update(usage)
        elif t == "content_block_start":
            idx = payload.get("index", 0)
            cb = payload.get("content_block", {})
            block = AssembledBlock(index=idx,
                                   block_type=cb.get("type", "unknown"))
            if block.block_type == "tool_use":
                block.tool_name = cb.get("name", "")
                block.tool_id = cb.get("id", "")
            elif block.block_type == "text":
                block.text = cb.get("text", "")
            elif block.block_type == "thinking":
                block.text = cb.get("thinking", "")
            block.raw_blocks.append(cb)
            out.blocks[idx] = block
        elif t == "content_block_delta":
            idx = payload.get("index", 0)
            block = out.blocks.get(idx)
            if block is None:
                block = AssembledBlock(index=idx, block_type="unknown")
                out.blocks[idx] = block
            delta = payload.get("delta", {})
            dt = delta.get("type", "")
            if dt == "text_delta":
                block.text += delta.get("text", "")
            elif dt == "input_json_delta":
                block.tool_input_json += delta.get("partial_json", "")
            elif dt == "thinking_delta":
                block.text += delta.get("thinking", "")
            elif dt == "signature_delta":
                # Carry signature on the block for completeness; not displayed.
                block.text += ""  # noop, but keep the branch for clarity
            else:
                out.other_events.append(ev)
        elif t == "content_block_stop":
            pass
        elif t == "message_delta":
            delta = payload.get("delta", {})
            if "stop_reason" in delta:
                out.stop_reason = delta.get("stop_reason")
            usage = payload.get("usage")
            if usage:
                out.usage.update(usage)
        elif t == "message_stop":
            pass
        elif t in ("ping",):
            pass
        else:
            out.other_events.append(ev)
    return out


# --- Rendering -------------------------------------------------------------


HR = "=" * 78
SUB = "-" * 78


def truncate(s: str, n: int) -> str:
    if n <= 0 or len(s) <= n:
        return s
    return s[:n] + f" …[+{len(s) - n} chars]"


def render_request(req: Record, args: argparse.Namespace) -> str:
    out: list[str] = []
    start, headers, body = split_http_record(req.body())
    out.append(start)
    masked = mask_headers(headers)
    if masked:
        out.append("Headers:")
        for k in sorted(masked):
            out.append(f"  {k}: {masked[k]}")
    payload: Optional[dict] = None
    try:
        payload = json.loads(body)
    except json.JSONDecodeError:
        out.append("")
        out.append("Body (unparseable, raw):")
        out.append(truncate(body, args.max_body))
        return "\n".join(out)
    out.append("")
    out.append("Body:")
    model = payload.get("model")
    if model:
        out.append(f"  model: {model}")
    for k in ("stream", "temperature", "top_p", "top_k", "max_tokens",
              "reasoning", "tool_choice"):
        if k in payload and payload[k] is not None:
            out.append(f"  {k}: {json.dumps(payload[k])}")
    system = payload.get("system")
    if system is not None and not args.no_system:
        if isinstance(system, list):
            system_text = json.dumps(system, indent=2, ensure_ascii=False)
        else:
            system_text = str(system)
        out.append(f"  system ({len(system_text)} chars):")
        for line in truncate(system_text, args.max_body).splitlines():
            out.append(f"    {line}")
    tools = payload.get("tools") or payload.get("functions") or []
    if tools and not args.no_tools:
        out.append(f"  tools ({len(tools)}):")
        for t in tools:
            name = t.get("name") or (t.get("function", {}) or {}).get("name", "?")
            desc = t.get("description") or (t.get("function", {}) or {}).get("description", "")
            desc1 = desc.splitlines()[0] if desc else ""
            out.append(f"    - {name}: {truncate(desc1, 100)}")
    messages = payload.get("messages") or payload.get("input") or []
    if messages:
        out.append(f"  messages ({len(messages)}):")
        for i, msg in enumerate(messages):
            role = msg.get("role", "?")
            content = msg.get("content", "")
            preview = format_message_content(content, args.max_body)
            out.append(f"    [{i}] {role}:")
            for line in preview.splitlines():
                out.append(f"      {line}")
    return "\n".join(out)


def format_message_content(content, max_body: int) -> str:
    """Render an Anthropic / OpenAI message content field for display."""
    if isinstance(content, str):
        return truncate(content, max_body)
    if isinstance(content, list):
        parts: list[str] = []
        for part in content:
            if not isinstance(part, dict):
                parts.append(repr(part))
                continue
            ptype = part.get("type", "?")
            if ptype == "text":
                parts.append(truncate(part.get("text", ""), max_body))
            elif ptype == "tool_use":
                name = part.get("name", "?")
                inp = part.get("input", {})
                parts.append(
                    f"<tool_use name={name} id={part.get('id', '?')}>\n"
                    + truncate(json.dumps(inp, indent=2, ensure_ascii=False), max_body)
                )
            elif ptype == "tool_result":
                tid = part.get("tool_use_id", "?")
                inner = part.get("content", "")
                inner_s = (inner if isinstance(inner, str)
                           else json.dumps(inner, ensure_ascii=False))
                parts.append(
                    f"<tool_result for={tid}>\n{truncate(inner_s, max_body)}"
                )
            elif ptype == "image":
                src = part.get("source", {})
                parts.append(
                    f"<image media_type={src.get('media_type', '?')} "
                    f"data={len(src.get('data', ''))}b>"
                )
            elif ptype == "document":
                src = part.get("source", {})
                parts.append(
                    f"<document media_type={src.get('media_type', '?')} "
                    f"data={len(src.get('data', ''))}b>"
                )
            elif ptype == "thinking":
                parts.append(
                    "<thinking>\n"
                    + truncate(part.get("thinking", ""), max_body)
                )
            else:
                parts.append(
                    f"<{ptype}>\n"
                    + truncate(json.dumps(part, ensure_ascii=False), max_body)
                )
        return "\n".join(parts)
    return repr(content)


def render_assembled(assembled: AssembledResponse,
                     args: argparse.Namespace) -> str:
    out: list[str] = []
    if assembled.model:
        out.append(f"model: {assembled.model}")
    if assembled.stop_reason:
        out.append(f"stop_reason: {assembled.stop_reason}")
    if assembled.usage:
        usage_parts = []
        for k in ("input_tokens", "output_tokens",
                  "cache_creation_input_tokens",
                  "cache_read_input_tokens"):
            v = assembled.usage.get(k)
            if v is not None:
                usage_parts.append(f"{k}={v}")
        if usage_parts:
            out.append("usage: " + ", ".join(usage_parts))
    for block in assembled.ordered_blocks():
        out.append("")
        if block.block_type == "text":
            out.append(f"[{block.index}] text ({len(block.text)} chars):")
            for line in truncate(block.text, args.max_body).splitlines():
                out.append(f"  {line}")
        elif block.block_type == "tool_use":
            out.append(f"[{block.index}] tool_use {block.tool_name} "
                       f"(id={block.tool_id}):")
            payload = block.tool_input_json or "{}"
            try:
                parsed = json.loads(payload)
                pretty = json.dumps(parsed, indent=2, ensure_ascii=False)
            except json.JSONDecodeError:
                pretty = payload
            for line in truncate(pretty, args.max_body).splitlines():
                out.append(f"  {line}")
        elif block.block_type == "thinking":
            out.append(f"[{block.index}] thinking ({len(block.text)} chars):")
            for line in truncate(block.text, args.max_body).splitlines():
                out.append(f"  {line}")
        else:
            out.append(f"[{block.index}] {block.block_type}:")
            for raw in block.raw_blocks:
                for line in truncate(
                    json.dumps(raw, ensure_ascii=False, indent=2),
                    args.max_body,
                ).splitlines():
                    out.append(f"  {line}")
    if assembled.other_events:
        out.append("")
        out.append(f"Unhandled SSE events: {len(assembled.other_events)}")
        for ev in assembled.other_events[:5]:
            out.append(f"  event={ev.event} data={truncate(ev.data, 200)}")
    return "\n".join(out)


def looks_like_sse(text: str) -> bool:
    head = text.lstrip()[:500]
    return "event:" in head and "data:" in head


def render_call(call: Call, args: argparse.Namespace) -> str:
    out: list[str] = []
    out.append(HR)
    out.append(f"CALL {call.call_id}")
    out.append(HR)
    if call.request:
        out.append(f"Started: {call.request.timestamp}")
    if call.response:
        out.append(f"Ended:   {call.response.timestamp}  "
                   f"elapsed={call.response.elapsed}s  status=ok")
    if call.error:
        out.append(f"Ended:   {call.error.timestamp}  "
                   f"elapsed={call.error.elapsed}s  status=error")
    out.append(f"Chunks: {len(call.chunks)}"
               + (f"  ({sum(c.chunk_bytes or 0 for c in call.chunks)} bytes)"
                  if call.chunks else ""))

    if args.raw:
        if call.request:
            out.append("")
            out.append(SUB)
            out.append("RAW REQUEST")
            out.append(SUB)
            out.append(call.request.body())
        for chunk in call.chunks:
            out.append("")
            out.append(SUB)
            out.append(f"RAW CHUNK {chunk.timestamp} "
                       f"({chunk.chunk_bytes} bytes)")
            out.append(SUB)
            out.append(chunk.body())
        if call.response:
            out.append("")
            out.append(SUB)
            out.append("RAW RESPONSE")
            out.append(SUB)
            out.append(call.response.body())
        if call.error:
            out.append("")
            out.append(SUB)
            out.append("RAW ERROR")
            out.append(SUB)
            out.append(call.error.body())
        return "\n".join(out)

    if call.request:
        out.append("")
        out.append(SUB)
        out.append("REQUEST")
        out.append(SUB)
        out.append(render_request(call.request, args))

    # Reconstruct the streamed response from the chunk records. If the
    # response wasn't streamed, fall through to the response-body render
    # below.
    sse_text = ""
    if call.chunks:
        sse_text = "\n".join(c.body() for c in call.chunks)
    elif call.response and looks_like_sse(split_response_record(
            call.response.body())):
        sse_text = split_response_record(call.response.body())

    if sse_text and looks_like_sse(sse_text):
        events = parse_sse(sse_text)
        assembled = assemble_anthropic_stream(events)
        out.append("")
        out.append(SUB)
        out.append(f"STREAM ({len(events)} SSE events)")
        out.append(SUB)
        out.append(render_assembled(assembled, args))
    elif call.response:
        body = split_response_record(call.response.body())
        out.append("")
        out.append(SUB)
        out.append("RESPONSE BODY")
        out.append(SUB)
        try:
            parsed = json.loads(body)
            out.append(truncate(json.dumps(parsed, indent=2, ensure_ascii=False),
                                args.max_body))
        except json.JSONDecodeError:
            out.append(truncate(body, args.max_body))

    if call.error:
        out.append("")
        out.append(SUB)
        out.append("ERROR")
        out.append(SUB)
        out.append(call.error.body())

    return "\n".join(out)


# --- main ------------------------------------------------------------------


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("path", nargs="?", default="-",
                        help="Log file (default: stdin).")
    parser.add_argument("--call", action="append", default=[],
                        help="Filter to one or more call UUIDs "
                             "(matches case-insensitively, may be a prefix).")
    parser.add_argument("--raw", action="store_true",
                        help="Print raw request / chunk / response bodies "
                             "unchanged (still grouped by call).")
    parser.add_argument("--no-system", action="store_true",
                        help="Skip the system prompt block in request render.")
    parser.add_argument("--no-tools", action="store_true",
                        help="Skip the tools list in request render.")
    parser.add_argument("--max-body", type=int, default=4000,
                        help="Truncate text bodies to this many characters "
                             "(0 = unlimited). Default 4000.")
    args = parser.parse_args()

    if args.path == "-":
        text = sys.stdin.read()
    else:
        with open(args.path, "r", encoding="utf-8", errors="replace") as f:
            text = f.read()

    records = parse_records(text)
    calls = group_by_call(records)

    if args.call:
        needles = [c.lower() for c in args.call]
        calls = [c for c in calls
                 if any(c.call_id.lower().startswith(n) for n in needles)]

    if not calls:
        print("No call records found.", file=sys.stderr)
        return 1

    print(f"Parsed {len(records)} records into {len(calls)} call(s).\n")
    for call in calls:
        print(render_call(call, args))
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
