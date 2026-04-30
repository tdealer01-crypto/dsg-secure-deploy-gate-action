# DSG Secure Deploy Gate

Deterministic production readiness, security, and governance gate for CI/CD.

DSG Secure Deploy Gate blocks unsafe deployments before production by checking readiness endpoints, protected route behavior, and generating GO / NO-GO evidence with a SHA256 evidence hash.

## Usage

```yaml
name: DSG Secure Deploy Gate

on:
  pull_request:
  push:
    branches: [main]

jobs:
  dsg-gate:
    runs-on: ubuntu-latest
    steps:
      - uses: tdealer01-crypto/dsg-secure-deploy-gate-action@v1
        with:
          readiness_url: "https://your-app.vercel.app/api/finance-governance/readiness"
          expected_status: "200"
          require_json_ok: "true"
          protected_url: "https://your-app.vercel.app/api/finance-governance/audit-ledger"
          protected_expected: "401,403"
```

## What it checks

- Readiness endpoint returns the expected HTTP status.
- Optional JSON body contains `ok: true`.
- Optional protected route returns the expected unauthenticated status.
- Emits deterministic `GO` / `NO-GO` output.
- Writes an evidence hash into GitHub Actions output and job summary.

## Inputs

| Input | Required | Default | Description |
|---|---:|---:|---|
| `readiness_url` | yes | none | Production readiness endpoint URL. |
| `expected_status` | no | `200` | Expected HTTP status code. |
| `require_json_ok` | no | `true` | Require response JSON to contain `ok: true`. |
| `protected_url` | no | empty | Optional protected route URL expected to deny unauthenticated access. |
| `protected_expected` | no | `401,403` | Comma-separated expected unauthenticated statuses. |

## Outputs

| Output | Meaning |
|---|---|
| `verdict` | `GO` or `NO-GO` |
| `readiness_status` | HTTP status from readiness endpoint |
| `evidence_hash` | SHA256 hash of the evidence payload |

## DSG product fit

This action is designed for DSG Control Plane, AI-agent deployment gates, SaaS governance systems, and production readiness workflows.

The v1 scope is intentionally narrow:

- no direct production deploy
- no database mutation
- no arbitrary shell execution
- no secret storage

The action is a gate, not a god-mode runner.
