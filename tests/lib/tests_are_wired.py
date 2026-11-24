#!/usr/bin/env python3
"""Every nf-test file must either run in CI or be excluded on the record.

CI runs an explicit allowlist of test files (.github/workflows/nf-test.yml), so
a newly added test file is silent by default: committed, never executed, and
nothing says so. The 2026-10-26 real-time audit found 41 of 101 test files in
that state, two of them pure-function suites excluded only because their
filenames begin with "realtime" (finding F13). A suite that does not run is not
a safety net.

This script fails when a test file is neither referenced in the workflow nor
listed in tests/ci_excluded_tests.txt with a reason, and also when the
exclusions file has gone stale -- a path that no longer exists, or one that is
excluded and referenced at the same time. Like tests_are_wired's sibling
fixtures_are_tracked.py, it refuses to pass when it finds nothing to check: an
empty scan is a broken scan, not a clean bill of health.

Run from the repository root; exits non-zero on any problem.
"""

import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parents[2]
WORKFLOW = REPO / ".github/workflows/nf-test.yml"
EXCLUSIONS = REPO / "tests/ci_excluded_tests.txt"
SEARCH_ROOTS = ("tests", "modules", "subworkflows", "workflows")
VALID_REASONS = {"watchpath", "nf-core", "unverified"}


def discover_tests():
    found = set()
    for root in SEARCH_ROOTS:
        base = REPO / root
        if base.is_dir():
            for p in base.rglob("*.nf.test"):
                found.add(p.relative_to(REPO).as_posix())
    return found


def referenced_in_workflow():
    if not WORKFLOW.is_file():
        print(f"ERROR: no CI workflow at {WORKFLOW.relative_to(REPO)}")
        sys.exit(1)
    text = WORKFLOW.read_text()
    return set(
        re.findall(r"(?:tests|modules|subworkflows|workflows)/[A-Za-z0-9_/.-]*\.nf\.test", text)
    )


def parse_exclusions():
    """{path: reason}. Malformed or unknown-reason lines are fatal."""
    if not EXCLUSIONS.is_file():
        print(f"ERROR: no exclusions file at {EXCLUSIONS.relative_to(REPO)}")
        sys.exit(1)
    out, bad = {}, []
    for n, raw in enumerate(EXCLUSIONS.read_text().splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) < 2:
            bad.append(f"  line {n}: needs a path and a reason code -- {raw!r}")
            continue
        path, reason = parts[0], parts[1]
        if reason not in VALID_REASONS:
            bad.append(
                f"  line {n}: reason {reason!r} is not one of {sorted(VALID_REASONS)}"
            )
            continue
        out[path] = reason
    if bad:
        print(f"{EXCLUSIONS.relative_to(REPO)} is malformed:")
        print("\n".join(bad))
        sys.exit(1)
    return out


def main():
    tests = discover_tests()
    if not tests:
        print("ERROR: found no *.nf.test files at all -- the scan is broken, not clean")
        return 1

    referenced = referenced_in_workflow()
    if not referenced:
        print("ERROR: the CI workflow references no test files -- the scan is broken")
        return 1

    excluded = parse_exclusions()
    problems = []

    unwired = sorted(tests - referenced - set(excluded))
    if unwired:
        problems.append(
            "These test files are neither run by CI nor listed in "
            f"{EXCLUSIONS.relative_to(REPO)}:\n"
            + "\n".join(f"  {p}" for p in unwired)
            + "\n  Add them to the nf-test workflow, or record why they are "
            "excluded.\n  A committed test that never runs proves nothing."
        )

    stale = sorted(p for p in excluded if p not in tests)
    if stale:
        problems.append(
            f"{EXCLUSIONS.relative_to(REPO)} lists paths that do not exist:\n"
            + "\n".join(f"  {p}" for p in stale)
        )

    both = sorted(p for p in excluded if p in referenced)
    if both:
        problems.append(
            "These are excluded AND referenced by the CI workflow -- remove one:\n"
            + "\n".join(f"  {p} ({excluded[p]})" for p in both)
        )

    ghosts = sorted(referenced - tests)
    if ghosts:
        problems.append(
            "The CI workflow references test files that do not exist:\n"
            + "\n".join(f"  {p}" for p in ghosts)
        )

    if problems:
        print("\n\n".join(problems))
        return 1

    by_reason = {r: sum(1 for v in excluded.values() if v == r) for r in sorted(VALID_REASONS)}
    print(f"nf-test files: {len(tests)}")
    print(f"  run in CI:  {len(tests & referenced)}")
    print(f"  excluded:   {len(excluded)}  ({', '.join(f'{k}={v}' for k, v in by_reason.items())})")
    if by_reason.get("unverified"):
        print(
            f"  note: {by_reason['unverified']} excluded with reason 'unverified' -- "
            "no reason to skip them has been established"
        )
    print("every test file is either run or excluded on the record")
    return 0


if __name__ == "__main__":
    sys.exit(main())
