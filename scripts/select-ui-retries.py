#!/usr/bin/env python3
"""Retry only explicitly failed UI cases, preserving a complete first-attempt ledger.

Fail closed for incomplete logs, unknown cases, duplicate terminals or no failures.
A retry cannot stand in for tests never executed in the first attempt.
"""
import argparse
import json
import re
from pathlib import Path

CASE = re.compile(r"Test Case '-\[BubuTimeMachineUITests\.BubuTimeMachineUITests (test\w+)\]' (passed|failed|skipped)")

def completed_cases(text, expected, allowed_skips=()):
    observed = {}
    for name, status in CASE.findall(text):
        if name in observed:
            raise ValueError("Duplicate test completion: " + name)
        observed[name] = status
    if set(observed) != set(expected):
        raise ValueError("Incomplete or unexpected UI coverage: missing=" + str(sorted(set(expected) - set(observed)))
                         + "; unexpected=" + str(sorted(set(observed) - set(expected))))
    unexpected_skips = {name for name, status in observed.items() if status == "skipped"} - set(allowed_skips)
    if unexpected_skips:
        raise ValueError("Unexpected unexecuted UI cases: " + str(sorted(unexpected_skips)))
    return observed

def select(first, expected, device):
    allowed_skips = {"testIPadLandscapeKeepsNavigationAndRecord"} if device == "iPhone" else set()
    observed = completed_cases(first, expected, allowed_skips)
    failures = sorted(name for name, result in observed.items() if result == "failed")
    if not failures:
        raise ValueError("Nonzero first-attempt exit without explicit failed cases; do not hide infrastructure failures")
    return observed, failures

def self_test():
    def log(name, status): return f"Test Case '-[BubuTimeMachineUITests.BubuTimeMachineUITests {name}]' {status} (1 seconds).\n"
    ipad_only = "testIPadLandscapeKeepsNavigationAndRecord"
    expected = {"testA", "testB", ipad_only}
    first = log("testA", "passed") + log("testB", "failed") + log(ipad_only, "skipped")
    observed, failures = select(first, expected, "iPhone")
    assert failures == ["testB"] and observed[ipad_only] == "skipped"
    invalid = [log("testB", "failed"), first + log("testB", "failed"),
               first + log("testUnknown", "passed"), first.replace("failed", "passed"),
               first.replace("testA]\' passed", "testA]\' skipped")]
    for text in invalid:
        try: select(text, expected, "iPhone")
        except ValueError: pass
        else: raise AssertionError("Invalid/incomplete coverage accepted")
    try: select(first, expected, "iPad")
    except ValueError: pass
    else: raise AssertionError("iPad skipped its own required landscape journey")
    assert completed_cases(log("testB", "passed"), failures) == {"testB": "passed"}
    for retry in ["", log("testB", "skipped")]:
        try: completed_cases(retry, failures)
        except ValueError: pass
        else: raise AssertionError("Missing/skipped retry accepted")
    print("UI_RETRY_SELECTION_OK: explicit failures only; missing/duplicate/unknown/no-failure/unexpected-skip logs rejected")

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--self-test', action='store_true')
    p.add_argument('--device', choices=['iPhone', 'iPad'])
    p.add_argument('--source', type=Path)
    p.add_argument('--first-log', type=Path)
    p.add_argument('--retry-log', type=Path)
    p.add_argument('--validate-only', action='store_true')
    p.add_argument('--only-case', action='append', default=[])
    p.add_argument('--output', type=Path)
    a = p.parse_args()
    if a.self_test: self_test(); return
    if not a.source or not a.first_log or not a.output or not a.device: p.error('device, source, first-log, output required')
    expected = set(re.findall(r'\bfunc\s+(test\w+)\s*\(', a.source.read_text()))
    if not expected: raise ValueError('No expected XCTest cases found')
    if a.only_case:
        if not set(a.only_case) <= expected:
            raise ValueError('Focused selection contains a case absent from source')
        expected = set(a.only_case)
    if a.validate_only:
        allowed_skips = {'testIPadLandscapeKeepsNavigationAndRecord'} if a.device == 'iPhone' else set()
        observed = completed_cases(a.first_log.read_text(), expected, allowed_skips)
        if any(status == 'failed' for status in observed.values()):
            raise SystemExit('A failed case cannot be reported as a first-attempt pass')
        a.output.mkdir(parents=True, exist_ok=True)
        (a.output/'attempt-summary.json').write_text(json.dumps({
            'first_attempt': observed, 'first_attempt_failed': False,
            'result': 'passed_first_attempt', 'expected_count': len(expected), 'device': a.device,
            'intentional_platform_skips': sorted(name for name, status in observed.items() if status == 'skipped'),
        }, indent=2) + '\n')
        return
    first, failures = select(a.first_log.read_text(), expected, a.device)
    result = {'first_attempt': first, 'first_attempt_failed': True, 'retry_selected': failures,
              'result': 'retry_pending', 'expected_count': len(expected), 'device': a.device,
              'intentional_platform_skips': sorted(name for name, status in first.items() if status == 'skipped')}
    a.output.mkdir(parents=True, exist_ok=True)
    (a.output/'retry-tests.txt').write_text('\n'.join(failures)+'\n')
    if a.retry_log:
        retry = completed_cases(a.retry_log.read_text(), failures)
        result['retry_attempt'] = retry
        result['result'] = 'passed_after_retry' if all(value == 'passed' for value in retry.values()) else 'failed_after_retry'
    (a.output/'attempt-summary.json').write_text(json.dumps(result,indent=2)+'\n')
    if result['result'] == 'failed_after_retry': raise SystemExit('Some selected UI retries did not pass')

if __name__ == '__main__': main()
