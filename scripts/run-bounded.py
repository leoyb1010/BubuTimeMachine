#!/usr/bin/env python3
"""Run one owned process group with bounded interruption and a durable exit record.

The command's exit status is preserved. Timeout/cancellation is always nonzero,
even if the command handles interruption and exits successfully. SIGINT gives
xcodebuild an opportunity to finish its result bundle before forced cleanup.
"""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import time


def main():
    parser = argparse.ArgumentParser()
    limits = parser.add_mutually_exclusive_group(required=True)
    limits.add_argument("--seconds", type=float)
    limits.add_argument("--deadline-epoch", type=float)
    parser.add_argument("--grace-seconds", type=float, default=30)
    parser.add_argument("--record", type=Path, required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command or args.grace_seconds < 0:
        parser.error("a command and nonnegative grace are required")
    seconds = args.seconds if args.seconds is not None else args.deadline_epoch - time.time()
    started = time.monotonic()
    received = []
    for name in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(name, lambda signum, frame: received.append(signum))

    result = {"timeout_seconds": seconds, "grace_seconds": args.grace_seconds,
              "timed_out": False, "cancel_signal": None, "command_exit": None}
    proc = None
    status = 124
    try:
        if seconds <= 0:
            result["timed_out"] = True
            result["not_started"] = True
        else:
            proc = subprocess.Popen(command, start_new_session=True)
            result["owned_process_group"] = proc.pid
            deadline = started + seconds
            while proc.poll() is None and not received and time.monotonic() < deadline:
                time.sleep(min(0.1, max(0, deadline - time.monotonic())))
            interrupted = bool(received) or proc.poll() is None
            if interrupted:
                result["cancel_signal"] = received[0] if received else None
                result["timed_out"] = not received
                try:
                    os.killpg(proc.pid, signal.SIGINT)
                except ProcessLookupError:
                    pass
                try:
                    proc.wait(timeout=args.grace_seconds)
                except subprocess.TimeoutExpired:
                    pass
                # The leader may exit while an owned descendant ignores SIGINT.
                # Always terminate the complete group, not just the leader.
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                proc.wait()
                status = 128 + received[0] if received else 124
            else:
                status = proc.returncode if proc.returncode >= 0 else 128 - proc.returncode
            result["command_exit"] = proc.returncode
    except OSError as error:
        result["launch_error"] = str(error)
        status = 127
    finally:
        result["elapsed_seconds"] = round(time.monotonic() - started, 3)
        result["exit"] = status
        args.record.parent.mkdir(parents=True, exist_ok=True)
        args.record.write_text(json.dumps(result, indent=2) + "\n")
        print("BOUNDED_COMMAND_RESULT", json.dumps(result), flush=True)
    return status


if __name__ == "__main__":
    raise SystemExit(main())
