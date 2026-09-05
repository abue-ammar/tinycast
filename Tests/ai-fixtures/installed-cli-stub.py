#!/usr/bin/env python3
"""A fake Claude/OpenCode CLI for the installed-provider harness."""

import json
import os
import sys


ROOT = os.environ["TC_INSTALLED_STUB_ROOT"]
COMMAND = os.path.basename(sys.argv[0])


def record(name, value):
    with open(os.path.join(ROOT, name), "a") as handle:
        handle.write(value + "\n")


record(COMMAND + "-args.log", json.dumps(sys.argv[1:]))

if COMMAND == "opencode" and sys.argv[1:3] == ["session", "delete"]:
    record("deleted.log", sys.argv[3])
    raise SystemExit(0)

prompt = sys.stdin.read()
record(COMMAND + "-prompt.log", prompt)
record(COMMAND + "-environment.log", os.environ.get("OPENCODE_CONFIG_CONTENT", ""))

if COMMAND == "opencode":
    print(json.dumps({"type": "step_start", "sessionID": "ses_stub", "part": {}}))
    print(
        json.dumps(
            {
                "type": "text",
                "sessionID": "ses_stub",
                "part": {"text": "OpenCode reply"},
            }
        )
    )
    print(
        json.dumps(
            {
                "type": "step_finish",
                "sessionID": "ses_stub",
                "part": {"tokens": {"input": 9, "output": 2}},
            }
        )
    )
else:
    print(
        json.dumps(
            {
                "type": "stream_event",
                "event": {"delta": {"type": "text_delta", "text": "Claude reply"}},
            }
        )
    )
    print(
        json.dumps(
            {
                "type": "result",
                "is_error": False,
                "usage": {"input_tokens": 8, "output_tokens": 2},
            }
        )
    )
