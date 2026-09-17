"""Capture only batch 3 changes relative to its saved working-tree inputs."""
from pathlib import Path
import difflib
import hashlib
import json

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
FILES = {
    "matpower/lib/+mp/psse_xfmr_control.m": "before/psse_xfmr_control.m",
    "matpower/lib/+mp/psse_unified_control_update.m": "before/psse_unified_control_update.m",
    "matpower/lib/+mp/psse_xfmr_tap_decision.m": None,
    "matpower/lib/runcpf_vsc_mtdc.m": "before/runcpf_vsc_mtdc.m",
    "tests/t_ultc_acceptance_batch3.m": None,
    "tests/t_ultc_beerten_batch3.m": None,
    "docs/ULTC_DECISION_CONTRACT.md": None,
    "docs/CONTROL_ACCEPTANCE.md": "before/CONTROL_ACCEPTANCE.md",
    "tests/README.md": "before/README.md",
    "outputs/algorithm_cleanup_batch3_20260910/run_batch3_suite.m": None,
    "outputs/algorithm_cleanup_batch3_20260910/capture_patch.py": None,
    "outputs/algorithm_cleanup_batch3_20260910/REPORT.md": None,
}


def diff(name, before, after):
    return "".join(difflib.unified_diff(
        before.splitlines(True), after.splitlines(True),
        fromfile="a/" + name if before else "/dev/null", tofile="b/" + name))


patch = []
manifest = {}
for name, old in FILES.items():
    current = ROOT / name
    before = (OUT / old).read_text(encoding="utf-8-sig") if old else ""
    after = current.read_text(encoding="utf-8-sig")
    manifest[name] = {
        "before_sha256": hashlib.sha256((OUT / old).read_bytes()).hexdigest() if old else None,
        "after_sha256": hashlib.sha256(current.read_bytes()).hexdigest(),
        "before_lines": len(before.splitlines()), "after_lines": len(after.splitlines()),
    }
    patch.append(diff(name, before, after))
(OUT / "batch3.patch").write_text("".join(patch), encoding="utf-8", newline="\n")
(OUT / "source_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
name = "matpower/lib/+mp/psse_unified_control_update.m"
before = (OUT / FILES[name]).read_text(encoding="utf-8-sig")
repaired = (OUT / "lock_repaired_unified.m").read_text(encoding="utf-8-sig")
(OUT / "lockout_repair.patch").write_text(diff(name, before, repaired), encoding="utf-8", newline="\n")
name = "matpower/lib/runcpf_vsc_mtdc.m"
(OUT / "cpf_balance_repair.patch").write_text(
    diff(name, (OUT / FILES[name]).read_text(encoding="utf-8-sig"),
         (ROOT / name).read_text(encoding="utf-8-sig")), encoding="utf-8", newline="\n")
