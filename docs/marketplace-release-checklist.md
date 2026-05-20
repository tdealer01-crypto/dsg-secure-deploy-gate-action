# GitHub Marketplace Release Checklist

## Pre-merge

- [ ] Dedicated repo: `tdealer01-crypto/dsg-secure-deploy-gate-action`
- [ ] Public repository
- [ ] Root `action.yml`
- [ ] No `.github/workflows/*`
- [ ] Workflow examples are `.example.yml` under `examples/`
- [ ] No `__pycache__` or `.pyc`
- [ ] `bash -n scripts/dsg-gate.sh` passes
- [ ] `bash -n scripts/dsg-pr-comment.sh` passes
- [ ] `python3 -m py_compile scripts/verify-proof.py` passes
- [ ] No certification overclaim

## Release in GitHub UI

1. Merge PR to `main`.
2. Draft release tag `v1.1.0`.
3. Tick **Publish this Action to the GitHub Marketplace**.
4. If disabled, accept the Marketplace Developer Agreement.
5. Choose category.
6. Publish with 2FA.

Do not claim Marketplace publication until the release is actually published.
