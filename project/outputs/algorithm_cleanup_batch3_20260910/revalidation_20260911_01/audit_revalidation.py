"""Audit existing batch 3 sources and fresh MCP evidence without replacing history."""
from pathlib import Path
import ast
import difflib
import hashlib
import json
import re
import subprocess
import sys

OUT = Path(__file__).resolve().parent
BATCH = OUT.parent
ROOT = BATCH.parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(name, value):
    (OUT / name).write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


manifest = json.loads((OUT / "source_manifest_before.json").read_text())
source_audit = {}
for name, record in manifest.items():
    path = ROOT / name
    # The parent report is the only deliberately updated original artifact.
    original = OUT / "REPORT_before.md" if name.endswith("/REPORT.md") else path
    source_audit[name] = {
        "recorded_sha256": record["after_sha256"],
        "revalidation_entry_sha256": digest(original),
        "matches_recorded_batch3": digest(original) == record["after_sha256"],
        "current_sha256": digest(path),
    }
write_json("source_audit.json", source_audit)
assert all(x["matches_recorded_batch3"] for x in source_audit.values())

prior = json.loads((BATCH / "batch2_preservation_final.json").read_text())
preservation = {name: {
    "expected_sha256": record["current_sha256"],
    "actual_sha256": digest(ROOT / name),
    "unchanged_since_batch3": digest(ROOT / name) == record["current_sha256"],
} for name, record in prior.items()}
write_json("batch2_preservation.json", preservation)
assert all(x["unchanged_since_batch3"] for x in preservation.values())

# Apply the existing isolated batch patch to a fresh mirror of saved inputs.
tree = ast.parse((BATCH / "capture_patch.py").read_text())
files = next(ast.literal_eval(n.value) for n in tree.body
             if isinstance(n, ast.Assign) and any(
                 isinstance(t, ast.Name) and t.id == "FILES" for t in n.targets))
scratch = OUT / "patch_application"
if not scratch.exists():
    scratch.mkdir()
    for name, old in files.items():
        if old:
            target = scratch / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text((BATCH / old).read_text(encoding="utf-8-sig"),
                              encoding="utf-8", newline="\n")
    applied = subprocess.run(["git", "apply", str(BATCH / "batch3.patch")],
                             cwd=scratch, text=True, capture_output=True)
    write_json("patch_apply_process.json", {
        "exit_code": applied.returncode, "stdout": applied.stdout,
        "stderr": applied.stderr})
    assert applied.returncode == 0, applied.stderr
patch_audit = {}
for name in files:
    target = OUT / "REPORT_before.md" if name.endswith("/REPORT.md") else ROOT / name
    patch_audit[name] = ((scratch / name).read_text(encoding="utf-8-sig") ==
                        target.read_text(encoding="utf-8-sig"))
write_json("patch_application_verified.json", patch_audit)
assert all(patch_audit.values())

ac_before = (BATCH / "before/psse_xfmr_control.m").read_text(encoding="utf-8-sig")
ac_after = (ROOT / "matpower/lib/+mp/psse_xfmr_control.m").read_text(encoding="utf-8-sig")
unified_before = (BATCH / "lock_repaired_unified.m").read_text(encoding="utf-8-sig")
unified_after = (ROOT / "matpower/lib/+mp/psse_unified_control_update.m").read_text(encoding="utf-8-sig")
ac_expected = re.sub(
    r"function \[new_raw, new_tap\] = next_tap_state\(state, vm\).*?(?=function sig =)",
    "", ac_before, flags=re.S).replace(
        "[new_raw, new_tap] = next_tap_state(state, vm);",
        "[new_raw, new_tap] = mp.psse_xfmr_tap_decision(state, vm, ...\n"
        "    active_control_idx(state));")
unified_expected = re.sub(
    r"function \[new_raw, new_tap\] = next_xfmr_tap_state\(state, vm\).*?(?=function )",
    "", unified_before, flags=re.S).replace(
        "[new_raw, new_tap] = next_xfmr_tap_state(state, vm);",
        "[new_raw, new_tap] = mp.psse_xfmr_tap_decision(state, vm, ...\n"
        "    state.controllable & state.reg_bus_idx > 0);")
structural = {
    "ac_only_selector_extraction": ac_expected == ac_after,
    "unified_only_selector_extraction_after_lock_repair": unified_expected == unified_after,
    "switched_shunt_suffix_unchanged": unified_before.split(
        "function [mpc, state] = direct_swshunt_control", 1)[1] == unified_after.split(
        "function [mpc, state] = direct_swshunt_control", 1)[1],
}
write_json("structural_preservation.json", structural)
assert all(structural.values())

suites = []
for counts in sorted(OUT.glob("*/counts.json")):
    record = json.loads(counts.read_text())
    record["directory"] = counts.parent.name
    log = (counts.parent / "run.log").read_text(encoding="utf-8-sig")
    record["warning_lines"] = [line for line in log.splitlines()
                               if re.search(r"\bWarning:", line)]
    suites.append(record)
summary = {"suites": suites, "total_passed": sum(s["passed"] for s in suites),
           "total_failed": sum(s["failed"] for s in suites),
           "total_skipped": sum(s["skipped"] for s in suites),
           "exceptions": [s["exception"] for s in suites if s["exception"]]}
expected = {s["name"]: s for s in json.loads(
    (BATCH / "verification_summary.json").read_text())["suites"]}
summary["pending_suites"] = sorted(set(expected) - {s["name"] for s in suites})
summary["counts_match_previous_verified_runs"] = all(
    all(s[key] == expected[s["name"]][key]
        for key in ("planned", "executed", "passed", "failed", "skipped"))
    for s in suites)
write_json("verification_summary.json", summary)

beerten = json.loads((OUT / "t_ultc_beerten_batch3/evidence/beerten.json").read_text())
balances = {}
for suffix in (".ac_balance", ".cpf_ac_balance", ".converter_balance", ".dc_balance"):
    group = [c for c in beerten if c["id"].endswith(suffix)]
    values = [float(re.search(r"balance ([\d.eE+-]+) pu", c["detail"])[1]) for c in group]
    balances[suffix[1:]] = {"checks": len(group), "maximum_pu": max(values),
                            "tolerance_pu": 1e-8, "all_passed": all(c["passed"] for c in group)}
write_json("beerten_balance_summary.json", balances)

# The original batch patch remains immutable. This patch captures report updates.
report_before = (OUT / "REPORT_before.md").read_text(encoding="utf-8-sig")
report_after = (BATCH / "REPORT.md").read_text(encoding="utf-8-sig")
report_path = "outputs/algorithm_cleanup_batch3_20260910/REPORT.md"
report_patch = "".join(difflib.unified_diff(
    report_before.splitlines(True), report_after.splitlines(True),
    fromfile="a/" + report_path, tofile="b/" + report_path))
(OUT / "report_update.patch").write_text(report_patch, encoding="utf-8", newline="\n")
if "--finalize" in sys.argv:
    assert not summary["pending_suites"]
    assert summary["counts_match_previous_verified_runs"]
    assert not summary["exceptions"] and summary["total_failed"] == 0
    final_files = dict(files)
    final_files[str(Path(__file__).resolve().relative_to(ROOT)).replace("\\", "/")] = None
    final_patch, final_manifest = [], {}
    final_scratch = OUT / "final_patch_application"
    assert not final_scratch.exists(), "Final patch verification needs a fresh directory"
    final_scratch.mkdir()
    for name, old in final_files.items():
        before = (BATCH / old).read_text(encoding="utf-8-sig") if old else ""
        after = (ROOT / name).read_text(encoding="utf-8-sig")
        final_patch.append("".join(difflib.unified_diff(
            before.splitlines(True), after.splitlines(True),
            fromfile="a/" + name if old else "/dev/null", tofile="b/" + name)))
        final_manifest[name] = {"before_sha256": digest(BATCH / old) if old else None,
                                "after_sha256": digest(ROOT / name)}
        if old:
            target = final_scratch / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(before, encoding="utf-8", newline="\n")
    (OUT / "batch3.patch").write_text("".join(final_patch), encoding="utf-8", newline="\n")
    write_json("source_manifest.json", final_manifest)
    applied = subprocess.run(["git", "apply", str(OUT / "batch3.patch")],
                             cwd=final_scratch, text=True, capture_output=True)
    assert applied.returncode == 0, applied.stderr
    final_verified = {name: (final_scratch / name).read_text(encoding="utf-8-sig") ==
                      (ROOT / name).read_text(encoding="utf-8-sig") for name in final_files}
    write_json("final_patch_verified.json", final_verified)
    assert all(final_verified.values())
print(json.dumps({"source_hashes_match": True, "batch2_preserved": True,
                  "isolated_patch_verified": True, "suites": len(suites),
                  "passed": summary["total_passed"], "failed": summary["total_failed"],
                  "skipped": summary["total_skipped"]}))
