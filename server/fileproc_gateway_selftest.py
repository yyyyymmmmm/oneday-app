#!/usr/bin/env python3
"""fileproc_gateway 自测（包 1.8.0，断桥批一）。

在隔离临时目录里对 patches/fileproc_gateway.py 做行为级自测：
spreadsheet 转码（值语义/公式无缓存计数/路径纪律）与 rendition
（生成/缓存/ETag 304/参数纪律）。逻辑预期全部按桥口径
（fileproc_bridge.py §125/§138），本脚本随包走，应用前在本机
或部署机跑：python3 fileproc_gateway_selftest.py，全过回 0。
"""

import io
import os
import sys
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(tempfile.mkdtemp(prefix="fileproc-selftest-"))
DATA = ROOT / "data"
DATA.mkdir()
os.environ["SPREADSHEET_ROOT"] = str(DATA)
os.environ["RENDITION_ROOT"] = str(DATA)
os.environ["FILEPROC_CACHE_DIR"] = str(ROOT / "cache")

sys.path.insert(0, str(Path(__file__).parent / "patches"))
import fileproc_gateway as fp  # noqa: E402

FAILURES = []


def check(name, cond, detail=""):
    if cond:
        print(f"  ok {name}")
    else:
        print(f"FAIL {name} {detail}")
        FAILURES.append(name)


def expect_err(name, status, fn):
    try:
        fn()
    except fp._Err as e:
        check(name, e.status == status,
              f"(got {e.status}: {e.message})")
        return
    except Exception as e:  # noqa: BLE001
        check(name, False, f"(wrong exc {e!r})")
        return
    check(name, False, "(no error raised)")


# ------------------------------------------------------------ xlsx fixture
NS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
NSR = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

WORKBOOK = f"""<?xml version="1.0" encoding="UTF-8"?>
<workbook xmlns="{NS}" xmlns:r="{NSR}">
<sheets><sheet name="成绩" sheetId="1" r:id="rId1"/></sheets>
</workbook>"""
RELS = f"""<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
</Relationships>"""
SHARED = f"""<?xml version="1.0" encoding="UTF-8"?>
<sst xmlns="{NS}" count="3" uniqueCount="3">
<si><t>姓名</t></si><si><t>分数</t></si><si><t>小明</t></si>
</sst>"""
SHEET = f"""<?xml version="1.0" encoding="UTF-8"?>
<worksheet xmlns="{NS}">
<sheetData>
<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>
<row r="2"><c r="A2" t="s"><v>2</v></c><c r="B2"><v>95.5</v></c></row>
<row r="3"><c r="A3" t="s"><v>2</v></c><c r="B3"><f>SUM(B2:B2)</f></c></row>
</sheetData>
</worksheet>"""

xlsx_path = DATA / "scores.xlsx"
with zipfile.ZipFile(xlsx_path, "w") as zf:
    zf.writestr("xl/workbook.xml", WORKBOOK)
    zf.writestr("xl/_rels/workbook.xml.rels", RELS)
    zf.writestr("xl/sharedStrings.xml", SHARED)
    zf.writestr("xl/worksheets/sheet1.xml", SHEET)

# ------------------------------------------------------------ spreadsheet
out = fp.spreadsheet(str(xlsx_path))
check("spreadsheet name", out["name"] == "scores.xlsx")
check("spreadsheet sheets", len(out["sheets"]) == 1
      and out["sheets"][0]["name"] == "成绩")
csv_text = out["sheets"][0]["csv"]
check("spreadsheet csv values",
      csv_text == "姓名,分数\n小明,95.5\n小明,\n",
      f"(got {csv_text!r})")
check("spreadsheet total_rows", out["sheets"][0]["total_rows"] == 2)
check("spreadsheet formula note",
      any("公式单元格没有缓存值" in n for n in out["notes"]),
      f"(notes={out['notes']!r})")

expect_err("spreadsheet missing path arg", 400,
           lambda: fp.spreadsheet(""))
expect_err("spreadsheet relative path", 400,
           lambda: fp.spreadsheet("scores.xlsx"))
expect_err("spreadsheet outside root", 400,
           lambda: fp.spreadsheet("/etc/hostname"))
expect_err("spreadsheet missing file", 404,
           lambda: fp.spreadsheet(str(DATA / "nope.xlsx")))
(DATA / "my-credentials.xlsx").write_bytes(b"PK\x03\x04")
expect_err("spreadsheet sensitive name", 403,
           lambda: fp.spreadsheet(str(DATA / "my-credentials.xlsx")))
bad = DATA / "bad.xlsx"
bad.write_bytes(b"this is not a zip")
expect_err("spreadsheet not xlsx", 422,
           lambda: fp.spreadsheet(str(bad)))

# ------------------------------------------------------------ rendition
from PIL import Image  # noqa: E402

# 内存闸探的是宿主 /proc/meminfo：自测机内存吃紧时闸会（正确地）
# 回 503。故生成路径用探针打桩隔离环境，闸本身单独断言两态。
_real_mem = fp._mem_used_percent

img_path = DATA / "photo.png"
Image.new("RGB", (720, 480), (200, 30, 30)).save(img_path)

fp._mem_used_percent = lambda: 99.0  # noqa: E731
expect_err("rendition memory gate 503", 503,
           lambda: fp.rendition(str(img_path), "360", "image"))
fp._mem_used_percent = lambda: 10.0  # noqa: E731

status, body, etag = fp.rendition(str(img_path), "360", "image")
check("rendition 200", status == 200)
check("rendition jpeg magic", body[:2] == b"\xff\xd8")
with Image.open(io.BytesIO(body)) as im:
    check("rendition width tier", im.size[0] == 360,
          f"(got {im.size})")
status2, body2, etag2 = fp.rendition(
    str(img_path), "360", "image", if_none_match=etag)
check("rendition 304 on etag", status2 == 304 and body2 is None
      and etag2 == etag)
status3, body3, _ = fp.rendition(str(img_path), "1080", "image")
with Image.open(io.BytesIO(body3)) as im:
    check("rendition never upscales", im.size[0] == 720,
          f"(got {im.size})")
check("rendition cache landed",
      len(list((ROOT / "cache").glob("*.jpg"))) >= 2)

expect_err("rendition bad width", 400,
           lambda: fp.rendition(str(img_path), "999", "image"))
expect_err("rendition bad kind", 400,
           lambda: fp.rendition(str(img_path), "360", "thumb"))
expect_err("rendition missing file", 404,
           lambda: fp.rendition(str(DATA / "nope.png"), "360", "image"))
expect_err("rendition sensitive name", 403,
           lambda: fp.rendition(str(DATA / "token.png"), "360", "image"))
fp._mem_used_percent = _real_mem

print()
if FAILURES:
    print(f"SELFTEST FAILED: {len(FAILURES)} 项: {FAILURES}")
    sys.exit(1)
print("SELFTEST PASSED (全部行为断言通过)")
