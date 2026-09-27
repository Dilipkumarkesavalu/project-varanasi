# Runbook: GitHub repository setup (one-time)

Makes CI a hard gate (M1-FOU-011): a PR with any failing check, including a single broken
test, cannot be merged.

## 1. Create the repository and push

```bash
git remote add origin https://github.com/Dilipkumarkesavalu/project-varanasi.git
git push -u origin main
```

## 2. Code owners

While this is a personal repository, `.github/CODEOWNERS` assigns everything to
`@Dilipkumarkesavalu`. When it moves to an organization, split it into teams:
`architecture`, `backend`, `platform-team`, `billing-team`, `hrms-team`, `frontend-core`,
`devops`.

## 3. Protect `main`

Go to **Settings → Rules → Rulesets → New branch ruleset**, target `main`, and enable:

- Restrict deletions; block force pushes.
- **Require a pull request before merging**. Required approvals:
  - **0 while there is a single developer**, because GitHub never lets authors approve
    their own PRs, so 1 would block every merge;
  - **1, plus "Require review from Code Owners"**, as soon as a second developer joins
    (ADR-0008 §9).
- **Require status checks to pass**, adding the check **`CI passed`**. It succeeds only when
  every CI job succeeded.
- Require branches to be up to date before merging.
- Allowed merge method: **squash only** (ADR-0008 §9).

## 4. Prove it works (M1-FOU-011 "done when")

```bash
git switch -c test/ci-blocks-broken-test
# break one assertion on purpose
sed -i 's/assert response.status_code == 200/assert response.status_code == 201/' \
  backend/tests/unit/shared/test_health.py
git commit -am "test(shared): prove CI blocks a broken test"
git push -u origin test/ci-blocks-broken-test
```

Open a PR. **Backend · tests** fails, **CI passed** fails, and the merge button stays
disabled. Close the PR and delete the branch.
