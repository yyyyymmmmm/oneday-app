"""Pure classification + thread assembly for the OneDay activity
feed (queue 176, package 2.18.6; proposal
briefs/activity-feed-rework-proposal.md, positioning
briefs/identity-feed-positioning.md).

The identity page's stream is the assistant's ACTIVITY: one thread
per piece of work the assistant did FOR the user. The work ledger
stays the full audit book -- every item is still recorded there.
This module decides, deterministically and from the item's own
fields alone, which items the activity exit may carry, and groups
the survivors into threads.

Inclusion rule (the positioning contract): an item enters the
feed only when it traces to a user intent source -- a user
session, a user decision, a user-built schedule, a user goal.
Anything that cannot be traced stays in the book (audit faces
still read it) and is stamped ``activityExcluded`` + a reason
code by the collector-cadence pass in oneday_seg_ledger:

- ``system_round``: a platform generation round's own record
  (bridge-self job items; stateless runs the bridge submitted
  for its rounds, whose seed text is the round's instruction).
- ``no_user_intent``: no user intent source is traceable from
  the item's fields (stateless API runs with no user session
  anchor; unknown kinds).
- ``monitor``: monitor self-check change records -- the platform
  watching itself, not work done for the user.
- ``definition``: scheduled-task DEFINITIONS never enter the
  ledger (they live on the /api/jobs face), so no ledger item
  carries this code today; it is reserved so the code table
  matches the proposal's one-to-one.

Threads: one thread per piece of work, four prototypes with
deterministic identity keys (re-assembly over the same items
always yields the same keys -- grouping is a pure function of
the items, so repeated collector passes cannot duplicate
threads):

- run      -> ``thread:run:<runId>``
- approval -> ``thread:appr:<anchor>`` (the batch's source
  session/run anchor when the item carries one; a lone decision
  with no anchor is its own thread, keyed by its decision id)
- kanban   -> ``thread:kanban:<taskId>``
- device   -> ``thread:dev:<callId>`` (a device call carries no
  session id in its audit line; it reaches the book only through
  the agent's tool channel in a user context, so it stands as
  its own single-item thread)

Scheduled-task executions would key as
``thread:job:<jobId>:<fireTs>``; the ledger books no such items
today (the bridge books only its own rounds as kind=job, and
those are platform rounds -- excluded above), so the prototype
exists in the key table but has no live instances yet.
"""

import base64
import json

REASON_SYSTEM_ROUND = "system_round"
REASON_NO_USER_INTENT = "no_user_intent"
REASON_DEFINITION = "definition"
REASON_MONITOR = "monitor"

REASONS = (REASON_SYSTEM_ROUND, REASON_NO_USER_INTENT,
           REASON_DEFINITION, REASON_MONITOR)

ACTIVE_STATUSES = ("queued", "running", "blocked_approval",
                   "stale")

# The bridge rounds brief the model with a role assignment --
# their seed text opens by naming the role ("你是 OneDay 的…",
# "你是一个调研员…") -- and the round families name themselves
# in their first line. These needles only ever REFINE the reason
# code of a stateless run that is already excluded; they never
# exclude a user-session item on their own.
_ROUND_HEAD_NEEDLES = (
    "口味笔记整理者", "动态报社宪法", "动态社交取材", "动态取材",
    "点子生成器", "会话摘要器", "简报整理者", "动态作者",
    "派题桌", "质检员", "改写员",
    "feed_reconcile", "feed_constitution", "feed_social_material",
    "feed_material", "ideas_gen",
)


def is_instruction_head(title) -> bool:
    """True when a run item's seed text is a round instruction:
    a role-assignment opening or a known round-family name."""
    text = title if isinstance(title, str) else ""
    text = text.strip()
    if not text:
        return False
    if text.startswith("你是"):
        return True
    return any(n in text for n in _ROUND_HEAD_NEEDLES)


def classify_item(item, skip_sessions=()) -> tuple:
    """(excluded, reason, prototype) for one ledger item.

    Pure and deterministic: the verdict depends only on the
    item's own fields (and the skip-session set the bridge is
    configured with), so the marking pass, the list exit and the
    threads exit can never disagree."""
    if not isinstance(item, dict):
        return True, REASON_NO_USER_INTENT, None
    kind = item.get("kind")
    if kind == "job":
        # The bridge books ONLY its own system rounds as job
        # items (morning/ideas/briefing). A scheduled task's
        # definition is not a ledger item at all (see the module
        # docstring on the reserved ``definition`` code).
        return True, REASON_SYSTEM_ROUND, None
    if kind == "monitor":
        return True, REASON_MONITOR, None
    if kind == "run":
        sid = item.get("sessionId")
        if not isinstance(sid, str) or not sid:
            # No session anchor at all: nothing traces this run
            # to a user. (Live book: every run item carries one.)
            return True, REASON_NO_USER_INTENT, None
        if sid in skip_sessions:
            return True, REASON_SYSTEM_ROUND, None
        if sid.startswith("run_"):
            # A stateless gateway run (submitted via /v1/runs):
            # the bridge's rounds ride this channel, and no user
            # session anchor exists to trace intent from. The
            # instruction-headed ones are recognisably rounds;
            # the rest are untraceable either way.
            if is_instruction_head(item.get("title")):
                return True, REASON_SYSTEM_ROUND, None
            return True, REASON_NO_USER_INTENT, None
        return False, None, "run"
    if kind == "approval":
        # A decision exists only because the user was asked and
        # answered (or a rule they set fired -- via_rule items
        # still record the user's own standing instruction).
        return False, None, "approval"
    if kind == "device":
        # Device items are born from the device audit log's
        # tool-call lines (sync:* bookkeeping never becomes an
        # item -- the collector skips it at ingestion). A tool
        # call reaches the device only through the agent acting
        # in a user context (MCP channel / permission resume).
        return False, None, "device"
    if kind == "kanban":
        # A kanban item is a unit of goal work the assistant
        # carried; the board's own bookkeeping never enters the
        # ledger as an item.
        return False, None, "kanban"
    # Unknown kind: the burden of proof is on inclusion.
    return True, REASON_NO_USER_INTENT, None


def thread_key(item, prototype) -> str:
    """The deterministic identity key for an included item."""
    iid = str(item.get("id") or "")
    link = item.get("link") or {}
    if prototype == "run":
        rid = item.get("runId") or iid[len("run:"):] \
            if iid.startswith("run:") else (item.get("runId")
                                            or iid)
        return f"thread:run:{rid}"
    if prototype == "approval":
        anchor = item.get("sessionId") or item.get("runId")
        if anchor:
            return f"thread:appr:{anchor}"
        pid = link.get("targetId") or (
            iid[len("appr:"):] if iid.startswith("appr:") else iid)
        return f"thread:appr:{pid}"
    if prototype == "kanban":
        tid = link.get("targetId") or (
            iid[len("task:"):] if iid.startswith("task:") else iid)
        return f"thread:kanban:{tid}"
    if prototype == "device":
        cid = iid[len("dev:"):] if iid.startswith("dev:") else iid
        return f"thread:dev:{cid}"
    return f"thread:item:{iid}"


def _member_sort(item):
    return (item.get("startedAt") or 0, str(item.get("id") or ""))


def assemble_threads(items, skip_sessions=()) -> list:
    """Group included items into threads. Pure: same items in,
    same threads out (identity keys are a function of the items),
    so repeated assembly is idempotent by construction.

    Ordering: in-progress threads first (a thread is in progress
    when any member is in an active status or has no endedAt),
    then by end time descending; threadId breaks ties so the
    order is total and pagination is stable."""
    groups = {}
    for item in items or []:
        excluded, _reason, proto = classify_item(item,
                                                 skip_sessions)
        if excluded:
            continue
        groups.setdefault(thread_key(item, proto),
                          []).append(item)
    threads = []
    for key, members in groups.items():
        members = sorted(members, key=_member_sort)
        proto = classify_item(members[0], skip_sessions)[2]
        started = min((m.get("startedAt") or 0) for m in members)
        in_progress = any(
            m.get("status") in ACTIVE_STATUSES
            or not m.get("endedAt") for m in members)
        ended = None if in_progress else max(
            (m.get("endedAt") or 0) for m in members)
        # Representative member: the one that ended last (or
        # started last while in progress) -- its headline and
        # status speak for the thread. Prefer a member carrying
        # a human headline when picking the title.
        rep = max(members,
                  key=lambda m: (m.get("endedAt")
                                 or m.get("startedAt") or 0,
                                 str(m.get("id") or "")))
        titled = [m for m in members
                  if str(m.get("title_human") or "").strip()]
        # A model-summarised headline (queue 193: titleHumanSource
        # == "model"; queue 200: "model_backfill" for headlines
        # bar 3's stock pass wrote) outranks every rule-derived
        # one, whichever member carries it -- the engine writes
        # onto one member and the thread speaks with that member's
        # headline and summary. A live close's own summary ranks
        # above a backfilled one. Among equals the latest-ending
        # member wins, exactly as before.
        title_rep = max(
            titled, key=lambda m: (
                2 if m.get("titleHumanSource") == "model"
                else 1 if m.get("titleHumanSource")
                == "model_backfill" else 0,
                m.get("endedAt") or m.get("startedAt") or 0,
                str(m.get("id") or ""))) \
            if titled else rep
        counts = {}
        for m in members:
            for k, v in (m.get("counts") or {}).items():
                if isinstance(v, (int, float)):
                    counts[k] = (counts.get(k) or 0) + v
        threads.append({
            "threadId": key,
            "prototype": proto,
            "title": title_rep.get("title_human")
            or title_rep.get("title") or "",
            "title_human": title_rep.get("title_human"),
            # Provenance of the headline the thread speaks with:
            # "model" (queue 193 engine, at the close itself),
            # "model_backfill" (queue 200 stock pass), "rule_
            # fallback" (the 173/183 derivations), or "raw"
            # (only the seed title exists). Additive field --
            # the client's render precedence (title_human
            # first) is unchanged.
            "titleSource": (
                "model" if title_rep.get("titleHumanSource")
                == "model"
                else "model_backfill" if title_rep.get(
                    "titleHumanSource") == "model_backfill"
                else "rule_fallback" if title_rep.get("title_human")
                else "raw"),
            "summary": title_rep.get("summary")
            if title_rep.get("titleHumanSource")
            in ("model", "model_backfill")
            else rep.get("summary"),
            "status": rep.get("status"),
            "inProgress": in_progress,
            "scheduled": proto == "job",
            "startedAt": started,
            "endedAt": ended,
            "itemIds": [m.get("id") for m in members],
            "itemCount": len(members),
            "counts": counts,
            "link": rep.get("link"),
        })
    threads.sort(key=lambda t: (
        0 if t["inProgress"] else 1,
        -((t["endedAt"] if t["endedAt"] is not None
           else t["startedAt"]) or 0),
        t["threadId"]))
    return threads


def _encode_cursor(thread) -> str:
    raw = json.dumps(
        [1 if thread["inProgress"] else 0,
         (thread["endedAt"] if thread["endedAt"] is not None
          else thread["startedAt"]) or 0,
         thread["threadId"]],
        ensure_ascii=False).encode("utf-8")
    return base64.urlsafe_b64encode(raw).decode("ascii")


def _decode_cursor(cursor):
    try:
        raw = base64.urlsafe_b64decode(
            str(cursor).encode("ascii"))
        pin, ts, tid = json.loads(raw.decode("utf-8"))
        return (0 if pin else 1, -(ts or 0), str(tid))
    except Exception:
        return None


def paginate_threads(threads, cursor=None, limit=50) -> tuple:
    """Keyset pagination over assemble_threads' total order.
    Returns (page, next_cursor); next_cursor is None at the end.
    An undecodable cursor restarts from the top rather than
    failing the whole feed."""
    try:
        limit = int(limit)
    except (TypeError, ValueError):
        limit = 50
    limit = max(1, min(limit, 200))
    ordered = list(threads or [])
    start = 0
    if cursor:
        mark = _decode_cursor(cursor)
        if mark is not None:
            for idx, t in enumerate(ordered):
                key = (0 if t["inProgress"] else 1,
                       -((t["endedAt"] if t["endedAt"] is not None
                          else t["startedAt"]) or 0),
                       t["threadId"])
                if key > mark:
                    start = idx
                    break
            else:
                start = len(ordered)
    page = ordered[start:start + limit]
    next_cursor = None
    if page and start + limit < len(ordered):
        next_cursor = _encode_cursor(page[-1])
    return page, next_cursor
