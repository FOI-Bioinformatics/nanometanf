#!/usr/bin/env python3
"""Every fixture a test references must exist on a fresh clone.

Run from the repository root:

    python3 tests/lib/fixtures_are_tracked.py

Exits non-zero and names the offenders if any fixture referenced by an
``*.nf.test`` file is present locally but not tracked by git.

WHY THIS EXISTS
---------------
``.gitignore`` carried a blanket ``test_*`` pattern, which matches at any
depth. It silently excluded every fixture named ``test_something``:

    tests/fixtures/validation/test_genomes.json
    tests/fixtures/validation/test_kraken_output.txt
    modules/local/validation_cumulative_aggregator/tests/fixtures/**/test_*

Thirteen fixtures in total. Every test that used them passed locally, where
the files exist, and failed on a fresh clone with "No such file or directory".
CI is a fresh clone, so this surfaced the first time CI ever ran -- 20 of 155
tests failed, and almost all of them for this one reason.

The pattern had already bitten twice before: ``testing*`` excluded
docs/development/TESTING.md, and two per-directory whitelists had been added
for ``test_*`` without covering the rest. Fixing the pattern a third time does
not stop a fourth; asserting the property does.

Deliberately a standalone script rather than an nf-test case: it must run
without Nextflow, cheaply, and it inspects git rather than pipeline behaviour.
"""

from __future__ import annotations

import pathlib
import re
import subprocess
import sys

#: Path components that are build output rather than source. Matched against
#: each component of the path RELATIVE to the repository root, never against
#: the absolute path: the GitHub runner checks out to
#: /home/runner/work/<repo>/<repo>, so an absolute substring test for "work/"
#: matched every file and the check passed having examined nothing. CI caught
#: that on the first run after this script was added, reporting
#: "fixture paths referenced by nf-tests: 0".
SKIP_COMPONENTS = {".nf-test", "work", ".git"}


def referenced_fixture_paths(root: pathlib.Path) -> set[str]:
    """Every ``$projectDir/...`` path mentioned by any nf-test file."""
    refs: set[str] = set()
    for test in root.rglob("*.nf.test"):
        if SKIP_COMPONENTS & set(test.relative_to(root).parts):
            continue
        for match in re.finditer(
            r"\$\{?projectDir\}?/([A-Za-z0-9_./-]+)", test.read_text()
        ):
            refs.add(match.group(1))
    return refs


def tracked_files(root: pathlib.Path) -> set[str]:
    out = subprocess.run(
        ["git", "ls-files"], cwd=root, capture_output=True, text=True, check=True
    )
    return set(out.stdout.split())


def main() -> int:
    root = pathlib.Path(__file__).resolve().parent.parent.parent
    refs = referenced_fixture_paths(root)
    tracked = tracked_files(root)

    missing: list[str] = []
    for ref in sorted(refs):
        path = root / ref
        if not path.exists():
            # Referenced but absent locally too: that is a different problem
            # (a stale reference), and a test run will report it plainly.
            continue
        if path.is_dir():
            prefix = ref.rstrip("/") + "/"
            if not any(f.startswith(prefix) for f in tracked):
                missing.append(f"{ref}  (directory with no tracked contents)")
        elif ref not in tracked:
            missing.append(ref)

    print(f"fixture paths referenced by nf-tests: {len(refs)}")

    # A check that examined nothing must not report success. This script
    # already shipped one such state: an absolute-path skip matched the
    # runner's /home/runner/work/... checkout and filtered every test file,
    # so CI printed "0 fixture paths" and passed.
    if len(refs) < 20:
        print()
        print(f"only {len(refs)} fixture references found; this repository has "
              f"dozens. The scan is not seeing the test files, so a pass here "
              f"would mean nothing.")
        return 2

    if not missing:
        print("all present on a fresh clone")
        return 0

    print()
    print(f"{len(missing)} fixture(s) exist locally but are NOT tracked by git.")
    print("Tests using them pass here and fail on a fresh clone, which is CI:")
    print()
    for m in missing:
        print(f"  {m}")
    print()
    print("Usually a .gitignore pattern matching at any depth. Check with:")
    print("  git check-ignore -v <path>")
    return 1


if __name__ == "__main__":
    sys.exit(main())
