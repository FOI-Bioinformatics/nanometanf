# GitHub Actions Workflows

## Test Workflows

| Workflow           | Trigger          | Purpose                                                    | Duration |
| ------------------ | ---------------- | ---------------------------------------------------------- | -------- |
| `nf-test.yml`      | PRs, releases    | Multi-profile sharded testing (Docker, Singularity, Conda) | Variable |
| `nightly.yml`      | Daily (2 AM UTC) | All core tests                                             | ~30 min  |
| `test-feature.yml` | Manual           | Feature-specific debugging                                 | Variable |

## Other Workflows

| Workflow       | Purpose                           |
| -------------- | --------------------------------- |
| `linting.yml`  | nf-core compliance and pre-commit |
| `branch.yml`   | Branch naming validation          |
| `clean-up.yml` | Cache cleanup                     |

## Running Tests Locally

```bash
# Quick validation (core + fast)
nf-test test --tag core --tag fast

# All core tests
nf-test test --tag core

# Full test suite
nf-test test
```

## Tag System

| Tag        | Purpose                |
| ---------- | ---------------------- |
| `core`     | Must-pass tests        |
| `extended` | Nice-to-pass tests     |
| `fast`     | Quick tests (< 1 min)  |
| `slow`     | Longer tests (> 1 min) |

Optional feature tags: `realtime`, `basecalling`, `qc`, `classification`
