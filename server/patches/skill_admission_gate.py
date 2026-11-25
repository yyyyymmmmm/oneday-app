#!/usr/bin/env python3
"""OneDay skill admission hard gate -- gateway/tools service module
(local patch, hermes-deploy DESIGN section 444).

Until section 439 the OneDay package enforced skill admission only at
the bookkeeping level: the oneday-memory skill procedure asks the
agent to run a skill's own verification and record a row in the
admission ledger (``memories/oneday/admission/skill_admission.jsonl``),
and ``oneday_memory.admission_audit()`` reconciles the skills on disk
against that ledger after the fact.  Nothing stopped a broken or
credential-carrying skill from landing on disk first -- admission was
an account, not a gate.

This module is the write-time hard gate the section-439 spec
registered as a blocker ("the hard gate needs a full-file patch of
the upstream skill_manage tool; landing point identified: the tools
layer").  The upstream write path funnels EVERY content write of the
skill_manage tool -- create / edit / patch / write_file, direct calls,
atomic batches, and approved write-gate replays alike -- through
``tools.skill_manager_tool._guarded_write``.  The package hook inserts
one call to :func:`admission_check` in ``_guarded_write`` after the
existing read guards and BEFORE ``atomic_write_text`` runs, so:

- the would-be result of the write is staged in a temp directory
  (current skill tree copied, the pending file applied) and the
  admission suite validates the RESULT, never the live tree;
- a rejection returns an error before any byte lands -- the on-disk
  skill is untouched by construction, and a patch that would break a
  healthy skill leaves the previous admitted version in place;
- every decision (admitted / rejected / exempted / gate error /
  gate disabled) is appended to the section-439 admission ledger in
  the ledger's own row format, with the machine-readable gate report
  under ``memories/oneday/state/skill_gate/`` as the evidence
  pointer -- so the section-439 audit picks gate decisions up with
  no format change;
- the gate FAILS CLOSED: any fault inside the validator (including
  the ledger being unwritable on a pass) refuses the write and
  leaves a trace.  A gate that cannot run must never wave a write
  through.  The deliberate escape hatches are both user-owned and
  ledgered: the kill switch and per-skill exemptions live in
  ``<HERMES_HOME>/skill_gate.json``, a file only the user edits.

Admission suite (deterministic, stdlib-only, no model calls):

- ``structure``   -- SKILL.md present; per-file and total size caps
  aligned with the upstream tool's own limits.
- ``frontmatter`` -- frontmatter parses; ``name`` present and equal
  to the skill directory name; ``description`` present, non-empty,
  within the upstream 1024-char cap; non-empty body.
- ``syntax``      -- every ``.py`` file compiles (parsed, never
  executed); every ``.json`` file parses; ``.sh`` files pass
  ``bash -n`` when bash is available.
- ``references``  -- paths declared in frontmatter (tools/scripts/
  files/references/templates/assets lists) and relative paths
  referenced from the SKILL.md body (markdown links, backticked
  support-file paths) exist in the staged tree; declared tool names
  are checked against a tool registry when one is provided.  One
  deliberate leniency: on ``create`` the tree is definitionally
  incomplete (the upstream flow writes SKILL.md first and adds
  supporting files with follow-up write_file calls), so missing
  referenced paths are recorded as report notes instead of
  failures; every later write (edit / patch / write_file) is
  checked strictly, so a tree can never be left dangling by a
  gated write.
- ``credentials`` -- no credential literals anywhere in the tree:
  private-key blocks, known token prefixes, bearer tokens, and
  secret-named assignments with literal values (placeholders and
  environment lookups are fine).  Reports carry rule id + file +
  line only -- never the matched text.

Relationship to upstream machinery: the write-approval gate
(``tools.write_approval``) is an approval-staging layer (human
decides); this gate is an admission layer (deterministic suite
decides) and runs on BOTH the direct-allow path and the approved
replay path, because both end in ``_guarded_write``.  The upstream
opt-in post-write security scan (``tools.skills_guard``, config
``skills.guard_agent_created``, default off) is complementary: this
gate runs pre-write and always on for skill_manage writes.
Deletes and remove_file do not pass through ``_guarded_write`` and
are out of scope -- removing a skill is not an admission event.

The module is import-safe with no Hermes imports at module level
(paths resolve at call time from the environment), and it doubles as
a CLI for drills and verify probes:
``python3 skill_admission_gate.py check <skill_dir> [--name N]``.
"""

import json
import logging
import os
import re
import shutil
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path

logger = logging.getLogger("tools.skill_admission_gate")

# Aligned with tools/skill_manager_tool.py (upstream v0.23.0).
MAX_SKILL_CONTENT_CHARS = 100_000
MAX_SKILL_FILE_BYTES = 1_048_576
MAX_DESCRIPTION_LENGTH = 1024
MAX_STAGED_TOTAL_BYTES = 8 * 1_048_576

_TEXT_SUFFIXES = {
    ".md", ".py", ".sh", ".bash", ".json", ".yaml", ".yml", ".toml",
    ".txt", ".cfg", ".ini", ".js", ".ts", ".rb", ".pl", ".ps1", ".bat",
}
_PATHISH_KEYS = ("scripts", "files", "references", "templates", "assets")
_FILE_EXTS = (".md", ".py", ".sh", ".json", ".yaml", ".yml", ".toml",
              ".txt", ".js", ".ts")


# ------------------------------------------------------------------ paths

def _hermes_home() -> Path:
    return Path(os.environ.get("HERMES_HOME") or "/opt/data")


def _memory_root() -> Path:
    override = os.environ.get("ONEDAY_MEMORY_ROOT")
    if override:
        return Path(override)
    return _hermes_home() / "memories"


def _ledger_path() -> Path:
    return _memory_root() / "oneday" / "admission" / "skill_admission.jsonl"


def _reports_dir() -> Path:
    return _memory_root() / "oneday" / "state" / "skill_gate"


def _config_path() -> Path:
    override = os.environ.get("SKILL_GATE_CONFIG")
    if override:
        return Path(override)
    return _hermes_home() / "skill_gate.json"


def _now_iso() -> str:
    return datetime.now(tz=timezone.utc).isoformat().replace("+00:00", "Z")


# ------------------------------------------------------------------ config

def _load_config() -> dict:
    """User-owned gate config; absent file = defaults (gate on, no
    exemptions, no tool registry).  A malformed file is a gate fault
    (fail-closed): the caller treats the exception as a refusal."""
    path = _config_path()
    if not path.is_file():
        return {"enabled": True, "exemptions": {}, "known_tools": None}
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("skill_gate config must be a JSON object")
    exemptions = data.get("exemptions") or {}
    if not isinstance(exemptions, dict):
        raise ValueError("skill_gate config exemptions must be an object")
    known = data.get("known_tools")
    if known is None:
        registry = _hermes_home() / "skill_gate_tools.json"
        if registry.is_file():
            reg = json.loads(registry.read_text(encoding="utf-8"))
            tools = reg.get("tools") if isinstance(reg, dict) else None
            if isinstance(tools, list):
                known = [str(t) for t in tools]
    return {
        "enabled": bool(data.get("enabled", True)),
        "exemptions": exemptions,
        "known_tools": known,
    }


def _exemption_for(cfg: dict, name: str):
    """A per-skill exemption counts ONLY when the user personally
    approved it (``approved_by: "user"`` in the user-owned config).
    Anything else is ignored -- an agent cannot exempt itself."""
    bare = Path(name).name
    for key in (name, bare):
        entry = (cfg.get("exemptions") or {}).get(key)
        if isinstance(entry, dict) and entry.get("approved_by") == "user":
            return entry
    return None


# ------------------------------------------------------------------ ledger

def _append_ledger(row: dict) -> None:
    path = _ledger_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "a", encoding="utf-8") as f:
        f.write(json.dumps(row, ensure_ascii=False) + "\n")
        f.flush()
        os.fsync(f.fileno())


def _ledger_row(name: str, actor: str, action: str, status: str,
                evidence: str, failures=None) -> dict:
    now = _now_iso()
    row = {
        "skill": Path(name).name,
        "created_by": actor,
        "action": action,
        "verify": {
            "method": "skill_gate:pre_write_suite",
            "evidence": evidence,
            "at": now,
        },
        "status": status,
        "first": now,
    }
    if failures:
        row["failures"] = list(failures)
    return row


def _write_report(report: dict) -> str:
    """Persist the machine-readable gate report; returns the evidence
    pointer (path relative to the memory root, section-439 style)."""
    reports = _reports_dir()
    reports.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(tz=timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    fname = "%s-%s-%s.json" % (stamp, report.get("skill") or "skill",
                               report.get("action") or "write")
    path = reports / fname
    tmp = path.with_suffix(".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=1)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)
    try:
        return str(path.relative_to(_memory_root()))
    except ValueError:
        return str(path)


# ------------------------------------------------------- frontmatter parse

def _parse_frontmatter(content: str):
    """Return (frontmatter dict | None, body str, error str | None).

    Uses a real YAML parser when importable (hermes_yaml in the
    container, PyYAML elsewhere) and falls back to a deterministic
    subset parser covering the flat key/value + simple list shape
    skill frontmatter uses in practice.
    """
    text = (content or "").lstrip("\ufeff")
    if not text.startswith("---"):
        return None, "", "SKILL.md does not start with YAML frontmatter (---)."
    end = re.search(r"\n---\s*\n", text[3:])
    if not end:
        return None, "", "SKILL.md frontmatter is not closed (no second ---)."
    raw = text[3:end.start() + 3]
    body = text[end.end() + 3:]
    parsed = None
    yaml_mod = None
    try:
        import hermes_yaml as yaml_mod  # vendored in the Hermes tree
    except Exception:
        try:
            import yaml as yaml_mod
        except Exception:
            yaml_mod = None
    if yaml_mod is not None:
        try:
            parsed = yaml_mod.safe_load(raw)
        except Exception as e:
            return None, body, "YAML frontmatter parse error: %s" % e
    else:
        parsed = _parse_frontmatter_subset(raw)
    if not isinstance(parsed, dict):
        return None, body, "Frontmatter must be a YAML mapping (key: value pairs)."
    return parsed, body, None


def _parse_frontmatter_subset(raw: str) -> dict:
    out = {}
    current_key = None
    for line in raw.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        item = re.match(r"^\s+-\s+(.*)$", line)
        if item and current_key:
            value = item.group(1).strip().strip("'\"")
            prev = out.get(current_key)
            if isinstance(prev, list):
                prev.append(value)
            elif prev in (None, ""):
                out[current_key] = [value]
            continue
        pair = re.match(r"^([A-Za-z0-9_-]+):\s*(.*)$", line)
        if pair:
            current_key = pair.group(1)
            value = pair.group(2).strip()
            if value.startswith("[") and value.endswith("]"):
                out[current_key] = [v.strip().strip("'\"")
                                    for v in value[1:-1].split(",") if v.strip()]
            else:
                out[current_key] = value.strip("'\"")
    return out


# ------------------------------------------------------------------ checks

def _tree_files(root: Path) -> list:
    return sorted(p for p in root.rglob("*") if p.is_file())


def _read_text(path: Path):
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except Exception:
        return None


def _check_structure(root: Path) -> list:
    failures = []
    if not (root / "SKILL.md").is_file():
        failures.append("SKILL.md missing at the skill root")
        return failures
    total = 0
    for path in _tree_files(root):
        try:
            size = path.stat().st_size
        except OSError as e:
            failures.append("unreadable file %s: %s" % (path.name, e))
            continue
        total += size
        if size > MAX_SKILL_FILE_BYTES:
            failures.append("%s is %d bytes (per-file limit %d)"
                            % (path.relative_to(root), size,
                               MAX_SKILL_FILE_BYTES))
    if total > MAX_STAGED_TOTAL_BYTES:
        failures.append("skill tree is %d bytes (total limit %d)"
                        % (total, MAX_STAGED_TOTAL_BYTES))
    skill_md = _read_text(root / "SKILL.md") or ""
    if len(skill_md) > MAX_SKILL_CONTENT_CHARS:
        failures.append("SKILL.md is %d chars (limit %d)"
                        % (len(skill_md), MAX_SKILL_CONTENT_CHARS))
    return failures


def _check_frontmatter(root: Path, skill_name: str, content: str) -> list:
    failures = []
    fm, body, err = _parse_frontmatter(content)
    if err:
        return [err]
    name = fm.get("name")
    if not name or not str(name).strip():
        failures.append("frontmatter must include a 'name' field")
    elif str(name).strip() != skill_name:
        failures.append("frontmatter name '%s' does not match the skill "
                        "directory name '%s'" % (name, skill_name))
    desc = fm.get("description")
    if desc is None or not str(desc).strip():
        failures.append("frontmatter must include a non-empty 'description' field")
    elif len(str(desc)) > MAX_DESCRIPTION_LENGTH:
        failures.append("description is %d chars (limit %d)"
                        % (len(str(desc)), MAX_DESCRIPTION_LENGTH))
    if not body.strip():
        failures.append("SKILL.md must have content after the frontmatter")
    return failures


def _check_syntax(root: Path) -> list:
    failures = []
    skipped = []
    for path in _tree_files(root):
        rel = str(path.relative_to(root))
        suffix = path.suffix.lower()
        text = _read_text(path)
        if text is None:
            failures.append("%s: unreadable" % rel)
            continue
        if suffix == ".py":
            try:
                compile(text, rel, "exec")
            except SyntaxError as e:
                failures.append("%s: Python syntax error (line %s: %s)"
                                % (rel, e.lineno, e.msg))
        elif suffix == ".json":
            try:
                json.loads(text)
            except Exception as e:
                failures.append("%s: JSON parse error (%s)" % (rel, e))
        elif suffix in (".sh", ".bash"):
            bash = shutil.which("bash")
            if bash is None:
                skipped.append(rel)
                continue
            proc = subprocess.run([bash, "-n", str(path)],
                                  capture_output=True, text=True, timeout=15)
            if proc.returncode != 0:
                first = (proc.stderr or "").strip().splitlines()
                failures.append("%s: shell syntax error (%s)"
                                % (rel, first[0] if first else "bash -n failed"))
    if skipped:
        failures.append("shell syntax unchecked (no bash available): %s"
                        % ", ".join(skipped))
    return failures


def _declared_values(fm: dict, key: str) -> list:
    value = fm.get(key)
    if value is None:
        return []
    if isinstance(value, list):
        return [str(v) for v in value]
    return [str(value)]


def _check_references(root: Path, skill_md_text: str, fm: dict,
                      known_tools, initial: bool = False) -> list:
    failures = []
    notes = []

    def missing(msg):
        # On create the tree is incomplete by design (supporting
        # files arrive via follow-up write_file calls): record, do
        # not block.  Every later write is held to the strict rule.
        (notes if initial else failures).append(msg)

    # (a) frontmatter-declared support paths must exist in the tree.
    for key in _PATHISH_KEYS:
        for entry in _declared_values(fm, key):
            entry = entry.strip()
            if not entry:
                continue
            if "/" in entry or entry.lower().endswith(_FILE_EXTS):
                if not (root / entry).exists():
                    missing("frontmatter %s declares '%s', which is "
                            "not in the skill tree" % (key, entry))
    # (b) declared tool names: checked only when a registry is known;
    #     without one the check is recorded as skipped, never invented.
    tools = _declared_values(fm, "tools")
    if tools:
        if known_tools is None:
            notes.append("tool registry unavailable; %d declared tool "
                         "name(s) unchecked" % len(tools))
        else:
            known = set(known_tools)
            for tool in tools:
                if tool.strip() and tool.strip() not in known:
                    failures.append("frontmatter declares tool '%s', which "
                                    "is not in the tool registry" % tool)
    # (c) paths referenced from the SKILL.md body must exist.
    referenced = set()
    for match in re.finditer(r"\]\(([^)\s]+)\)", skill_md_text):
        target = match.group(1).split("#")[0].strip()
        if target and not target.startswith(("http://", "https://", "/",
                                             "mailto:", "#")):
            referenced.add(target)
    for match in re.finditer(r"`((?:references|templates|scripts|assets)"
                             r"/[^`\s]+)`", skill_md_text):
        referenced.add(match.group(1))
    for target in sorted(referenced):
        if not (root / target).exists():
            missing("SKILL.md references '%s', which is not in "
                    "the skill tree" % target)
    return failures, notes


_CREDENTIAL_RULES = [
    ("private_key_block",
     re.compile(r"-----BEGIN (?:[A-Z0-9 ]+ )?PRIVATE KEY-----")),
    ("token_prefix_sk", re.compile(r"\bsk-(?:proj-)?[A-Za-z0-9_-]{16,}")),
    ("token_prefix_github", re.compile(r"\b(?:ghp|gho)_[A-Za-z0-9]{30,}"
                                       r"|\bgithub_pat_[A-Za-z0-9_]{30,}")),
    ("token_prefix_aws", re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    ("token_prefix_slack", re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{10,}")),
    ("token_prefix_google", re.compile(r"\bAIza[0-9A-Za-z_-]{30,}")),
    ("token_prefix_gitlab", re.compile(r"\bglpat-[A-Za-z0-9_-]{16,}")),
    ("bearer_token", re.compile(r"\bBearer\s+[A-Za-z0-9._~+/-]{16,}")),
]
_SECRET_ASSIGN_RE = re.compile(
    r"(?i)\b(api[_-]?key|secret(?:[_-]?key)?|password|passwd|"
    r"access[_-]?token|auth[_-]?token|private[_-]?key|client[_-]?secret)"
    r"\b\s*[:=]\s*[\"']([^\"']{8,})[\"']")
_PLACEHOLDER_RE = re.compile(
    r"(?i)^(x{3,}|\*+|your[-_ ].*|example.*|placeholder.*|changeme|"
    r"todo.*|none|null|test.*|dummy.*|sample.*|<.*>|\$\{.*\}|"
    r".*\.example|.*os\.environ.*|.*getenv.*)$")


def _check_credentials(root: Path) -> list:
    """Rule id + file + line only -- the matched text is a secret and
    is never copied into the report or the ledger."""
    failures = []
    for path in _tree_files(root):
        if path.suffix.lower() not in _TEXT_SUFFIXES:
            continue
        text = _read_text(path)
        if text is None:
            continue
        rel = str(path.relative_to(root))
        for lineno, line in enumerate(text.splitlines(), start=1):
            for rule_id, pattern in _CREDENTIAL_RULES:
                if pattern.search(line):
                    failures.append("%s:%d matches credential rule %s"
                                    % (rel, lineno, rule_id))
            for match in _SECRET_ASSIGN_RE.finditer(line):
                value = match.group(2).strip()
                if _PLACEHOLDER_RE.match(value):
                    continue
                failures.append("%s:%d assigns a literal value to '%s' "
                                "(credential rule secret_assignment)"
                                % (rel, lineno, match.group(1)))
    return failures


def validate_tree(root: Path, skill_name: str, known_tools=None,
                  initial: bool = False) -> dict:
    """Run the full admission suite against one staged skill tree."""
    root = Path(root)
    skill_md_path = root / "SKILL.md"
    skill_md_text = _read_text(skill_md_path) or ""
    fm, _body, _err = _parse_frontmatter(skill_md_text)
    checks = {}

    def run(check_id, fn):
        try:
            outcome = fn()
        except Exception as e:  # a broken check is a gate fault, not a pass
            raise RuntimeError("check %s failed internally: %s"
                               % (check_id, e)) from e
        if isinstance(outcome, tuple):
            failures, notes = outcome
        else:
            failures, notes = outcome, []
        checks[check_id] = {"ok": not failures, "failures": failures,
                            "notes": notes}
        return failures

    all_failures = []
    all_failures += run("structure",
                        lambda: _check_structure(root))
    all_failures += run("frontmatter",
                        lambda: _check_frontmatter(root, skill_name,
                                                   skill_md_text))
    all_failures += run("syntax", lambda: _check_syntax(root))
    all_failures += run("references",
                        lambda: _check_references(root, skill_md_text,
                                                  fm or {}, known_tools,
                                                  initial=initial))
    all_failures += run("credentials", lambda: _check_credentials(root))
    return {
        "object": "skill_admission_gate.report",
        "skill": skill_name,
        "at": _now_iso(),
        "ok": not all_failures,
        "checks": checks,
        "failures": [cid for cid, c in checks.items() if not c["ok"]],
    }


# ------------------------------------------------------------------ staging

def _stage_result(skill_dir: Path, target: Path, content: str) -> Path:
    """Copy the current skill tree into a temp staging area and apply
    the pending write there.  Returns the staging root (caller cleans
    up).  The live tree is only ever read."""
    if skill_dir is not None:
        try:
            rel = Path(target).relative_to(skill_dir)
        except ValueError:
            raise ValueError("write target %s is outside the skill dir %s"
                             % (target, skill_dir))
    else:
        rel = Path(Path(target).name)
    tmp = Path(tempfile.mkdtemp(prefix="skillgate-"))
    staged = tmp / "skill"
    if skill_dir is not None and Path(skill_dir).is_dir():
        shutil.copytree(skill_dir, staged)
    else:
        staged.mkdir(parents=True)
    dest = staged / rel
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(content, encoding="utf-8")
    return tmp


# ------------------------------------------------------------------ the gate

def admission_check(name: str, skill_dir, target, action: str,
                    content: str, *, actor: str = "agent",
                    known_tools=None) -> str | None:
    """Admission decision for one pending skill write.

    Mirrors the upstream validator contract: ``None`` allows the
    write, a string is the error the tool call must fail with.
    FAIL-CLOSED: any internal fault -- including the ledger being
    unwritable on an otherwise clean pass -- returns a refusal.
    """
    skill_dir = Path(skill_dir) if skill_dir is not None else None
    target = Path(target)
    tmp = None
    try:
        cfg = _load_config()
        if not cfg.get("enabled", True):
            _append_ledger(_ledger_row(name, actor, action,
                                       "gate_disabled", ""))
            return None
        exemption = _exemption_for(cfg, name)
        if exemption is not None:
            _append_ledger(_ledger_row(name, actor, action, "exempted",
                                       "skill_gate.json#exemptions/%s"
                                       % Path(name).name))
            logger.info("skill gate: write to '%s' exempted by user "
                        "approval in skill_gate.json", name)
            return None
        tmp = _stage_result(skill_dir, target, content)
        staged = tmp / "skill"
        report = validate_tree(
            staged, Path(name).name,
            known_tools=known_tools if known_tools is not None
            else cfg.get("known_tools"),
            initial=(action == "create"))
        report["action"] = action
        report["actor"] = actor
        evidence = _write_report(report)
        if report["ok"]:
            _append_ledger(_ledger_row(name, actor, action, "admitted",
                                       evidence))
            return None
        _append_ledger(_ledger_row(name, actor, action, "rejected",
                                   evidence, failures=report["failures"]))
        detail = "; ".join(
            "%s: %s" % (cid, report["checks"][cid]["failures"][0])
            for cid in report["failures"])
        return ("Skill admission gate rejected this %s of skill '%s' "
                "(%s). The on-disk skill was NOT modified. Fix the "
                "skill and retry; full report: %s"
                % (action, name, detail, evidence))
    except Exception as e:
        logger.exception("skill gate: fault during %s of '%s'", action, name)
        try:
            _append_ledger(_ledger_row(name, actor, action, "gate_error",
                                       ""))
        except Exception:
            logger.exception("skill gate: ledger append failed too")
        return ("Skill admission gate could not complete (%s: %s); the "
                "write is refused (fail-closed). The on-disk skill was "
                "NOT modified."
                % (type(e).__name__, e))
    finally:
        if tmp is not None:
            shutil.rmtree(tmp, ignore_errors=True)


# ------------------------------------------------------------------ CLI

def _main(argv=None) -> int:
    import argparse

    parser = argparse.ArgumentParser(prog="skill_admission_gate")
    sub = parser.add_subparsers(dest="cmd", required=True)
    p_check = sub.add_parser("check")
    p_check.add_argument("skill_dir")
    p_check.add_argument("--name", default=None)
    args = parser.parse_args(argv)
    if args.cmd == "check":
        skill_dir = Path(args.skill_dir)
        report = validate_tree(skill_dir,
                               args.name or skill_dir.name)
        print(json.dumps(report, ensure_ascii=False, indent=1))
        return 0 if report["ok"] else 1
    return 2


if __name__ == "__main__":
    raise SystemExit(_main())
