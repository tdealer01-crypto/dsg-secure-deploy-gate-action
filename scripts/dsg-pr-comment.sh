#!/usr/bin/env bash
set -euo pipefail

EVIDENCE_FILE="${DSG_EVIDENCE_FILE:-dsg-evidence.json}"
API_ROOT="${GITHUB_API_URL:-https://api.github.com}"
MARKER="<!-- dsg-secure-deploy-gate-comment -->"

if [[ -z "${PR_NUMBER:-}" || -z "${GITHUB_TOKEN:-}" || -z "${GITHUB_REPOSITORY:-}" ]]; then
  echo "::warning::Missing PR context. Skipping DSG PR comment."
  exit 0
fi

if [[ ! -f "$EVIDENCE_FILE" ]]; then
  echo "::warning::Evidence file not found: $EVIDENCE_FILE"
  exit 0
fi

comment_body="$(python3 - "$EVIDENCE_FILE" "$MARKER" <<'PY'
import json, sys
path, marker = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as f:
    evidence = json.load(f)
verdict = evidence.get("verdict", "NO-GO")
policy = evidence.get("policy", {})
checks = evidence.get("checks", {})
hashes = evidence.get("hashes", {})
readiness = checks.get("readiness", {})
protected = checks.get("protected_route", {})
icon = "✅" if verdict == "GO" else "❌"
lines = [
    marker,
    f"## DSG Secure Deploy Gate: {icon} {verdict}",
    "",
    "| Field | Value |",
    "|---|---|",
    f"| Verdict | {verdict} |",
    f"| Preset | {policy.get('preset', 'unknown')} |",
    f"| Readiness | {readiness.get('status', 'unknown')} |",
    f"| Protected route | {protected.get('status', 'not_checked')} |",
    f"| Failure reason | `{evidence.get('failure_reason') or 'none'}` |",
    f"| Evidence hash | `{hashes.get('evidence', 'missing')}` |",
    f"| Proof hash | `{hashes.get('proof', 'missing')}` |",
    f"| Chain hash | `{hashes.get('chain', 'missing')}` |",
    "",
]
if verdict == "GO":
    lines.append("Safe to deploy according to the configured DSG policy.")
else:
    lines.append("Fix the NO-GO reason before deploy, or run audit-only only when intentionally non-blocking.")
print("\n".join(lines))
PY
)"

comments_url="${API_ROOT}/repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/comments"
existing_comment_id="$(curl -fsSL -H "Authorization: Bearer ${GITHUB_TOKEN}" -H "Accept: application/vnd.github+json" "$comments_url?per_page=100" | python3 - "$MARKER" <<'PY'
import json, sys
marker = sys.argv[1]
try:
    comments = json.load(sys.stdin)
except Exception:
    comments = []
for comment in comments:
    if marker in comment.get("body", ""):
        print(comment.get("id", ""))
        break
PY
)" || existing_comment_id=""

payload="$(python3 - "$comment_body" <<'PY'
import json, sys
print(json.dumps({"body": sys.argv[1]}))
PY
)"

if [[ -n "$existing_comment_id" ]]; then
  curl -fsSL -X PATCH -H "Authorization: Bearer ${GITHUB_TOKEN}" -H "Accept: application/vnd.github+json" -H "Content-Type: application/json" "${API_ROOT}/repos/${GITHUB_REPOSITORY}/issues/comments/${existing_comment_id}" -d "$payload" >/dev/null
  echo "Updated DSG PR comment."
else
  curl -fsSL -X POST -H "Authorization: Bearer ${GITHUB_TOKEN}" -H "Accept: application/vnd.github+json" -H "Content-Type: application/json" "$comments_url" -d "$payload" >/dev/null
  echo "Created DSG PR comment."
fi
