#!/usr/bin/env python3
import copy
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import unittest

VERIFY_SCRIPT = os.path.join(os.path.dirname(__file__), "..", "scripts", "verify-proof.py")


def canonical(obj) -> str:
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def sha256_text(text: str) -> str:
    return "sha256:" + hashlib.sha256(text.encode("utf-8")).hexdigest()


def build_valid_evidence(previous: str = "") -> dict:
    policy = {"name": "test-policy", "preset": "basic", "version": "v1"}
    evidence: dict = {
        "schema": "dsg.proof.v1",
        "tool": "dsg-secure-deploy-gate",
        "timestamp": "2026-01-01T00:00:00Z",
        "run_id": "gha-test-001-1",
        "repository": "test-org/test-repo",
        "sha": "abc123",
        "ref": "refs/heads/main",
        "event": "push",
        "policy": policy,
        "checks": {
            "readiness": {
                "url": "http://example.com/health",
                "url_hash": sha256_text("http://example.com/health"),
                "status": 200,
                "expected_status": 200,
                "json_ok": True,
                "passed": True,
            }
        },
        "verdict": "GO",
        "failure_reason": "",
        "previous_proof_hash": previous,
    }
    without_hashes = copy.deepcopy(evidence)
    evidence_hash = sha256_text(canonical(without_hashes))
    policy_hash = sha256_text(canonical(policy))
    proof_obj = {
        "evidence_hash": evidence_hash,
        "policy_hash": policy_hash,
        "run_id": evidence["run_id"],
        "timestamp": evidence["timestamp"],
    }
    proof_hash = sha256_text(canonical(proof_obj))
    chain_hash = sha256_text(previous + proof_hash) if previous else proof_hash
    evidence["hashes"] = {
        "evidence": evidence_hash,
        "policy": policy_hash,
        "proof": proof_hash,
        "chain": chain_hash,
    }
    return evidence


class TestVerifyProof(unittest.TestCase):
    def _run_verify(self, evidence: dict) -> subprocess.CompletedProcess:
        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".json", delete=False
        ) as f:
            json.dump(evidence, f)
            fname = f.name
        try:
            return subprocess.run(
                [sys.executable, VERIFY_SCRIPT, fname],
                capture_output=True,
                text=True,
            )
        finally:
            os.unlink(fname)

    def test_valid_proof_passes(self):
        result = self._run_verify(build_valid_evidence())
        self.assertEqual(result.returncode, 0)
        self.assertIn("PASS", result.stdout)

    def test_tampered_verdict_fails(self):
        evidence = build_valid_evidence()
        evidence["verdict"] = "NO-GO"
        result = self._run_verify(evidence)
        self.assertEqual(result.returncode, 1)
        self.assertIn("FAIL", result.stdout)

    def test_tampered_policy_version_fails(self):
        evidence = build_valid_evidence()
        evidence["policy"]["version"] = "v999"
        result = self._run_verify(evidence)
        self.assertEqual(result.returncode, 1)
        self.assertIn("FAIL", result.stdout)

    def test_tampered_evidence_hash_field_fails(self):
        evidence = build_valid_evidence()
        evidence["hashes"]["evidence"] = "sha256:" + "0" * 64
        result = self._run_verify(evidence)
        self.assertEqual(result.returncode, 1)
        self.assertIn("FAIL", result.stdout)

    def test_tampered_chain_hash_fails(self):
        evidence = build_valid_evidence()
        evidence["hashes"]["chain"] = "sha256:" + "f" * 64
        result = self._run_verify(evidence)
        self.assertEqual(result.returncode, 1)
        self.assertIn("FAIL", result.stdout)

    def test_valid_chain_with_previous_proof(self):
        prev = "sha256:" + "a" * 64
        evidence = build_valid_evidence(previous=prev)
        result = self._run_verify(evidence)
        self.assertEqual(result.returncode, 0)
        self.assertIn("PASS", result.stdout)

    def test_wrong_chain_with_previous_proof_fails(self):
        prev = "sha256:" + "a" * 64
        evidence = build_valid_evidence(previous=prev)
        evidence["hashes"]["chain"] = "sha256:" + "0" * 64
        result = self._run_verify(evidence)
        self.assertEqual(result.returncode, 1)
        self.assertIn("FAIL", result.stdout)

    def test_wrong_arg_count_returns_2(self):
        result = subprocess.run(
            [sys.executable, VERIFY_SCRIPT],
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 2)

    def test_nonexistent_file_fails(self):
        result = subprocess.run(
            [sys.executable, VERIFY_SCRIPT, "/nonexistent/path/evidence.json"],
            capture_output=True,
            text=True,
        )
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
