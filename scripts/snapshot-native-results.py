#!/usr/bin/env python3
"""Copy readable result files once; uploads never traverse a live xcresult.

An interrupted bundle can still provide diagnostics. Missing files and missing
Info.plist are recorded explicitly and are never reported as a complete result.
"""
import argparse
import json
from pathlib import Path
import shutil


def snapshot(source, destination):
    records = []
    destination.mkdir(parents=True, exist_ok=True)
    for bundle in sorted(source.glob("*.xcresult")):
        output = destination / bundle.name
        record = {"bundle": bundle.name, "finalized": (bundle / "Info.plist").is_file(),
                  "copied_files": 0, "copy_errors": []}
        output.mkdir()
        for path in sorted(bundle.rglob("*")):
            if not path.is_file() or path.is_symlink():
                continue
            relative = path.relative_to(bundle)
            target = output / relative
            try:
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, target)
                record["copied_files"] += 1
            except OSError as error:
                record["copy_errors"].append({"path": str(relative), "error": str(error)})
                target.unlink(missing_ok=True)
        record["complete_copy"] = record["finalized"] and not record["copy_errors"]
        records.append(record)
    (destination / "snapshot-status.json").write_text(json.dumps(records, indent=2) + "\n")
    return records


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--destination", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(snapshot(args.source, args.destination), indent=2))
