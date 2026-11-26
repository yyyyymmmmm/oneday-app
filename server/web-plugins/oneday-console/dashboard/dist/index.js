/**
 * OneDay Console — dashboard plugin (大活12 网页端对齐, 棒 0 地基).
 *
 * Route A shell: registers as a native dashboard tab via
 * window.__HERMES_PLUGINS__ and renders with the plugin SDK's React.
 *
 * The logic core (Core) is habitat-agnostic on purpose: it only speaks
 * the live gateway contract over same-origin fetch —
 *   POST /api/env/reveal {key:"API_SERVER_KEY"}  (dashboard session cookie)
 *   GET  /v1/approvals                            (Bearer key from reveal)
 * Route B (standalone SPA under /oneday/) reuses the same core verbatim;
 * only this shell would change. No credentials are ever baked into this
 * file; the revealed key lives in sessionStorage only (tab-scoped,
 * gone when the tab closes) and is never logged.
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

  function apiGet(path, key) {
    return fetch(path, {
      method: "GET",
      credentials: "same-origin",
      headers: { "Authorization": "Bearer " + key }
    });
  }

  // One real data path: pending approvals, same endpoint the App reads.
  function fetchApprovals() {
    var key = sessionGet();
    var first = key ? apiGet("/v1/approvals", key) : Promise.reject({ stale: true });
    return first.then(function (resp) {
      if (resp.status === 401) throw { stale: true };
      if (!resp.ok) throw new Error("approvals 应答 " + resp.status);
      return resp.json();
    }).catch(function (e) {
      if (!e || !e.stale) throw e;
      sessionClear();
      return revealKey().then(function (fresh) {
        return apiGet("/v1/approvals", fresh).then(function (resp) {
          if (!resp.ok) throw new Error("approvals 应答 " + resp.status);
          return resp.json();
        });
      });
    });
  }

  function extractItems(payload) {
    if (Array.isArray(payload)) return payload;
    if (payload && typeof payload === "object") {
      var preferred = ["items", "approvals", "records", "pending", "data"];
      for (var i = 0; i < preferred.length; i++) {
        if (Array.isArray(payload[preferred[i]])) return payload[preferred[i]];
      }
      for (var k in payload) {
        if (Array.isArray(payload[k])) return payload[k];
      }
    }
    return [];
  }

  function itemLabel(it) {
    if (!it || typeof it !== "object") return String(it);
    return it.title_human || it.title || it.summary || it.description ||
      it.action || it.tool_name || it.request_id || it.id || "待批项";
  }

  function itemMeta(it) {
    if (!it || typeof it !== "object") return "";
    var bits = [];
    if (it.session_id) bits.push("会话 " + String(it.session_id).slice(0, 8));
    if (it.created_at) bits.push(String(it.created_at));
    else if (it.timestamp) bits.push(String(it.timestamp));
    return bits.join(" · ");
  }

  var Core = {
    revealKey: revealKey,
    fetchApprovals: fetchApprovals,
    extractItems: extractItems,
    itemLabel: itemLabel,
    itemMeta: itemMeta
  };
  window.__ONEDAY_CONSOLE_CORE__ = Core;

  // ---------------- route A shell (dashboard plugin) ----------------
  var SDK = window.__HERMES_PLUGIN_SDK__;
  if (!SDK || !window.__HERMES_PLUGINS__) return;

  var React = SDK.React;
  var h = React.createElement;
  var hooks = SDK.hooks;
  var C = SDK.components || {};
  var Card = C.Card || function (p) { return h("div", { className: "odc-card" }, p.children); };
  var CardContent = C.CardContent || function (p) { return h("div", null, p.children); };

  var FUTURE_FACES = [
    { name: "凭据库", bar: "棒 1" },
    { name: "动态", bar: "棒 2" },
    { name: "想法", bar: "棒 2" },
    { name: "目标", bar: "棒 2" },
    { name: "枢纽", bar: "棒 3" }
  ];

  function OneDayConsolePage() {
    var statePair = hooks.useState({ phase: "loading", items: [], error: "" });
    var state = statePair[0];
    var setState = statePair[1];

    var load = hooks.useCallback(function () {
      setState({ phase: "loading", items: [], error: "" });
      Core.fetchApprovals().then(function (payload) {
        setState({ phase: "ready", items: Core.extractItems(payload), error: "" });
      }).catch(function (err) {
        setState({ phase: "error", items: [], error: (err && err.message) || String(err) });
      });
    }, []);

    hooks.useEffect(function () { load(); }, [load]);

    var children = [
      h("div", { key: "head", className: "odc-head" },
        h("h2", null, "OneDay 控制台"),
        h("p", { className: "odc-sub" },
          "地基验证页（棒 0）：凭据链 reveal → Bearer → /v1/approvals 已走通；" +
          "下方待批数为网关真数据。各功能面按棒次落地。")
      )
    ];

    if (state.phase === "loading") {
      children.push(h(Card, { key: "c" }, h(CardContent, null,
        h("p", null, "正在经 dashboard 会话换钥并读取待批……"))));
    } else if (state.phase === "error") {
      children.push(h(Card, { key: "c" }, h(CardContent, null,
        h("p", null, "读取失败：" + state.error),
        h("button", { className: "odc-btn", onClick: load }, "重试"))));
    } else {
      var rows = state.items.slice(0, 10).map(function (it, i) {
        return h("li", { key: String(i), className: "odc-row" },
          h("span", { className: "odc-row-title" }, Core.itemLabel(it)),
          h("span", { className: "odc-row-meta" }, Core.itemMeta(it)));
      });
      children.push(h(Card, { key: "c" }, h(CardContent, null,
        h("p", { className: "odc-count" },
          "当前待批：", h("strong", null, String(state.items.length)), " 件（与 App 同一接口）"),
        state.items.length
          ? h("ul", { className: "odc-list" }, rows)
          : h("p", { className: "odc-empty" }, "暂无待批，批准面施工在棒 1 落地处理动作。"),
        h("button", { className: "odc-btn", onClick: load }, "刷新"))));
    }

    children.push(h("div", { key: "faces", className: "odc-faces" },
      h("span", { className: "odc-face odc-face-on" }, "批准（本地基）"),
      FUTURE_FACES.map(function (f) {
        return h("span", { key: f.name, className: "odc-face" }, f.name + " · " + f.bar);
      })));

    return h("div", { className: "odc-root" }, children);
  }

  window.__HERMES_PLUGINS__.register("oneday-console", OneDayConsolePage);
})();
