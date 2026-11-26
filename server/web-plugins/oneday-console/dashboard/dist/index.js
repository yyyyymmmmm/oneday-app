/**
 * OneDay Console — dashboard plugin (大活12 网页端对齐).
 *
 * 棒 0 地基 + 棒 1 功能面 (approvals decide + credential vault):
 * registers as a native dashboard tab via window.__HERMES_PLUGINS__
 * and renders with the plugin SDK's React.
 *
 * The logic core (Core) is habitat-agnostic on purpose: it only speaks
 * the live gateway contract over same-origin fetch —
 *   POST /api/env/reveal {key:"API_SERVER_KEY"}  (dashboard session cookie)
 *   GET  /v1/approvals ; POST /v1/approvals/{id}  (Bearer key from reveal)
 *   POST /v1/grants/revoke                        (undo an "always")
 *   GET  /v1/vault/entries                        (metadata only, no values)
 *   GET  /v1/vault/requests?status=pending        (owner mode, master key)
 *   POST /v1/vault/requests/{id}/fulfill          (values go out, never back)
 * Route B (standalone SPA under /oneday/) reuses the same core verbatim;
 * only this shell would change. No credentials are ever baked into this
 * file; the revealed key lives in sessionStorage only (tab-scoped,
 * gone when the tab closes) and is never logged. Vault secret values
 * typed into the request form are sent once in the fulfill body and
 * are never rendered back, stored, or logged.
 *
 * Approval semantics mirror the App word for word (ApprovalCardSpec):
 * buttons come from each record's own `choices` — once=批准 (filled
 * primary), session=本次会话允许, always=总是允许这一类 (outlined
 * secondary), deny=驳回 (text). One tap decides; an "always" raises a
 * revocable notice (已允许并记住（…）+ 撤销); decided records fold into
 * plain summary lines and never flow back into the pending list.
 */
(function () {
  "use strict";

  // ---------------- logic core (A/B dual-habitat) ----------------
  var STORAGE_KEY = "oneday-console.api_key";

  function sessionGet() {
    try { return window.sessionStorage.getItem(STORAGE_KEY); } catch (e) { return null; }
  }
  function sessionSet(v) {
    try { window.sessionStorage.setItem(STORAGE_KEY, v); } catch (e) { /* private mode: keep in-memory only */ }
  }
  function sessionClear() {
    try { window.sessionStorage.removeItem(STORAGE_KEY); } catch (e) { /* noop */ }
  }

  function revealKey() {
    return fetch("/api/env/reveal", {
      method: "POST",
      credentials: "same-origin",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ key: "API_SERVER_KEY" })
    }).then(function (resp) {
      if (resp.status === 401) {
        var err = new Error("dashboard 会话未登录或已过期，请先登录面板再打开本页");
        err.code = "no_session";
        throw err;
      }
      if (!resp.ok) throw new Error("reveal 应答 " + resp.status);
      return resp.json();
    }).then(function (data) {
      if (!data || typeof data.value !== "string" || !data.value) {
        throw new Error("reveal 未返回可用钥");
      }
      sessionSet(data.value);
      return data.value;
    });
  }

  function rawCall(method, path, key, body) {
    var opts = {
      method: method,
      credentials: "same-origin",
      headers: { "Authorization": "Bearer " + key }
    };
    if (body !== undefined) {
      opts.headers["Content-Type"] = "application/json";
      opts.body = JSON.stringify(body);
    }
    return fetch(path, opts);
  }

  // One authenticated call with the bar-0 discipline: a 401 drops the
  // stored key, reveals a fresh one, and retries exactly once.
  function api(method, path, body) {
    var key = sessionGet();
    var first = key ? rawCall(method, path, key, body) : Promise.reject({ stale: true });
    return first.then(function (resp) {
      if (resp.status === 401) throw { stale: true };
      return resp;
    }).catch(function (e) {
      if (!e || !e.stale) throw e;
      sessionClear();
      return revealKey().then(function (fresh) {
        return rawCall(method, path, fresh, body);
      });
    });
  }

  function apiJson(method, path, body) {
    return api(method, path, body).then(function (resp) {
      if (!resp.ok) {
        var err = new Error(path + " 应答 " + resp.status);
        err.status = resp.status;
        throw err;
      }
      return resp.json();
    });
  }

  var Core = {
    revealKey: revealKey,
    fetchApprovals: function () { return apiJson("GET", "/v1/approvals"); },
    decideApproval: function (requestId, choice) {
      return apiJson("POST", "/v1/approvals/" + encodeURIComponent(requestId), { choice: choice });
    },
    revokeGrant: function (source, patternKey) {
      return apiJson("POST", "/v1/grants/revoke", { source: source, pattern_key: patternKey });
    },
    fetchVaultEntries: function () { return apiJson("GET", "/v1/vault/entries"); },
    fetchVaultRequests: function () { return apiJson("GET", "/v1/vault/requests?status=pending"); },
    fetchVaultRequestStatus: function (requestId) {
      return apiJson("GET", "/v1/vault/requests/" + encodeURIComponent(requestId));
    },
    fulfillVaultRequest: function (requestId, body) {
      return apiJson("POST", "/v1/vault/requests/" + encodeURIComponent(requestId) + "/fulfill", body);
    }
  };
  window.__ONEDAY_CONSOLE_CORE__ = Core;

  // ---------------- shared formatting ----------------
  function fmtTime(epoch) {
    if (!epoch) return "";
    var d = new Date(Number(epoch) * 1000);
    if (isNaN(d.getTime())) return String(epoch);
    return d.toLocaleString();
  }
  function fmtClock(epoch) {
    if (!epoch) return "";
    var d = new Date(Number(epoch) * 1000);
    if (isNaN(d.getTime())) return "";
    return d.toLocaleTimeString();
  }

  var CHOICE_LABELS = {
    once: "批准",
    session: "本次会话允许",
    always: "总是允许这一类",
    deny: "驳回"
  };
  var CHOICE_CLASSES = {
    once: "odc-btn odc-btn-primary",
    session: "odc-btn odc-btn-secondary",
    always: "odc-btn odc-btn-secondary",
    deny: "odc-btn odc-btn-text"
  };
  var DECIDED_LABELS = {
    approved: "已批准",
    denied: "已驳回",
    expired: "已过期",
    superseded: "已被新请求取代",
    smart_denied: "智能拒绝"
  };

  // ---------------- route A shell (dashboard plugin) ----------------
  var SDK = window.__HERMES_PLUGIN_SDK__;
  if (!SDK || !window.__HERMES_PLUGINS__) return;

  var React = SDK.React;
  var h = React.createElement;
  var hooks = SDK.hooks;
  var C = SDK.components || {};
  var Card = C.Card || function (p) { return h("div", { className: "odc-card" }, p.children); };
  var CardContent = C.CardContent || function (p) { return h("div", null, p.children); };

  function useFace(loader) {
    var pair = hooks.useState({ phase: "loading", data: null, error: "" });
    var state = pair[0];
    var setState = pair[1];
    var load = hooks.useCallback(function () {
      setState({ phase: "loading", data: null, error: "" });
      loader().then(function (data) {
        setState({ phase: "ready", data: data, error: "" });
      }).catch(function (err) {
        setState({ phase: "error", data: null, error: (err && err.message) || String(err) });
      });
    }, []);
    hooks.useEffect(function () { load(); }, [load]);
    return [state, load, setState];
  }

  function faceShell(title, sub, face, onRefresh, body) {
    var inner;
    if (face.phase === "loading") {
      inner = h("p", null, "正在经 dashboard 会话换钥并读取……");
    } else if (face.phase === "error") {
      inner = [h("p", { key: "e" }, "读取失败：" + face.error),
        h("button", { key: "r", className: "odc-btn", onClick: onRefresh }, "重试")];
    } else {
      inner = body;
    }
    return h(Card, null, h(CardContent, null,
      h("div", { className: "odc-face-head" },
        h("h3", null, title),
        h("button", { className: "odc-btn odc-btn-small", onClick: onRefresh }, "刷新")),
      h("p", { className: "odc-sub" }, sub),
      inner));
  }

  // ---------------- approvals face ----------------
  function ApprovalsFace(props) {
    var facePair = useFace(Core.fetchApprovals);
    var face = facePair[0];
    var load = facePair[1];
    var busyPair = hooks.useState("");
    var busy = busyPair[0];
    var setBusy = busyPair[1];
    var notePair = hooks.useState(null);
    var note = notePair[0];
    var setNote = notePair[1];

    function decide(rec, choice) {
      setBusy(rec.request_id + ":" + choice);
      setNote(null);
      Core.decideApproval(rec.request_id, choice).then(function () {
        setBusy("");
        if (choice === "always") {
          setNote({ kind: "always", rec: rec });
        } else {
          setNote({ kind: "done", text: "已提交：" + (CHOICE_LABELS[choice] || choice) + "（以回读为准）" });
        }
        load();
        if (props.onDecided) props.onDecided();
      }).catch(function (err) {
        setBusy("");
        setNote({ kind: "error", text: "裁决失败：" + ((err && err.message) || String(err)) + "（可能已被处理，请看回读）" });
        load();
      });
    }

    function undoAlways() {
      var rec = note.rec;
      var keys = rec.pattern_keys || [];
      setBusy("undo");
      Promise.all(keys.map(function (pk) { return Core.revokeGrant(rec.source, pk); }))
        .then(function () {
          setBusy("");
          setNote({ kind: "done", text: "已撤销总是允许（" + keys.join("、") + "）" });
          load();
        }).catch(function (err) {
          setBusy("");
          setNote({ kind: "error", text: "撤销失败：" + ((err && err.message) || String(err)) });
        });
    }

    var body = null;
    if (face.phase === "ready") {
      var payload = face.data || {};
      var records = Array.isArray(payload.approvals) ? payload.approvals : [];
      var pending = records.filter(function (r) { return r.status === "pending"; });
      var decided = records.filter(function (r) { return r.status !== "pending"; }).slice(0, 20);
      var parts = [];
      parts.push(h("p", { key: "count", className: "odc-count" },
        "当前待批：", h("strong", null, String(payload.pending_count != null ? payload.pending_count : pending.length)), " 件（与 App 同一接口）"));
      if (payload.ledger_degraded) {
        parts.push(h("p", { key: "deg", className: "odc-warn" }, "注意：服务端账本降级，已决记录可能不完整。"));
      }
      if (note) {
        if (note.kind === "always") {
          parts.push(h("div", { key: "note", className: "odc-toast" },
            h("span", null, "✓ 已允许并记住（" + ((note.rec.pattern_keys || []).join("、") || note.rec.source || "") + "）"),
            h("button", { className: "odc-btn odc-btn-text", disabled: busy === "undo", onClick: undoAlways }, "撤销")));
        } else {
          parts.push(h("p", { key: "note", className: note.kind === "error" ? "odc-error" : "odc-done" }, note.text));
        }
      }
      if (!pending.length) {
        parts.push(h("p", { key: "empty", className: "odc-empty" }, "暂无待批。"));
      }
      pending.forEach(function (rec) {
        var title = rec.description || rec.command || rec.request_id;
        var meta = [];
        if (rec.session_id) meta.push("会话 " + String(rec.session_id).slice(0, 8));
        if (rec.created_at) meta.push(fmtTime(rec.created_at));
        if (rec.pattern_keys && rec.pattern_keys.length) meta.push("类别 " + rec.pattern_keys.join("、"));
        var kids = [
          h("span", { key: "t", className: "odc-row-title" }, title),
          h("span", { key: "m", className: "odc-row-meta" }, meta.join(" · "))
        ];
        if (rec.command && rec.description && rec.command !== rec.description) {
          kids.push(h("code", { key: "cmd", className: "odc-cmd" }, rec.command));
        }
        if (rec.answerable === false) {
          kids.push(h("span", { key: "na", className: "odc-warn" },
            "原等待者已不在，本条只能查看（裁决会由服务端拒绝）。"));
        } else {
          var choices = (rec.choices && rec.choices.length) ? rec.choices : ["once", "deny"];
          kids.push(h("span", { key: "acts", className: "odc-actions" },
            choices.map(function (choice) {
              var bkey = rec.request_id + ":" + choice;
              return h("button", {
                key: choice,
                className: CHOICE_CLASSES[choice] || "odc-btn",
                disabled: !!busy,
                onClick: function () { decide(rec, choice); }
              }, busy === bkey ? "提交中…" : (CHOICE_LABELS[choice] || choice));
            })));
        }
        parts.push(h("div", { key: rec.request_id, className: "odc-row odc-row-card" }, kids));
      });
      if (decided.length) {
        parts.push(h("div", { key: "sum", className: "odc-summary" },
          h("p", { className: "odc-summary-head" }, "已决汇总（不回流待批）"),
          decided.map(function (rec) {
            var label = DECIDED_LABELS[rec.status] || rec.status;
            if (rec.status === "approved" && rec.choice === "always") label = "已批准（总是允许）";
            if (rec.status === "approved" && rec.choice === "session") label = "已批准（本次会话）";
            return h("p", { key: rec.request_id, className: "odc-summary-line" },
              label + " · " + (rec.description || rec.command || rec.request_id) +
              (rec.decided_at ? " · " + fmtClock(rec.decided_at) : ""));
          })));
      }
      body = parts;
    }
    return faceShell("批准", "待批与 App 同一接口、同一语义：一次点按即生效，按钮按服务端给本条的 choices 渲染。", face, load, body);
  }

  // ---------------- vault entries face (read-only) ----------------
  function VaultEntriesFace() {
    var facePair = useFace(Core.fetchVaultEntries);
    var face = facePair[0];
    var load = facePair[1];
    var body = null;
    if (face.phase === "ready") {
      var entries = (face.data && Array.isArray(face.data.data)) ? face.data.data : [];
      if (!entries.length) {
        body = h("p", { className: "odc-empty" }, "凭据库暂无条目。");
      } else {
        body = h("ul", { className: "odc-list" }, entries.map(function (e) {
          var meta = [];
          if (e.service) meta.push(e.service);
          if (e.domains && e.domains.length) meta.push(e.domains.join("、"));
          if (e.username) meta.push("账号 " + e.username);
          meta.push("字段 " + ((e.field_names || []).join("、") || "—"));
          meta.push("版本 " + (e.version != null ? e.version : "—"));
          if (e.updated_at) meta.push("更新 " + fmtTime(e.updated_at));
          meta.push(e.has_secret ? "秘密已封存" : "无秘密");
          return h("li", { key: e.id, className: "odc-row" },
            h("span", { className: "odc-row-title" }, e.name || e.id),
            h("span", { className: "odc-row-meta" }, meta.join(" · ")));
        }));
      }
    }
    return faceShell("凭据库", "只读呈现：服务端只回元数据，凭据值永不经本面显示。新建/替换/撤销仍在 App。", face, load, body);
  }

  // ---------------- vault requests face (todo) ----------------
  function VaultRequestCard(props) {
    var req = props.request;
    var openPair = hooks.useState(false);
    var open = openPair[0];
    var setOpen = openPair[1];
    var valsPair = hooks.useState({});
    var vals = valsPair[0];
    var setVals = valsPair[1];
    var userPair = hooks.useState("");
    var username = userPair[0];
    var setUsername = userPair[1];
    var busyPair = hooks.useState(false);
    var busy = busyPair[0];
    var setBusy = busyPair[1];
    var msgPair = hooks.useState(null);
    var msg = msgPair[0];
    var setMsg = msgPair[1];

    function afterAction(text) {
      setBusy(false);
      setVals({});
      setUsername("");
      setOpen(false);
      Core.fetchVaultRequestStatus(req.request_id).then(function (st) {
        setMsg({ ok: true, text: text + "；状态回读：" + (st.status || "未知") });
        props.onChanged();
      }).catch(function () {
        setMsg({ ok: true, text: text + "（状态回读失败，请刷新列表确认）" });
        props.onChanged();
      });
    }
    function fail(err) {
      setBusy(false);
      setMsg({ ok: false, text: "失败：" + ((err && err.message) || String(err)) });
    }
    function reject() {
      setBusy(true);
      Core.fulfillVaultRequest(req.request_id, { decision: "reject" })
        .then(function () { afterAction("已拒绝该请求"); }, fail);
    }
    function fulfill() {
      var values = {};
      var missing = [];
      (req.fields || []).forEach(function (f) {
        var v = (vals[f] || "").trim();
        if (!v) missing.push(f);
        values[f] = v;
      });
      if (missing.length) {
        setMsg({ ok: false, text: "请填齐字段：" + missing.join("、") + "（须与请求字段恰好同集）" });
        return;
      }
      setBusy(true);
      var body = { decision: "fulfill", values: values };
      if (username.trim()) body.username = username.trim();
      Core.fulfillVaultRequest(req.request_id, body)
        .then(function (res) {
          afterAction("已存入凭据库" + (res && res.credential_ref ? "（条目 " + res.credential_ref + "）" : ""));
        }, fail);
    }

    var meta = [];
    if (req.domain) meta.push(req.domain);
    if (req.reason) meta.push(req.reason);
    if (req.expires_at) meta.push("过期 " + fmtTime(req.expires_at));
    var kids = [
      h("span", { key: "t", className: "odc-row-title" }, req.service || req.request_id),
      h("span", { key: "m", className: "odc-row-meta" }, meta.join(" · ")),
      h("span", { key: "f", className: "odc-chips" },
        (req.fields || []).map(function (f) { return h("span", { key: f, className: "odc-chip" }, f); }))
    ];
    if (msg) {
      kids.push(h("p", { key: "msg", className: msg.ok ? "odc-done" : "odc-error" }, msg.text));
    }
    if (open) {
      (req.fields || []).forEach(function (f) {
        kids.push(h("label", { key: "in-" + f, className: "odc-field" },
          h("span", null, f),
          h("input", {
            type: f === "password" || f === "secret" || f === "token" || f === "api_key" || f === "otp" ? "password" : "text",
            autoComplete: "off",
            value: vals[f] || "",
            onChange: function (ev) {
              var next = {};
              for (var k in vals) next[k] = vals[k];
              next[f] = ev.target.value;
              setVals(next);
            }
          })));
      });
      kids.push(h("label", { key: "in-user", className: "odc-field" },
        h("span", null, "账号（可选）"),
        h("input", {
          type: "text", autoComplete: "off", value: username,
          onChange: function (ev) { setUsername(ev.target.value); }
        })));
      kids.push(h("span", { key: "acts", className: "odc-actions" },
        h("button", { className: "odc-btn odc-btn-primary", disabled: busy, onClick: fulfill }, busy ? "提交中…" : "提交并存入凭据库"),
        h("button", { className: "odc-btn odc-btn-text", disabled: busy, onClick: function () { setOpen(false); } }, "收起")));
    } else {
      kids.push(h("span", { key: "acts", className: "odc-actions" },
        h("button", { className: "odc-btn odc-btn-primary", disabled: busy, onClick: function () { setOpen(true); } }, "填写并批准"),
        h("button", { className: "odc-btn odc-btn-text", disabled: busy, onClick: reject }, busy ? "提交中…" : "拒绝")));
    }
    return h("div", { className: "odc-row odc-row-card" }, kids);
  }

  function VaultRequestsFace() {
    var facePair = useFace(Core.fetchVaultRequests);
    var face = facePair[0];
    var load = facePair[1];
    var body = null;
    if (face.phase === "ready") {
      var reqs = (face.data && Array.isArray(face.data.data)) ? face.data.data : [];
      body = reqs.length
        ? reqs.map(function (r) {
            return h(VaultRequestCard, { key: r.request_id, request: r, onChanged: load });
          })
        : h("p", { className: "odc-empty" }, "暂无待办凭据请求（0 件也是真数据）。");
    }
    return faceShell("凭据请求", "独立待办面（与 App 聊天内嵌卡功能对齐、形态差异）：智能体在对话里索要凭据时在此办理。填写的值只进提交请求体，提交后即清、不回显、不落盘；办理结果由服务端落审计（只记动作不记值）。", face, load, body);
  }

  // ---------------- page ----------------
  var FUTURE_FACES = [
    { name: "动态", bar: "棒 2" },
    { name: "想法", bar: "棒 2" },
    { name: "目标", bar: "棒 2" },
    { name: "枢纽", bar: "棒 3" }
  ];

  function OneDayConsolePage() {
    return h("div", { className: "odc-root" },
      h("div", { key: "head", className: "odc-head" },
        h("h2", null, "OneDay 控制台"),
        h("p", { className: "odc-sub" },
          "棒 1：批准裁决＋凭据库只读＋凭据请求待办。凭据流与 App 同构——dashboard 会话 cookie → reveal 换钥（只存 sessionStorage）→ Bearer 调现行网关接口。")),
      h(ApprovalsFace, { key: "appr" }),
      h(VaultEntriesFace, { key: "entries" }),
      h(VaultRequestsFace, { key: "reqs" }),
      h("div", { key: "faces", className: "odc-faces" },
        h("span", { className: "odc-face odc-face-on" }, "批准 · 凭据（棒 1）"),
        FUTURE_FACES.map(function (f) {
          return h("span", { key: f.name, className: "odc-face" }, f.name + " · " + f.bar);
        })));
  }

  window.__HERMES_PLUGINS__.register("oneday-console", OneDayConsolePage);
})();
