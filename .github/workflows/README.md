# GitHub Actions Workflows

| Workflow       | Trigger     | Purpose                                       |
| -------------- | ----------- | --------------------------------------------- |
| `ci.yml`       | PRs         | Verify pipeline syntax (dry-run) and help text |
| `linting.yml`  | PRs         | Pre-commit formatting checks                  |
| `clean-up.yml` | Weekly cron | Close stale issues/PRs                        |

## Running Tests Locally

```bash
# Quick validation (core + fast)
nf-test test --tag core --tag fast

# Full test suite
nf-test test
```
