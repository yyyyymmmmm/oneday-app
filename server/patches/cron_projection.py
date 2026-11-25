"""Pure projection helpers for OneDay's cron API fields."""

import re


_SYSTEM_NAME_PATTERNS = (
    re.compile(r"^OneDay\s+系统轮"),
    re.compile(r"^OneDay\s+(?:记忆|memory)", re.IGNORECASE),
    re.compile(r"^OneDay\s+(?:目标|goal).*(?:提炼|distill)", re.IGNORECASE),
)
_SYSTEM_SOURCE_PATTERNS = (
    re.compile(r"oneday-round-[a-z0-9_-]+\.py$", re.IGNORECASE),
    re.compile(r"oneday-(?:memory|goal)[a-z0-9_-]*\.py$", re.IGNORECASE),
)


def is_system_job(job: dict) -> bool:
    """Recognize registered OneDay rounds and OneDay memory/goal jobs."""
    if not isinstance(job, dict):
        return False
    name = str(job.get("name") or "").strip()
    if any(pattern.search(name) for pattern in _SYSTEM_NAME_PATTERNS):
        return True

    sources = [str(job.get(key) or "") for key in
               ("script", "source", "source_name", "origin")]
    sources = [source.replace("\\", "/").split("/")[-1].strip()
               for source in sources]
    return any(pattern.search(source) for pattern in _SYSTEM_SOURCE_PATTERNS
               for source in sources)


def project_jobs(jobs):
    """Copy cron jobs and add the OneDay-owned system classification."""
    return [dict(job, is_system=is_system_job(job))
            if isinstance(job, dict) else job for job in jobs]
