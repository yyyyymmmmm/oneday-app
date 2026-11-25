#!/usr/bin/env python3
"""§125 self-test for the fileproc_bridge spreadsheet transcode
endpoint (GET /files/spreadsheet?path=): xlsx -> per-sheet CSV,
value semantics, App-side failure taxonomy by status code.

HTTP contract against a subprocess bridge with SPREADSHEET_ROOT
pointed at a scratch dir holding hand-built xlsx fixtures:
- auth required (401 without the bridge key)
- shared strings / numbers / booleans / formula cached values /
  formula without cache (empty + counted in notes) / date styles
  rendered ISO / CSV escaping
- multi-sheet order + names
- 500 data-row cap: truncated + total_rows reported, never silent
- path rules mirror the files download endpoint: missing 404,
  directory 400, relative 400, escape 400, sensitive name 403,
  legacy .xls 422, garbage 422
"""
# Moved 2026-11-14 with the endpoint: API-direct package B4/B5
# split /files/spreadsheet + /media/rendition out of the oneday
# bridge into the standalone fileproc module; contract unchanged.
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.request
import urllib.error
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
BRIDGE = os.path.join(HERE, "fileproc_bridge.py")
KEY = "spreadsheet-selftest-key"
PORT = 18751
BASE = f"http://127.0.0.1:{PORT}"

passed = failed = 0


def check(name, cond, extra=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"PASS {name}")
    else:
        failed += 1
        print(f"FAIL {name} {extra}")


def call(method, path, key=KEY):
    req = urllib.request.Request(BASE + path, method=method)
    if key:
        req.add_header("Authorization", f"Bearer {key}")
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status, json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"raw": raw}


NS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
NS_R = ("http://schemas.openxmlformats.org/officeDocument/2006/"
        "relationships")
NS_PKG_R = ("http://schemas.openxmlformats.org/package/2006/"
            "relationships")


def make_xlsx(root, filename, sheets, shared=None, styles=None):
    """sheets: [(name, sheet_xml_body_rows)] -- rows are raw <row>
    XML strings; shared: list of strings for sharedStrings."""
    path = os.path.join(root, filename)
    with zipfile.ZipFile(path, "w") as zf:
        sheet_tags = "".join(
            f'<sheet name="{name}" sheetId="{i + 1}" r:id="rId{i + 1}"/>'
            for i, (name, _) in enumerate(sheets))
        zf.writestr(
            "xl/workbook.xml",
            f'<workbook xmlns="{NS}" xmlns:r="{NS_R}">'
            f"<sheets>{sheet_tags}</sheets></workbook>")
        rels = "".join(
            f'<Relationship Id="rId{i + 1}" '
            f'Type="{NS_R}/worksheet" '
            f'Target="worksheets/sheet{i + 1}.xml"/>'
            for i in range(len(sheets)))
        zf.writestr(
            "xl/_rels/workbook.xml.rels",
            f'<Relationships xmlns="{NS_PKG_R}">{rels}</Relationships>')
        for i, (_, rows) in enumerate(sheets):
            zf.writestr(
                f"xl/worksheets/sheet{i + 1}.xml",
                f'<worksheet xmlns="{NS}"><sheetData>{rows}'
                f"</sheetData></worksheet>")
        if shared is not None:
            items = "".join(f"<si><t>{s}</t></si>" for s in shared)
            zf.writestr(
                "xl/sharedStrings.xml",
                f'<sst xmlns="{NS}">{items}</sst>')
        if styles is not None:
            zf.writestr("xl/styles.xml", styles)
    return path


def main():
    tmp = tempfile.mkdtemp(prefix="xlsx-root-")
    data_tmp = tempfile.mkdtemp(prefix="xlsx-data-")

    styles = (
        f'<styleSheet xmlns="{NS}"><cellXfs count="2">'
        f'<xf numFmtId="0"/><xf numFmtId="14"/></cellXfs>'
        f"</styleSheet>")
    basic_rows = (
        '<row r="1">'
        '<c r="A1" t="s"><v>0</v></c>'
        '<c r="B1" t="s"><v>1</v></c>'
        '<c r="C1" t="s"><v>2</v></c>'
        '<c r="D1" t="s"><v>3</v></c>'
        '<c r="E1" t="s"><v>4</v></c>'
        "</row>"
        '<row r="2">'
        '<c r="A2" t="s"><v>5</v></c>'
        "<c r=\"B2\"><v>42.5</v></c>"
        '<c r="C2"><f>SUM(B2:B2)</f><v>42.5</v></c>'
        '<c r="D2" t="b"><v>1</v></c>'
        '<c r="E2" s="1"><v>45292</v></c>'
        "</row>"
        '<row r="3">'
        '<c r="A3" t="s"><v>6</v></c>'
        '<c r="C3"><f>NOW()</f></c>'
        "</row>")
    basic = make_xlsx(
        tmp, "basic.xlsx",
        [("数据", basic_rows)],
        shared=["姓名", "数值", "公式", "开关", "日期",
                "小,明", '他说"好"'],
        styles=styles)

    many_rows = ['<row r="1"><c r="A1" t="s"><v>0</v></c></row>']
    for i in range(600):
        many_rows.append(
            f'<row r="{i + 2}"><c r="A{i + 2}"><v>{i}</v></c></row>')
    make_xlsx(
        tmp, "many.xlsx",
        [("一", "".join(many_rows)), ("二", '<row r="1">'
          '<c r="A1" t="s"><v>0</v></c></row>')],
        shared=["列"])

    # sensitive name but valid content -> must still be 403
    make_xlsx(tmp, "mytoken.xlsx", [("S", basic_rows)],
              shared=["a", "b", "c", "d", "e", "f", "g"],
              styles=styles)
    with open(os.path.join(tmp, "legacy.xls"), "wb") as f:
        f.write(b"\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1" + b"\x00" * 64)
    with open(os.path.join(tmp, "junk.xlsx"), "wb") as f:
        f.write(b"not a zip at all")
    os.mkdir(os.path.join(tmp, "dir.xlsx"))

    env = dict(os.environ, FILEPROC_BRIDGE_KEY=KEY,
               DATA_PATH=os.path.join(data_tmp, "data.json"),
               FILEPROC_PORT=str(PORT), SPREADSHEET_ROOT=tmp)
    env.pop("HERMES_API_KEY", None)
    proc = subprocess.Popen(
        [sys.executable, BRIDGE], env=env,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(50):
            try:
                s, _ = call("GET", "/health", key=None)
                if s == 200:
                    break
            except Exception:
                pass
            time.sleep(0.2)

        q = urllib.request.quote(basic, safe="")
        s, _ = call("GET", f"/files/spreadsheet?path={q}", key=None)
        check("no key -> 401", s == 401, f"{s}")

        s, body = call("GET", f"/files/spreadsheet?path={q}")
        check("basic 200", s == 200, f"{s} {body}")
        sheet = body["sheets"][0]
        check("sheet name kept", sheet["name"] == "数据")
        lines = sheet["csv"].splitlines()
        check("header row values",
              lines[0] == "姓名,数值,公式,开关,日期", lines[0])
        check("typed row: number/formula-cache/bool/date",
              lines[1] == '"小,明",42.5,42.5,TRUE,2024-01-01',
              lines[1])
        check("csv quoting for embedded quote",
              lines[2].startswith('"他说""好""'), lines[2])
        check("formula without cache renders empty",
              lines[2].endswith(",,") or lines[2].split(",")[2] == "",
              lines[2])
        check("missing-cache counted in notes",
              any("没有缓存值" in n for n in body["notes"]),
              str(body["notes"]))
        check("basic not truncated, total_rows=2",
              sheet["truncated"] is False and sheet["total_rows"] == 2,
              str(sheet))

        q2 = urllib.request.quote(
            os.path.join(tmp, "many.xlsx"), safe="")
        s, body = call("GET", f"/files/spreadsheet?path={q2}")
        first, second = body["sheets"]
        check("multi-sheet order", [first["name"], second["name"]]
              == ["一", "二"])
        check("truncation flagged + total reported",
              first["truncated"] is True
              and first["total_rows"] == 600, str(first)[:120])
        check("truncated csv = header + 500 rows",
              len(first["csv"].splitlines()) == 501,
              str(len(first["csv"].splitlines())))

        def status_of(p):
            qq = urllib.request.quote(p, safe="")
            return call("GET", f"/files/spreadsheet?path={qq}")[0]

        check("missing file -> 404",
              status_of(os.path.join(tmp, "nope.xlsx")) == 404)
        check("directory -> 400",
              status_of(os.path.join(tmp, "dir.xlsx")) == 400)
        check("relative path -> 400", status_of("basic.xlsx") == 400)
        check("escape root -> 400",
              status_of("/etc/passwd") == 400)
        check("sensitive name -> 403",
              status_of(os.path.join(tmp, "mytoken.xlsx")) == 403)
        check("legacy .xls -> 422",
              status_of(os.path.join(tmp, "legacy.xls")) == 422)
        check("garbage -> 422",
              status_of(os.path.join(tmp, "junk.xlsx")) == 422)
        s, _ = call("GET", "/files/spreadsheet")
        check("missing path param -> 400", s == 400, f"{s}")
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except Exception:
            proc.kill()

    print(f"spreadsheet selftest: {passed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
