/**
 * OneDay Console — dashboard plugin (大活12 网页端对齐).
 *
 * 棒 0 地基 + 棒 1 功能面 (approvals decide + credential vault)
 * + 棒 2 内容三面 (feed activity/posts, ideas, goals)
 * + 棒 3 枢纽面 (work ledger / audit / grants / cron): registers as
 * a native dashboard tab via window.__HERMES_PLUGINS__ and renders
 * with the plugin SDK's React.
 *
 * The logic core (Core) is habitat-agnostic on purpose: it only speaks
 * the live gateway contract over same-origin fetch —
 *   POST /api/env/reveal {key:"API_SERVER_KEY"}  (dashboard session cookie)
 *   GET  /v1/approvals ; POST /v1/approvals/{id}  (Bearer key from reveal)
 *   POST /v1/grants/revoke                        (undo an "always")
 *   GET  /v1/vault/entries                        (metadata only, no values)
 *   GET  /v1/vault/requests?status=pending        (owner mode, master key)
 *   POST /v1/vault/requests/{id}/fulfill          (values go out, never back)
 *   GET  /v1/oneday/ledger[/summary|/{id}]        (hub work ledger, bar 3)
 *   GET  /v1/write-gate/status|decisions|rules ; DELETE rules/{id} (audit)
 *   GET  /v1/grants                               (standing grants, both sources)
 *   GET  /api/jobs                                (cron user-visible projection;
 *                                                  nginx exact location -> gateway)
 *   GET  /health ; GET /v1/capabilities           (hub connection band)
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
    },
    // ---- bar 2: content faces (same gateway, canonical /v1/oneday/*) ----
    fetchActivity: function () { return apiJson("GET", "/v1/write-gate/activity?limit=50"); },
    fetchFeed: function () { return apiJson("GET", "/v1/oneday/feed?days=30"); },
    fetchFeedGeneration: function () { return apiJson("GET", "/v1/oneday/feed/generation"); },
    fetchFeedBrief: function () { return apiJson("GET", "/v1/oneday/meta/brief"); },
    generateFeed: function () { return apiJson("POST", "/v1/oneday/feed/generate", {}); },
    likeFeedPost: function (id, liked) {
      return apiJson("POST", "/v1/oneday/feed/" + encodeURIComponent(id) + "/like", { liked: liked });
    },
    readFeedPost: function (id) {
      return apiJson("POST", "/v1/oneday/feed/" + encodeURIComponent(id) + "/read", {});
    },
    signalFeedPost: function (id) {
      return apiJson("POST", "/v1/oneday/feed/" + encodeURIComponent(id) + "/signal", { type: "discuss" });
    },
    fetchIdeas: function () { return apiJson("GET", "/v1/oneday/ideas"); },
    fetchIdeasGeneration: function () { return apiJson("GET", "/v1/oneday/ideas/generation"); },
    createIdea: function (body) { return apiJson("POST", "/v1/oneday/ideas", body); },
    patchIdea: function (id, body) {
      return apiJson("PATCH", "/v1/oneday/ideas/" + encodeURIComponent(id), body);
    },
    deleteIdea: function (id) {
      return apiJson("DELETE", "/v1/oneday/ideas/" + encodeURIComponent(id));
    },
    fetchGoals: function () { return apiJson("GET", "/v1/oneday/goals"); },
    createGoal: function (body) { return apiJson("POST", "/v1/oneday/goals", body); },
    patchGoal: function (id, body) {
      return apiJson("PATCH", "/v1/oneday/goals/" + encodeURIComponent(id), body);
    },
    deleteGoal: function (id) {
      return apiJson("DELETE", "/v1/oneday/goals/" + encodeURIComponent(id));
    },
    fetchGoalEntries: function (goalId) {
      return apiJson("GET", "/v1/oneday/goals/" + encodeURIComponent(goalId) + "/entries");
    },
    createGoalEntry: function (goalId, body) {
      return apiJson("POST", "/v1/oneday/goals/" + encodeURIComponent(goalId) + "/entries", body);
    },
    deleteGoalEntry: function (goalId, entryId) {
      return apiJson("DELETE", "/v1/oneday/goals/" + encodeURIComponent(goalId) +
        "/entries/" + encodeURIComponent(entryId));
    },
    fetchGoalBriefings: function (goalId) {
      return apiJson("GET", "/v1/oneday/goals/" + encodeURIComponent(goalId) + "/briefings");
    },
    openBriefing: function (goalId, briefingId) {
      return apiJson("POST", "/v1/oneday/goals/" + encodeURIComponent(goalId) +
        "/briefings/" + encodeURIComponent(briefingId) + "/opened", {});
    },
    fetchGoalTasks: function (goalId) {
      return apiJson("GET", "/v1/oneday/goals/" + encodeURIComponent(goalId) + "/tasks");
    },
    // ---- bar 3: hub faces (work ledger / audit / grants / cron) ----
    fetchLedgerSummary: function () { return apiJson("GET", "/v1/oneday/ledger/summary"); },
    fetchLedger: function () { return apiJson("GET", "/v1/oneday/ledger"); },
    fetchLedgerDetail: function (id) {
      return apiJson("GET", "/v1/oneday/ledger/" + encodeURIComponent(id));
    },
    fetchWriteGateStatus: function () { return apiJson("GET", "/v1/write-gate/status"); },
    fetchDecisions: function () { return apiJson("GET", "/v1/write-gate/decisions?limit=50"); },
    fetchWriteGateRules: function () { return apiJson("GET", "/v1/write-gate/rules"); },
    deleteWriteGateRule: function (ruleId) {
      return apiJson("DELETE", "/v1/write-gate/rules/" + encodeURIComponent(ruleId));
    },
    fetchGrants: function () { return apiJson("GET", "/v1/grants"); },
    fetchJobs: function () { return apiJson("GET", "/api/jobs"); },
    fetchCapabilities: function () { return apiJson("GET", "/v1/capabilities"); },
    fetchHealth: function () {
      return fetch("/health").then(function (r) { return r.ok ? r.json() : null; })
        .catch(function () { return null; });
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
  // Dual-format timestamps: bridge faces send epoch seconds (number),
  // the write-gate activity stream sends ISO strings. Both render here.
  function fmtTs(v) {
    if (v == null || v === "") return "";
    var d = (typeof v === "number") ? new Date(v * 1000) : new Date(v);
    if (isNaN(d.getTime())) return String(v);
    return d.toLocaleString();
  }
  function fmtTsShort(v) {
    if (v == null || v === "") return "";
    var d = (typeof v === "number") ? new Date(v * 1000) : new Date(v);
    if (isNaN(d.getTime())) return "";
    return d.toLocaleDateString() + " " + d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
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

  // Ledger wording mirrors the App hub (LedgerBoard.swift LedgerText):
  // list faces use human words only; raw enums stay in detail views.
  var LEDGER_STATUS_WORDS = {
    queued: "排队中",
    running: "进行中",
    blocked_approval: "等待审批",
    completed: "已完成",
    failed: "失败",
    cancelled: "已取消",
    stale: "失联待核"
  };
  var LEDGER_KIND_WORDS = {
    run: "对话运行",
    kanban: "看板任务",
    job: "定时作业",
    approval: "审批",
    device: "设备调用",
    monitor: "监测"
  };
  var LEDGER_SOURCE_WORDS = {
    app: "OneDay 发起",
    dashboard: "控制台",
    cron: "定时任务",
    api: "其他应用",
    bridge: "自动作业",
    device: "设备"
  };
  function ledgerStatusWord(s) { return LEDGER_STATUS_WORDS[s] || "状态未知"; }
  function ledgerKindWord(k) { return LEDGER_KIND_WORDS[k] || (k || "其他"); }
  function ledgerSourceWord(s) { return LEDGER_SOURCE_WORDS[s] || (s || "其他来源"); }
  function ledgerStatusClass(s) {
    if (s === "completed") return "odc-st odc-st-done";
    if (s === "failed") return "odc-st odc-st-failed";
    if (s === "queued" || s === "running" || s === "blocked_approval" || s === "stale") return "odc-st odc-st-pending";
    return "odc-st";
  }

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

  // ---------------- feed face: task流水 (write-gate activity) + posts ----------------
  var ACT_STATUS = {
    pending: { label: "待批", cls: "odc-st-pending" },
    completed: { label: "已完成", cls: "odc-st-done" },
    failed: { label: "有驳回", cls: "odc-st-failed" }
  };
  var SUBSYSTEM_LABELS = { skills: "技能", memory: "记忆" };

  function memberHeadline(m) {
    if (m.summary) return m.summary;
    var sub = SUBSYSTEM_LABELS[m.subsystem] || m.subsystem || "";
    var op = m.op || m.action || "";
    var parts = [];
    if (sub) parts.push(sub);
    if (op) parts.push(op);
    if (m.target_name) parts.push("《" + m.target_name + "》");
    if (m.op_count && m.op_count > 1) parts.push("共 " + m.op_count + " 项");
    return parts.join(" ") || (m.id || "记录");
  }
  function memberStateLine(m) {
    if (m.state === "pending") return "待批 · " + fmtTsShort(m.created_at);
    var word = "已处理";
    if (m.decision === "approved") word = m.via_rule ? "已按规则放行" : "已批准";
    if (m.decision === "rejected") word = "已驳回";
    return word + " · " + fmtTsShort(m.decided_at || m.created_at);
  }

  function ActivityGroupCard(props) {
    var g = props.group;
    var openPair = hooks.useState(false);
    var open = openPair[0];
    var setOpen = openPair[1];
    var st = ACT_STATUS[g.status] || { label: g.status || "", cls: "" };
    var meta = [];
    if (g.counts && g.counts.total > 1) meta.push("共 " + g.counts.total + " 笔");
    if (g.counts && g.counts.pending) meta.push("待批 " + g.counts.pending);
    if (g.tier) meta.push(g.tier);
    meta.push(fmtTsShort(g.updated_at));
    var kids = [
      h("span", { key: "t", className: "odc-row-title" },
        h("span", { className: "odc-st " + st.cls }, st.label), " ", g.title_human || "(无标题)"),
      h("span", { key: "m", className: "odc-row-meta" }, meta.join(" · ")),
    ];
    if (g.preview) kids.push(h("span", { key: "p", className: "odc-preview" }, g.preview));
    kids.push(h("span", { key: "acts", className: "odc-actions" },
      h("button", { className: "odc-btn odc-btn-text", onClick: function () { setOpen(!open); } },
        open ? "收起" : "展开 " + ((g.records || []).length) + " 笔")));
    if (open) {
      (g.records || []).forEach(function (m, i) {
        kids.push(h("div", { key: "rec" + i, className: "odc-member" },
          h("span", { className: "odc-row-title odc-member-title" }, memberHeadline(m)),
          h("span", { className: "odc-row-meta" }, memberStateLine(m)),
          (m.content_preview && m.content_preview !== m.summary)
            ? h("span", { className: "odc-preview" }, m.content_preview) : null));
      });
    }
    return h("div", { className: "odc-row odc-row-card" }, kids);
  }

  var FEED_KIND_LABELS = { research: "调研", morning: "晨报", event: "事件", digest: "汇编" };

  function FeedPostCard(props) {
    var post = props.post;
    var onSettled = props.onSettled;
    var openPair = hooks.useState(false);
    var open = openPair[0];
    var setOpen = openPair[1];
    var busyPair = hooks.useState("");
    var busy = busyPair[0];
    var setBusy = busyPair[1];
    var msgPair = hooks.useState(null);
    var msg = msgPair[0];
    var setMsg = msgPair[1];
    var liked = !!post.likedAt;
    var read = !!post.readAt;

    function toggleOpen() {
      var next = !open;
      setOpen(next);
      if (next && !post.readAt) {
        Core.readFeedPost(post.id).then(function (p) { if (p && p.id) onSettled(p); }, function () { /* read mark is best-effort */ });
      }
    }
    function toggleLike() {
      setBusy("like");
      Core.likeFeedPost(post.id, !liked).then(function (p) {
        setBusy("");
        if (p && p.id) onSettled(p);
      }).catch(function (err) {
        setBusy("");
        setMsg("点赞失败：" + ((err && err.message) || String(err)));
      });
    }
    function discuss() {
      setBusy("signal");
      Core.signalFeedPost(post.id).then(function () {
        setBusy("");
        setMsg("已记下「想聊这篇」，回聊天时可继续。");
      }).catch(function (err) {
        setBusy("");
        setMsg("登记失败：" + ((err && err.message) || String(err)));
      });
    }

    var meta = [];
    if (post.category) meta.push(post.category);
    meta.push(fmtTsShort(post.createdAt));
    if (read) meta.push("已读");
    var kids = [
      h("span", { key: "t", className: "odc-row-title" },
        (post.emoji ? post.emoji + " " : "") + (post.title || "(无标题)")),
      h("span", { key: "m", className: "odc-row-meta" },
        (FEED_KIND_LABELS[post.kind] || post.kind || "") + (meta.length ? " · " + meta.join(" · ") : "")),
    ];
    if (open) {
      if (post.why) kids.push(h("p", { key: "why", className: "odc-preview" }, "为什么选这篇：" + post.why));
      kids.push(h("div", { key: "body", className: "odc-body" }, post.body || ""));
      (post.images || []).forEach(function (img, i) {
        if (img && img.url) kids.push(h("img", { key: "img" + i, className: "odc-img", src: img.url, alt: "" }));
      });
      if (post.sourceCard && post.sourceCard.name) {
        kids.push(h("p", { key: "sc", className: "odc-preview" },
          "来源：" + post.sourceCard.name + (post.sourceCard.description ? " — " + post.sourceCard.description : "")));
      }
      (post.links || []).forEach(function (lnk, i) {
        if (lnk && lnk.url) {
          kids.push(h("a", { key: "lnk" + i, className: "odc-link", href: lnk.url, target: "_blank", rel: "noreferrer" },
            lnk.title || lnk.url));
        }
      });
    }
    if (msg) kids.push(h("p", { key: "msg", className: "odc-done" }, msg));
    kids.push(h("span", { key: "acts", className: "odc-actions" },
      h("button", { className: "odc-btn odc-btn-text", onClick: toggleOpen }, open ? "收起" : "展开"),
      h("button", { className: "odc-btn odc-btn-text", disabled: busy === "like", onClick: toggleLike },
        liked ? "♥ 已赞" : "♡ 点赞"),
      h("button", { className: "odc-btn odc-btn-text", disabled: busy === "signal", onClick: discuss }, "想聊这篇")));
    return h("div", { className: "odc-row odc-row-card" }, kids);
  }

  function FeedFace() {
    var actPair = useFace(Core.fetchActivity);
    var act = actPair[0];
    var actLoad = actPair[1];
    var postsPair = useFace(function () {
      return Core.fetchFeed().then(function (feed) {
        return Promise.all([
          Core.fetchFeedGeneration().catch(function () { return null; }),
          Core.fetchFeedBrief().catch(function () { return null; })
        ]).then(function (r) { return { feed: feed, gen: r[0], brief: r[1] }; });
      });
    });
    var posts = postsPair[0];
    var postsLoad = postsPair[1];
    var postsSet = postsPair[2];
    var genBusyPair = hooks.useState(false);
    var genBusy = genBusyPair[0];
    var setGenBusy = genBusyPair[1];
    var genMsgPair = hooks.useState(null);
    var genMsg = genMsgPair[0];
    var setGenMsg = genMsgPair[1];

    function settlePost(p) {
      if (!posts.data) return;
      var items = (posts.data.feed.items || []).map(function (x) { return x.id === p.id ? p : x; });
      postsSet({ phase: "ready", error: "", data: { feed: { items: items }, gen: posts.data.gen, brief: posts.data.brief } });
    }
    function generateNow() {
      setGenBusy(true);
      setGenMsg(null);
      Core.generateFeed().then(function () {
        setGenBusy(false);
        setGenMsg({ ok: true, text: "已起一轮生成，稍后刷新查看。" });
        postsLoad();
      }).catch(function (err) {
        setGenBusy(false);
        setGenMsg({ ok: false, text: "没能开始生成（" + ((err && err.message) || String(err)) + "）——生成在跑时桥回 409，属既有口径。" });
      });
    }

    var actBody = null;
    if (act.phase === "ready") {
      var payload = act.data || {};
      if (payload.grouped && (payload.groups || []).length) {
        actBody = payload.groups.map(function (g) { return h(ActivityGroupCard, { key: g.id, group: g }); });
      } else if ((payload.records || []).length) {
        actBody = payload.records.map(function (m, i) {
          return h("div", { key: "flat" + i, className: "odc-row odc-row-card" },
            h("span", { className: "odc-row-title" }, memberHeadline(m)),
            h("span", { className: "odc-row-meta" }, memberStateLine(m)));
        });
      } else {
        actBody = h("p", { className: "odc-empty" }, "暂无任务流水记录。");
      }
    }

    var postsBody = null;
    if (posts.phase === "ready") {
      var items = (posts.data.feed && posts.data.feed.items) || [];
      var gen = posts.data.gen;
      var brief = posts.data.brief;
      var parts = [];
      var seg = gen && (gen.research || gen.morning);
      var genLine = [];
      if (gen && gen.unread != null) genLine.push("未读 " + gen.unread + " 篇");
      if (seg && seg.lastRunAt) genLine.push("上次生成 " + fmtTsShort(seg.lastRunAt));
      if (seg && seg.running) genLine.push("生成中…");
      if (seg && seg.nextRunAt) genLine.push("下次 " + fmtTsShort(seg.nextRunAt));
      parts.push(h("p", { key: "gen", className: "odc-count" }, genLine.length ? genLine.join(" · ") : "生成状态未读到"));
      if (genMsg) parts.push(h("p", { key: "gmsg", className: genMsg.ok ? "odc-done" : "odc-error" }, genMsg.text));
      parts.push(h("span", { key: "gacts", className: "odc-actions" },
        h("button", { className: "odc-btn odc-btn-secondary", disabled: genBusy, onClick: generateNow },
          genBusy ? "提交中…" : "立即生成一轮")));
      if (brief && brief.text) {
        parts.push(h("details", { key: "brief", className: "odc-brief" },
          h("summary", null, "当前简报方向（只读，编辑在 App）" + (brief.polished ? " · 润色稿" : "")),
          h("div", { className: "odc-body" }, brief.text)));
      }
      if (!items.length) {
        parts.push(h("p", { key: "empty", className: "odc-empty" }, "近 30 天暂无动态帖。"));
      }
      items.forEach(function (p) {
        parts.push(h(FeedPostCard, { key: p.id, post: p, onSettled: settlePost }));
      });
      postsBody = parts;
    }

    return h("div", null,
      faceShell("动态 · 任务流水", "写闸记录按归属会话聚合成任务级人话组（与 App 枢纽审核记录同一出口、只读呈现；裁决仍在批准面）。", act, actLoad, actBody),
      faceShell("动态 · 晨报与汇编", "与 App 动态页同一数据源（近 30 天）：点赞/已读/想聊这篇与 App 同口径回执对账。", posts, postsLoad, postsBody));
  }

  // ---------------- ideas face ----------------
  var IDEA_STATUS = {
    pending: "待定", adopted: "已采纳", built: "已落地",
    dismissed: "已忽略", expired: "已过期"
  };
  var IDEA_KIND = { chat: "对话", routine: "例行", goal: "目标" };

  function IdeaCard(props) {
    var idea = props.idea;
    var onChanged = props.onChanged;
    var openPair = hooks.useState(false);
    var open = openPair[0];
    var setOpen = openPair[1];
    var busyPair = hooks.useState("");
    var busy = busyPair[0];
    var setBusy = busyPair[1];
    var msgPair = hooks.useState(null);
    var msg = msgPair[0];
    var setMsg = msgPair[1];

    function act(kind) {
      if (kind === "delete" && !window.confirm("删除这条想法？（与 App 同一删除口）")) return;
      setBusy(kind);
      var call = kind === "delete"
        ? Core.deleteIdea(idea.id)
        : Core.patchIdea(idea.id, kind === "tooGeneric"
            ? { status: "dismissed", dismissReason: "tooGeneric" }
            : { status: "dismissed" });
      call.then(function () {
        setBusy("");
        onChanged();
      }).catch(function (err) {
        setBusy("");
        setMsg("失败：" + ((err && err.message) || String(err)) + "（状态机非法流转时桥回人话，请看回读）");
        onChanged();
      });
    }

    var meta = [];
    if (idea.categoryLabel) meta.push(idea.categoryLabel);
    else if (idea.domain) meta.push(idea.domain);
    if (idea.kind) meta.push(IDEA_KIND[idea.kind] || idea.kind);
    meta.push(idea.source === "generated" ? "生成" : "手记");
    meta.push(fmtTsShort(idea.createdAt));
    if (idea.expiresAt) meta.push("过期 " + fmtTsShort(idea.expiresAt));
    var kids = [
      h("span", { key: "t", className: "odc-row-title" },
        (idea.emoji ? idea.emoji + " " : "") + (idea.title || "(无标题)")),
      h("span", { key: "m", className: "odc-row-meta" },
        (IDEA_STATUS[idea.status] || idea.status || "") + (meta.length ? " · " + meta.join(" · ") : "")),
    ];
    if (idea.evidence) kids.push(h("span", { key: "ev", className: "odc-preview" }, "依据：" + idea.evidence));
    if (open) {
      if (idea.detail) kids.push(h("div", { key: "d", className: "odc-body" }, idea.detail));
      (idea.deliverables || []).forEach(function (d, i) {
        kids.push(h("p", { key: "dl" + i, className: "odc-preview" },
          "交付物：" + (d.name || "") + (d.summary ? " — " + d.summary : "")));
      });
      if (idea.taskId) kids.push(h("p", { key: "tk", className: "odc-preview" }, "已转任务：" + idea.taskId));
      if (idea.dismissReason === "tooGeneric") kids.push(h("p", { key: "dr", className: "odc-preview" }, "忽略原因：太泛了"));
    }
    if (msg) kids.push(h("p", { key: "msg", className: "odc-error" }, msg));
    var actions = [
      h("button", { key: "open", className: "odc-btn odc-btn-text", onClick: function () { setOpen(!open); } },
        open ? "收起" : "详情")
    ];
    if (idea.status === "pending") {
      actions.push(h("button", { key: "dis", className: "odc-btn odc-btn-text", disabled: !!busy, onClick: function () { act("dismiss"); } }, "忽略"));
      actions.push(h("button", { key: "tg", className: "odc-btn odc-btn-text", disabled: !!busy, onClick: function () { act("tooGeneric"); } }, "太泛了"));
      actions.push(h("button", { key: "del", className: "odc-btn odc-btn-text", disabled: !!busy, onClick: function () { act("delete"); } }, "删除"));
    }
    kids.push(h("span", { key: "acts", className: "odc-actions" }, actions));
    return h("div", { className: "odc-row odc-row-card" }, kids);
  }

  function IdeasFace() {
    var facePair = useFace(function () {
      return Core.fetchIdeas().then(function (ideas) {
        return Core.fetchIdeasGeneration().catch(function () { return null; })
          .then(function (gen) { return { ideas: ideas, gen: gen }; });
      });
    });
    var face = facePair[0];
    var load = facePair[1];
    var filterPair = hooks.useState("all");
    var filter = filterPair[0];
    var setFilter = filterPair[1];
    var formPair = hooks.useState(null);
    var form = formPair[0];
    var setForm = formPair[1];
    var busyPair = hooks.useState(false);
    var busy = busyPair[0];
    var setBusy = busyPair[1];
    var msgPair = hooks.useState(null);
    var msg = msgPair[0];
    var setMsg = msgPair[1];

    function create() {
      var title = ((form && form.title) || "").trim();
      if (!title) { setMsg("标题不能为空。"); return; }
      setBusy(true);
      var body = { title: title };
      var detail = ((form && form.detail) || "").trim();
      if (detail) body.detail = detail;
      Core.createIdea(body).then(function () {
        setBusy(false);
        setForm(null);
        setMsg(null);
        load();
      }).catch(function (err) {
        setBusy(false);
        setMsg("新建失败：" + ((err && err.message) || String(err)));
      });
    }

    var body = null;
    if (face.phase === "ready") {
      var items = (face.data.ideas && face.data.ideas.items) || [];
      var gen = face.data.gen;
      var parts = [];
      var counts = {};
      items.forEach(function (i) { counts[i.status] = (counts[i.status] || 0) + 1; });
      var filters = [["all", "全部 " + items.length]]
        .concat(Object.keys(IDEA_STATUS).filter(function (s) { return counts[s]; })
          .map(function (s) { return [s, (IDEA_STATUS[s] || s) + " " + counts[s]]; }));
      parts.push(h("span", { key: "filters", className: "odc-chips" }, filters.map(function (f) {
        return h("button", {
          key: f[0],
          className: "odc-chip odc-chip-btn" + (filter === f[0] ? " odc-chip-on" : ""),
          onClick: function () { setFilter(f[0]); }
        }, f[1]);
      })));
      if (gen) {
        var gl = [];
        if (gen.running) gl.push("生成中…");
        if (gen.lastRunAt) gl.push("上次生成 " + fmtTsShort(gen.lastRunAt));
        if (gen.nextRunAt) gl.push("下次 " + fmtTsShort(gen.nextRunAt));
        var lastHist = (gen.history || [])[0];
        if (lastHist && lastHist.error) gl.push("最近一轮：" + lastHist.error);
        else if (lastHist) gl.push("最近一轮：" + (lastHist.status || "") + " · 产 " + (lastHist.produced || 0) + " 张");
        parts.push(h("p", { key: "gen", className: "odc-row-meta" }, gl.join(" · ")));
      }
      if (msg) parts.push(h("p", { key: "msg", className: "odc-error" }, msg));
      if (form) {
        parts.push(h("div", { key: "form", className: "odc-form" },
          h("label", { className: "odc-field" }, h("span", null, "标题"),
            h("input", {
              type: "text", value: form.title || "",
              onChange: function (ev) { setForm({ title: ev.target.value, detail: form.detail || "" }); }
            })),
          h("label", { className: "odc-field" }, h("span", null, "详情（可选）"),
            h("textarea", {
              rows: 3, value: form.detail || "",
              onChange: function (ev) { setForm({ title: form.title || "", detail: ev.target.value }); }
            })),
          h("span", { className: "odc-actions" },
            h("button", { className: "odc-btn odc-btn-primary", disabled: busy, onClick: create }, busy ? "提交中…" : "新建"),
            h("button", { className: "odc-btn odc-btn-text", onClick: function () { setForm(null); } }, "取消"))));
      } else {
        parts.push(h("span", { key: "new", className: "odc-actions" },
          h("button", { className: "odc-btn odc-btn-secondary", onClick: function () { setForm({ title: "", detail: "" }); } }, "＋ 新建想法")));
      }
      var shown = items.filter(function (i) { return filter === "all" || i.status === filter; });
      if (!shown.length) parts.push(h("p", { key: "empty", className: "odc-empty" }, "这一档暂无想法。"));
      shown.forEach(function (idea) {
        parts.push(h(IdeaCard, { key: idea.id, idea: idea, onChanged: load }));
      });
      body = parts;
    }
    return faceShell("想法", "与 App 想法页同一数据源：生成卡与手记卡同表；忽略/太泛了/删除/新建与 App 同口，采纳转任务仍在对话里办。", face, load, body);
  }

  // ---------------- goals face ----------------
  var GOAL_CATEGORY = {
    health: "健康", relationships: "关系", finance: "财务", career: "事业",
    interest: "兴趣", efficiency: "效率", other: "其他"
  };

  function goalActivityLine(a) {
    if (!a) return "";
    var parts = [];
    if (a.label) parts.push(a.label);
    var counts = [];
    if (a.runningCount) counts.push("运行 " + a.runningCount);
    if (a.blockedCount) counts.push("阻塞 " + a.blockedCount);
    if (a.failedCount) counts.push("失败 " + a.failedCount);
    if (a.waitingCount) counts.push("等待 " + a.waitingCount);
    if (a.doneCount) counts.push("完成 " + a.doneCount);
    if (counts.length) parts.push(counts.join(" · "));
    return parts.join("（") + (counts.length ? "）" : "");
  }

  function GoalDetail(props) {
    var goal = props.goal;
    var pair = hooks.useState(null);
    var data = pair[0];
    var setData = pair[1];
    var entryPair = hooks.useState("");
    var entryText = entryPair[0];
    var setEntryText = entryPair[1];
    var busyPair = hooks.useState("");
    var busy = busyPair[0];
    var setBusy = busyPair[1];
    var msgPair = hooks.useState(null);
    var msg = msgPair[0];
    var setMsg = msgPair[1];
    var openBriefPair = hooks.useState("");
    var openBrief = openBriefPair[0];
    var setOpenBrief = openBriefPair[1];

    function loadDetail() {
      Promise.all([
        Core.fetchGoalEntries(goal.id).catch(function () { return { items: [] }; }),
        Core.fetchGoalBriefings(goal.id).catch(function () { return { items: [] }; }),
        Core.fetchGoalTasks(goal.id).catch(function () { return { items: [] }; })
      ]).then(function (r) {
        setData({ entries: r[0].items || [], briefings: r[1].items || [], tasks: r[2].items || [] });
      });
    }
    hooks.useEffect(function () { loadDetail(); }, []);

    function addEntry() {
      var text = entryText.trim();
      if (!text) return;
      setBusy("entry");
      Core.createGoalEntry(goal.id, { body: text, source: "user" }).then(function () {
        setBusy("");
        setEntryText("");
        loadDetail();
      }).catch(function (err) {
        setBusy("");
        setMsg("记录进展失败：" + ((err && err.message) || String(err)));
      });
    }
    function delEntry(eid) {
      setBusy("del" + eid);
      Core.deleteGoalEntry(goal.id, eid).then(function () {
        setBusy("");
        loadDetail();
      }).catch(function (err) {
        setBusy("");
        setMsg("删除进展失败：" + ((err && err.message) || String(err)));
      });
    }
    function toggleBriefing(b) {
      if (openBrief === b.id) { setOpenBrief(""); return; }
      setOpenBrief(b.id);
      if (!b.lastOpenedAt) Core.openBriefing(goal.id, b.id).then(function () { loadDetail(); }, function () { /* best effort */ });
    }

    if (!data) return h("p", { className: "odc-row-meta" }, "正在读进展/简报/任务……");
    var kids = [];
    if (goal.note) kids.push(h("div", { key: "note", className: "odc-body" }, goal.note));
    if (msg) kids.push(h("p", { key: "msg", className: "odc-error" }, msg));
    kids.push(h("p", { key: "eh", className: "odc-summary-head" }, "进展时间线（新→旧）"));
    if (!data.entries.length) kids.push(h("p", { key: "ee", className: "odc-empty" }, "暂无进展记录。"));
    data.entries.slice().reverse().forEach(function (e) {
      kids.push(h("div", { key: "e" + e.id, className: "odc-member" },
        e.title ? h("span", { className: "odc-row-title odc-member-title" }, e.title) : null,
        h("span", { className: "odc-body odc-entry-body" }, e.body || ""),
        h("span", { className: "odc-row-meta" },
          (e.source === "agent" ? "智能体记账" : "手记") + " · " + fmtTsShort(e.createdAt)),
        h("span", { className: "odc-actions" },
          h("button", {
            className: "odc-btn odc-btn-text", disabled: busy === "del" + e.id,
            onClick: function () { delEntry(e.id); }
          }, "删除此条"))));
    });
    kids.push(h("div", { key: "eform", className: "odc-form" },
      h("label", { className: "odc-field" }, h("span", null, "记一条进展"),
        h("textarea", {
          rows: 2, value: entryText,
          onChange: function (ev) { setEntryText(ev.target.value); }
        })),
      h("span", { className: "odc-actions" },
        h("button", { className: "odc-btn odc-btn-primary", disabled: busy === "entry", onClick: addEntry },
          busy === "entry" ? "提交中…" : "记录进展"))));
    kids.push(h("p", { key: "bh", className: "odc-summary-head" }, "周简报"));
    if (!data.briefings.length) kids.push(h("p", { key: "be", className: "odc-empty" }, "暂无简报。"));
    data.briefings.forEach(function (b) {
      kids.push(h("div", { key: "b" + b.id, className: "odc-member" },
        h("span", { className: "odc-row-title odc-member-title" }, (b.period ? b.period + " · " : "") + (b.title || "简报")),
        h("span", { className: "odc-row-meta" },
          fmtTsShort(b.createdAt) + (b.lastOpenedAt ? " · 已打开" : " · 未打开")),
        openBrief === b.id ? h("div", { className: "odc-body" }, b.body || "") : null,
        b.note && openBrief === b.id ? h("span", { className: "odc-preview" }, b.note) : null,
        h("span", { className: "odc-actions" },
          h("button", { className: "odc-btn odc-btn-text", onClick: function () { toggleBriefing(b); } },
            openBrief === b.id ? "收起" : "打开"))));
    });
    kids.push(h("p", { key: "th", className: "odc-summary-head" }, "关联任务"));
    if (!data.tasks.length) kids.push(h("p", { key: "te", className: "odc-empty" }, "暂无关联任务。"));
    data.tasks.forEach(function (t) {
      kids.push(h("div", { key: "t" + (t.taskId || t.linkId), className: "odc-member" },
        h("span", { className: "odc-row-title odc-member-title" }, t.title || t.taskId || "任务"),
        h("span", { className: "odc-row-meta" },
          (t.status || t.bucket || "") + (t.updatedAt ? " · " + fmtTsShort(t.updatedAt) : ""))));
    });
    return h("div", { className: "odc-detail" }, kids);
  }

  function GoalCard(props) {
    var goal = props.goal;
    var onChanged = props.onChanged;
    var openPair = hooks.useState(false);
    var open = openPair[0];
    var setOpen = openPair[1];
    var editPair = hooks.useState(null);
    var edit = editPair[0];
    var setEdit = editPair[1];
    var busyPair = hooks.useState("");
    var busy = busyPair[0];
    var setBusy = busyPair[1];
    var msgPair = hooks.useState(null);
    var msg = msgPair[0];
    var setMsg = msgPair[1];

    function run(kind, call) {
      setBusy(kind);
      call.then(function () { setBusy(""); setEdit(null); onChanged(); }).catch(function (err) {
        setBusy("");
        setMsg("失败：" + ((err && err.message) || String(err)));
        onChanged();
      });
    }
    var meta = [];
    meta.push(goal.status === "completed" ? "已完成" : "进行中");
    if (goal.category && GOAL_CATEGORY[goal.category]) meta.push(GOAL_CATEGORY[goal.category]);
    if (goal.parentId) meta.push("子目标");
    if (goal.source === "chat") meta.push("对话创建");
    meta.push("更新 " + fmtTsShort(goal.updatedAt));
    var kids = [
      h("span", { key: "t", className: "odc-row-title" }, goal.title || "(无标题)"),
      h("span", { key: "m", className: "odc-row-meta" }, meta.join(" · ")),
    ];
    var actLine = goalActivityLine(goal.activity);
    if (actLine) kids.push(h("span", { key: "a", className: "odc-preview" }, "活动：" + actLine));
    if (goal.latestEntry) {
      kids.push(h("span", { key: "le", className: "odc-preview" },
        "最新进展：" + (goal.latestEntry.title || (goal.latestEntry.body || "").slice(0, 60)) +
        " · " + fmtTsShort(goal.latestEntry.createdAt)));
    }
    if (msg) kids.push(h("p", { key: "msg", className: "odc-error" }, msg));
    if (edit) {
      kids.push(h("div", { key: "edit", className: "odc-form" },
        h("label", { className: "odc-field" }, h("span", null, "标题"),
          h("input", {
            type: "text", value: edit.title,
            onChange: function (ev) { setEdit({ title: ev.target.value, note: edit.note }); }
          })),
        h("label", { className: "odc-field" }, h("span", null, "备注"),
          h("textarea", {
            rows: 2, value: edit.note,
            onChange: function (ev) { setEdit({ title: edit.title, note: ev.target.value }); }
          })),
        h("span", { className: "odc-actions" },
          h("button", {
            className: "odc-btn odc-btn-primary", disabled: busy === "save",
            onClick: function () {
              run("save", Core.patchGoal(goal.id, { title: edit.title.trim(), note: edit.note.trim() }));
            }
          }, busy === "save" ? "提交中…" : "保存"),
          h("button", { className: "odc-btn odc-btn-text", onClick: function () { setEdit(null); } }, "取消"))));
    }
    var actions = [
      h("button", { key: "open", className: "odc-btn odc-btn-text", onClick: function () { setOpen(!open); } },
        open ? "收起详情" : "详情（进展/简报/任务）"),
      h("button", {
        key: "edit", className: "odc-btn odc-btn-text",
        onClick: function () { setEdit({ title: goal.title || "", note: goal.note || "" }); }
      }, "编辑"),
    ];
    if (goal.status === "completed") {
      actions.push(h("button", {
        key: "st", className: "odc-btn odc-btn-text", disabled: !!busy,
        onClick: function () { run("st", Core.patchGoal(goal.id, { status: "active" })); }
      }, "重新打开"));
    } else {
      actions.push(h("button", {
        key: "st", className: "odc-btn odc-btn-text", disabled: !!busy,
        onClick: function () { run("st", Core.patchGoal(goal.id, { status: "completed" })); }
      }, "标记完成"));
    }
    actions.push(h("button", {
      key: "del", className: "odc-btn odc-btn-text", disabled: !!busy,
      onClick: function () {
        if (window.confirm("删除目标「" + (goal.title || "") + "」？（与 App 同一删除口）")) {
          run("del", Core.deleteGoal(goal.id));
        }
      }
    }, "删除"));
    kids.push(h("span", { key: "acts", className: "odc-actions" }, actions));
    if (open) kids.push(h(GoalDetail, { key: "detail", goal: goal }));
    return h("div", { className: "odc-row odc-row-card" }, kids);
  }

  function GoalsFace() {
    var facePair = useFace(Core.fetchGoals);
    var face = facePair[0];
    var load = facePair[1];
    var formPair = hooks.useState(null);
    var form = formPair[0];
    var setForm = formPair[1];
    var busyPair = hooks.useState(false);
    var busy = busyPair[0];
    var setBusy = busyPair[1];
    var msgPair = hooks.useState(null);
    var msg = msgPair[0];
    var setMsg = msgPair[1];
    var showDonePair = hooks.useState(false);
    var showDone = showDonePair[0];
    var setShowDone = showDonePair[1];

    function create() {
      var title = ((form && form.title) || "").trim();
      if (!title) { setMsg("标题不能为空。"); return; }
      setBusy(true);
      var body = { title: title, source: "manual" };
      var note = ((form && form.note) || "").trim();
      if (note) body.note = note;
      if (form && form.parentId) body.parentId = form.parentId;
      Core.createGoal(body).then(function () {
        setBusy(false);
        setForm(null);
        setMsg(null);
        load();
      }).catch(function (err) {
        setBusy(false);
        setMsg("新建失败：" + ((err && err.message) || String(err)));
      });
    }

    var body = null;
    if (face.phase === "ready") {
      var items = (face.data && face.data.items) || [];
      var active = items.filter(function (g) { return g.status !== "completed"; });
      var done = items.filter(function (g) { return g.status === "completed"; });
      var topLevel = items.filter(function (g) { return !g.parentId; });
      var parts = [];
      parts.push(h("p", { key: "count", className: "odc-count" },
        "进行中 ", h("strong", null, String(active.length)), " 个 · 已完成 ", h("strong", null, String(done.length)), " 个（与 App 同一数据源，网页端新建 App 侧可见、反之亦然）"));
      if (msg) parts.push(h("p", { key: "msg", className: "odc-error" }, msg));
      if (form) {
        parts.push(h("div", { key: "form", className: "odc-form" },
          h("label", { className: "odc-field" }, h("span", null, "标题"),
            h("input", {
              type: "text", value: form.title || "",
              onChange: function (ev) { setForm({ title: ev.target.value, note: form.note || "", parentId: form.parentId || "" }); }
            })),
          h("label", { className: "odc-field" }, h("span", null, "备注（可选）"),
            h("textarea", {
              rows: 2, value: form.note || "",
              onChange: function (ev) { setForm({ title: form.title || "", note: ev.target.value, parentId: form.parentId || "" }); }
            })),
          h("label", { className: "odc-field" }, h("span", null, "父目标（可选，只能挂顶层目标）"),
            h("select", {
              value: form.parentId || "",
              onChange: function (ev) { setForm({ title: form.title || "", note: form.note || "", parentId: ev.target.value }); }
            },
              h("option", { value: "" }, "（顶层目标）"),
              topLevel.map(function (g) { return h("option", { key: g.id, value: g.id }, g.title); }))),
          h("span", { className: "odc-actions" },
            h("button", { className: "odc-btn odc-btn-primary", disabled: busy, onClick: create }, busy ? "提交中…" : "新建目标"),
            h("button", { className: "odc-btn odc-btn-text", onClick: function () { setForm(null); } }, "取消"))));
      } else {
        parts.push(h("span", { key: "new", className: "odc-actions" },
          h("button", { className: "odc-btn odc-btn-secondary", onClick: function () { setForm({ title: "", note: "", parentId: "" }); } }, "＋ 新建目标")));
      }
      if (!active.length) parts.push(h("p", { key: "ae", className: "odc-empty" }, "暂无进行中目标。"));
      active.forEach(function (g) { parts.push(h(GoalCard, { key: g.id, goal: g, onChanged: load })); });
      if (done.length) {
        parts.push(h("span", { key: "dt", className: "odc-actions" },
          h("button", { className: "odc-btn odc-btn-text", onClick: function () { setShowDone(!showDone); } },
            (showDone ? "收起" : "展开") + "已完成 " + done.length + " 个")));
        if (showDone) done.forEach(function (g) { parts.push(h(GoalCard, { key: g.id, goal: g, onChanged: load })); });
      }
      body = parts;
    }
    return faceShell("目标", "与 App 目标页同一数据源：新建/编辑/完成/删除、进展记录、周简报、关联任务与活动流同口径。", face, load, body);
  }

  // ---------------- hub work face (bar 3, gap #6) ----------------
  function LedgerItem(props) {
    var item = props.item;
    var openPair = hooks.useState(false);
    var open = openPair[0];
    var setOpen = openPair[1];
    var detPair = hooks.useState(null); // null | "loading" | detail object | "error"
    var det = detPair[0];
    var setDet = detPair[1];
    function toggle() {
      var next = !open;
      setOpen(next);
      if (next && det === null) {
        setDet("loading");
        Core.fetchLedgerDetail(item.id).then(function (d) { setDet(d); })
          .catch(function () { setDet("error"); });
      }
    }
    var parts = [];
    parts.push(h("div", { key: "hd", className: "odc-actions", style: { justifyContent: "space-between" } },
      h("span", { key: "t", className: "odc-row-title" }, item.title || "（无标题）"),
      h("span", { key: "s", className: ledgerStatusClass(item.status) }, ledgerStatusWord(item.status))));
    var meta = [ledgerKindWord(item.kind), ledgerSourceWord(item.source), fmtTsShort(item.startedAt)];
    if (item.endedAt) meta.push("结束 " + fmtTsShort(item.endedAt));
    parts.push(h("p", { key: "m", className: "odc-row-meta" }, meta.filter(Boolean).join(" · ")));
    if (item.status === "failed" && item.failReason && item.failReason.excerpt) {
      parts.push(h("p", { key: "f", className: "odc-error" },
        (item.failReason.category ? item.failReason.category + "：" : "") + item.failReason.excerpt));
    }
    parts.push(h("span", { key: "tg", className: "odc-actions" },
      h("button", { className: "odc-btn odc-btn-text odc-btn-small", onClick: toggle }, open ? "收起详情" : "详情")));
    if (open) {
      if (det === "loading" || det === null) {
        parts.push(h("p", { key: "d", className: "odc-row-meta" }, "正在读取详情……"));
      } else if (det === "error") {
        parts.push(h("p", { key: "d", className: "odc-error" }, "详情读取失败，可刷新本面重试。"));
      } else {
        var dparts = [];
        if (det.summary) dparts.push(h("p", { key: "sum", className: "odc-body" }, det.summary));
        var hist = Array.isArray(det.history) ? det.history : [];
        if (hist.length) {
          dparts.push(h("div", { key: "hist", className: "odc-detail" },
            h("p", { className: "odc-summary-head" }, "状态变迁"),
            hist.map(function (ev, i) {
              return h("p", { key: i, className: "odc-summary-line" },
                fmtTs(ev.at) + "：" + ledgerStatusWord(ev.from || "") + " → " + ledgerStatusWord(ev.to || "") +
                (ev.by ? "（" + ev.by + "）" : ""));
            })));
        }
        var tech = [];
        tech.push("编号 " + det.id);
        if (det.origin) tech.push("记账 " + det.origin);
        if (det.titleSource) tech.push("标题来源 " + det.titleSource);
        if (det.link && det.link.targetId) tech.push("关联 " + (det.link.kind || "") + "/" + det.link.targetId);
        if (det.evidenceLagging) tech.push("证据滞后");
        dparts.push(h("p", { key: "tech", className: "odc-row-meta" }, tech.join(" · ")));
        parts.push(h("div", { key: "d", className: "odc-detail" }, dparts));
      }
    }
    return h("li", { className: "odc-row odc-row-card" }, parts);
  }

  function HubFace() {
    var facePair = useFace(function () {
      return Promise.all([
        Core.fetchLedgerSummary(),
        Core.fetchLedger(),
        Core.fetchHealth(),
        Core.fetchCapabilities().catch(function () { return null; })
      ]).then(function (r) {
        return { summary: r[0], ledger: r[1], health: r[2], caps: r[3] };
      });
    });
    var face = facePair[0];
    var load = facePair[1];
    var body = null;
    if (face.phase === "ready") {
      var d = face.data;
      var s = d.summary || {};
      var items = (d.ledger && d.ledger.items) || [];
      var parts = [];
      // connection band
      var conn = [];
      if (d.health) {
        conn.push("网关健康：" + (d.health.status || "ok") + "（Hermes " + (d.health.version || "?") + "）");
      } else {
        conn.push("网关健康：读不到（/health 未应答）");
      }
      if (d.caps && d.caps.version_gate) {
        conn.push("App 版本门：最低 " + d.caps.version_gate.min_app_version +
          " / 推荐 " + d.caps.version_gate.recommended_app_version);
      }
      if (s.collectorHeartbeatAt && s.serverNow) {
        conn.push("台账采集心跳：" + Math.max(0, Math.round(s.serverNow - s.collectorHeartbeatAt)) + " 秒前");
      }
      if (s.ledgerUpdatedAt) conn.push("台账更新于 " + fmtTsShort(s.ledgerUpdatedAt));
      parts.push(h("p", { key: "conn", className: "odc-summary-line" }, conn.join(" · ")));
      if (s.degraded) {
        parts.push(h("p", { key: "deg", className: "odc-warn" }, "台账处于降级状态：个别来源暂不可读，计数可能不全。"));
      }
      // counts
      var counts = [
        ["进行中", s.inProgress], ["等待审批", s.blockedApproval], ["失联待核", s.stale],
        ["今日完成", s.todayCompleted], ["今日失败", s.todayFailed], ["今日取消", s.todayCancelled],
        ["总条目", s.total]
      ];
      parts.push(h("div", { key: "counts", className: "odc-counts" }, counts.map(function (c) {
        return h("div", { key: c[0], className: "odc-count-cell" },
          h("div", { className: "odc-count-num" }, c[1] == null ? "—" : String(c[1])),
          h("div", { className: "odc-row-meta" }, c[0]));
      })));
      // kind chips over the returned window
      var kindCounts = {};
      items.forEach(function (it) { kindCounts[it.kind] = (kindCounts[it.kind] || 0) + 1; });
      var kindKeys = Object.keys(kindCounts).sort(function (a, b) { return kindCounts[b] - kindCounts[a]; });
      if (kindKeys.length) {
        parts.push(h("div", { key: "kinds", className: "odc-chips" }, kindKeys.map(function (k) {
          return h("span", { key: k, className: "odc-chip" }, ledgerKindWord(k) + " " + kindCounts[k]);
        })));
        parts.push(h("p", { key: "kn", className: "odc-row-meta" },
          "分类计数按本次回读窗口（最近 " + items.length + " 条）统计，总量以台账摘要为准。"));
      }
      if (!items.length) {
        parts.push(h("p", { key: "e", className: "odc-empty" }, "台账暂无条目。"));
      } else {
        parts.push(h("ul", { key: "list", className: "odc-list" },
          items.slice(0, 30).map(function (it) { return h(LedgerItem, { key: it.id, item: it }); })));
        if (items.length > 30) {
          parts.push(h("p", { key: "more", className: "odc-row-meta" }, "仅显示最近 30 条，共回读 " + items.length + " 条。"));
        }
      }
      body = parts;
    }
    return faceShell("枢纽 · 工作台账", "与 App 枢纽工作面同一台账（/v1/oneday/ledger）：计数摘要＋最近条目＋详情下钻（状态变迁）。只读呈现，裁决仍在批准面。", face, load, body);
  }

  // ---------------- hub audit face (bar 3, gap #7) ----------------
  function AuditFace() {
    var facePair = useFace(function () {
      return Promise.all([
        Core.fetchWriteGateStatus(),
        Core.fetchDecisions(),
        Core.fetchWriteGateRules()
      ]).then(function (r) { return { status: r[0], decisions: r[1], rules: r[2] }; });
    });
    var face = facePair[0];
    var load = facePair[1];
    var busyPair = hooks.useState({});
    var busy = busyPair[0];
    var setBusy = busyPair[1];
    var notePair = hooks.useState("");
    var note = notePair[0];
    var setNote = notePair[1];
    function revokeRule(rule) {
      var next = {}; Object.keys(busy).forEach(function (k) { next[k] = busy[k]; });
      next[rule.id] = true; setBusy(next);
      setNote("");
      Core.deleteWriteGateRule(rule.id).then(function () {
        load(); // verdict by read-back, same rule as the App hub
      }).catch(function (err) {
        setNote("撤销没成（" + ((err && err.message) || err) + "），已按服务端真值重读。");
        load();
      }).then(function () {
        var n2 = {}; Object.keys(busy).forEach(function (k) { n2[k] = busy[k]; });
        delete n2[rule.id]; setBusy(n2);
      });
    }
    var body = null;
    if (face.phase === "ready") {
      var d = face.data;
      var parts = [];
      var st = d.status || {};
      var counts = st.counts || {};
      parts.push(h("p", { key: "st", className: "odc-summary-line" },
        "写闸" + (st.supported ? "在位" : "未在位") +
        " · 待处理：记忆 " + (counts.memory || 0) + " / 技能 " + (counts.skills || 0)));
      if (note) parts.push(h("p", { key: "note", className: "odc-warn" }, note));
      var decisions = (d.decisions && d.decisions.decisions) || [];
      parts.push(h("p", { key: "dh", className: "odc-summary-head" }, "决策记录（锚点时间线，最近 " + decisions.length + " 条）"));
      if (!decisions.length) {
        parts.push(h("p", { key: "de", className: "odc-empty" }, "暂无决策记录。"));
      } else {
        parts.push(h("ul", { key: "dl", className: "odc-list" }, decisions.map(function (rec) {
          var word = DECIDED_LABELS[rec.decision] || rec.decision || "";
          var cls = rec.decision === "approved" ? "odc-st odc-st-done"
            : (rec.decision === "denied" || rec.decision === "smart_denied") ? "odc-st odc-st-failed" : "odc-st";
          var meta = [rec.subsystem, rec.origin, fmtTs(rec.decided_at || rec.created_at)];
          if (rec.anchor && rec.anchor.tier) meta.push("锚点 " + rec.anchor.tier);
          if (rec.op_count) meta.push(rec.op_count + " 项操作");
          return h("li", { key: rec.id, className: "odc-row odc-row-card" },
            h("div", { className: "odc-actions", style: { justifyContent: "space-between" } },
              h("span", { className: "odc-row-title" }, rec.summary || rec.action || rec.id),
              h("span", { className: cls }, word)),
            h("p", { className: "odc-row-meta" }, meta.filter(Boolean).join(" · ")));
        })));
      }
      var rules = (d.rules && d.rules.rules) || [];
      parts.push(h("p", { key: "rh", className: "odc-summary-head" }, "写闸规矩（" + rules.length + " 条）"));
      if (!rules.length) {
        parts.push(h("p", { key: "re", className: "odc-empty" }, "暂无写闸规矩。"));
      } else {
        parts.push(h("ul", { key: "rl", className: "odc-list" }, rules.map(function (rule) {
          return h("li", { key: rule.id, className: "odc-row" },
            h("span", null,
              h("span", { className: "odc-row-title" }, (rule.subsystem || "") + " · " + (rule.origin || "")),
              h("p", { className: "odc-row-meta" }, "立于 " + fmtTs(rule.created_at))),
            h("button", {
              className: "odc-btn odc-btn-text", disabled: !!busy[rule.id],
              onClick: function () { revokeRule(rule); }
            }, busy[rule.id] ? "撤销中…" : "撤销"));
        })));
      }
      body = parts;
    }
    return faceShell("枢纽 · 审计", "与 App 枢纽审计面同源：写闸状态＋决策记录（带会话锚点）＋写闸规矩。撤销规矩以事后回读为准。", face, load, body);
  }

  // ---------------- grants face (bar 3, gap #13, full management) ----------------
  function GrantsFace() {
    var facePair = useFace(Core.fetchGrants);
    var face = facePair[0];
    var load = facePair[1];
    var busyPair = hooks.useState({});
    var busy = busyPair[0];
    var setBusy = busyPair[1];
    var notePair = hooks.useState("");
    var note = notePair[0];
    var setNote = notePair[1];
    function revoke(grant) {
      var next = {}; Object.keys(busy).forEach(function (k) { next[k] = busy[k]; });
      next[grant.grant_key] = true; setBusy(next);
      setNote("");
      var p = grant.source === "writegate"
        ? Core.deleteWriteGateRule(grant.rule_id)
        : Core.revokeGrant(grant.source, grant.pattern_key);
      p.then(function () {
        load(); // verdict by read-back (App hub rule)
      }).catch(function (err) {
        setNote("撤销没成（" + ((err && err.message) || err) + "），已按服务端真值重读。");
        load();
      }).then(function () {
        var n2 = {}; Object.keys(busy).forEach(function (k) { n2[k] = busy[k]; });
        delete n2[grant.grant_key]; setBusy(n2);
      });
    }
    var body = null;
    if (face.phase === "ready") {
      var d = face.data || {};
      var grants = d.grants || [];
      var parts = [];
      if (d.partial) {
        parts.push(h("p", { key: "part", className: "odc-warn" },
          "有一源读不到，清单不完整（" + ((d.source_errors || []).join("、") || "未知") + "）。"));
      }
      if (d.projection_degraded) {
        parts.push(h("p", { key: "deg", className: "odc-warn" }, "授权投影处于降级状态，个别条目元数据可能不全。"));
      }
      if (note) parts.push(h("p", { key: "note", className: "odc-warn" }, note));
      parts.push(h("p", { key: "cnt", className: "odc-count" },
        "当前已立规矩：" + grants.length + " 条（命令授权 " +
        (d.exec_count == null ? "读不到" : d.exec_count) + " · 写闸规矩 " +
        (d.writegate_count == null ? "读不到" : d.writegate_count) + "）"));
      if (!grants.length) {
        parts.push(h("p", { key: "e", className: "odc-empty" }, "暂无已立规矩。在批准面选「总是允许这一类」后，规矩会出现在这里。"));
      } else {
        var groups = [
          { source: "exec", title: "命令授权" },
          { source: "writegate", title: "写闸规矩" }
        ];
        groups.forEach(function (g) {
          var rows = grants.filter(function (x) { return x.source === g.source; });
          if (!rows.length) return;
          parts.push(h("p", { key: "h-" + g.source, className: "odc-summary-head" }, g.title + "（" + rows.length + "）"));
          parts.push(h("ul", { key: "l-" + g.source, className: "odc-list" }, rows.map(function (grant) {
            var meta = [];
            if (grant.granted_at) meta.push("立于 " + fmtTs(grant.granted_at));
            if (grant.source_decision) meta.push("来自裁决 " + grant.source_decision);
            meta.push(grant.status || "active");
            return h("li", { key: grant.grant_key, className: "odc-row" },
              h("span", null,
                h("span", { className: "odc-row-title" }, grant.scope_label || grant.pattern_key || grant.grant_key),
                h("p", { className: "odc-row-meta" }, meta.join(" · "))),
              h("button", {
                className: "odc-btn odc-btn-text", disabled: !!busy[grant.grant_key],
                onClick: function () { revoke(grant); }
              }, busy[grant.grant_key] ? "撤销中…" : "撤销"));
          })));
        });
      }
      body = parts;
    }
    return faceShell("授权管理 · 规矩", "与 App 设置授权节同一清单（GET /v1/grants 双源投影）：在批准时选「总是允许」立下的规矩全量列在这里，逐条可撤销；命令授权走网关撤销口、写闸规矩走写闸规则口（服务端单一写者口径），成败以回读为准。", face, load, body);
  }

  // ---------------- cron face (bar 3, user-visible projection) ----------------
  var JOB_STATUS_WORDS = { ok: "成功", success: "成功", error: "失败", failed: "失败", skipped: "跳过", running: "运行中" };
  function CronFace() {
    var facePair = useFace(Core.fetchJobs);
    var face = facePair[0];
    var load = facePair[1];
    var body = null;
    if (face.phase === "ready") {
      var jobs = (face.data && face.data.jobs) || [];
      var parts = [];
      var sysCount = jobs.filter(function (j) { return j.is_system; }).length;
      var offCount = jobs.filter(function (j) { return !j.enabled; }).length;
      parts.push(h("p", { key: "cnt", className: "odc-count" },
        "共 " + jobs.length + " 个定时任务 · 系统任务 " + sysCount + " 个 · 已停用 " + offCount + " 个"));
      if (!jobs.length) {
        parts.push(h("p", { key: "e", className: "odc-empty" }, "暂无定时任务。"));
      } else {
        parts.push(h("ul", { key: "list", className: "odc-list" }, jobs.map(function (job) {
          var sched = job.schedule_display ||
            (job.schedule && (job.schedule.display || job.schedule.expr)) || "";
          var meta = [];
          if (sched) meta.push(sched);
          if (job.next_run_at) meta.push("下次 " + fmtTs(job.next_run_at));
          if (job.last_run_at) {
            meta.push("上次 " + fmtTs(job.last_run_at) +
              (job.last_status ? "（" + (JOB_STATUS_WORDS[job.last_status] || job.last_status) + "）" : ""));
          }
          var badges = [];
          if (job.is_system) badges.push(h("span", { key: "sys", className: "odc-st" }, "系统任务"));
          if (!job.enabled) badges.push(h("span", { key: "off", className: "odc-st odc-st-failed" }, "已停用"));
          else if (job.state) badges.push(h("span", { key: "st", className: "odc-st" }, job.state));
          return h("li", { key: job.id, className: "odc-row odc-row-card" },
            h("div", { className: "odc-actions", style: { justifyContent: "space-between" } },
              h("span", { className: "odc-row-title" }, job.name || job.id),
              h("span", { className: "odc-chips" }, badges)),
            h("p", { className: "odc-row-meta" }, meta.join(" · ")));
        })));
      }
      body = parts;
    }
    return faceShell("定时任务", "用户可见口径（网关 /api/jobs 投影：系统任务带标记，与 App 定时任务面同一分类）。只读总览；建改与启停在 dashboard 的 Cron 页办。", face, load, body);
  }

  // ---------------- page ----------------
  var NAV_ITEMS = [
    { id: "odc-face-approvals", label: "批准" },
    { id: "odc-face-entries", label: "凭据库" },
    { id: "odc-face-requests", label: "凭据请求" },
    { id: "odc-face-feed", label: "动态" },
    { id: "odc-face-ideas", label: "想法" },
    { id: "odc-face-goals", label: "目标" },
    { id: "odc-face-hub", label: "枢纽" },
    { id: "odc-face-audit", label: "审计" },
    { id: "odc-face-grants", label: "规矩" },
    { id: "odc-face-cron", label: "定时任务" }
  ];

  function scrollToFace(id) {
    var el = document.getElementById(id);
    if (el && el.scrollIntoView) el.scrollIntoView({ behavior: "smooth", block: "start" });
  }

  function OneDayConsolePage() {
    return h("div", { className: "odc-root" },
      h("div", { key: "head", className: "odc-head" },
        h("h2", null, "OneDay 控制台"),
        h("p", { className: "odc-sub" },
          "棒 3：批准＋凭据（棒 1）＋动态/想法/目标（棒 2）＋枢纽台账/审计、授权管理、定时任务（棒 3）。凭据流与 App 同构——dashboard 会话 cookie → reveal 换钥（只存 sessionStorage）→ Bearer 调现行网关接口；各面与 App 同一数据源。")),
      h("div", { key: "w-appr", id: "odc-face-approvals", className: "odc-anchor" }, h(ApprovalsFace, null)),
      h("div", { key: "w-entries", id: "odc-face-entries", className: "odc-anchor" }, h(VaultEntriesFace, null)),
      h("div", { key: "w-reqs", id: "odc-face-requests", className: "odc-anchor" }, h(VaultRequestsFace, null)),
      h("div", { key: "w-feed", id: "odc-face-feed", className: "odc-anchor" }, h(FeedFace, null)),
      h("div", { key: "w-ideas", id: "odc-face-ideas", className: "odc-anchor" }, h(IdeasFace, null)),
      h("div", { key: "w-goals", id: "odc-face-goals", className: "odc-anchor" }, h(GoalsFace, null)),
      h("div", { key: "w-hub", id: "odc-face-hub", className: "odc-anchor" }, h(HubFace, null)),
      h("div", { key: "w-audit", id: "odc-face-audit", className: "odc-anchor" }, h(AuditFace, null)),
      h("div", { key: "w-grants", id: "odc-face-grants", className: "odc-anchor" }, h(GrantsFace, null)),
      h("div", { key: "w-cron", id: "odc-face-cron", className: "odc-anchor" }, h(CronFace, null)),
      h("nav", { key: "faces", className: "odc-faces", "aria-label": "功能面导航" },
        NAV_ITEMS.map(function (n) {
          return h("button", {
            key: n.id, className: "odc-face odc-face-nav", type: "button",
            onClick: function () { scrollToFace(n.id); }
          }, n.label);
        })));
  }

  window.__HERMES_PLUGINS__.register("oneday-console", OneDayConsolePage);
})();
