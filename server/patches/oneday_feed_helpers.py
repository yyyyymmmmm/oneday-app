"""Pure feed category & usefulness scoring helpers (extracted from oneday_seg_feed.py, Phase 5.1)."""

from __future__ import annotations


def _feed_category_for(direction) -> str | None:
    """A post's category (§459): the brief direction it was
    written under, verbatim -- the plan seat keeps direction
    names stable across rounds, so the direction IS the
    topic classification. No direction -> no category
    (the post reads as uncategorised, never a fake label)."""
    d = str(direction or "").strip()
    return d[:60] if d else None


def _feed_usefulness(p: dict, now: float) -> float:
    """One post's usefulness score (see the constants above).
    Pure function of the post's own recorded engagement --
    the same number the list sorts by rides the view, so the
    App can show why a post sits where it sits."""
    score = 0.0
    if p.get("likedAt"):
        score += 50.0
    score += 15.0 * min(int(p.get("discussCount") or 0), 3)
    if p.get("readAt"):
        score += 10.0
    age_days = max(0.0, (now - float(p.get("createdAt")
                                     or now)) / 86400.0)
    score += max(0.0, 20.0 - 5.0 * age_days)
    return round(score, 1)
