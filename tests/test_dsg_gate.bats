#!/usr/bin/env bats
# Behavioral regression tests for scripts/dsg-gate.sh

GATE_SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/dsg-gate.sh"
VERIFY_SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/verify-proof.py"

setup() {
  export RUNNER_TEMP
  RUNNER_TEMP="$(mktemp -d)"
  export GITHUB_RUN_ID="test-001"
  export GITHUB_RUN_NUMBER="1"
  export GITHUB_REPOSITORY="test-org/test-repo"
  export GITHUB_SHA="abc123def456"
  export GITHUB_REF="refs/heads/main"
  export GITHUB_EVENT_NAME="push"
  export GITHUB_OUTPUT="$RUNNER_TEMP/github_output"
  export GITHUB_STEP_SUMMARY="$RUNNER_TEMP/step_summary"
  touch "$GITHUB_OUTPUT" "$GITHUB_STEP_SUMMARY"

  # Inject mock curl into PATH
  export MOCK_BIN="$RUNNER_TEMP/bin"
  mkdir -p "$MOCK_BIN"
  cp "$(dirname "$BATS_TEST_FILENAME")/mock-curl" "$MOCK_BIN/curl"
  chmod +x "$MOCK_BIN/curl"
  export PATH="$MOCK_BIN:$PATH"

  # Default mock: 200 with {"ok":true}, no protected path
  unset MOCK_READINESS_STATUS MOCK_READINESS_BODY MOCK_PROTECTED_PATH MOCK_PROTECTED_STATUS MOCK_PROTECTED_BODY
}

teardown() {
  rm -rf "$RUNNER_TEMP"
}

# ---------------------------------------------------------------------------

@test "invalid preset exits 1 with error message" {
  export DSG_READINESS_URL="http://localhost/health"
  export DSG_PRESET="nonexistent"
  run bash "$GATE_SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown preset"* ]]
}

@test "basic preset with 200 produces GO verdict and valid evidence file" {
  export DSG_READINESS_URL="http://localhost/health"
  export DSG_PRESET="basic"
  export DSG_EVIDENCE_FILE="$RUNNER_TEMP/evidence.json"
  export DSG_PROOF_TIMESTAMP="2026-01-01T00:00:00Z"
  run bash "$GATE_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"GO"* ]]
  [ -f "$DSG_EVIDENCE_FILE" ]
  python3 -c "
import json
with open('$DSG_EVIDENCE_FILE') as f:
    e = json.load(f)
assert e['verdict'] == 'GO', f\"Expected GO got {e['verdict']}\"
for k in ['schema','tool','timestamp','run_id','verdict','policy','checks','hashes']:
    assert k in e, f\"Missing field: {k}\"
assert e['hashes']['evidence'].startswith('sha256:')
assert e['hashes']['chain'].startswith('sha256:')
"
}

@test "standard preset json_ok=false produces NO-GO" {
  export DSG_READINESS_URL="http://localhost/health"
  export DSG_PRESET="standard"
  export DSG_REQUIRE_JSON_OK="true"
  export DSG_EVIDENCE_FILE="$RUNNER_TEMP/evidence.json"
  export DSG_PROOF_TIMESTAMP="2026-01-01T00:00:00Z"
  export MOCK_READINESS_BODY='{"ok":false}'
  run bash "$GATE_SCRIPT"
  [ "$status" -eq 0 ]
  python3 -c "
import json
with open('$DSG_EVIDENCE_FILE') as f:
    e = json.load(f)
assert e['verdict'] == 'NO-GO', f\"Expected NO-GO got {e['verdict']}\"
assert 'json_ok' in e['failure_reason'], f\"Unexpected reason: {e['failure_reason']}\"
"
}

@test "basic preset with non-200 status produces NO-GO" {
  export DSG_READINESS_URL="http://localhost/health"
  export DSG_PRESET="basic"
  export DSG_EVIDENCE_FILE="$RUNNER_TEMP/evidence.json"
  export DSG_PROOF_TIMESTAMP="2026-01-01T00:00:00Z"
  export MOCK_READINESS_STATUS="503"
  export MOCK_READINESS_BODY='{"status":"error"}'
  run bash "$GATE_SCRIPT"
  [ "$status" -eq 0 ]
  python3 -c "
import json
with open('$DSG_EVIDENCE_FILE') as f:
    e = json.load(f)
assert e['verdict'] == 'NO-GO'
assert '503' in e['failure_reason']
"
}

@test "strict preset with empty protected_url produces NO-GO" {
  export DSG_READINESS_URL="http://localhost/health"
  export DSG_PRESET="strict"
  export DSG_PROTECTED_URL=""
  export DSG_EVIDENCE_FILE="$RUNNER_TEMP/evidence.json"
  export DSG_PROOF_TIMESTAMP="2026-01-01T00:00:00Z"
  run bash "$GATE_SCRIPT"
  [ "$status" -eq 0 ]
  python3 -c "
import json
with open('$DSG_EVIDENCE_FILE') as f:
    e = json.load(f)
assert e['verdict'] == 'NO-GO'
"
}

@test "strict preset with protected route returning 401 produces GO" {
  export DSG_READINESS_URL="http://localhost/health"
  export DSG_PRESET="strict"
  export DSG_PROTECTED_URL="http://localhost/protected"
  export DSG_EVIDENCE_FILE="$RUNNER_TEMP/evidence.json"
  export DSG_PROOF_TIMESTAMP="2026-01-01T00:00:00Z"
  export MOCK_PROTECTED_PATH="/protected"
  export MOCK_PROTECTED_STATUS="401"
  run bash "$GATE_SCRIPT"
  [ "$status" -eq 0 ]
  python3 -c "
import json
with open('$DSG_EVIDENCE_FILE') as f:
    e = json.load(f)
assert e['verdict'] == 'GO', f\"Expected GO got {e['verdict']}: {e['failure_reason']}\"
"
}

@test "verify-proof.py passes on freshly generated evidence" {
  export DSG_READINESS_URL="http://localhost/health"
  export DSG_PRESET="basic"
  export DSG_EVIDENCE_FILE="$RUNNER_TEMP/evidence.json"
  export DSG_PROOF_TIMESTAMP="2026-01-01T00:00:00Z"
  bash "$GATE_SCRIPT"
  run python3 "$VERIFY_SCRIPT" "$DSG_EVIDENCE_FILE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

@test "chain hash differs when previous_proof_hash is provided" {
  export DSG_READINESS_URL="http://localhost/health"
  export DSG_PRESET="basic"
  export DSG_PROOF_TIMESTAMP="2026-01-01T00:00:00Z"

  export DSG_PREVIOUS_PROOF_HASH=""
  export DSG_EVIDENCE_FILE="$RUNNER_TEMP/evidence_no_prev.json"
  bash "$GATE_SCRIPT"
  chain_no_prev=$(python3 -c "import json; print(json.load(open('$RUNNER_TEMP/evidence_no_prev.json'))['hashes']['chain'])")

  export DSG_PREVIOUS_PROOF_HASH="sha256:$(printf '%064d' 0)"
  export DSG_EVIDENCE_FILE="$RUNNER_TEMP/evidence_with_prev.json"
  bash "$GATE_SCRIPT"
  chain_with_prev=$(python3 -c "import json; print(json.load(open('$RUNNER_TEMP/evidence_with_prev.json'))['hashes']['chain'])")

  [ "$chain_no_prev" != "$chain_with_prev" ]
}
