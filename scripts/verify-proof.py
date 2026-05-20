#!/usr/bin/env python3
import copy
import hashlib
import json
import sys

def canonical(obj) -> str:
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)

def sha256_text(text: str) -> str:
    return "sha256:" + hashlib.sha256(text.encode("utf-8")).hexdigest()

def main() -> int:
    if len(sys.argv) != 2:
        print("usage: verify-proof.py <evidence.json>", file=sys.stderr)
        return 2
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        evidence = json.load(f)
    hashes = evidence.get("hashes") or {}
    without_hashes = copy.deepcopy(evidence)
    without_hashes.pop("hashes", None)
    expected_evidence = sha256_text(canonical(without_hashes))
    expected_policy = sha256_text(canonical(evidence.get("policy", {})))
    proof_obj = {
        "evidence_hash": expected_evidence,
        "policy_hash": expected_policy,
        "run_id": evidence.get("run_id", ""),
        "timestamp": evidence.get("timestamp", ""),
    }
    expected_proof = sha256_text(canonical(proof_obj))
    previous = evidence.get("previous_proof_hash", "")
    expected_chain = sha256_text(previous + expected_proof) if previous else expected_proof
    checks = {
        "evidence": (hashes.get("evidence"), expected_evidence),
        "policy": (hashes.get("policy"), expected_policy),
        "proof": (hashes.get("proof"), expected_proof),
        "chain": (hashes.get("chain"), expected_chain),
    }
    failed = False
    for name, (actual, expected) in checks.items():
        if actual != expected:
            print(f"{name}: FAIL actual={actual} expected={expected}")
            failed = True
        else:
            print(f"{name}: PASS {actual}")
    if failed:
        print("DSG proof verification: FAIL")
        return 1
    print("DSG proof verification: PASS")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
