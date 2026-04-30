# GitHub Marketplace Listing Draft

## Name

DSG Secure Deploy Gate

## One-line description

Deterministic readiness and governance evidence for CI/CD releases.

## Short description

DSG Secure Deploy Gate validates a production readiness endpoint, checks optional protected-route behavior, emits a GO / NO-GO verdict, and produces a SHA256 evidence hash for release records.

## Category

Continuous integration

Secondary fit: Deployment

## Problem

Teams often know that a build passed, but they do not have a compact release record that explains why a production release was allowed to continue.

## Differentiator

This action is not only an HTTP check. It creates release evidence:

- readiness result
- protected route result
- GO / NO-GO verdict
- failure reason
- SHA256 evidence hash
- GitHub step summary

## Suggested marketplace description

DSG Secure Deploy Gate adds a governance checkpoint to GitHub Actions. It verifies a readiness URL, optionally checks that protected routes reject unauthenticated requests, and writes deterministic GO / NO-GO evidence into the workflow output.

Use it for SaaS release readiness, audit-friendly deployment records, and DSG Control Plane workflows.

## Install snippet

```yaml
- uses: tdealer01-crypto/dsg-secure-deploy-gate-action@v1
  with:
    readiness_url: "https://your-app.vercel.app/api/finance-governance/readiness"
    expected_status: "200"
    require_json_ok: "true"
```

## Commercial path

Free Action:

- readiness check
- protected route check
- GO / NO-GO output
- evidence hash

Paid add-ons:

- hosted evidence dashboard
- monthly readiness report
- Vercel and Supabase deep checks
- Slack / email alerts
- custom policy rules
- team release history
