import importlib.util, json, os, sys, tempfile, time
from pathlib import Path

tmp = Path(tempfile.mkdtemp())
(tmp / "SOUL.md").write_text("# 旧名\n\n正文\n", encoding="utf-8")
os.environ["IDENTITY_BRIDGE_KEY"] = "test-key"
os.environ["IDENTITY_SOUL_PATH"] = str(tmp / "SOUL.md")
os.environ["AVATAR_DIR"] = str(tmp / "identity-data")
os.environ["ONEDAY_BRIDGE_KEY"] = ""  # traces spill locally

spec = importlib.util.spec_from_file_location(
    "identity_bridge",
    str(Path(__file__).resolve().parent.parent / "modules" / "identity_bridge.py"))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

fails = []
def check(name, cond):
    print(("PASS " if cond else "FAIL ") + name)
    if not cond:
        fails.append(name)

# 1. name: no bridge record -> mtime fallback, source unknown
v = m._get_name()
check("legacy name value", v["soulName"] == "旧名")
check("legacy name mtime fallback", abs(v["updatedAt"] - (tmp / "SOUL.md").stat().st_mtime) < 1)
check("legacy name source unknown", v["source"] == "unknown")

# 2. set_name records server receipt time + source
before = time.time()
m._set_name("三狗", False, "agent")
v = m._get_name()
check("renamed", v["soulName"] == "三狗")
check("name updatedAt stamped", before <= v["updatedAt"] <= time.time())
check("name source=agent", v["source"] == "agent")
st = json.loads((tmp / "identity-data" / "name-state.json").read_text())
check("name-state persisted", st["name"] == "三狗" and st["source"] == "agent")

# 3. dry-run must not move the stamp
stamp1 = v["updatedAt"]
time.sleep(0.02)
m._set_name("别的名字", True, "agent")
v = m._get_name()
check("dry-run keeps name", v["soulName"] == "三狗")
check("dry-run keeps stamp", v["updatedAt"] == stamp1)

# 4. external soul edit (no bridge record for new name) -> mtime fallback
(tmp / "SOUL.md").write_text("# 外部改名\n", encoding="utf-8")
v = m._get_name()
check("external edit name", v["soulName"] == "外部改名")
check("external edit source unknown", v["source"] == "unknown")

# 5. avatar: add preset as current -> pointer stamp == item createdAt, source kept
r = m._add_avatar_preset("paw", "ai", True, "agent")
state = m._get_avatar()
check("avatar current", state["currentId"] == r["id"])
check("avatar pointer stamp", state["currentUpdatedAt"] == r["createdAt"])
check("avatar pointer source", state["currentSource"] == "ai")

# 6. add image NOT current -> pointer stamp unmoved
import base64
png = base64.b64encode(b"\x89PNG\r\n\x1a\n" + b"\x00" * 32).decode()
stamp_before = state["currentUpdatedAt"]
time.sleep(0.02)
img = m._add_avatar_image(png, "ai", False, "agent")
state = m._get_avatar()
check("non-current add keeps pointer", state["currentId"] == r["id"])
check("non-current add keeps stamp", state["currentUpdatedAt"] == stamp_before)

# 7. select old image -> pointer stamp refreshed to now (LWW key behavior)
time.sleep(0.02)
sel_before = time.time()
m._select_avatar(img["id"], "agent")
state = m._get_avatar()
check("select moves pointer", state["currentId"] == img["id"])
check("select refreshes stamp", state["currentUpdatedAt"] >= sel_before > img["createdAt"])
check("select source=actor", state["currentSource"] == "agent")

# 8. legacy index without pointer stamp -> fallback to current item createdAt
idxp = tmp / "identity-data" / "index.json"
idx = json.loads(idxp.read_text())
del idx["currentUpdatedAt"]; del idx["currentSource"]
idxp.write_text(json.dumps(idx))
state = m._get_avatar()
cur = next(it for it in state["items"] if it["id"] == state["currentId"])
check("legacy pointer fallback", state["currentUpdatedAt"] == cur["createdAt"])

print("RESULT:", "ALL PASS" if not fails else f"{len(fails)} FAILURES")
sys.exit(1 if fails else 0)
