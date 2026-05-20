#!/usr/bin/env bash
set -euo pipefail

READINESS_URL="${DSG_READINESS_URL:?Missing DSG_READINESS_URL}"
EXPECTED_STATUS="${DSG_EXPECTED_STATUS:-200}"
REQUIRE_JSON_OK="${DSG_REQUIRE_JSON_OK:-true}"
PROTECTED_URL="${DSG_PROTECTED_URL:-}"
PROTECTED_EXPECTED="${DSG_PROTECTED_EXPECTED:-401,403}"
PRESET="${DSG_PRESET:-strict}"
EVIDENCE_FILE="${DSG_EVIDENCE_FILE:-dsg-evidence.json}"
POLICY_NAME="${DSG_POLICY_NAME:-production-readiness}"
POLICY_VERSION="${DSG_POLICY_VERSION:-v1}"
PREVIOUS_PROOF_HASH="${DSG_PREVIOUS_PROOF_HASH:-}"
PROOF_TIMESTAMP="${DSG_PROOF_TIMESTAMP:-}"

BODY_FILE="${RUNNER_TEMP:-/tmp}/dsg-readiness-body.json"
PROTECTED_BODY_FILE="${RUNNER_TEMP:-/tmp}/dsg-protected-body.txt"
HASH_OUTPUT_FILE="${RUNNER_TEMP:-/tmp}/dsg-hashes.env"

case "$PRESET" in
  basic|standard|strict|audit-only) ;;
  *)
    echo "::error::Unknown preset '$PRESET'. Use basic, standard, strict, or audit-only."
    exit 1
    ;;
esac

if [[ -z "$PROOF_TIMESTAMP" ]]; then
  PROOF_TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
fi

RUN_ID="gha-${GITHUB_RUN_ID:-unknown}-${GITHUB_RUN_NUMBER:-0}"

should_check_json_ok="false"
should_check_protected="false"

case "$PRESET" in
  basic)
    should_check_json_ok="false"
    should_check_protected="false"
    ;;
  standard)
    should_check_json_ok="$REQUIRE_JSON_OK"
    should_check_protected="false"
    ;;
  strict)
    should_check_json_ok="true"
    should_check_protected="true"
    ;;
  audit-only)
    should_check_json_ok="$REQUIRE_JSON_OK"
    if [[ -n "$PROTECTED_URL" ]]; then
      should_check_protected="true"
    fi
    ;;
esac

if [[ -n "$PROTECTED_URL" ]]; then
  should_check_protected="true"
fi

http_status() {
  local url="$1"
  local out_file="$2"
  local status
  status="$(curl -sS -L -o "$out_file" -w "%{http_code}" --max-time 30 "$url" 2>/dev/null || true)"
  if [[ ! "$status" =~ ^[0-9]{3}$ ]]; then
    status="000"
  fi
  printf '%s' "$status"
}

verdict="GO"
failure_reason=""
readiness_status="000"
readiness_json_ok="null"
protected_status=""
protected_match="null"

printf '%s\n' "DSG Secure Deploy Gate"
printf 'Preset: %s\n' "$PRESET"

printf '%s\n' "::group::DSG readiness check"
readiness_status="$(http_status "$READINESS_URL" "$BODY_FILE")"
printf 'Readiness status: %s\n' "$readiness_status"

if [[ "$readiness_status" != "$EXPECTED_STATUS" ]]; then
  verdict="NO-GO"
  failure_reason="readiness_status_expected_${EXPECTED_STATUS}_got_${readiness_status}"
fi

if [[ "$verdict" == "GO" && "$should_check_json_ok" == "true" ]]; then
  readiness_json_ok="$(
    python3 - "$BODY_FILE" <<'PY'
import json, sys
path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    print("true" if data.get("ok") is True else "false")
except Exception:
    print("false")
PY
  )"

  if [[ "$readiness_json_ok" != "true" ]]; then
    verdict="NO-GO"
    failure_reason="readiness_json_ok_not_true"
  fi
fi
printf '%s\n' "::endgroup::"

if [[ "$should_check_protected" == "true" ]]; then
  printf '%s\n' "::group::DSG protected route check"
  if [[ -z "$PROTECTED_URL" ]]; then
    protected_status=""
    protected_match="false"
    if [[ -z "$failure_reason" ]]; then
      failure_reason="protected_url_required_for_${PRESET}_preset"
    fi
    verdict="NO-GO"
  else
    protected_status="$(http_status "$PROTECTED_URL" "$PROTECTED_BODY_FILE")"

    protected_match="$(
      python3 - "$protected_status" "$PROTECTED_EXPECTED" <<'PY'
import sys
actual = sys.argv[1].strip()
expected = [item.strip() for item in sys.argv[2].split(",") if item.strip()]
print("true" if actual in expected else "false")
PY
    )"

    if [[ "$protected_match" != "true" ]]; then
      verdict="NO-GO"
      if [[ -z "$failure_reason" ]]; then
        failure_reason="protected_route_expected_${PROTECTED_EXPECTED}_got_${protected_status}"
      fi
    fi
  fi
  printf 'Protected status: %s\n' "${protected_status:-not_checked}"
  printf '%s\n' "::endgroup::"
fi

export DSG_RESULT_VERDICT="$verdict"
export DSG_RESULT_FAILURE_REASON="$failure_reason"
export DSG_RESULT_READINESS_STATUS="$readiness_status"
export DSG_RESULT_READINESS_JSON_OK="$readiness_json_ok"
export DSG_RESULT_PROTECTED_STATUS="$protected_status"
export DSG_RESULT_PROTECTED_MATCH="$protected_match"
export DSG_RUN_ID="$RUN_ID"
export DSG_PROOF_TIMESTAMP_EFFECTIVE="$PROOF_TIMESTAMP"
export DSG_SHOULD_CHECK_PROTECTED="$should_check_protected"

python3 - "$EVIDENCE_FILE" "$HASH_OUTPUT_FILE" <<'PY'
import hashlib
import json
import os
import shlex
import sys
from urllib.parse import urlsplit, urlunsplit

evidence_path, hash_output_path = sys.argv[1], sys.argv[2]

def getenv(name: str, default: str = "") -> str:
    return os.environ.get(name, default)

def redact_url(url: str) -> str:
    if not url:
        return ""
    try:
        parts = urlsplit(url)
        if parts.query:
            return urlunsplit((parts.scheme, parts.netloc, parts.path, "[redacted]", parts.fragment))
        return url
    except Exception:
        return "[invalid-url]"

def url_hash(url: str) -> str:
    return "sha256:" + hashlib.sha256(url.encode("utf-8")).hexdigest()

def canonical(obj) -> str:
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)

def sha256_text(text: str) -> str:
    return "sha256:" + hashlib.sha256(text.encode("utf-8")).hexdigest()

def csv_statuses(raw: str):
    return [item.strip() for item in raw.split(",") if item.strip()]

def parse_bool_or_null(value: str):
    if value == "true":
        return True
    if value == "false":
        return False
    return None

def to_int(value: str, default: int = 0) -> int:
    try:
        return int(value)
    except Exception:
        return default

readiness_url = getenv("DSG_READINESS_URL")
protected_url = getenv("DSG_PROTECTED_URL")
protected_expected_raw = getenv("DSG_PROTECTED_EXPECTED", "401,403")
protected_status = getenv("DSG_RESULT_PROTECTED_STATUS")
protected_match_raw = getenv("DSG_RESULT_PROTECTED_MATCH", "null")
readiness_json_ok_raw = getenv("DSG_RESULT_READINESS_JSON_OK", "null")
should_check_protected = getenv("DSG_SHOULD_CHECK_PROTECTED", "false") == "true"

policy = {
    "name": getenv("DSG_POLICY_NAME", "production-readiness"),
    "version": getenv("DSG_POLICY_VERSION", "v1"),
    "preset": getenv("DSG_PRESET", "strict"),
}

readiness_json_ok = parse_bool_or_null(readiness_json_ok_raw)
checks = {
    "readiness": {
        "url": redact_url(readiness_url),
        "url_hash": url_hash(readiness_url),
        "status": to_int(getenv("DSG_RESULT_READINESS_STATUS", "0")),
        "expected_status": to_int(getenv("DSG_EXPECTED_STATUS", "200"), 200),
        "json_ok": readiness_json_ok,
    }
}
checks["readiness"]["passed"] = (
    checks["readiness"]["status"] == checks["readiness"]["expected_status"]
    and checks["readiness"]["json_ok"] is not False
)

if should_check_protected or protected_url or protected_status:
    expected = csv_statuses(protected_expected_raw)
    protected_check = {
        "url": redact_url(protected_url),
        "url_hash": url_hash(protected_url),
        "status": to_int(protected_status or "0"),
        "expected_statuses": [to_int(x) for x in expected if x.isdigit()],
        "passed": parse_bool_or_null(protected_match_raw),
    }
    checks["protected_route"] = protected_check

evidence = {
    "schema": "dsg.proof.v1",
    "tool": "dsg-secure-deploy-gate",
    "timestamp": getenv("DSG_PROOF_TIMESTAMP_EFFECTIVE"),
    "run_id": getenv("DSG_RUN_ID"),
    "repository": getenv("GITHUB_REPOSITORY", "unknown"),
    "sha": getenv("GITHUB_SHA", "unknown"),
    "ref": getenv("GITHUB_REF", "unknown"),
    "event": getenv("GITHUB_EVENT_NAME", "unknown"),
    "policy": policy,
    "checks": checks,
    "verdict": getenv("DSG_RESULT_VERDICT", "NO-GO"),
    "failure_reason": getenv("DSG_RESULT_FAILURE_REASON", ""),
    "previous_proof_hash": getenv("DSG_PREVIOUS_PROOF_HASH", ""),
}

evidence_hash = sha256_text(canonical(evidence))
policy_hash = sha256_text(canonical(policy))
proof = {
    "evidence_hash": evidence_hash,
    "policy_hash": policy_hash,
    "run_id": evidence["run_id"],
    "timestamp": evidence["timestamp"],
}
proof_hash = sha256_text(canonical(proof))

previous = evidence["previous_proof_hash"]
chain_hash = sha256_text(previous + proof_hash) if previous else proof_hash

evidence["hashes"] = {
    "evidence": evidence_hash,
    "policy": policy_hash,
    "proof": proof_hash,
    "chain": chain_hash,
}

with open(evidence_path, "w", encoding="utf-8") as f:
    f.write(canonical(evidence) + "\n")

with open(hash_output_path, "w", encoding="utf-8") as f:
    for key, value in evidence["hashes"].items():
        f.write(f"{key}_hash={shlex.quote(value)}\n")

print(json.dumps(evidence["hashes"], sort_keys=True))
PY

# shellcheck disable=SC1090
source "$HASH_OUTPUT_FILE"

{
  echo "verdict=$verdict"
  echo "readiness_status=$readiness_status"
  echo "protected_status=$protected_status"
  echo "failure_reason=$failure_reason"
  echo "evidence_hash=$evidence_hash"
  echo "policy_hash=$policy_hash"
  echo "proof_hash=$proof_hash"
  echo "chain_hash=$chain_hash"
  echo "evidence_file=$EVIDENCE_FILE"
} >> "${GITHUB_OUTPUT:-/dev/null}"

{
  echo "## DSG Secure Deploy Gate"
  echo ""
  echo "| Field | Value |"
  echo "|---|---|"
  echo "| Verdict | $verdict |"
  echo "| Preset | $PRESET |"
  echo "| Readiness status | $readiness_status |"
  echo "| Protected status | ${protected_status:-not_checked} |"
  echo "| Failure reason | ${failure_reason:-none} |"
  echo "| Evidence hash | \`$evidence_hash\` |"
  echo "| Proof hash | \`$proof_hash\` |"
  echo "| Chain hash | \`$chain_hash\` |"
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"

printf 'DSG verdict: %s\n' "$verdict"
printf 'Evidence file: %s\n' "$EVIDENCE_FILE"
printf 'Evidence hash: %s\n' "$evidence_hash"
printf 'Proof hash: %s\n' "$proof_hash"
printf 'Chain hash: %s\n' "$chain_hash"

if [[ "$verdict" != "GO" ]]; then
  printf 'DSG NO-GO reason: %s\n' "$failure_reason"
fi

exit 0
