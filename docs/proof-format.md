# Proof format

DSG Secure Deploy Gate writes deterministic JSON evidence.

## Hashes

- `evidence_hash`: SHA-256 of canonical evidence without `hashes`
- `policy_hash`: SHA-256 of canonical policy
- `proof_hash`: SHA-256 of canonical proof object
- `chain_hash`: `proof_hash`, or SHA-256 of `previous_proof_hash + proof_hash`

## Canonical JSON

Canonical JSON uses sorted keys, compact separators, and UTF-8.

## URL handling

URLs are stored redacted when query strings exist. A URL hash is stored to preserve deterministic comparison without exposing query strings.

## Verification

Run:

```bash
python3 scripts/verify-proof.py dsg-evidence.json
```

Expected result:

```text
DSG proof verification: PASS
```

## Boundary

The proof format supports evidence workflows. It does not create legal, PDPA, ISO 27001, SOC 2, WORM, or third-party certification.
