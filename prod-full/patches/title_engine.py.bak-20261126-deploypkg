"""Pure core of the OneDay activity-feed title engine (queue 193,
package 2.18.7; proposal briefs/activity-feed-rework-proposal.md
bar 2).

Bar 1 (queue 176) decided WHICH work appears on the identity
page's activity stream and grouped it into threads; the thread
headline still came from the rule derivations of queues 173/183.
This bar adds the model summariser the proposal specifies: when
a thread closes, its on-record material (the user's intent, the
step sequence, the outcome -- all already in the book, nothing
new is collected) is queued, and a cheap-tier model rewrites the
headline asynchronously. The exit never waits for the model: a
thread shelves immediately with its rule-derived headline and is
renamed in place when the summary lands.

This module is the pure half -- prompt assembly, output parsing
and the three-gate mechanical check, the per-close idempotency
fingerprint, and the summary queue's state machine. It performs
no IO and reads no clock except through the `now` arguments its
callers pass in, so hub_fields_selftest can drive every path
standalone. The gateway-bound half (material assembly from the
ledger/state.db, the /v1/runs submission, the write-back, the
worker thread) lives in oneday_seg_ledger.py, which imports this
module as _title_mod, exactly as it imports activity_feed.

Three gates for a model headline (user-ruled 2026-11-26 18:19):
no garbled text, real distinctiveness, and a reader can tell at
a glance WHO did WHAT to WHAT. The prompt writes the gates as
hard constraints with counter-examples; parse_summary_output
then enforces the mechanical subset (shape, length, no
instruction openings, no internal terms) before anything is
allowed into the book -- a failing output is a failed attempt,
never a stored headline.
"""

import hashlib
import re

# -- queue discipline (cost + failure) ------------------------------
# One summary per thread close: the queue key is the thread id
# plus the close fingerprint, so a re-assembly over the same
# close can never enqueue (and bill) twice. A failed summary is
# retried a bounded number of times per enqueue; once the budget
# is spent the entry rests as failed and the thread keeps its
# rule headline -- the failure is a queue state, not a blank.
MAX_ATTEMPTS = 3
# A rested (failed) entry may be requeued when the channel has
# had time to recover, a bounded number of times per close.
MAX_REQUEUES = 2
REQUEUE_COOLDOWN_SECONDS = 1800

INTENT_CAP = 300
STEP_LINES_CAP = 20

# Internal vocabulary that must never surface in a headline
# (proposal prompt rule 1). Latin terms match case-insensitively
# on word boundaries so real words containing them survive.
_FORBIDDEN_TERMS = ("batch", "ops", "run", "job", "slug",
                    "thread", "ledger", "title_human", "runid",
                    "sessionid")
_FORBIDDEN_RE = re.compile(
    r"\b(" + "|".join(_FORBIDDEN_TERMS) + r")\b",
    re.IGNORECASE)

# The proposal's prompt draft (bar 2 spec, wording may be tuned,
# the spec may not shrink), with the three gates spelled out as
# hard constraints and counter-examples appended per the build
# brief. {intent} / {steps} / {outcome} are the only slots.
PROMPT_TEMPLATE = """你是一个活动记录的标题员。下面给你一件已经干完的活的记录：用户的原始要求、执行过程的步骤清单、最终结果。请你为这件活写两行字，用于展示在用户的活动流水里。

要求：
1. 第一行是主标题：一句话说清这件活是干什么的，用「动词＋对象」的自然说法，像「检查服务器状态」「新建了登录凭据」「把周报发给团队」。不要用内部术语（batch、ops、run、job、slug 这类词一律不许出现），不要把用户的原话整句抄上来，不要以「你是……」的指令口吻开头。
2. 第二行是副题：一行交代实际做了什么、结果如何，只写记录里真实发生的事；记录里没有的细节不许编。失败了就如实写失败在哪一步。
3. 语言跟随用户原始要求的语言：中文要求写中文，英文要求写英文。
4. 主标题不超过 20 个汉字（英文不超过 8 个词），副题不超过 40 个汉字。
5. 只输出两行，第一行主标题、第二行副题，不要加任何解释、引号或标号。

三条硬约束（缺一不可）：
- 不许出现乱码、截断的半句话、编号或哈希串；
- 标题要有区分度：换一件别的活就不成立的说法才合格，万能句（如「处理了用户的请求」「完成了一项任务」）不合格；
- 一眼能看懂谁对什么做了什么：主语是助手、动作和对象都要具体。

反例（这些都不是合格的标题，不许仿照）：
- 「你是 OneDay 的点子生成器……」——这是内部指令原文，不是标题；
- 「run_46c0f7a1 会话处理」——编号不是人话；
- 「处理了用户的请求」——没有具体动作和对象，换哪件活都成立。

用户的原始要求：
{intent}

执行步骤：
{steps}

最终结果：
{outcome}
"""


def build_prompt(intent, step_lines, outcome) -> str:
    """Assemble the summariser prompt from on-record material.
    The intent is capped (proposal: 300 chars) and the step
    lines are capped at 20, so one summary stays near the
    ~1k-token budget the proposal costed."""
    intent = (intent or "").strip()[:INTENT_CAP] or "（无记录）"
    lines = [str(s).strip() for s in (step_lines or [])
             if str(s).strip()]
    steps = "\n".join(lines[:STEP_LINES_CAP]) or "（无步骤记录）"
    outcome = (outcome or "").strip() or "（无结果记录）"
    return PROMPT_TEMPLATE.format(
        intent=intent, steps=steps, outcome=outcome)


def _clean_line(text) -> str:
    line = (text or "").strip()
    # Strip one layer of wrapping quotes / list markers the model
    # was told not to add but sometimes does.
    line = line.strip("`").strip()
    for marker in ("- ", "* ", "1. ", "1、", "· "):
        if line.startswith(marker):
            line = line[len(marker):].strip()
            break
    if len(line) >= 2 and line[0] in "\"'“" and \
            line[-1] in "\"'”":
        line = line[1:-1].strip()
    return line


def parse_summary_output(raw):
    """(title, summary) from the model's raw output, or None.

    Accepts exactly the two-line shape the prompt demands
    (a surrounding code fence is tolerated). The mechanical
    three-gate check runs here: a headline that opens with an
    instruction, carries internal terms, is over-long, or reads
    like a fragment is rejected wholesale -- the caller counts
    the attempt as failed and the rule headline stays."""
    if not isinstance(raw, str):
        return None
    text = raw.strip()
    if text.startswith("```"):
        text = text.strip("`").strip()
    lines = [_clean_line(ln) for ln in text.splitlines()]
    lines = [ln for ln in lines if ln]
    if len(lines) < 2:
        return None
    title, summary = lines[0], lines[1]
    if not validate_title(title, summary):
        return None
    return title, summary


def validate_title(title, summary) -> bool:
    """The mechanical subset of the three gates."""
    if not isinstance(title, str) or not isinstance(summary, str):
        return False
    title = title.strip()
    summary = summary.strip()
    if not title or not summary:
        return False
    # Length: the spec is ~20 CJK chars for the title and ~40
    # for the summary; a small slack absorbs counting differences
    # (mixed CJK/Latin), anything beyond is a ramble, not a
    # headline.
    if len(title) > 30 or len(summary) > 90:
        return False
    # Gate 1 (no garble): no truncation markers, no leading
    # markdown/fragment punctuation, must contain real words.
    if "…" in title or "..." in title:
        return False
    if title[0] in "{[#*\"'`>|-":
        return False
    if not re.search(r"[一-鿿A-Za-z]{2,}", title):
        return False
    if "http://" in title or "https://" in title:
        return False
    # Gate 3 (who did what): never an instruction opening, never
    # the seed text of a bridge round.
    if title.startswith("你是"):
        return False
    # Internal terms never surface (gate: no internal jargon).
    if _FORBIDDEN_RE.search(title) or _FORBIDDEN_RE.search(summary):
        return False
    return True


def fingerprint(thread) -> str:
    """The close fingerprint: a deterministic hash of the
    thread's identity and its settled shape. The same close
    re-assembled yields the same fingerprint (no second bill);
    a thread that gains members or a new end time is a NEW
    close and may be summarised once more."""
    basis = "|".join([
        str(thread.get("threadId") or ""),
        ",".join(sorted(str(i) for i in
                        thread.get("itemIds") or [])),
        str(thread.get("endedAt") or ""),
        str(thread.get("status") or ""),
    ])
    return hashlib.sha1(basis.encode("utf-8")).hexdigest()[:16]


def queue_key(thread_id, fp) -> str:
    return f"{thread_id}@{fp}"


# -- the summary queue ----------------------------------------------
# State is a plain dict so the seg glue can persist it as one
# JSON file next to the ledger:
#   {"entries": {key: entry}, "counters": {...},
#    "engineStartedAt": ts}
# entry: {key, threadId, fingerprint, state, attempts, requeues,
#         enqueuedAt, lastAttemptAt, doneAt, lastError, runId}
# state: pending -> done | failed; failed -> pending (requeue,
# bounded). Counters are cumulative audit numbers: submitted
# (model runs submitted), succeeded, failedAttempts.

def new_state(now) -> dict:
    return {"entries": {},
            "counters": {"submitted": 0, "succeeded": 0,
                         "failedAttempts": 0},
            "engineStartedAt": now}


def enqueue(state, thread_id, fp, now) -> bool:
    """Idempotent: True only when a new entry was created. A key
    already pending or done is left exactly as it is."""
    key = queue_key(thread_id, fp)
    if key in state["entries"]:
        return False
    state["entries"][key] = {
        "key": key, "threadId": thread_id, "fingerprint": fp,
        "state": "pending", "attempts": 0, "requeues": 0,
        "enqueuedAt": now, "lastAttemptAt": None,
        "doneAt": None, "lastError": None, "runId": None}
    return True


def sweep_requeues(state, now) -> int:
    """Rested entries whose cooldown has passed get one more
    budget of attempts, up to MAX_REQUEUES per close. Returns
    how many entries moved back to pending."""
    moved = 0
    for entry in state["entries"].values():
        if entry["state"] != "failed":
            continue
        if entry["requeues"] >= MAX_REQUEUES:
            continue
        last = entry.get("lastAttemptAt") or 0
        if now - last >= REQUEUE_COOLDOWN_SECONDS:
            entry["state"] = "pending"
            entry["attempts"] = 0
            entry["requeues"] += 1
            entry["enqueuedAt"] = now
            moved += 1
    return moved


def pick_next(state):
    """The next pending entry, newest close first (the
    proposal's backfill order: recent work gets its real
    headline soonest). None when the queue is drained."""
    pending = [e for e in state["entries"].values()
               if e["state"] == "pending"]
    if not pending:
        return None
    pending.sort(key=lambda e: (-(e.get("enqueuedAt") or 0),
                                e["key"]))
    return pending[0]


def record_attempt(state, key, run_id, now) -> None:
    entry = state["entries"].get(key)
    if entry is None:
        return
    entry["attempts"] += 1
    entry["lastAttemptAt"] = now
    entry["runId"] = run_id
    state["counters"]["submitted"] += 1


def record_success(state, key, now) -> None:
    entry = state["entries"].get(key)
    if entry is None:
        return
    entry["state"] = "done"
    entry["doneAt"] = now
    entry["lastError"] = None
    state["counters"]["succeeded"] += 1


def record_failure(state, key, error, now) -> None:
    """One failed attempt. The entry rests as failed once its
    per-enqueue attempt budget is spent; before that it stays
    pending and the worker will retry it (the worker paces
    retries itself)."""
    entry = state["entries"].get(key)
    if entry is None:
        return
    entry["lastError"] = str(error)[:200]
    entry["lastAttemptAt"] = now
    state["counters"]["failedAttempts"] += 1
    if entry["attempts"] >= MAX_ATTEMPTS:
        entry["state"] = "failed"


def pending_count(state) -> int:
    """Threads still waiting for a model headline -- the
    monitoring face's 待补汇总计数 (pending plus rested)."""
    return sum(1 for e in state["entries"].values()
               if e["state"] in ("pending", "failed"))


def stats(state) -> dict:
    counts = {"pending": 0, "done": 0, "failed": 0}
    for e in state["entries"].values():
        counts[e["state"]] = counts.get(e["state"], 0) + 1
    out = dict(state["counters"])
    out.update(counts)
    out["awaiting"] = counts["pending"] + counts["failed"]
    return out
