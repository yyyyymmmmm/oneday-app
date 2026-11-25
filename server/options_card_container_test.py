"""Container real-code test for options_pending.attach_options (Part B).

Runs INSIDE the hermes container against a real SessionDB on a temp
SQLite file (no production data touched):
  python3 /tmp/options_card_container_test.py
Asserts: options payload lands on the target row; pre-existing
display_metadata keys (reactions + a delivery marker) survive the
read-modify-write verbatim; a row outside the session lineage refuses.
"""

import pathlib
import sys
import tempfile

sys.path.insert(0, "/tmp")
sys.path.insert(0, "/opt/hermes")

from hermes_state import SessionDB  # noqa: E402
import options_pending as pending  # noqa: E402

tmp = pathlib.Path(tempfile.mkdtemp(prefix="options-test-"))
db = SessionDB(db_path=tmp / "state.db")
sid = "options-test-session"
db.create_session(sid, "api_server")
db.append_message(sid, "user", "我们接下来怎么办？")
a_row = db.append_message(
    sid, "assistant", "两条路，你挑一条。",
    display_metadata={"delivery": {"surface": "test"}})
db.set_message_reaction(sid, a_row, "👍", author="user")

options = [{"label": "方案 A", "send_text": "按方案 A 走"},
           {"label": "方案 B", "send_text": "按方案 B 走"}]
assert pending.attach_options(db, sid, a_row, options) is True

msgs = {m["id"]: m for m in db.get_messages(sid)}
meta = msgs[a_row].get("display_metadata") or {}
assert meta.get("options", {}).get("options") == options, meta
assert meta.get("options", {}).get("v") == 1, meta
assert meta.get("delivery") == {"surface": "test"}, meta
reactions = meta.get("reactions") or []
assert any(r.get("emoji") == "👍" and r.get("author") == "user" for r in reactions), meta

other = "options-test-other"
db.create_session(other, "api_server")
o_row = db.append_message(other, "assistant", "别会话的消息")
assert pending.attach_options(db, sid, o_row, options) is False
assert pending.attach_options(db, sid, 999999, options) is False
meta_other = {m["id"]: m for m in db.get_messages(other)}[o_row].get("display_metadata") or {}
assert "options" not in meta_other, meta_other

print("CONTAINER TEST PASSED")
