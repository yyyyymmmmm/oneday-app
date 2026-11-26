"""Pure projection helpers for OneDay's cron API fields."""

import re


_SYSTEM_NAME_PATTERNS = (
    re.compile(r"^OneDay\s+系统轮"),
    re.compile(r"^OneDay\s+(?:记忆|memory)", re.IGNORECASE),
    re.compile(r"^OneDay\s+(?:目标|goal).*(?:提炼|distill)",
               re.IGNORECASE),
)
_SYSTEM_SOURCE_PATTERNS = (
    re.compile(r"oneday-round-[a-z0-9_-]+\.py$", re.IGNORECASE),
    re.compile(r"oneday-(?:memory|goal)[a-z0-9_-]*\.py$", re.IGNORECASE),
)


def is_system_job(job: dict) -> bool:
    """Recognize registered OneDay rounds and OneDay memory/goal jobs.

    User-owned jobs default to false; arbitrary names alone are not enough
    unless they carry the OneDay namespace and a known system-task pattern.
    """
    if not isinstance(job, dict):
        return False
    name = str(job.get("name") or "").strip()
    if any(p.search(name) for p in _SYSTEM_NAME_PATTERNS):
        return True

    sources = [str(job.get(k) or "") for k in
               ("script", "source", "source_name", "origin")]
    sources = [s.replace("\\", "/").split("/")[-1].strip()
               for s in sources]
    return any(p.search(source) for p in _SYSTEM_SOURCE_PATTERNS
               for source in sources)


_WEEKDAY_NAMES = ("日", "一", "二", "三", "四", "五", "六")

_MACRO_SCHEDULES = {
    "@hourly": "每小时整点",
    "@daily": "每天 0:00",
    "@midnight": "每天 0:00",
    "@weekly": "每周日 0:00",
    "@monthly": "每月 1 日 0:00",
    "@yearly": "每年 1 月 1 日 0:00",
    "@annually": "每年 1 月 1 日 0:00",
}

_EVERY_RE = re.compile(r"^every\s+(\d+)\s*([smhd])$", re.IGNORECASE)


def _cron_field_values(field, lo, hi):
    """Parse one cron field to ('any',) / ('step', n) / ('list', [..])
    / ('range', a, b); None when the shape is outside the humanizer's
    coverage (the caller then keeps the raw expression)."""
    f = (field or "").strip()
    if f == "*":
        return ("any",)
    m = re.fullmatch(r"\*/(\d+)", f)
    if m:
        return ("step", int(m.group(1)))
    m = re.fullmatch(r"(\d+)-(\d+)(?:/(\d+))?", f)
    if m:
        a, b = int(m.group(1)), int(m.group(2))
        if m.group(3) or not (lo <= a <= b <= hi):
            return None
        return ("range", a, b)
    vals = []
    for part in f.split(","):
        if not re.fullmatch(r"\d+", part):
            return None
        v = int(part)
        if not (lo <= v <= hi):
            return None
        vals.append(v)
    return ("list", vals) if vals else None


def humanize_schedule(expr):
    """(human_text, ok): translate a cron expression into a human
    schedule line (每天 7:30 / 每周一 9:00 / 每月 1 日 3:05 …).
    ok=False returns the original expression: shapes outside the
    covered set keep the raw text rather than a wrong translation,
    and the caller marks them so they can be counted and reported."""
    if not isinstance(expr, str):
        return expr, False
    raw = expr.strip()
    if not raw:
        return expr, False
    low = raw.lower()
    if low in _MACRO_SCHEDULES:
        return _MACRO_SCHEDULES[low], True
    m = _EVERY_RE.match(low)
    if m:
        n, unit = int(m.group(1)), m.group(2)
        return (f"每 {n} 分钟" if unit == "m" else
                f"每 {n} 小时" if unit == "h" else
                f"每 {n} 天" if unit == "d" else
                f"每 {n} 秒"), True
    fields = raw.split()
    if len(fields) != 5:
        return expr, False
    minute = _cron_field_values(fields[0], 0, 59)
    hour = _cron_field_values(fields[1], 0, 23)
    dom = _cron_field_values(fields[2], 1, 31)
    month = _cron_field_values(fields[3], 1, 12)
    dow = _cron_field_values(fields[4], 0, 7)
    if None in (minute, hour, dom, month, dow):
        return expr, False
    if minute[0] == "step" and hour[0] == "any" and dom[0] == "any" \
            and month[0] == "any" and dow[0] == "any":
        return f"每 {minute[1]} 分钟", True
    if hour[0] == "step" and minute[0] == "list" \
            and len(minute[1]) == 1 and dom[0] == "any" \
            and month[0] == "any" and dow[0] == "any":
        mm = minute[1][0]
        return (f"每 {hour[1]} 小时" if mm == 0
                else f"每 {hour[1]} 小时的 {mm:02d} 分"), True
    if minute[0] == "list" and hour[0] == "any" and dom[0] == "any" \
            and month[0] == "any" and dow[0] == "any":
        # Fixed minute(s) of every hour ('5 * * * *', queue 183:
        # the hourly evaluation round kept its raw expression).
        mins = "、".join(str(v) for v in minute[1])
        return f"每小时第 {mins} 分钟", True
    if minute[0] != "list" or hour[0] != "list":
        return expr, False
    times = [f"{h}:{m:02d}" for h in hour[1] for m in minute[1]]
    if len(times) > 4:
        return expr, False
    time_text = "、".join(times)
    if dom[0] in ("list", "range") and dow[0] in ("list", "range"):
        # cron fires on dom OR dow here; a single human line would
        # misstate it, so keep the raw expression.
        return expr, False
    prefix = ""
    if month[0] == "list":
        prefix = "、".join(f"{v} 月" for v in month[1]) + " "
    elif month[0] == "range":
        prefix = f"{month[1]}–{month[2]} 月 "
    if dom[0] == "list":
        days = "、".join(str(v) for v in dom[1])
        return f"{prefix}每月 {days} 日 {time_text}", True
    if dom[0] == "range":
        return f"{prefix}每月 {dom[1]}–{dom[2]} 日 {time_text}", True
    if dow[0] == "list":
        names = "、".join(_WEEKDAY_NAMES[v % 7] for v in dow[1])
        return f"{prefix}每周{names} {time_text}", True
    if dow[0] == "range":
        if dow[1] == 1 and dow[2] == 5:
            return f"{prefix}工作日 {time_text}", True
        return (f"{prefix}每周{_WEEKDAY_NAMES[dow[1] % 7]}至"
                f"{_WEEKDAY_NAMES[dow[2] % 7]} {time_text}"), True
    return f"{prefix}每天 {time_text}", True


def project_jobs(jobs):
    """Copy cron jobs, add the OneDay-owned system classification,
    and render schedule_display as a human schedule line (queue
    173: the field carried the raw cron expression, 9 of 9 live
    jobs). Shapes the humanizer does not cover keep the raw
    expression and gain a schedule_display_raw marker so they stay
    countable instead of silently passing as translated."""
    out = []
    for job in jobs:
        if not isinstance(job, dict):
            out.append(job)
            continue
        job = dict(job, is_system=is_system_job(job))
        expr = job.get("schedule_display")
        if isinstance(expr, str) and expr.strip():
            human, ok = humanize_schedule(expr)
            if ok:
                job["schedule_display"] = human
            else:
                job["schedule_display_raw"] = expr
        out.append(job)
    return out
