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


def project_jobs(jobs):
    """Copy cron jobs and add the OneDay-owned system classification."""
    return [dict(job, is_system=is_system_job(job))
            if isinstance(job, dict) else job for job in jobs]
