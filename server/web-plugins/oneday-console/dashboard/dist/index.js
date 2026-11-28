/**
 * OneDay Console — dashboard plugin (大活12 网页端对齐).
 *
 * 棒 0 地基 + 棒 1 功能面 (approvals decide + credential vault)
 * + 棒 2 内容三面 (feed activity/posts, ideas, goals)
 * + 棒 3 枢纽面 (work ledger / audit / grants / cron)
 * + 棒 4 管理面 (memory layers/insights/learning graph, file library,
 *   monitors, MCP connectors, delegation routing)
 * + 棒 5 P2 面 (toolsets, message reactions, TTS speak, dictation,
 *   identity, devices, computer status, structured settings,
 *   cross-face search): registers as
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
 *   GET  /v1/memory/layers ; GET /v1/memory/insights   (bar 4, Bearer)
 *   GET  /api/oneday-bridge/file-library          (bar 4, Bearer via nginx
 *                                                  bridge-auth swap)
 *   GET  /api/oneday-bridge/monitors[/{id}/changes]    (bar 4, Bearer)
 *   --- dashboard-session faces (bar 4): plain same-origin fetch, the
 *   dashboard cookie is the credential, no Bearer is sent ---
 *   GET  /api/learning/graph ; GET|PUT|DELETE /api/learning/node
 *   GET  /api/files/download?path=                (preview bytes)
 *   GET  /api/mcp/servers ; PUT .../enabled ; POST .../test
 *   GET  /api/mcp/catalog ; POST /api/mcp/catalog/install
 *   GET  /api/delegation/routing ; PUT /api/delegation/backend ;
 *   PUT  /api/delegation/backends/model_map|profile_routes
 *   GET  /v1/toolsets ; PUT /v1/toolsets/{name}     (bar 5, Bearer)
 *   GET  /v1/settings/registry                      (bar 5, read-only face)
 *   GET  /v1/identity/name|avatar ; GET avatar/image?id=  (bar 5, Bearer;
 *                                                  image bytes via blob)
 *   GET  /api/device-bridge/health|device/sync/status   (bar 5, Bearer)
 *   GET  /v1/push/tokens ; GET /v1/auth/sessions    (bar 5, devices face)
 *   PUT|DELETE /v1/reactions/{session}/{row}        (bar 5, reactions)
 *   --- dashboard-session faces (bar 5) ---
 *   GET  /api/sessions ; GET /api/sessions/{id}/messages  (reactions read:
 *                                                  display_metadata.reactions)
 *   GET  /api/audio/voice-config ; POST /api/audio/speak  (TTS, data_url)
 *   GET  /v1/diagnostics/crash-reports              (bar 6, Bearer)
 * Bar 6 closing items: diagnostics face (connection self-check across
 * health/capabilities/approvals/registry/asset/jobs + crash reports +
 * pending-approval browser notifications via the Notification API and
 * a 30 s in-page poll — Web Push would need new server push plumbing,
 * NOT wired, stated on the face) and a pure front-end image lightbox
 * (feed / file-preview / avatar images open full-screen). Session pin
 * is NOT wired: the session list carries `pinned`, but the only
 * browser-reachable edit path (dashboard 9119) is upstream's
 * revision-fenced relay for its desktop app (bare PATCH -> 409
 * client_upgrade_required; the web SPA itself never manages pins),
 * and the gateway's plain PATCH /api/sessions/{id} is not routed
 * publicly — verdict 未补齐·遗留, evidence in BAR6-INVENTORY.md.
 * Dictation uses the browser Web Speech API only; server-side
 * transcription is NOT wired into this plugin (legacy item, stated
 * on the face). Quote-reply (gap #19) is verified infeasible here:
 * the dashboard chat is an xterm terminal surface, the plugin cannot
 * compose a quote structure into it and owns no send path — left
 * explicitly 未销账·遗留 (conclusion recorded on the reactions face).
 * Delegation api_key values are masked previews from the server (the
 * App contract: the client never holds the real key); they round-trip
 * in memory only, are rendered as "已存密钥" placeholders, and a newly
 * typed key exists only in the submit body. MCP catalog env values and
 * monitor/file data follow the same rule: values go out in request
 * bodies, never render back, never persist.
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

  // Dashboard-session channel (bar 4): the dashboard's own /api/*
  // faces (learning, mcp, delegation, files) authenticate with the
  // dashboard session cookie, not the gateway Bearer. Plain
  // same-origin fetch; a 401 means the dashboard session is gone.
  function dashJson(method, path, body) {
    var opts = { method: method, credentials: "same-origin", headers: {} };
    if (body !== undefined) {
      opts.headers["Content-Type"] = "application/json";
      opts.body = JSON.stringify(body);
    }
    return fetch(path, opts).then(function (resp) {
      if (resp.status === 401) {
        var err = new Error("dashboard 会话未登录或已过期，请先登录面板再打开本页");
        err.code = "no_session";
        throw err;
      }
      return resp.text().then(function (text) {
        var data = null;
        try { data = text ? JSON.parse(text) : null; } catch (e) { data = null; }
        if (!resp.ok) {
          var msg = (data && (data.error || data.detail || data.message)) ||
            (path + " 应答 " + resp.status);
          var err2 = new Error(typeof msg === "string" ? msg : path + " 应答 " + resp.status);
          err2.status = resp.status;
          throw err2;
        }
        return data;
      });
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
    // ---- bar 6: diagnostics face ----
    fetchCrashReports: function () { return apiJson("GET", "/v1/diagnostics/crash-reports"); },
    fetchPluginRegistry: function () { return dashJson("GET", "/api/dashboard/plugins"); },
    fetchPluginAssetOk: function () {
      return fetch("/dashboard-plugins/oneday-console/dist/index.js", { method: "GET" })
        .then(function (r) {
          if (r.body && r.body.cancel) r.body.cancel();
          return r.ok;
        }).catch(function () { return false; });
    },
    fetchHealth: function () {
      return fetch("/health").then(function (r) { return r.ok ? r.json() : null; })
        .catch(function () { return null; });
    },
    // ---- bar 4: management faces ----
    fetchMemoryLayers: function () { return apiJson("GET", "/v1/memory/layers"); },
    fetchMemoryInsights: function () { return apiJson("GET", "/v1/memory/insights"); },
    fetchLearningGraph: function () { return dashJson("GET", "/api/learning/graph"); },
    fetchLearningNode: function (id) {
      return dashJson("GET", "/api/learning/node?id=" + encodeURIComponent(id));
    },
    saveLearningNode: function (id, content) {
      return dashJson("PUT", "/api/learning/node", { id: id, content: content });
    },
    deleteLearningNode: function (id) {
      return dashJson("DELETE", "/api/learning/node", { id: id });
    },
    fetchFileLibrary: function () { return apiJson("GET", "/api/oneday-bridge/file-library"); },
    fetchFileBlob: function (path) {
      return fetch("/api/files/download?path=" + encodeURIComponent(path), {
        credentials: "same-origin"
      }).then(function (resp) {
        if (!resp.ok) throw new Error("download 应答 " + resp.status);
        return resp.blob();
      });
    },
    fetchMonitors: function () { return apiJson("GET", "/api/oneday-bridge/monitors"); },
    fetchMonitorChanges: function (id) {
      return apiJson("GET", "/api/oneday-bridge/monitors/" + encodeURIComponent(id) + "/changes");
    },
    createMonitor: function (body) { return apiJson("POST", "/api/oneday-bridge/monitors", body); },
    checkMonitor: function (id) {
      return apiJson("POST", "/api/oneday-bridge/monitors/" + encodeURIComponent(id) + "/check", {});
    },
    pauseMonitor: function (id) {
      return apiJson("POST", "/api/oneday-bridge/monitors/" + encodeURIComponent(id) + "/pause", {});
    },
    resumeMonitor: function (id) {
      return apiJson("POST", "/api/oneday-bridge/monitors/" + encodeURIComponent(id) + "/resume", {});
    },
    deleteMonitor: function (id) {
      return apiJson("DELETE", "/api/oneday-bridge/monitors/" + encodeURIComponent(id));
    },
    readMonitorChange: function (id, changeId) {
      return apiJson("POST", "/api/oneday-bridge/monitors/" + encodeURIComponent(id) +
        "/changes/" + encodeURIComponent(changeId) + "/read", {});
    },
    fetchMcpServers: function () { return dashJson("GET", "/api/mcp/servers"); },
    setMcpServerEnabled: function (name, enabled) {
      return dashJson("PUT", "/api/mcp/servers/" + encodeURIComponent(name) + "/enabled",
        { enabled: enabled });
    },
    testMcpServer: function (name) {
      return dashJson("POST", "/api/mcp/servers/" + encodeURIComponent(name) + "/test", {});
    },
    fetchMcpCatalog: function () { return dashJson("GET", "/api/mcp/catalog"); },
    installMcpCatalog: function (body) { return dashJson("POST", "/api/mcp/catalog/install", body); },
    fetchDelegation: function () { return dashJson("GET", "/api/delegation/routing"); },
    setDelegationBackend: function (backend) {
      return dashJson("PUT", "/api/delegation/backend", { backend: backend });
    },
    setDelegationModelMap: function (options, def) {
      var body = { options: options };
      if (def) body["default"] = def;
      return dashJson("PUT", "/api/delegation/backends/model_map", body);
    },
    setDelegationProfileRoutes: function (profiles, def) {
      var body = { profiles: profiles };
      if (def) body["default"] = def;
      return dashJson("PUT", "/api/delegation/backends/profile_routes", body);
    },
    // ---- bar 5: P2 faces ----
    fetchToolsets: function () { return apiJson("GET", "/v1/toolsets"); },
    setToolsetEnabled: function (name, enabled) {
      return apiJson("PUT", "/v1/toolsets/" + encodeURIComponent(name), { enabled: enabled });
    },
    fetchSettingsRegistry: function () { return apiJson("GET", "/v1/settings/registry"); },
    fetchIdentityName: function () { return apiJson("GET", "/v1/identity/name"); },
    fetchIdentityAvatar: function () { return apiJson("GET", "/v1/identity/avatar"); },
    fetchAvatarImageBlob: function (id) {
      return api("GET", "/v1/identity/avatar/image?id=" + encodeURIComponent(id))
        .then(function (resp) {
          if (!resp.ok) throw new Error("头像图片应答 " + resp.status);
          return resp.blob();
        });
    },
    fetchDeviceHealth: function () { return apiJson("GET", "/api/device-bridge/health"); },
    fetchDeviceSyncStatus: function () { return apiJson("GET", "/api/device-bridge/device/sync/status"); },
    fetchPushTokens: function () { return apiJson("GET", "/v1/push/tokens"); },
    fetchAuthSessions: function () { return apiJson("GET", "/v1/auth/sessions"); },
    fetchDashSessions: function () { return dashJson("GET", "/api/sessions"); },
    fetchDashMessages: function (sessionId) {
      return dashJson("GET", "/api/sessions/" + encodeURIComponent(sessionId) + "/messages");
    },
    setReaction: function (sessionId, rowId, emoji) {
      return apiJson("PUT", "/v1/reactions/" + encodeURIComponent(sessionId) + "/" +
        encodeURIComponent(rowId), { emoji: emoji });
    },
    clearReaction: function (sessionId, rowId) {
      return apiJson("DELETE", "/v1/reactions/" + encodeURIComponent(sessionId) + "/" +
        encodeURIComponent(rowId));
    },
    fetchVoiceConfig: function () { return dashJson("GET", "/api/audio/voice-config"); },
    speak: function (text) { return dashJson("POST", "/api/audio/speak", { text: text }); },
    // ---- v1.0.0: unified admin console faces (profiles / soul / skills / plugins) ----
    fetchProfiles: function () { return dashJson("GET", "/api/profiles"); },
    createProfile: function (body) { return dashJson("POST", "/api/profiles", body); },
    activateProfile: function (name) {
      return dashJson("POST", "/api/profiles/" + encodeURIComponent(name) + "/activate", {});
    },
    deleteProfile: function (name) {
      return dashJson("DELETE", "/api/profiles/" + encodeURIComponent(name));
    },
    fetchSoul: function () { return dashJson("GET", "/api/soul"); },
    saveSoul: function (content) { return dashJson("PUT", "/api/soul", { content: content }); },
    fetchSkills: function () { return dashJson("GET", "/api/skills"); },
    searchSkillHub: function (q) {
      return dashJson("GET", "/api/skills/hub/search?q=" + encodeURIComponent(q || ""));
    },
    installSkillHub: function (identifier) {
      return dashJson("POST", "/api/skills/hub/install", { identifier: identifier });
    },
    uninstallSkillHub: function (name) {
      return dashJson("POST", "/api/skills/hub/uninstall", { name: name });
    },
    fetchPlugins: function () { return dashJson("GET", "/api/plugins"); },
    togglePlugin: function (name, enabled) {
      return dashJson("PUT", "/api/plugins/" + encodeURIComponent(name) + "/enabled", { enabled: enabled });
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

  // ---------------- image lightbox (bar 6, pure front-end) ----------------
  // Feed / file-preview / avatar images open in a full-screen viewer;
  // click anywhere or press Esc to close. No state, no backend.
  function lightboxKey(ev) { if (ev.key === "Escape") closeLightbox(); }
  function closeLightbox() {
    var el = document.getElementById("odc-lightbox");
    if (el && el.parentNode) el.parentNode.removeChild(el);
    document.removeEventListener("keydown", lightboxKey);
  }
  function openLightbox(src) {
    if (!src) return;
    closeLightbox();
    var overlay = document.createElement("div");
    overlay.className = "odc-lightbox";
    overlay.id = "odc-lightbox";
    var img = document.createElement("img");
    img.src = src;
    img.alt = "";
    overlay.appendChild(img);
    overlay.addEventListener("click", closeLightbox);
    document.body.appendChild(overlay);
    document.addEventListener("keydown", lightboxKey);
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
        if (img && img.url) kids.push(h("img", { key: "img" + i, className: "odc-img odc-img-zoom", src: img.url, alt: "", title: "点击看大图", onClick: function () { openLightbox(img.url); } }));
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

  // ---------------- memory face (bar 4, gap #8) ----------------
  var MEMORY_LAYER_TITLES = {
    core: "核心长期记忆", memory: "核心长期记忆",
    user: "用户画像", profile: "用户画像",
    episodic: "情景记忆", episodes: "情景记忆",
    semantic: "事实与知识", facts: "事实与知识",
    procedural: "行为规则", rules: "行为规则",
    insights: "提炼洞察",
    projects: "项目与目标", goals: "项目与目标",
    scratch: "工作暂存", working: "工作暂存"
  };
  var INSIGHT_STATUS_WORDS = { active: "生效中", candidate: "候选中", retired: "已退役" };
  function fmtBytes(n) {
    if (n == null) return "";
    if (n < 1024) return n + " B";
    if (n < 1024 * 1024) return (n / 1024).toFixed(1) + " KB";
    return (n / 1024 / 1024).toFixed(1) + " MB";
  }
  function learningNodeContent(data) {
    if (!data) return null;
    if (typeof data === "string") return data;
    var keys = ["content", "text", "body"];
    for (var i = 0; i < keys.length; i++) {
      if (typeof data[keys[i]] === "string") return data[keys[i]];
    }
    if (data.node && typeof data.node === "object") {
      for (var j = 0; j < keys.length; j++) {
        if (typeof data.node[keys[j]] === "string") return data.node[keys[j]];
      }
    }
    return null;
  }

  function MemoryFace() {
    var facePair = useFace(function () {
      return Promise.all([
        Core.fetchMemoryLayers(),
        Core.fetchMemoryInsights().catch(function () { return null; }),
        Core.fetchLearningGraph().catch(function () { return null; })
      ]).then(function (r) { return { layers: r[0], insights: r[1], graph: r[2] }; });
    });
    var face = facePair[0];
    var load = facePair[1];
    var selPair = hooks.useState(null);
    var sel = selPair[0];
    var setSel = selPair[1];
    var draftPair = hooks.useState("");
    var draft = draftPair[0];
    var setDraft = draftPair[1];
    var busyPair = hooks.useState(false);
    var busy = busyPair[0];
    var setBusy = busyPair[1];
    var notePair = hooks.useState("");
    var note = notePair[0];
    var setNote = notePair[1];

    function openNode(node) {
      setSel({ node: node, content: null, loading: true });
      setNote("");
      Core.fetchLearningNode(node.id).then(function (data) {
        var content = learningNodeContent(data);
        setSel({ node: node, content: content, loading: false });
        setDraft(content || "");
      }).catch(function (err) {
        setSel({ node: node, content: null, loading: false });
        setNote("节点全文没读出来：" + ((err && err.message) || String(err)));
      });
    }
    function saveNode() {
      if (!sel) return;
      setBusy(true);
      Core.saveLearningNode(sel.node.id, draft).then(function () {
        setBusy(false);
        setNote("已保存（以回读为准）。");
        load();
        openNode(sel.node);
      }).catch(function (err) {
        setBusy(false);
        setNote("保存失败：" + ((err && err.message) || String(err)));
      });
    }
    function removeNode() {
      if (!sel) return;
      setBusy(true);
      Core.deleteLearningNode(sel.node.id).then(function () {
        setBusy(false);
        setSel(null);
        setNote("已删除（以回读为准）。");
        load();
      }).catch(function (err) {
        setBusy(false);
        setNote("删除失败：" + ((err && err.message) || String(err)));
      });
    }

    var body = null;
    if (face.phase === "ready") {
      var d = face.data || {};
      var layers = (d.layers && d.layers.layers) || [];
      var insights = [];
      if (d.insights) {
        insights = d.insights.insights || d.insights.data || d.insights.items ||
          (Array.isArray(d.insights) ? d.insights : []);
      }
      var graph = d.graph || {};
      var nodes = graph.nodes || [];
      var skillNodes = nodes.filter(function (n) { return n.kind === "skill"; });
      var memoryNodes = nodes.filter(function (n) { return n.kind === "memory"; });
      var stats = graph.stats || {};
      var parts = [];
      parts.push(h("p", { key: "lc", className: "odc-count" },
        "记忆分层 " + layers.length + " 层 · 洞察 " + insights.length + " 条 · 学习图谱节点 " +
        nodes.length + "（技能 " + skillNodes.length + " · 记忆 " + memoryNodes.length +
        "） · 记忆卡 " + ((graph.memory || graph.memories || graph.cards || []).length) + " 张"));
      if (!layers.length) {
        parts.push(h("p", { key: "le", className: "odc-empty" }, "暂无分层记忆。"));
      } else {
        parts.push(h("div", { key: "layers", className: "odc-counts" }, layers.map(function (l) {
          return h("div", { key: l.layer, className: "odc-count-cell" },
            h("span", { className: "odc-count-num" }, String(l.entries != null ? l.entries : 0)),
            h("span", null, (MEMORY_LAYER_TITLES[String(l.layer || "").toLowerCase()] || l.layer) +
              " · " + (l.files || 0) + " 个文件 · " + fmtBytes(l.bytes || 0) +
              (l.provenance_coverage != null
                ? " · 出处覆盖 " + Math.round(l.provenance_coverage * 100) + "%" : "") +
              (l.newest_mtime ? " · 最新 " + l.newest_mtime : "")));
        })));
      }
      parts.push(h("p", { key: "ih", className: "odc-summary-head" }, "提炼洞察（ExpeL 账本）"));
      if (!insights.length) {
        parts.push(h("p", { key: "ie", className: "odc-empty" }, "暂无洞察。"));
      } else {
        parts.push(h("ul", { key: "il", className: "odc-list" }, insights.map(function (it) {
          var meta = [];
          meta.push(INSIGHT_STATUS_WORDS[it.status] || it.status || "");
          if (it.scope) meta.push("范围 " + it.scope);
          meta.push("赞成 " + (it.votes_up || 0) + " · 反对 " + (it.votes_down || 0) +
            " · 复发 " + (it.relapse_count || 0));
          if (it.last) meta.push("最近 " + it.last);
          return h("li", { key: it.id, className: "odc-row odc-row-card" },
            h("span", { className: "odc-row-title" }, it.rule || it.id),
            h("p", { className: "odc-row-meta" }, meta.join(" · ")));
        })));
      }
      parts.push(h("p", { key: "gh", className: "odc-summary-head" },
        "学习图谱（技能 " + skillNodes.length + " · 记忆 " + memoryNodes.length +
        " · 边 " + ((graph.edges || []).length) + "）"));
      if (stats.learned_skills != null || stats.memory_nodes != null) {
        parts.push(h("p", { key: "gs", className: "odc-row-meta" },
          "服务端统计：学到的技能 " + (stats.learned_skills != null ? stats.learned_skills : "—") +
          " · 记忆节点 " + (stats.memory_nodes != null ? stats.memory_nodes : "—") +
          " · 已关联 " + (stats.linked_nodes != null ? stats.linked_nodes : "—")));
      }
      function nodeRow(n) {
        var meta = [];
        if (n.category) meta.push(n.category);
        if (n.useCount) meta.push("用过 " + n.useCount + " 次");
        if (n.state) meta.push(n.state);
        if (n.createdBy) meta.push("来自 " + n.createdBy);
        if (n.timestamp) meta.push(fmtTs(n.timestamp));
        return h("li", { key: n.id, className: "odc-row" },
          h("span", null,
            h("span", { className: "odc-row-title" }, n.label || n.id),
            h("p", { className: "odc-row-meta" }, meta.join(" · "))),
          h("span", { className: "odc-chips" },
            n.pinned ? h("span", { key: "pin", className: "odc-st" }, "已置顶") : null,
            h("button", {
              key: "open", className: "odc-btn odc-btn-text",
              onClick: function () { openNode(n); }
            }, "全文／编辑")));
      }
      if (skillNodes.length) {
        parts.push(h("p", { key: "skh", className: "odc-summary-head" }, "学到的技能"));
        parts.push(h("ul", { key: "skl", className: "odc-list" }, skillNodes.map(nodeRow)));
      }
      if (memoryNodes.length) {
        parts.push(h("p", { key: "mmh", className: "odc-summary-head" }, "记忆节点"));
        parts.push(h("ul", { key: "mml", className: "odc-list" }, memoryNodes.map(nodeRow)));
      }
      if (!nodes.length) {
        parts.push(h("p", { key: "ge", className: "odc-empty" }, "学习图谱暂无节点。"));
      }
      if (note) parts.push(h("p", { key: "note", className: "odc-warn" }, note));
      if (sel) {
        parts.push(h("div", { key: "detail", className: "odc-detail" },
          h("p", { className: "odc-summary-head" }, "节点全文 · " + (sel.node.label || sel.node.id)),
          sel.loading
            ? h("p", null, "正在读全文……")
            : (sel.content == null
              ? h("p", { className: "odc-warn" }, "服务端没给出全文（回执无 content 字段），不冒充已读到。")
              : h("label", { className: "odc-field" }, h("span", null, "内容（保存走 PUT /api/learning/node，与 App 同一口）"),
                h("textarea", {
                  rows: 8, value: draft,
                  onChange: function (ev) { setDraft(ev.target.value); }
                }))),
          h("span", { className: "odc-actions" },
            h("button", {
              className: "odc-btn odc-btn-primary", disabled: busy || sel.loading || sel.content == null,
              onClick: saveNode
            }, busy ? "处理中…" : "保存"),
            h("button", {
              className: "odc-btn odc-btn-text", disabled: busy,
              onClick: removeNode
            }, "删除节点"),
            h("button", {
              className: "odc-btn odc-btn-text",
              onClick: function () { setSel(null); }
            }, "收起"))));
      }
      body = parts;
    }
    return faceShell("记忆", "与 App 智能体记忆面同一数据源：分层清单（GET /v1/memory/layers）、提炼洞察账本（/v1/memory/insights）、学习图谱（/api/learning/graph，节点全文走 /api/learning/node 可编辑/删除，与 App 同一口）。只呈现 App 同口径可见内容。", face, load, body);
  }

  // ---------------- file library face (bar 4, gap #9) ----------------
  // Pin + open-history are client-local stores in the App too
  // (pinStore / FileOpenHistoryStore never leave the device); the web
  // face mirrors that with localStorage, scoped to this browser.
  function lsGet(key, fallback) {
    try {
      var v = window.localStorage.getItem(key);
      return v ? JSON.parse(v) : fallback;
    } catch (e) { return fallback; }
  }
  function lsSet(key, v) {
    try { window.localStorage.setItem(key, JSON.stringify(v)); } catch (e) { /* private mode */ }
  }
  var PIN_KEY = "oneday-console.file-pins";
  var HISTORY_KEY = "oneday-console.file-history";

  function FilesFace() {
    var facePair = useFace(Core.fetchFileLibrary);
    var face = facePair[0];
    var load = facePair[1];
    var pinsPair = hooks.useState(function () { return lsGet(PIN_KEY, []); });
    var pins = pinsPair[0];
    var setPins = pinsPair[1];
    var histPair = hooks.useState(function () { return lsGet(HISTORY_KEY, []); });
    var hist = histPair[0];
    var setHist = histPair[1];
    var prevPair = hooks.useState(null);
    var prev = prevPair[0];
    var setPrev = prevPair[1];
    var notePair = hooks.useState("");
    var note = notePair[0];
    var setNote = notePair[1];

    function togglePin(path) {
      var next = pins.indexOf(path) >= 0
        ? pins.filter(function (p) { return p !== path; })
        : [path].concat(pins);
      setPins(next);
      lsSet(PIN_KEY, next);
    }
    function closePreview() {
      if (prev && prev.url) { try { URL.revokeObjectURL(prev.url); } catch (e) { /* noop */ } }
      setPrev(null);
    }
    function openItem(item) {
      var entry = { path: item.path, name: item.name, at: Date.now() };
      var nextHist = [entry].concat(hist.filter(function (x) { return x.path !== item.path; })).slice(0, 30);
      setHist(nextHist);
      lsSet(HISTORY_KEY, nextHist);
      closePreview();
      setPrev({ item: item, kind: "loading", url: null, text: null });
      setNote("");
      Core.fetchFileBlob(item.path).then(function (blob) {
        var mime = item.mime_type || blob.type || "";
        if (mime.indexOf("image/") === 0) {
          setPrev({ item: item, kind: "image", url: URL.createObjectURL(blob), text: null });
        } else if (mime === "application/pdf") {
          setPrev({ item: item, kind: "pdf", url: URL.createObjectURL(blob), text: null });
        } else if (mime.indexOf("text/") === 0 || /json|xml|markdown/.test(mime)) {
          blob.text().then(function (text) {
            setPrev({ item: item, kind: "text", url: null, text: text });
          });
        } else {
          var url = URL.createObjectURL(blob);
          var a = document.createElement("a");
          a.href = url;
          a.download = item.name || "download";
          document.body.appendChild(a);
          a.click();
          document.body.removeChild(a);
          setTimeout(function () { try { URL.revokeObjectURL(url); } catch (e) { /* noop */ } }, 4000);
          setPrev({ item: item, kind: "downloaded", url: null, text: null });
        }
      }).catch(function (err) {
        setPrev({ item: item, kind: "error", url: null, text: null });
        setNote("预览没取回来：" + ((err && err.message) || String(err)));
      });
    }

    var body = null;
    if (face.phase === "ready") {
      var d = face.data || {};
      var items = d.items || [];
      var parts = [];
      parts.push(h("p", { key: "cnt", className: "odc-count" },
        "交付物共 " + (d.total != null ? d.total : items.length) + " 件（服务端聚合下发，与 App 文件库同一函数同一集）" +
        (d.truncated ? " · 服务端报告已截断" : "")));
      if (note) parts.push(h("p", { key: "note", className: "odc-warn" }, note));
      if (prev) {
        var pk = [h("p", { key: "ph", className: "odc-summary-head" },
          "预览 · " + (prev.item.name || prev.item.path))];
        if (prev.kind === "loading") pk.push(h("p", { key: "pl" }, "正在取文件……"));
        if (prev.kind === "image") pk.push(h("img", { key: "pi", className: "odc-img odc-img-zoom", src: prev.url, alt: prev.item.name || "", title: "点击看大图", onClick: function () { openLightbox(prev.url); } }));
        if (prev.kind === "pdf") pk.push(h("iframe", { key: "pp", className: "odc-preview", src: prev.url, title: prev.item.name || "pdf" }));
        if (prev.kind === "text") pk.push(h("pre", { key: "pt", className: "odc-entry-body" }, prev.text));
        if (prev.kind === "downloaded") pk.push(h("p", { key: "pd" }, "此类型不在页内预览，已触发下载。"));
        if (prev.kind === "error") pk.push(h("p", { key: "pe", className: "odc-error" }, "预览失败（见上方提示）。"));
        pk.push(h("span", { key: "pc", className: "odc-actions" },
          h("button", { className: "odc-btn odc-btn-text", onClick: closePreview }, "关闭预览")));
        parts.push(h("div", { key: "prev", className: "odc-detail" }, pk));
      }
      if (hist.length) {
        parts.push(h("p", { key: "hh", className: "odc-summary-head" }, "打开历史（本浏览器本地记录，与 App 同口径）"));
        parts.push(h("ul", { key: "hl", className: "odc-list" }, hist.slice(0, 8).map(function (x) {
          var found = items.filter(function (i) { return i.path === x.path; })[0];
          return h("li", { key: x.path, className: "odc-row" },
            h("span", null,
              h("span", { className: "odc-row-title" }, x.name || x.path),
              h("p", { className: "odc-row-meta" }, new Date(x.at).toLocaleString())),
            found ? h("button", {
              className: "odc-btn odc-btn-text",
              onClick: function () { openItem(found); }
            }, "再打开") : h("span", { className: "odc-row-meta" }, "已不在库中"));
        })));
      }
      if (!items.length) {
        parts.push(h("p", { key: "e", className: "odc-empty" }, "文件库暂无交付物。"));
      } else {
        var sorted = items.slice().sort(function (a, b) {
          var pa = pins.indexOf(a.path) >= 0 ? 0 : 1;
          var pb = pins.indexOf(b.path) >= 0 ? 0 : 1;
          return pa - pb;
        });
        parts.push(h("ul", { key: "list", className: "odc-list" }, sorted.map(function (item) {
          var pinned = pins.indexOf(item.path) >= 0;
          var meta = [];
          if (item.source) meta.push("来源 " + item.source);
          if (item.size != null) meta.push(fmtBytes(item.size));
          if (item.mtime) meta.push(fmtTs(item.mtime));
          if (item.mime_type) meta.push(item.mime_type);
          return h("li", { key: item.path, className: "odc-row" },
            h("span", null,
              h("span", { className: "odc-row-title" }, (pinned ? "［置顶］" : "") + (item.name || item.path)),
              h("p", { className: "odc-row-meta" }, meta.join(" · "))),
            h("span", { className: "odc-actions" },
              h("button", {
                className: "odc-btn odc-btn-text",
                onClick: function () { togglePin(item.path); }
              }, pinned ? "取消置顶" : "置顶"),
              h("button", {
                className: "odc-btn odc-btn-small",
                onClick: function () { openItem(item); }
              }, "预览")));
        })));
      }
      body = parts;
    }
    return faceShell("文件库", "交付物库（GET /api/oneday-bridge/file-library 服务端聚合，与 App 同一函数）：预览走 dashboard 文件通道 /api/files/download，与 App 打开同一文件同源对账；置顶与打开历史是本机本地记录（App 同为本地存储）。与 dashboard 的 Files 服务器文件浏览器分工并存、不合并。", face, load, body);
  }

  // ---------------- monitors face (bar 4, gap #10) ----------------
  var MONITOR_RESULT_WORDS = { changed: "有变化", unchanged: "无变化", failed: "检查失败" };
  var MONITOR_FREQ = [
    { v: "manual", label: "手动检查", text: "手动检查", interval: null },
    { v: "hourly", label: "每小时", text: "每小时检查", interval: 3600 },
    { v: "daily", label: "每天", text: "每天检查", interval: 86400 }
  ];
  function MonitorsFace() {
    var facePair = useFace(Core.fetchMonitors);
    var face = facePair[0];
    var load = facePair[1];
    var formPair = hooks.useState(null);
    var form = formPair[0];
    var setForm = formPair[1];
    var busyPair = hooks.useState("");
    var busy = busyPair[0];
    var setBusy = busyPair[1];
    var notePair = hooks.useState("");
    var note = notePair[0];
    var setNote = notePair[1];
    var openPair = hooks.useState("");
    var openId = openPair[0];
    var setOpenId = openPair[1];
    var chgPair = hooks.useState(null);
    var chg = chgPair[0];
    var setChg = chgPair[1];
    var confirmPair = hooks.useState("");
    var confirmId = confirmPair[0];
    var setConfirmId = confirmPair[1];

    function act(id, fn, doneMsg) {
      setBusy(id);
      setNote("");
      fn().then(function () {
        setBusy("");
        if (doneMsg) setNote(doneMsg);
        load();
        if (openId === id) loadChanges(id);
      }).catch(function (err) {
        setBusy("");
        setNote("操作没成：" + ((err && err.message) || String(err)) + "（已按服务端真值重读）");
        load();
      });
    }
    function loadChanges(id) {
      setChg({ id: id, loading: true, items: null });
      Core.fetchMonitorChanges(id).then(function (data) {
        setChg({ id: id, loading: false, items: (data && data.items) || [] });
      }).catch(function (err) {
        setChg({ id: id, loading: false, items: null });
        setNote("变化记录没读出来：" + ((err && err.message) || String(err)));
      });
    }
    function toggleOpen(m) {
      if (openId === m.id) { setOpenId(""); setChg(null); }
      else { setOpenId(m.id); loadChanges(m.id); }
    }
    function create() {
      var name = ((form && form.name) || "").trim();
      var target = ((form && form.target) || "").trim();
      if (!name) { setNote("请填写监测名称。"); return; }
      if (!target) { setNote("请填写要盯的链接。"); return; }
      if (target.indexOf("http://") !== 0 && target.indexOf("https://") !== 0) {
        setNote("链接要以 http:// 或 https:// 开头。");
        return;
      }
      var freq = MONITOR_FREQ.filter(function (f) { return f.v === (form.freq || "manual"); })[0];
      var body = { name: name, target: target, scheduleText: freq.text };
      if (freq.interval) body.intervalSeconds = freq.interval;
      setBusy("create");
      setNote("");
      Core.createMonitor(body).then(function () {
        setBusy("");
        setForm(null);
        setNote("已新建（以回读列表为准）。");
        load();
      }).catch(function (err) {
        setBusy("");
        setNote("新建失败：" + ((err && err.message) || String(err)));
      });
    }

    var body = null;
    if (face.phase === "ready") {
      var items = (face.data && face.data.items) || [];
      var parts = [];
      var unreadTotal = items.reduce(function (s, m) { return s + (m.unreadChanges || 0); }, 0);
      parts.push(h("p", { key: "cnt", className: "odc-count" },
        "共 " + items.length + " 个监测 · 未读变化 " + unreadTotal + " 条"));
      if (note) parts.push(h("p", { key: "note", className: "odc-warn" }, note));
      if (form) {
        parts.push(h("div", { key: "form", className: "odc-form" },
          h("label", { className: "odc-field" }, h("span", null, "名称"),
            h("input", {
              type: "text", value: form.name || "",
              onChange: function (ev) { setForm(Object.assign({}, form, { name: ev.target.value })); }
            })),
          h("label", { className: "odc-field" }, h("span", null, "要盯的链接（http/https）"),
            h("input", {
              type: "text", value: form.target || "",
              onChange: function (ev) { setForm(Object.assign({}, form, { target: ev.target.value })); }
            })),
          h("label", { className: "odc-field" }, h("span", null, "频率"),
            h("select", {
              value: form.freq || "manual",
              onChange: function (ev) { setForm(Object.assign({}, form, { freq: ev.target.value })); }
            }, MONITOR_FREQ.map(function (f) {
              return h("option", { key: f.v, value: f.v }, f.label);
            }))),
          h("span", { className: "odc-actions" },
            h("button", {
              className: "odc-btn odc-btn-primary", disabled: busy === "create", onClick: create
            }, busy === "create" ? "提交中…" : "新建监测"),
            h("button", {
              className: "odc-btn odc-btn-text",
              onClick: function () { setForm(null); }
            }, "取消"))));
      } else {
        parts.push(h("span", { key: "new", className: "odc-actions" },
          h("button", {
            className: "odc-btn odc-btn-secondary",
            onClick: function () { setForm({ name: "", target: "", freq: "manual" }); }
          }, "＋ 新建监测")));
      }
      if (!items.length) {
        parts.push(h("p", { key: "e", className: "odc-empty" }, "暂无监测（0 件也是真数据）。"));
      } else {
        parts.push(h("ul", { key: "list", className: "odc-list" }, items.map(function (m) {
          var meta = [];
          if (m.scheduleText) meta.push(m.scheduleText);
          if (m.lastCheckedAt) {
            meta.push("最近检查 " + fmtTs(m.lastCheckedAt) + " · " +
              (MONITOR_RESULT_WORDS[m.lastResult] || (m.lastResult ? m.lastResult + "（未识别态）" : "未检查")));
          } else meta.push("从未检查");
          if (m.lastError) meta.push("失败原因：" + m.lastError);
          if (m.latestChangeSummary) {
            meta.push("最近变化：" + m.latestChangeSummary +
              (m.latestChangeAt ? "（" + fmtTs(m.latestChangeAt) + "）" : ""));
          }
          var kids = [
            h("div", { key: "hd", className: "odc-actions", style: { justifyContent: "space-between" } },
              h("span", { className: "odc-row-title" }, m.name || m.id),
              h("span", { className: "odc-chips" },
                m.enabled
                  ? h("span", { key: "on", className: "odc-st odc-st-done" }, "启用中")
                  : h("span", { key: "off", className: "odc-st odc-st-failed" }, "已暂停"),
                (m.unreadChanges || 0) > 0
                  ? h("span", { key: "un", className: "odc-st odc-st-pending" }, "未读变化 " + m.unreadChanges)
                  : null)),
            h("p", { key: "mt", className: "odc-row-meta" }, meta.join(" · ")),
            h("p", { key: "tg", className: "odc-cmd" }, m.target || ""),
            h("span", { key: "ac", className: "odc-actions" },
              h("button", {
                className: "odc-btn odc-btn-small", disabled: busy === m.id,
                onClick: function () { act(m.id, function () { return Core.checkMonitor(m.id); }, "已检查（以回读为准）。"); }
              }, "立即检查"),
              m.enabled
                ? h("button", {
                  className: "odc-btn odc-btn-small", disabled: busy === m.id,
                  onClick: function () { act(m.id, function () { return Core.pauseMonitor(m.id); }, "已暂停（以回读为准）。"); }
                }, "暂停")
                : h("button", {
                  className: "odc-btn odc-btn-small", disabled: busy === m.id,
                  onClick: function () { act(m.id, function () { return Core.resumeMonitor(m.id); }, "已恢复（以回读为准）。"); }
                }, "恢复"),
              h("button", {
                className: "odc-btn odc-btn-small",
                onClick: function () { toggleOpen(m); }
              }, openId === m.id ? "收起变化" : "变化记录"),
              confirmId === m.id
                ? h("button", {
                  className: "odc-btn odc-btn-small", disabled: busy === m.id,
                  onClick: function () {
                    setConfirmId("");
                    act(m.id, function () { return Core.deleteMonitor(m.id); }, "已删除（连同其变化记录）。");
                  }
                }, "确认删除")
                : h("button", {
                  className: "odc-btn odc-btn-text",
                  onClick: function () { setConfirmId(m.id); }
                }, "删除"))
          ];
          if (openId === m.id) {
            if (!chg || chg.loading) {
              kids.push(h("p", { key: "cl" }, "正在读变化记录……"));
            } else if (chg.items && chg.items.length) {
              kids.push(h("ul", { key: "cl", className: "odc-list" }, chg.items.map(function (c) {
                return h("li", { key: c.id, className: "odc-row" },
                  h("span", null,
                    h("span", { className: "odc-row-title" }, c.summary || c.id),
                    h("p", { className: "odc-row-meta" },
                      fmtTs(c.detectedAt) + (c.read ? " · 已读" : " · 未读") +
                      (c.before ? " · 前：" + String(c.before).slice(0, 80) : "") +
                      (c.after ? " · 后：" + String(c.after).slice(0, 80) : ""))),
                  !c.read ? h("button", {
                    className: "odc-btn odc-btn-text", disabled: busy === m.id,
                    onClick: function () {
                      act(m.id, function () { return Core.readMonitorChange(m.id, c.id); }, "已标已读。");
                    }
                  }, "标已读") : null);
              })));
            } else if (chg.items) {
              kids.push(h("p", { key: "ce", className: "odc-empty" }, "暂无变化记录。"));
            }
          }
          return h("li", { key: m.id, className: "odc-row odc-row-card" }, kids);
        })));
      }
      body = parts;
    }
    return faceShell("监控", "与 App 智能体监控面同一数据源（GET /api/oneday-bridge/monitors）：盯网页变化、检出留痕。立即检查/暂停/恢复/删除/新建与 App 同口，成败以回读为准。", face, load, body);
  }

  // ---------------- connectors face (bar 4, gap #11) ----------------
  function mcpIsSecretEnv(name) {
    var n = String(name || "").toUpperCase();
    return ["KEY", "TOKEN", "SECRET", "PASSWORD", "AUTH"].some(function (k) {
      return n.indexOf(k) >= 0;
    });
  }
  function mcpTestVerdict(data) {
    if (!data) return { ok: false, text: "测试回执为空，不判成功。" };
    var msg = data.message || data.error || "";
    if (typeof data.ok === "boolean") {
      return { ok: data.ok, text: (data.ok ? "测试通过" : "测试未通过") +
        (data.tool_count != null ? " · 工具 " + data.tool_count + " 个" : "") +
        (msg ? " · " + msg : "") };
    }
    var st = String(data.status || "").toLowerCase();
    if (["ok", "success", "succeeded", "connected", "healthy"].indexOf(st) >= 0) {
      return { ok: true, text: "测试通过 · 状态 " + data.status +
        (data.tool_count != null ? " · 工具 " + data.tool_count + " 个" : "") +
        (msg ? " · " + msg : "") };
    }
    return { ok: false, text: "回执无明确成功信号（状态 " + (data.status || "未知") + "）" +
      (msg ? " · " + msg : "") + "，不判成功。" };
  }
  function ConnectorsFace() {
    var facePair = useFace(function () {
      return Promise.all([
        Core.fetchMcpServers(),
        Core.fetchMcpCatalog().catch(function () { return null; })
      ]).then(function (r) { return { servers: r[0], catalog: r[1] }; });
    });
    var face = facePair[0];
    var load = facePair[1];
    var busyPair = hooks.useState("");
    var busy = busyPair[0];
    var setBusy = busyPair[1];
    var notePair = hooks.useState("");
    var note = notePair[0];
    var setNote = notePair[1];
    var testPair = hooks.useState({});
    var testMap = testPair[0];
    var setTestMap = testPair[1];
    var queryPair = hooks.useState("");
    var query = queryPair[0];
    var setQuery = queryPair[1];
    var instPair = hooks.useState(null);
    var inst = instPair[0];
    var setInst = instPair[1];

    function toggleServer(s) {
      setBusy("srv:" + s.name);
      setNote("");
      Core.setMcpServerEnabled(s.name, !s.enabled).then(function () {
        setBusy("");
        setNote("「" + s.name + "」已" + (!s.enabled ? "启用" : "停用") + "（以回读为准）。");
        load();
      }).catch(function (err) {
        setBusy("");
        setNote("开关没成：" + ((err && err.message) || String(err)) + "（已按服务端真值重读）");
        load();
      });
    }
    function testServer(s) {
      setBusy("test:" + s.name);
      Core.testMcpServer(s.name).then(function (data) {
        setBusy("");
        var v = mcpTestVerdict(data);
        var next = Object.assign({}, testMap);
        next[s.name] = v.text;
        setTestMap(next);
      }).catch(function (err) {
        setBusy("");
        var next = Object.assign({}, testMap);
        next[s.name] = "测试请求失败：" + ((err && err.message) || String(err));
        setTestMap(next);
      });
    }
    function submitInstall() {
      if (!inst) return;
      var env = {};
      (inst.entry.required_env || []).forEach(function (f) {
        var v = (inst.env && inst.env[f.name]) || "";
        if (String(v).trim()) env[f.name] = v;
      });
      var body = { name: inst.entry.name, env: env, enable: !!inst.enable };
      setBusy("install");
      setNote("");
      Core.installMcpCatalog(body).then(function (data) {
        setBusy("");
        setInst(null);
        var bg = data && data.background === true;
        setNote("「" + body.name + "」" + (bg ? "已开始后台安装" : "安装请求已受理") +
          "；落定状态以目录回读为准（正在重读）。");
        load();
      }).catch(function (err) {
        setBusy("");
        setNote("安装没成：" + ((err && err.message) || String(err)));
      });
    }

    var body = null;
    if (face.phase === "ready") {
      var d = face.data || {};
      var servers = Array.isArray(d.servers) ? d.servers
        : ((d.servers && (d.servers.servers || d.servers.items)) || []);
      var entries = (d.catalog && d.catalog.entries) || [];
      var diagnostics = (d.catalog && d.catalog.diagnostics) || [];
      var parts = [];
      parts.push(h("p", { key: "cnt", className: "odc-count" },
        "已装服务 " + servers.length + " 个 · 目录条目 " + entries.length + " 条" +
        (diagnostics.length ? " · 诊断 " + diagnostics.length + " 条" : "")));
      diagnostics.forEach(function (dg, i) {
        parts.push(h("p", { key: "dg" + i, className: "odc-error" },
          (dg.source ? dg.source + "：" : "") + (dg.message || "")));
      });
      if (note) parts.push(h("p", { key: "note", className: "odc-warn" }, note));
      parts.push(h("p", { key: "sh", className: "odc-summary-head" }, "已装的 MCP 服务"));
      if (!servers.length) {
        parts.push(h("p", { key: "se", className: "odc-empty" }, "暂无已装服务。"));
      } else {
        parts.push(h("ul", { key: "sl", className: "odc-list" }, servers.map(function (s) {
          var origin = s.source === "plugin"
            ? "插件预置" + (s.plugin ? " · " + s.plugin : "")
            : "手动配置";
          var endpoint = s.url || s.command || "";
          return h("li", { key: s.name, className: "odc-row odc-row-card" },
            h("div", { className: "odc-actions", style: { justifyContent: "space-between" } },
              h("span", { className: "odc-row-title" }, s.name),
              h("span", { className: "odc-st " + (s.enabled ? "odc-st-done" : "odc-st-failed") },
                s.enabled ? "已启用" : "已停用")),
            h("p", { className: "odc-row-meta" },
              origin + (s.transport ? " · 传输 " + s.transport : "")),
            endpoint ? h("p", { className: "odc-cmd" }, endpoint) : null,
            testMap[s.name] ? h("p", { className: "odc-row-meta" }, testMap[s.name]) : null,
            s.source === "plugin"
              ? h("p", { className: "odc-row-meta" }, "插件预置服务由插件管理，服务端不接受开关修改（实测 409 原话），本面只测连通。")
              : null,
            h("span", { className: "odc-actions" },
              s.source === "plugin" ? null : h("button", {
                className: "odc-btn odc-btn-small", disabled: busy === "srv:" + s.name,
                onClick: function () { toggleServer(s); }
              }, s.enabled ? "停用" : "启用"),
              h("button", {
                className: "odc-btn odc-btn-small", disabled: busy === "test:" + s.name,
                onClick: function () { testServer(s); }
              }, busy === "test:" + s.name ? "测试中…" : "测试连接")));
        })));
      }
      parts.push(h("p", { key: "ch", className: "odc-summary-head" }, "连接器目录（可安装）"));
      parts.push(h("label", { key: "cq", className: "odc-field" }, h("span", null, "搜索目录"),
        h("input", {
          type: "text", value: query,
          onChange: function (ev) { setQuery(ev.target.value); }
        })));
      var q = query.trim().toLowerCase();
      var shown = entries.filter(function (e) {
        if (!q) return true;
        return (e.name || "").toLowerCase().indexOf(q) >= 0 ||
          (e.description || "").toLowerCase().indexOf(q) >= 0;
      });
      if (!shown.length) {
        parts.push(h("p", { key: "ce", className: "odc-empty" }, "目录里没有匹配的条目。"));
      } else {
        parts.push(h("ul", { key: "cl", className: "odc-list" }, shown.map(function (e) {
          var state = !e.installed ? "未安装" : (e.enabled ? "已安装 · 已启用" : "已安装 · 未启用");
          var meta = [];
          meta.push("状态 " + state);
          if (e.transport) meta.push("传输 " + e.transport);
          if (e.auth_type) meta.push("鉴权 " + e.auth_type);
          if (e.source) meta.push("来源 " + e.source);
          if (e.connector_slug) meta.push("连接器 " + e.connector_slug);
          var kids = [
            h("span", { key: "t", className: "odc-row-title" }, e.name),
            h("p", { key: "m", className: "odc-row-meta" }, meta.join(" · ")),
            e.description ? h("p", { key: "d", className: "odc-row-meta" }, e.description) : null,
            (e.command || e.url)
              ? h("p", { key: "c", className: "odc-cmd" }, (e.command || "") + (e.url ? " " + e.url : ""))
              : null,
            (e.required_env || []).length
              ? h("p", { key: "env", className: "odc-row-meta" },
                "所需配置：" + e.required_env.map(function (f) {
                  return f.name + (f.required ? "（必填）" : "（可选）");
                }).join("、"))
              : null
          ];
          if (e.needs_install) {
            kids.push(h("span", { key: "a", className: "odc-actions" },
              h("button", {
                className: "odc-btn odc-btn-small",
                onClick: function () {
                  setInst({ entry: e, env: {}, enable: true });
                }
              }, "安装…")));
          }
          if (inst && inst.entry.name === e.name) {
            kids.push(h("div", { key: "form", className: "odc-form" },
              (e.required_env || []).map(function (f) {
                return h("label", { key: f.name, className: "odc-field" },
                  h("span", null, (f.prompt || f.name) + (f.required ? "（必填）" : "（可选）")),
                  h("input", {
                    type: mcpIsSecretEnv(f.name) ? "password" : "text",
                    value: (inst.env && inst.env[f.name]) || "",
                    autoComplete: "off",
                    onChange: function (ev) {
                      var env = Object.assign({}, inst.env);
                      env[f.name] = ev.target.value;
                      setInst({ entry: inst.entry, env: env, enable: inst.enable });
                    }
                  }));
              }),
              h("label", { className: "odc-field" },
                h("span", null, "装完立即启用"),
                h("input", {
                  type: "checkbox", checked: !!inst.enable,
                  onChange: function (ev) {
                    setInst({ entry: inst.entry, env: inst.env, enable: ev.target.checked });
                  }
                })),
              h("p", { className: "odc-row-meta" },
                "密钥类字段只随本次安装请求发出，不回显、不落盘；安装多为后台进行，成败以目录回读为准。"),
              h("span", { className: "odc-actions" },
                h("button", {
                  className: "odc-btn odc-btn-primary", disabled: busy === "install",
                  onClick: submitInstall
                }, busy === "install" ? "提交中…" : "开始安装"),
                h("button", {
                  className: "odc-btn odc-btn-text",
                  onClick: function () { setInst(null); }
                }, "取消"))));
          }
          return h("li", { key: e.name, className: "odc-row odc-row-card" }, kids);
        })));
      }
      body = parts;
    }
    return faceShell("连接器", "与 App 智能体连接器面同一数据源（dashboard /api/mcp/servers 与 /api/mcp/catalog）：已装服务开关/测试、目录安装同口。目录密钥只在安装请求里出现一次，不回显不落盘。", face, load, body);
  }

  // ---------------- delegation face (bar 4, gap #12) ----------------
  // api_key on a model route is a MASKED PREVIEW from the server (App
  // contract: the client never holds the real key). It round-trips
  // untouched in memory, renders only as a placeholder, and a newly
  // typed key replaces it in the submit body only. Unmodeled fields
  // ride along in `extras` (the raw option object) and are written
  // back unchanged.
  function DelegationFace() {
    var facePair = useFace(Core.fetchDelegation);
    var face = facePair[0];
    var load = facePair[1];
    var busyPair = hooks.useState("");
    var busy = busyPair[0];
    var setBusy = busyPair[1];
    var notePair = hooks.useState("");
    var note = notePair[0];
    var setNote = notePair[1];
    var mdPair = hooks.useState(null);
    var md = mdPair[0];
    var setMd = mdPair[1];
    var keysPair = hooks.useState({});
    var keyInputs = keysPair[0];
    var setKeyInputs = keysPair[1];
    var pdPair = hooks.useState(null);
    var pd = pdPair[0];
    var setPd = pdPair[1];

    function switchBackend(name) {
      setBusy("backend");
      setNote("");
      Core.setDelegationBackend(name).then(function () {
        setBusy("");
        setNote("已切换委派后端（以回读为准）。");
        load();
      }).catch(function (err) {
        setBusy("");
        setNote("切换没成：" + ((err && err.message) || String(err)) + "（已按服务端真值重读）");
        load();
      });
    }
    function editModelField(i, field, value) {
      var options = md.options.slice();
      options[i] = Object.assign({}, options[i], (function () {
        var o = {}; o[field] = value; return o;
      })());
      setMd({ options: options, "default": md["default"] });
    }
    function saveModelMap() {
      var errs = [];
      var seen = {};
      md.options.forEach(function (o, i) {
        var nm = String(o.name || "").trim();
        if (!nm) errs.push("第 " + (i + 1) + " 条缺名称");
        else if (seen[nm]) errs.push("名称重复：" + nm);
        seen[nm] = true;
        if (!String(o.description || "").trim()) errs.push("「" + (nm || i + 1) + "」缺说明");
        if (!String(o.model || "").trim()) errs.push("「" + (nm || i + 1) + "」缺模型");
        if (!String(o.provider || "").trim() && !String(o.base_url || "").trim()) {
          errs.push("「" + (nm || i + 1) + "」服务商与接口地址至少填一个");
        }
      });
      var def = md["default"] || "";
      if (def && !seen[def]) errs.push("默认路线不在名单内：" + def);
      if (errs.length) { setNote("先补齐：" + errs.join("；")); return; }
      var options = md.options.map(function (o, i) {
        var out = Object.assign({}, o);
        var nk = keyInputs[i];
        if (nk && String(nk).trim()) out.api_key = nk;
        return out;
      });
      setBusy("modelmap");
      setNote("");
      Core.setDelegationModelMap(options, def || null).then(function () {
        setBusy("");
        setMd(null);
        setKeyInputs({});
        setNote("模型路线已保存（以回读为准）。");
        load();
      }).catch(function (err) {
        setBusy("");
        setNote("保存没成：" + ((err && err.message) || String(err)) + "（已按服务端真值重读）");
        load();
      });
    }
    function saveProfileRoutes(profiles) {
      var errs = [];
      var seen = {};
      pd.profiles.forEach(function (r, i) {
        var nm = String(r.name || "").trim();
        if (!nm) errs.push("第 " + (i + 1) + " 条没选档案");
        else if (profiles.indexOf(nm) < 0) errs.push("档案不在名单内：" + nm);
        else if (seen[nm]) errs.push("档案重复：" + nm);
        seen[nm] = true;
      });
      var def = pd["default"] || "";
      if (def && !seen[def]) errs.push("默认档案路线不在名单内：" + def);
      if (errs.length) { setNote("先补齐：" + errs.join("；")); return; }
      setBusy("profmap");
      setNote("");
      Core.setDelegationProfileRoutes(pd.profiles, def || null).then(function () {
        setBusy("");
        setPd(null);
        setNote("档案路线已保存（以回读为准）。");
        load();
      }).catch(function (err) {
        setBusy("");
        setNote("保存没成：" + ((err && err.message) || String(err)) + "（已按服务端真值重读）");
        load();
      });
    }

    var body = null;
    if (face.phase === "ready") {
      var d = face.data || {};
      var backends = d.backends || [];
      var modelMap = d.model_map || { options: [], "default": "" };
      var profileRoutes = d.profile_routes || { profiles: [], "default": "" };
      var profiles = (d.profiles || []).map(function (p) {
        return typeof p === "string" ? p : (p && p.name) || String(p);
      });
      var parts = [];
      parts.push(h("p", { key: "cnt", className: "odc-count" },
        "当前后端：" + (d.configured || "未配置") + " · 后端 " + backends.length +
        " 个 · 模型路线 " + ((modelMap.options || []).length) + " 条 · 档案路线 " +
        ((profileRoutes.profiles || []).length) + " 条 · 档案 " + profiles.length + " 个"));
      if (d.blocked_reason) {
        parts.push(h("p", { key: "blk", className: "odc-error" }, "委派被拦：" + d.blocked_reason));
      }
      if (note) parts.push(h("p", { key: "note", className: "odc-warn" }, note));
      parts.push(h("p", { key: "bh", className: "odc-summary-head" }, "委派后端"));
      if (!backends.length) {
        parts.push(h("p", { key: "be", className: "odc-empty" }, "服务端没报后端名单。"));
      } else {
        parts.push(h("ul", { key: "bl", className: "odc-list" }, backends.map(function (b) {
          var current = b.name === d.configured;
          return h("li", { key: b.name, className: "odc-row odc-row-card" },
            h("div", { className: "odc-actions", style: { justifyContent: "space-between" } },
              h("span", { className: "odc-row-title" }, (b.label || b.name) + (b.builtin ? "（内置）" : "")),
              current
                ? h("span", { className: "odc-st odc-st-done" }, "当前")
                : h("span", { className: "odc-st " + (b.available ? "odc-st-pending" : "odc-st-failed") },
                  b.available ? "可用" : "不可用")),
            b.description ? h("p", { className: "odc-row-meta" }, b.description) : null,
            (!b.available && b.reason) ? h("p", { className: "odc-row-meta" }, "不可用原因：" + b.reason) : null,
            (!current && b.available)
              ? h("span", { className: "odc-actions" },
                h("button", {
                  className: "odc-btn odc-btn-small", disabled: busy === "backend",
                  onClick: function () { switchBackend(b.name); }
                }, "切换到这个后端"))
              : null);
        })));
      }
      // ---- model routes ----
      parts.push(h("p", { key: "mh", className: "odc-summary-head" }, "模型路线（子任务用哪个模型）"));
      if (!md) {
        var opts = modelMap.options || [];
        if (!opts.length) {
          parts.push(h("p", { key: "me", className: "odc-empty" }, "暂无模型路线（空集也是真数据）。"));
        } else {
          parts.push(h("ul", { key: "ml", className: "odc-list" }, opts.map(function (o) {
            var meta = [];
            if (o.provider) meta.push("服务商 " + o.provider);
            if (o.model) meta.push("模型 " + o.model);
            if (o.base_url) meta.push(o.base_url);
            if (o.api_mode) meta.push("模式 " + o.api_mode);
            if (o.reasoning_effort) meta.push("思考档 " + o.reasoning_effort);
            if (o.service_tier) meta.push("服务档 " + o.service_tier);
            meta.push(o.api_key ? "密钥已存（脱敏预览，不显示）" : "未存密钥");
            return h("li", { key: o.name, className: "odc-row" },
              h("span", null,
                h("span", { className: "odc-row-title" },
                  o.name + (modelMap["default"] === o.name ? "（默认）" : "")),
                h("p", { className: "odc-row-meta" }, (o.description || "") + (o.description ? " · " : "") + meta.join(" · "))));
          })));
        }
        parts.push(h("span", { key: "medit", className: "odc-actions" },
          h("button", {
            className: "odc-btn odc-btn-secondary",
            onClick: function () {
              setMd({
                options: (modelMap.options || []).map(function (o) { return Object.assign({}, o); }),
                "default": modelMap["default"] || ""
              });
              setKeyInputs({});
            }
          }, "编辑模型路线")));
      } else {
        var mfields = [
          ["name", "名称"], ["description", "说明"], ["provider", "服务商"],
          ["model", "模型"], ["base_url", "接口地址"], ["api_mode", "接口模式"],
          ["reasoning_effort", "思考档"], ["service_tier", "服务档"]
        ];
        var mkids = md.options.map(function (o, i) {
          return h("div", { key: "mo" + i, className: "odc-form" },
            mfields.map(function (f) {
              return h("label", { key: f[0], className: "odc-field" }, h("span", null, f[1]),
                h("input", {
                  type: "text", value: o[f[0]] || "",
                  onChange: function (ev) { editModelField(i, f[0], ev.target.value); }
                }));
            }),
            h("label", { className: "odc-field" },
              h("span", null, "接口密钥（留空＝保留已存；已存的只是脱敏预览，永不显示明文）"),
              h("input", {
                type: "password", value: keyInputs[i] || "", autoComplete: "off",
                placeholder: o.api_key ? "已存密钥（脱敏）" : "未存密钥",
                onChange: function (ev) {
                  var next = Object.assign({}, keyInputs);
                  next[i] = ev.target.value;
                  setKeyInputs(next);
                }
              })),
            h("span", { className: "odc-actions" },
              h("button", {
                className: "odc-btn odc-btn-text",
                onClick: function () {
                  var options = md.options.slice();
                  options.splice(i, 1);
                  setMd({ options: options, "default": md["default"] });
                }
              }, "删这条")));
        });
        mkids.push(h("label", { key: "mdef", className: "odc-field" }, h("span", null, "默认路线"),
          h("select", {
            value: md["default"] || "",
            onChange: function (ev) { setMd({ options: md.options, "default": ev.target.value }); }
          },
            [h("option", { key: "", value: "" }, "（不设默认）")].concat(md.options.map(function (o) {
              return h("option", { key: o.name || "", value: o.name || "" }, o.name || "（未命名）");
            })))));
        mkids.push(h("span", { key: "mact", className: "odc-actions" },
          h("button", {
            className: "odc-btn odc-btn-secondary",
            onClick: function () {
              setMd({
                options: md.options.concat([{
                  name: "", description: "", provider: "", model: "", base_url: "",
                  api_mode: "", reasoning_effort: "", service_tier: "", api_key: ""
                }]),
                "default": md["default"]
              });
            }
          }, "＋ 加一条"),
          h("button", {
            className: "odc-btn odc-btn-primary", disabled: busy === "modelmap", onClick: saveModelMap
          }, busy === "modelmap" ? "保存中…" : "保存模型路线"),
          h("button", {
            className: "odc-btn odc-btn-text",
            onClick: function () { setMd(null); setKeyInputs({}); }
          }, "取消")));
        parts.push(h("div", { key: "mform" }, mkids));
      }
      // ---- profile routes ----
      parts.push(h("p", { key: "ph2", className: "odc-summary-head" }, "档案路线（哪个档案走哪条）"));
      if (!pd) {
        var prs = profileRoutes.profiles || [];
        if (!prs.length) {
          parts.push(h("p", { key: "pe2", className: "odc-empty" }, "暂无档案路线（空集也是真数据）。"));
        } else {
          parts.push(h("ul", { key: "pl2", className: "odc-list" }, prs.map(function (r) {
            return h("li", { key: r.name, className: "odc-row" },
              h("span", null,
                h("span", { className: "odc-row-title" },
                  r.name + (profileRoutes["default"] === r.name ? "（默认）" : "")),
                r.description ? h("p", { className: "odc-row-meta" }, r.description) : null));
          })));
        }
        parts.push(h("span", { key: "pedit", className: "odc-actions" },
          h("button", {
            className: "odc-btn odc-btn-secondary",
            onClick: function () {
              setPd({
                profiles: (profileRoutes.profiles || []).map(function (r) {
                  return { name: r.name || "", description: r.description || "" };
                }),
                "default": profileRoutes["default"] || ""
              });
            }
          }, "编辑档案路线")));
      } else {
        var pkids = pd.profiles.map(function (r, i) {
          return h("div", { key: "pr" + i, className: "odc-form" },
            h("label", { className: "odc-field" }, h("span", null, "档案"),
              h("select", {
                value: r.name || "",
                onChange: function (ev) {
                  var list = pd.profiles.slice();
                  list[i] = { name: ev.target.value, description: list[i].description };
                  setPd({ profiles: list, "default": pd["default"] });
                }
              },
                [h("option", { key: "", value: "" }, "（选择档案）")].concat(profiles.map(function (p) {
                  return h("option", { key: p, value: p }, p);
                })))),
            h("label", { className: "odc-field" }, h("span", null, "说明"),
              h("input", {
                type: "text", value: r.description || "",
                onChange: function (ev) {
                  var list = pd.profiles.slice();
                  list[i] = { name: list[i].name, description: ev.target.value };
                  setPd({ profiles: list, "default": pd["default"] });
                }
              })),
            h("span", { className: "odc-actions" },
              h("button", {
                className: "odc-btn odc-btn-text",
                onClick: function () {
                  var list = pd.profiles.slice();
                  list.splice(i, 1);
                  setPd({ profiles: list, "default": pd["default"] });
                }
              }, "删这条")));
        });
        pkids.push(h("label", { key: "pdef", className: "odc-field" }, h("span", null, "默认档案路线"),
          h("select", {
            value: pd["default"] || "",
            onChange: function (ev) { setPd({ profiles: pd.profiles, "default": ev.target.value }); }
          },
            [h("option", { key: "", value: "" }, "（不设默认）")].concat(pd.profiles.map(function (r) {
              return h("option", { key: r.name || "", value: r.name || "" }, r.name || "（未选）");
            })))));
        pkids.push(h("span", { key: "pact", className: "odc-actions" },
          h("button", {
            className: "odc-btn odc-btn-secondary",
            onClick: function () {
              setPd({
                profiles: pd.profiles.concat([{ name: "", description: "" }]),
                "default": pd["default"]
              });
            }
          }, "＋ 加一条"),
          h("button", {
            className: "odc-btn odc-btn-primary", disabled: busy === "profmap",
            onClick: function () { saveProfileRoutes(profiles); }
          }, busy === "profmap" ? "保存中…" : "保存档案路线"),
          h("button", {
            className: "odc-btn odc-btn-text",
            onClick: function () { setPd(null); }
          }, "取消")));
        parts.push(h("div", { key: "pform" }, pkids));
      }
      body = parts;
    }
    return faceShell("委派", "与 App 智能体委派面同一数据源（dashboard /api/delegation/routing）：后端切换、模型路线、档案路线同口，成败以回读为准。模型路线里的密钥只是服务端脱敏预览——永不显示明文，留空保存即保留已存密钥。", face, load, body);
  }

  // ---------------- bar 5 faces ----------------
  function settle(p) {
    return p.then(function (v) { return { ok: true, v: v }; },
      function (e) { return { ok: false, e: (e && e.message) || String(e) }; });
  }

  // ---- #15 toolsets face ----
  function ToolsetsFace() {
    var facePair = useFace(Core.fetchToolsets);
    var face = facePair[0];
    var load = facePair[1];
    var busyPair = hooks.useState("");
    var busy = busyPair[0];
    var setBusy = busyPair[1];
    var notePair = hooks.useState(null);
    var note = notePair[0];
    var setNote = notePair[1];

    function toggle(ts) {
      setBusy(ts.name);
      setNote(null);
      Core.setToolsetEnabled(ts.name, !ts.enabled).then(function () {
        setBusy("");
        setNote({ kind: "done", text: "已" + (!ts.enabled ? "启用" : "停用") + "「" + (ts.label || ts.name) + "」（以回读为准）" });
        load();
      }).catch(function (err) {
        setBusy("");
        setNote({ kind: "error", text: "切换失败：" + ((err && err.message) || String(err)) + "（请看回读）" });
        load();
      });
    }

    var body = null;
    if (face.phase === "ready") {
      var list = (face.data && Array.isArray(face.data.data)) ? face.data.data : [];
      var parts = [];
      var enabledN = 0, configuredN = 0;
      list.forEach(function (ts) { if (ts.enabled) enabledN++; if (ts.configured) configuredN++; });
      parts.push(h("p", { key: "count", className: "odc-count" },
        "工具集共 ", h("strong", null, String(list.length)), " 个（api_server 平台，与 App 设置同一接口）。已启用 " + enabledN + " · 已停用 " + (list.length - enabledN) + "（按启停开关计）；已配置 " + configuredN + "（凭据/参数齐全，与启停是两回事）。切换对新会话生效，进行中的会话不变。"));
      if (note) {
        parts.push(h("p", { key: "note", className: note.kind === "error" ? "odc-error" : "odc-done" }, note.text));
      }
      if (!list.length) parts.push(h("p", { key: "empty", className: "odc-empty" }, "暂无工具集。"));
      list.forEach(function (ts) {
        var meta = [];
        meta.push(ts.name);
        if (ts.description) meta.push(ts.description);
        if (Array.isArray(ts.tools)) meta.push(ts.tools.length + " 个工具");
        var kids = [
          h("span", { key: "t", className: "odc-row-title" }, ts.label || ts.name),
          h("span", { key: "m", className: "odc-row-meta" }, meta.join(" · ")),
          h("span", { key: "acts", className: "odc-actions" },
            h("span", { key: "cfg", className: "odc-chip" }, ts.configured ? "已配置" : "未配置"),
            h("button", {
              key: "tg",
              className: ts.enabled ? "odc-chip odc-chip-btn odc-chip-on" : "odc-chip odc-chip-btn",
              disabled: busy === ts.name,
              onClick: function () { toggle(ts); }
            }, busy === ts.name ? "切换中…" : (ts.enabled ? "已启用（点按停用）" : "已停用（点按启用）")))
        ];
        parts.push(h("div", { key: ts.name, className: "odc-row odc-row-card" }, kids));
      });
      body = parts;
    }
    return faceShell("工具集", "与 App 设置里的工具集开关全集同一数据源（GET/PUT /v1/toolsets）：这里启停的是 api_server 平台集，手机会话实际用的就是这一套。", face, load, body);
  }

  // ---- #23 structured settings face (read-only) ----
  var SETTINGS_SURFACE_WORDS = {
    top: "置顶", agent: "智能体", serverAndWorkspace: "服务器与工作区",
    preferences: "偏好", support: "支持", chat: "聊天", hub: "枢纽"
  };
  var SETTINGS_WRITABLE_WORDS = {
    none: "仅查看", user: "可在 App 修改", agent: "智能体可改", both: "App 与智能体可改"
  };
  function settingValueText(rec) {
    var v = rec.value;
    if (v === null || v === undefined) return "未设置";
    if (typeof v === "boolean") return v ? "开" : "关";
    if (typeof v === "number") return String(v);
    if (typeof v === "string") {
      if (/key|secret|token|password|credential/i.test(rec.key || "")) return "••••（不在网页端显示）";
      return v.length > 80 ? v.slice(0, 80) + "…" : v;
    }
    return "（结构化值，见 App）";
  }

  function SettingsFace() {
    var facePair = useFace(Core.fetchSettingsRegistry);
    var face = facePair[0];
    var load = facePair[1];
    var body = null;
    if (face.phase === "ready") {
      var records = (face.data && Array.isArray(face.data.records)) ? face.data.records : [];
      var groups = {};
      var order = [];
      records.forEach(function (rec) {
        var s = rec.surface || "其他";
        if (!groups[s]) { groups[s] = []; order.push(s); }
        groups[s].push(rec);
      });
      var parts = [];
      parts.push(h("p", { key: "count", className: "odc-count" },
        "注册表共 ", h("strong", null, String(records.length)), " 条（版本 " + (face.data.version != null ? face.data.version : "?") + "，与 App 设置注册表同一数据源）。"));
      order.forEach(function (s) {
        parts.push(h("p", { key: "g-" + s, className: "odc-summary-head" },
          (SETTINGS_SURFACE_WORDS[s] || s) + "（" + groups[s].length + " 条）"));
        groups[s].forEach(function (rec) {
          var meta = [];
          if (rec.destination) meta.push("去向 " + rec.destination);
          meta.push(SETTINGS_WRITABLE_WORDS[rec.writable_by] || "仅查看");
          parts.push(h("div", { key: rec.key, className: "odc-row" },
            h("span", { key: "t" },
              h("span", { className: "odc-row-title" }, rec.title || rec.key),
              h("span", { className: "odc-row-meta" }, " " + meta.join(" · "))),
            h("span", { key: "v", className: "odc-chip" }, settingValueText(rec))));
        });
      });
      if (!records.length) parts.push(h("p", { key: "empty", className: "odc-empty" }, "注册表暂无记录。"));
      body = parts;
    }
    return faceShell("结构化设置", "本面只读呈现（GET /v1/settings/registry）：修改请在 App 设置或对应功能面进行，本面不冒充可写。密钥类条目的值不在网页端显示。", face, load, body);
  }

  // ---- #22 identity face ----
  // App 预置头像目录（OneDayCore AgentAvatarPreset 色板与
  // BotCharacterSpec 渐变同口径）：preset 条目服务端只有
  // presetId、无图片字节（_read_avatar_image 对 kind!=image
  // 回 400），网页端本地按 presetId 给渐变色＋符号渲染，
  // 不发取图请求。partner 在 App 是相伴资产图，网页端以
  // 同色系符号格近似呈现。
  var AVATAR_PRESETS = {
    "blob-blue": { sym: "☺", cls: "odc-preset-blob-blue" },
    "cat-violet": { sym: "🐱", cls: "odc-preset-cat-violet" },
    "bear-amber": { sym: "🐻", cls: "odc-preset-bear-amber" },
    "bot-cyan": { sym: "🤖", cls: "odc-preset-bot-cyan" },
    "sprout-green": { sym: "🌱", cls: "odc-preset-sprout-green" },
    "star-pink": { sym: "⭐", cls: "odc-preset-star-pink" },
    "blob-coral": { sym: "☺", cls: "odc-preset-blob-coral" },
    "bot-slate": { sym: "🤖", cls: "odc-preset-bot-slate" },
    "paw": { sym: "🐾", cls: "odc-preset-sym" },
    "sparkles": { sym: "✨", cls: "odc-preset-sym" },
    "atom": { sym: "⚛", cls: "odc-preset-sym" },
    "partner": { sym: "🐶", cls: "odc-preset-partner" }
  };
  function avatarPreset(presetId) {
    return AVATAR_PRESETS[presetId] || AVATAR_PRESETS["blob-blue"];
  }

  function IdentityFace() {
    var facePair = useFace(function () {
      return Promise.all([Core.fetchIdentityName(), Core.fetchIdentityAvatar()]);
    });
    var face = facePair[0];
    var load = facePair[1];
    var urlsPair = hooks.useState({});
    var urls = urlsPair[0];
    var setUrls = urlsPair[1];
    var failedPair = hooks.useState({});
    var failed = failedPair[0];
    var setFailed = failedPair[1];

    hooks.useEffect(function () {
      if (face.phase !== "ready" || !face.data) return;
      var avatar = face.data[1] || {};
      (avatar.items || []).forEach(function (it) {
        if (it.kind !== "image") return; // preset 本地渲染，不取图
        if (urls[it.id] || failed[it.id]) return;
        Core.fetchAvatarImageBlob(it.id).then(function (blob) {
          var u = URL.createObjectURL(blob);
          setUrls(function (prev) {
            var n = {};
            for (var k in prev) n[k] = prev[k];
            n[it.id] = u;
            return n;
          });
        }).catch(function () {
          setFailed(function (prev) {
            var n = {};
            for (var k in prev) n[k] = prev[k];
            n[it.id] = true;
            return n;
          });
        });
      });
    }, [face.phase]);

    var body = null;
    if (face.phase === "ready") {
      var name = face.data[0] || {};
      var avatar2 = face.data[1] || {};
      var items = Array.isArray(avatar2.items) ? avatar2.items : [];
      var parts = [];
      parts.push(h("p", { key: "name", className: "odc-count" },
        "当前名称：", h("strong", null, name.soulName || "（未设置）")));
      var nmeta = [];
      if (name.source) nmeta.push("来源 " + name.source);
      if (name.updatedAt) nmeta.push("更新于 " + fmtTs(name.updatedAt));
      if (nmeta.length) parts.push(h("p", { key: "nmeta", className: "odc-row-meta" }, nmeta.join(" · ")));
      if (name.note) parts.push(h("p", { key: "note", className: "odc-sub" }, name.note));
      parts.push(h("p", { key: "ah", className: "odc-summary-head" },
        "头像（共 " + items.length + " 个，当前一个已标注）"));
      if (!items.length) {
        parts.push(h("p", { key: "aempty", className: "odc-empty" }, "暂无头像记录。"));
      } else {
        parts.push(h("div", { key: "agrid", className: "odc-avatar-grid" },
          items.map(function (it) {
            var meta = [];
            if (it.kind) meta.push(it.kind);
            if (it.kind === "preset" && it.presetId) meta.push(it.presetId);
            if (it.source) meta.push(it.source);
            if (it.createdAt) meta.push(fmtTsShort(it.createdAt));
            var on = it.current ? " odc-avatar-on" : "";
            var cell;
            if (it.kind === "preset") {
              var p = avatarPreset(it.presetId);
              cell = h("div", { className: "odc-avatar odc-avatar-preset " + p.cls + on }, p.sym);
            } else if (urls[it.id]) {
              cell = h("img", { className: "odc-avatar odc-img-zoom" + on, src: urls[it.id], alt: it.id, title: "点击看大图", onClick: function () { openLightbox(urls[it.id]); } });
            } else if (failed[it.id]) {
              cell = h("div", { className: "odc-avatar odc-avatar-ph odc-avatar-fail" + on }, "图片加载失败");
            } else {
              cell = h("div", { className: "odc-avatar odc-avatar-ph" + on }, "…");
            }
            return h("div", { key: it.id, className: "odc-avatar-cell" },
              cell,
              h("span", { className: "odc-row-meta" }, (it.current ? "当前 · " : "") + meta.join(" · ")));
          })));
      }
      body = parts;
    }
    return faceShell("身份", "与 dashboard 的 Profiles 分工：Profiles 管档案与 Soul 编辑，本面呈 OneDay 身份面（名称与头像）的当前状态。改名走 App 或 Soul 面——网关的名称写口已退役，本面只读。", face, load, body);
  }

  // ---- #20 devices face (status aggregation only) ----
  function DevicesFace() {
    var facePair = useFace(function () {
      return Promise.all([
        settle(Core.fetchDeviceHealth()),
        settle(Core.fetchDeviceSyncStatus()),
        settle(Core.fetchPushTokens()),
        settle(Core.fetchAuthSessions())
      ]);
    });
    var face = facePair[0];
    var load = facePair[1];
    var body = null;
    if (face.phase === "ready") {
      var health = face.data[0];
      var sync = face.data[1];
      var tokens = face.data[2];
      var sessions = face.data[3];
      var parts = [];
      // device channel
      parts.push(h("p", { key: "h1", className: "odc-summary-head" }, "设备通道"));
      if (health.ok) {
        var hv = health.v || {};
        parts.push(h("div", { key: "hv", className: "odc-row" },
          h("span", { className: "odc-row-title" }, hv.service || "device-bridge"),
          h("span", { className: hv.sessionOnline ? "odc-chip odc-chip-on" : "odc-chip" },
            hv.sessionOnline ? "设备会话在线" : "设备会话离线")));
      } else {
        parts.push(h("p", { key: "he", className: "odc-error" }, "通道状态读取失败：" + health.e));
      }
      // sync datasets
      parts.push(h("p", { key: "h2", className: "odc-summary-head" }, "数据同步"));
      if (sync.ok) {
        var datasets = (sync.v && sync.v.datasets) || {};
        var keys = Object.keys(datasets);
        if (!keys.length) parts.push(h("p", { key: "se", className: "odc-empty" }, "暂无同步数据集。"));
        keys.forEach(function (k) {
          var d = datasets[k] || {};
          var meta = [];
          if (d.freshness) meta.push(d.freshness);
          if (d.item_count != null) meta.push(d.item_count + " 条");
          if (d.permission_state) meta.push("权限 " + d.permission_state);
          if (d.auth_range) meta.push("范围 " + d.auth_range);
          if (d.syncing) meta.push("同步中");
          if (d.pending_write) meta.push("有待写");
          var kids = [
            h("span", { key: "t" },
              h("span", { className: "odc-row-title" }, d.label || k),
              h("span", { className: "odc-row-meta" }, " " + meta.join(" · "))),
            h("span", { key: "s", className: d.expired ? "odc-chip odc-st-failed" : "odc-chip odc-st-done" },
              d.expired ? "已过期" : (d.synced ? "已同步" : "未同步"))
          ];
          if (d.last_error) kids.push(h("span", { key: "err", className: "odc-error" }, "最近错误：" + d.last_error));
          parts.push(h("div", { key: "ds-" + k, className: "odc-row odc-row-card" }, kids));
        });
      } else {
        parts.push(h("p", { key: "se2", className: "odc-error" }, "同步状态读取失败：" + sync.e));
      }
      // push tokens
      parts.push(h("p", { key: "h3", className: "odc-summary-head" }, "推送设备"));
      if (tokens.ok) {
        var tv = tokens.v || {};
        var tlist = Array.isArray(tv.data) ? tv.data : [];
        parts.push(h("p", { key: "tc", className: "odc-sub" },
          "已登记 " + tlist.length + " 台 · APNs " + (tv.apns_configured ? "已配置" : "未配置") + "（令牌只显示服务端脱敏预览）"));
        tlist.forEach(function (t, i) {
          var meta = [];
          if (t.environment) meta.push(t.environment);
          if (t.bundle_id) meta.push(t.bundle_id);
          if (t.app_version) meta.push("App " + t.app_version);
          if (t.updated_at) meta.push("更新 " + fmtTs(t.updated_at));
          parts.push(h("div", { key: "tk-" + i, className: "odc-row" },
            h("span", { className: "odc-row-title" }, t.token_preview || "（令牌）"),
            h("span", { className: "odc-row-meta" }, meta.join(" · "))));
        });
      } else {
        parts.push(h("p", { key: "te", className: "odc-error" }, "推送设备读取失败：" + tokens.e));
      }
      // auth sessions
      parts.push(h("p", { key: "h4", className: "odc-summary-head" }, "设备登录会话"));
      if (sessions.ok) {
        var slist = (sessions.v && Array.isArray(sessions.v.data)) ? sessions.v.data : [];
        if (!slist.length) parts.push(h("p", { key: "sn", className: "odc-empty" }, "暂无设备会话。"));
        slist.forEach(function (s2, i) {
          var meta = [];
          if (s2.app_version) meta.push("App " + s2.app_version);
          if (s2.last_used_at) meta.push("最近使用 " + fmtTs(s2.last_used_at));
          parts.push(h("div", { key: "ss-" + i, className: "odc-row" },
            h("span", { className: "odc-row-title" }, s2.device_name || s2.session_id || "（设备）"),
            h("span", { className: s2.revoked ? "odc-chip odc-st-failed" : "odc-chip odc-st-done" },
              s2.revoked ? "已撤销" : "有效")));
          if (meta.length) {
            parts.push(h("p", { key: "ssm-" + i, className: "odc-row-meta" }, meta.join(" · ")));
          }
        });
      } else {
        parts.push(h("p", { key: "se3", className: "odc-error" }, "设备会话读取失败：" + sessions.e));
      }
      body = parts;
    }
    return faceShell("设备", "只做状态聚合呈现（设备通道／数据同步／推送设备／登录会话）：与 App 智能体设备面同一数据源，不做远程控制。", face, load, body);
  }

  // ---- #21 computer face (status aggregation only) ----
  function ComputerFace() {
    var facePair = useFace(function () {
      return Promise.all([
        settle(Core.fetchHealth()),
        settle(Core.fetchCapabilities()),
        settle(Core.fetchDeviceHealth()),
        settle(Core.fetchJobs())
      ]);
    });
    var face = facePair[0];
    var load = facePair[1];
    var body = null;
    if (face.phase === "ready") {
      var health = face.data[0];
      var caps = face.data[1];
      var dev = face.data[2];
      var jobs = face.data[3];
      var cells = [];
      if (health.ok && health.v) {
        cells.push({ k: "gw", label: "网关", value: health.v.status || "ok" });
        if (health.v.version) cells.push({ k: "gv", label: "网关版本", value: String(health.v.version) });
      } else {
        cells.push({ k: "gw", label: "网关", value: "读取失败" });
      }
      if (caps.ok && caps.v && caps.v.features) {
        var feat = caps.v.features;
        var on = Object.keys(feat).filter(function (k) { return feat[k] === true; }).length;
        cells.push({ k: "feat", label: "已开功能位", value: on + " / " + Object.keys(feat).length });
      }
      if (dev.ok && dev.v) {
        cells.push({ k: "dev", label: "设备会话", value: dev.v.sessionOnline ? "在线" : "离线" });
      }
      if (jobs.ok) {
        var jlist = Array.isArray(jobs.v) ? jobs.v : (jobs.v && Array.isArray(jobs.v.jobs) ? jobs.v.jobs : []);
        cells.push({ k: "jobs", label: "定时任务", value: String(jlist.length) + " 个" });
      }
      var parts = [];
      parts.push(h("div", { key: "cells", className: "odc-counts" },
        cells.map(function (c) {
          return h("div", { key: c.k, className: "odc-count-cell" },
            h("div", { className: "odc-count-num" }, c.value),
            h("div", { className: "odc-row-meta" }, c.label));
        })));
      parts.push(h("p", { key: "note", className: "odc-sub" },
        "电脑的终端与工作区在 dashboard 聊天页（上游面，比本面更强）：本面只聚合状态，不做远程控制。"));
      parts.push(h("p", { key: "links", className: "odc-actions" },
        h("a", { className: "odc-btn", href: "/" }, "打开 dashboard 聊天／工作区"),
        h("a", { className: "odc-btn", href: "/files" }, "打开服务器文件页"),
        h("a", { className: "odc-btn", href: "/system" }, "打开系统页")));
      body = parts;
    }
    return faceShell("电脑", "盒子状态聚合（网关健康／功能位／设备会话／定时任务）＋会话面链接聚合：只呈状态，不复刻终端。", face, load, body);
  }

  // ---- #16 reactions face ----
  var REACTION_PALETTE = ["👍", "❤️", "😂", "😮", "😢", "🙏", "🔥", "🎉"];
  var ROLE_WORDS = { user: "用户", assistant: "助手", tool: "工具", system: "系统" };
  function parseReactions(m) {
    var meta = m && m.display_metadata;
    if (typeof meta === "string") {
      try { meta = JSON.parse(meta); } catch (e) { meta = null; }
    }
    var rs = (meta && Array.isArray(meta.reactions)) ? meta.reactions : [];
    return rs.filter(function (r) { return r && typeof r.emoji === "string" && r.emoji; });
  }

  function ReactionsFace() {
    var sessPair = useFace(Core.fetchDashSessions);
    var sess = sessPair[0];
    var sessLoad = sessPair[1];
    var selPair = hooks.useState("");
    var sel = selPair[0];
    var setSel = selPair[1];
    var msgPair = hooks.useState({ phase: "idle", data: null, error: "" });
    var msgs = msgPair[0];
    var setMsgs = msgPair[1];
    var openPair = hooks.useState("");
    var openId = openPair[0];
    var setOpenId = openPair[1];
    var busyPair = hooks.useState("");
    var busy = busyPair[0];
    var setBusy = busyPair[1];
    var notePair = hooks.useState(null);
    var note = notePair[0];
    var setNote = notePair[1];

    function loadMessages(sid) {
      setMsgs({ phase: "loading", data: null, error: "" });
      Core.fetchDashMessages(sid).then(function (d) {
        setMsgs({ phase: "ready", data: d, error: "" });
      }).catch(function (e) {
        setMsgs({ phase: "error", data: null, error: (e && e.message) || String(e) });
      });
    }
    function choose(sid) {
      setSel(sid);
      setOpenId("");
      setNote(null);
      if (sid) loadMessages(sid);
      else setMsgs({ phase: "idle", data: null, error: "" });
    }
    function react(m, emoji) {
      var mine = parseReactions(m).filter(function (r) { return r.author === "user"; })[0];
      setBusy(String(m.id));
      setNote(null);
      var p = (mine && mine.emoji === emoji)
        ? Core.clearReaction(sel, m.id)
        : Core.setReaction(sel, m.id, emoji);
      p.then(function () {
        setBusy("");
        setNote({ kind: "done", text: "反应已更新（以回读为准）" });
        loadMessages(sel);
      }).catch(function (err) {
        setBusy("");
        setNote({ kind: "error", text: "反应失败：" + ((err && err.message) || String(err)) });
      });
    }
    function clearMine(m) {
      setBusy(String(m.id));
      setNote(null);
      Core.clearReaction(sel, m.id).then(function () {
        setBusy("");
        setNote({ kind: "done", text: "已撤回你的反应（以回读为准）" });
        loadMessages(sel);
      }).catch(function (err) {
        setBusy("");
        setNote({ kind: "error", text: "撤回失败：" + ((err && err.message) || String(err)) });
      });
    }

    var body = null;
    if (sess.phase === "ready") {
      var sessions = (sess.data && Array.isArray(sess.data.sessions)) ? sess.data.sessions : [];
      var parts = [];
      parts.push(h("label", { key: "pick", className: "odc-field" }, h("span", null, "选一个会话看消息与反应（最近 20 个，共 " + (sess.data.total != null ? sess.data.total : sessions.length) + " 个）"),
        h("select", {
          value: sel,
          onChange: function (ev) { choose(ev.target.value); }
        },
          [h("option", { key: "", value: "" }, "（请选择会话）")].concat(sessions.map(function (s) {
            var label = s.display_name || s.title || s.id;
            return h("option", { key: s.id, value: s.id },
              label + (s.message_count != null ? " · " + s.message_count + " 条" : ""));
          })))));
      if (note) {
        parts.push(h("p", { key: "note", className: note.kind === "error" ? "odc-error" : "odc-done" }, note.text));
      }
      if (msgs.phase === "loading") {
        parts.push(h("p", { key: "ml", className: "odc-empty" }, "正在读消息……"));
      } else if (msgs.phase === "error") {
        parts.push(h("p", { key: "me", className: "odc-error" }, "消息读取失败：" + msgs.error));
      } else if (msgs.phase === "ready") {
        var list = (msgs.data && Array.isArray(msgs.data.messages)) ? msgs.data.messages : [];
        var shown = list.slice(-60);
        if (!shown.length) parts.push(h("p", { key: "mn", className: "odc-empty" }, "这个会话暂无消息。"));
        shown.forEach(function (m) {
          var rs = parseReactions(m);
          var mine = rs.filter(function (r) { return r.author === "user"; })[0];
          var content = (typeof m.content === "string") ? m.content : "";
          var kids = [
            h("span", { key: "h" },
              h("span", { className: "odc-row-title" }, ROLE_WORDS[m.role] || (m.role || "消息")),
              h("span", { className: "odc-row-meta" }, " " + fmtTs(m.timestamp))),
            h("span", { key: "c", className: "odc-preview" },
              content ? (content.length > 160 ? content.slice(0, 160) + "…" : content) : "（无文本内容）")
          ];
          if (rs.length) {
            kids.push(h("span", { key: "rs", className: "odc-chips" },
              rs.map(function (r, i) {
                return h("span", { key: i, className: "odc-chip" },
                  r.emoji + " " + (r.author === "user" ? "我" : "助手"));
              })));
          }
          var acts = [];
          if (mine) {
            acts.push(h("button", {
              key: "mine", className: "odc-btn odc-btn-text", disabled: busy === String(m.id),
              onClick: function () { clearMine(m); }
            }, "你的反应：" + mine.emoji + "，点按撤回"));
          }
          acts.push(h("button", {
            key: "open", className: "odc-btn odc-btn-small",
            onClick: function () { setOpenId(openId === String(m.id) ? "" : String(m.id)); }
          }, openId === String(m.id) ? "收起表情盘" : "加反应"));
          kids.push(h("span", { key: "acts", className: "odc-actions" }, acts));
          if (openId === String(m.id)) {
            kids.push(h("span", { key: "pal", className: "odc-chips" },
              REACTION_PALETTE.map(function (e) {
                return h("button", {
                  key: e, className: "odc-emoji-btn", disabled: busy === String(m.id),
                  onClick: function () { react(m, e); }
                }, e);
              })));
          }
          parts.push(h("div", { key: String(m.id), className: "odc-row odc-row-card" }, kids));
        });
      }
      parts.push(h("p", { key: "q19", className: "odc-warn" },
        "引用回复核查结论（差集 #19）：未销账·遗留。dashboard 聊天是 xterm 终端面，插件无法往终端画布组装引用结构、也没有自有发送面把引用随消息送出；待上游聊天面形态变化或路线 B 独立聊天面再议。"));
      body = parts;
    }
    return faceShell("消息反应", "聊天是终端面、嵌不了反应条，反应在本面集中查看与设置：与 App 同一存储（消息 display_metadata.reactions），表情盘与 App 同一套八个。选会话 → 选消息 → 点表情即设置，再点同一个即撤回。", sess, sessLoad, body);
  }

  // ---- #17 TTS speak face ----
  var speechAudio = null;
  function SpeechFace() {
    var facePair = useFace(Core.fetchVoiceConfig);
    var face = facePair[0];
    var load = facePair[1];
    var textPair = hooks.useState("");
    var text = textPair[0];
    var setText = textPair[1];
    var busyPair = hooks.useState(false);
    var busy = busyPair[0];
    var setBusy = busyPair[1];
    var playPair = hooks.useState(false);
    var playing = playPair[0];
    var setPlaying = playPair[1];
    var notePair = hooks.useState(null);
    var note = notePair[0];
    var setNote = notePair[1];

    function stopAudio() {
      if (speechAudio) {
        try { speechAudio.pause(); speechAudio.currentTime = 0; } catch (e) { /* noop */ }
      }
      setPlaying(false);
    }
    function speakNow() {
      var t = (text || "").trim();
      if (!t) { setNote({ kind: "error", text: "先输入要播报的文字。" }); return; }
      setBusy(true);
      setNote(null);
      Core.speak(t).then(function (resp) {
        setBusy(false);
        if (!resp || resp.ok === false || !resp.data_url) {
          setNote({ kind: "error", text: "播报未成功：" + ((resp && (resp.error || resp.message)) || "服务端未返回音频") });
          return;
        }
        stopAudio();
        var a = new Audio(resp.data_url);
        speechAudio = a;
        a.onended = function () { setPlaying(false); };
        var pr = a.play();
        if (pr && pr.catch) pr.catch(function (e) {
          setPlaying(false);
          setNote({ kind: "error", text: "浏览器未能播放：" + ((e && e.message) || String(e)) });
        });
        setPlaying(true);
        setNote({ kind: "done", text: "正在播报（合成 provider：" + (resp.provider || "未知") + "，以服务端回执为准）" });
      }).catch(function (err) {
        setBusy(false);
        setNote({ kind: "error", text: "播报失败：" + ((err && err.message) || String(err)) });
      });
    }

    var body = null;
    if (face.phase === "ready") {
      var vc = face.data || {};
      var parts = [];
      var vmeta = [];
      if (vc.tts) vmeta.push("播报模式 " + (vc.tts.mode || "?") + (vc.tts.reason ? "（" + vc.tts.reason + "）" : ""));
      if (vc.stt) vmeta.push("听写模式 " + (vc.stt.mode || "?"));
      if (vmeta.length) parts.push(h("p", { key: "vc", className: "odc-sub" }, vmeta.join(" · ")));
      parts.push(h("label", { key: "ta", className: "odc-field" }, h("span", null, "要播报的文字"),
        h("textarea", {
          rows: 4, value: text, placeholder: "输入文字，点播报即合成播放",
          onChange: function (ev) { setText(ev.target.value); }
        })));
      parts.push(h("span", { key: "acts", className: "odc-actions" },
        h("button", { className: "odc-btn odc-btn-primary", disabled: busy, onClick: speakNow },
          busy ? "合成中…" : "播报"),
        h("button", { className: "odc-btn", disabled: !playing, onClick: stopAudio }, "停止")));
      if (note) {
        parts.push(h("p", { key: "note", className: note.kind === "error" ? "odc-error" : "odc-done" }, note.text));
      }
      body = parts;
    }
    return faceShell("语音播报", "与 App 播报同一端点（dashboard /api/audio/speak）：输入文字 → 服务端合成 → 本页播放。聊天内播报在终端面里做不了，集中在本面。", face, load, body);
  }

  // ---- #18 dictation face (browser Web Speech API only) ----
  var dictationRec = null;
  function DictationFace() {
    var textPair = hooks.useState("");
    var text = textPair[0];
    var setText = textPair[1];
    var recPair = hooks.useState(false);
    var recOn = recPair[0];
    var setRecOn = recPair[1];
    var notePair = hooks.useState("");
    var note = notePair[0];
    var setNote = notePair[1];
    var supported = !!(window.SpeechRecognition || window.webkitSpeechRecognition);
    var fakeFace = { phase: "ready", data: null, error: "" };

    function toggle() {
      if (recOn) {
        if (dictationRec) { try { dictationRec.stop(); } catch (e) { /* noop */ } }
        return;
      }
      if (!supported) {
        setNote("当前浏览器不支持 Web Speech 识别（Chrome 系浏览器支持较好）。");
        return;
      }
      var Ctor = window.SpeechRecognition || window.webkitSpeechRecognition;
      var rec = new Ctor();
      rec.lang = "zh-CN";
      rec.interimResults = false;
      rec.continuous = true;
      rec.onresult = function (ev) {
        var add = "";
        for (var i = ev.resultIndex; i < ev.results.length; i++) {
          if (ev.results[i].isFinal) add += ev.results[i][0].transcript;
        }
        if (add) {
          setText(function (prev) { return (prev ? prev + "\n" : "") + add; });
        }
      };
      rec.onend = function () { setRecOn(false); };
      rec.onerror = function (ev) {
        setNote("识别出错：" + (ev.error || "未知"));
        setRecOn(false);
      };
      dictationRec = rec;
      setNote("");
      try {
        rec.start();
        setRecOn(true);
      } catch (e) {
        setNote("识别启动失败：" + ((e && e.message) || String(e)));
      }
    }

    var body = [
      h("label", { key: "ta", className: "odc-field" }, h("span", null, "听写文本（识别结果逐句追加，也可直接编辑）"),
        h("textarea", {
          rows: 5, value: text, placeholder: "点开始听写，对着麦克风说话",
          onChange: function (ev) { setText(ev.target.value); }
        })),
      h("span", { key: "acts", className: "odc-actions" },
        h("button", { className: recOn ? "odc-btn odc-btn-primary" : "odc-btn", onClick: toggle },
          recOn ? "停止听写" : "开始听写"),
        h("button", {
          className: "odc-btn odc-btn-text",
          onClick: function () { setText(""); }
        }, "清空")),
      note ? h("p", { key: "note", className: "odc-warn" }, note) : null,
      h("p", { key: "legacy", className: "odc-warn" },
        "说明：本面听写用浏览器 Web Speech API 起步，识别在浏览器侧进行、可用性取决于浏览器；服务端转写尚未接入本面（遗留）。")
    ];
    return faceShell("听写", "插件面自有输入框＋浏览器原生语音识别：与 App 输入框听写对位，网页端先以浏览器识别落地。", fakeFace, function () { setNote(""); }, body);
  }

  // ---- #24 cross-face search (pure frontend aggregation) ----
  function arrOf(d, keys) {
    if (Array.isArray(d)) return d;
    if (!d || typeof d !== "object") return [];
    for (var i = 0; i < keys.length; i++) {
      if (Array.isArray(d[keys[i]])) return d[keys[i]];
    }
    return [];
  }

  function SearchFace() {
    var qPair = hooks.useState("");
    var q = qPair[0];
    var setQ = qPair[1];
    var runPair = hooks.useState({ phase: "idle", groups: null });
    var run = runPair[0];
    var setRun = runPair[1];
    var fakeFace = { phase: "ready", data: null, error: "" };

    function collect(promise, faceId, label, rowsFn, titleFn, metaFn, bodyFn) {
      return promise.then(function (d) {
        var rows = [];
        rowsFn(d).forEach(function (r) {
          var title = titleFn(r) || "";
          var meta = metaFn ? (metaFn(r) || "") : "";
          var b = bodyFn ? (bodyFn(r) || "") : "";
          rows.push({ title: title, meta: meta, b: b });
        });
        return { faceId: faceId, label: label, rows: rows };
      }).catch(function () {
        return { faceId: faceId, label: label, rows: null };
      });
    }

    function runSearch() {
      var needle = (q || "").trim().toLowerCase();
      if (!needle) return;
      setRun({ phase: "loading", groups: null });
      function hit(s) { return typeof s === "string" && s.toLowerCase().indexOf(needle) >= 0; }
      var jobs = [
        collect(Core.fetchGoals(), "odc-face-goals", "目标",
          function (d) { return arrOf(d, ["goals", "items", "data"]); },
          function (r) { return r.title || r.name; }, function (r) { return r.status; }, null),
        collect(Core.fetchIdeas(), "odc-face-ideas", "想法",
          function (d) { return arrOf(d, ["ideas", "items", "data"]); },
          function (r) { return r.title || r.name; }, function (r) { return r.status; },
          function (r) { return r.summary || r.body; }),
        collect(Core.fetchFeed(), "odc-face-feed", "动态",
          function (d) { return arrOf(d, ["posts", "items", "data"]); },
          function (r) { return r.title; }, function (r) { return r.source_name || r.kind; },
          function (r) { return r.body || r.content; }),
        collect(Core.fetchFileLibrary(), "odc-face-files", "文件库",
          function (d) { return arrOf(d, ["files", "items", "data"]); },
          function (r) { return r.name || r.title; }, function (r) { return r.path; }, null),
        collect(Core.fetchMonitors(), "odc-face-monitors", "监控",
          function (d) { return arrOf(d, ["monitors", "items", "data"]); },
          function (r) { return r.name; }, function (r) { return r.url; }, null),
        collect(Core.fetchLedger(), "odc-face-hub", "枢纽台账",
          function (d) { return arrOf(d, ["items", "data", "entries"]); },
          function (r) { return r.title_human || r.title || r.summary; },
          function (r) { return r.status; }, null),
        collect(Core.fetchVaultEntries(), "odc-face-entries", "凭据库（只搜名目）",
          function (d) { return arrOf(d, ["entries", "data", "items"]); },
          function (r) { return r.name || r.title; },
          function (r) { return r.service || r.domain; }, null),
        collect(Core.fetchToolsets(), "odc-face-toolsets", "工具集",
          function (d) { return arrOf(d, ["data", "toolsets", "items"]); },
          function (r) { return r.label || r.name; }, function (r) { return r.description; }, null)
      ];
      Promise.all(jobs).then(function (groups) {
        var out = groups.map(function (g) {
          if (!g.rows) return { faceId: g.faceId, label: g.label, failed: true, hits: [] };
          var hits = g.rows.filter(function (r) { return hit(r.title) || hit(r.meta) || hit(r.b); });
          return { faceId: g.faceId, label: g.label, failed: false, hits: hits.slice(0, 8), total: hits.length };
        });
        setRun({ phase: "ready", groups: out });
      });
    }

    var parts = [
      h("span", { key: "bar", className: "odc-actions" },
        h("input", {
          className: "odc-search-input", type: "text", value: q,
          placeholder: "搜目标／想法／动态／文件／监控／台账／凭据名目／工具集",
          onChange: function (ev) { setQ(ev.target.value); },
          onKeyDown: function (ev) { if (ev.key === "Enter") runSearch(); }
        }),
        h("button", { className: "odc-btn odc-btn-primary", disabled: run.phase === "loading", onClick: runSearch },
          run.phase === "loading" ? "搜索中…" : "搜索"))
    ];
    if (run.phase === "ready" && run.groups) {
      var anyHit = false;
      run.groups.forEach(function (g) {
        if (g.failed) {
          parts.push(h("p", { key: "g-" + g.faceId, className: "odc-error" }, g.label + "：读取失败，本组未搜。"));
          return;
        }
        if (!g.hits.length) return;
        anyHit = true;
        var kids = [h("p", { key: "h", className: "odc-summary-head" }, g.label + "（命中 " + g.total + " 条）")];
        g.hits.forEach(function (r, i) {
          kids.push(h("div", { key: "r" + i, className: "odc-row" },
            h("span", { className: "odc-row-title" }, r.title || "（无标题）"),
            h("span", { className: "odc-row-meta" }, r.meta || "")));
        });
        kids.push(h("span", { key: "go", className: "odc-actions" },
          h("button", {
            className: "odc-btn odc-btn-small",
            onClick: function () { scrollToFace(g.faceId); }
          }, "去" + g.label + "面看")));
        parts.push(h("div", { key: "g-" + g.faceId }, kids));
      });
      if (!anyHit) parts.push(h("p", { key: "none", className: "odc-empty" }, "没有命中。换个词试试。"));
    }
    return faceShell("全局搜索", "纯前端聚合：实时拉取本控制台各面已有列表接口再跨面匹配，不新造后端。凭据库只搜名目与服务，凭据值永不参与搜索。", fakeFace, runSearch, parts);
  }

  // ---------------- diagnostics face (bar 6) ----------------
  var CRASH_KIND_WORDS = {
    crash: "崩溃", hang: "卡死", cpuException: "CPU 异常",
    diskWriteException: "磁盘写异常", other: "其他"
  };

  function DiagFace() {
    var crashPair = useFace(Core.fetchCrashReports);
    var crash = crashPair[0];
    var crashLoad = crashPair[1];

    // ---- connection self-check: probes run on demand, rows stream in ----
    var chkPair = hooks.useState({ phase: "idle", rows: [] });
    var chk = chkPair[0];
    var setChk = chkPair[1];
    function runChecks() {
      var rows = [];
      setChk({ phase: "running", rows: [] });
      function push(name, ok, detail) {
        rows.push({ name: name, ok: ok, detail: detail || "" });
        setChk({ phase: "running", rows: rows.slice() });
      }
      Core.fetchHealth().then(function (hv) {
        push("网关健康（/health）", !!hv, hv ? ("状态 " + (hv.status || "ok")) : "无应答");
        return Core.fetchCapabilities();
      }).then(function (caps) {
        var feat = (caps && caps.features) || {};
        var on = Object.keys(feat).filter(function (k) { return feat[k]; }).length;
        push("网关能力（/v1/capabilities）", !!caps, caps ? ("功能位开启 " + on + " 个") : "无应答");
        return Core.fetchApprovals();
      }).then(function (appr) {
        var recs = (appr && appr.approvals) || [];
        var pend = recs.filter(function (r) { return r.status === "pending"; }).length;
        push("凭据链（reveal 换钥 → 待批读取）", true, "链路通，待批 " + pend + " 件");
        return Core.fetchPluginRegistry();
      }).then(function (reg) {
        var list = Array.isArray(reg) ? reg : ((reg && reg.plugins) || []);
        var hit = null;
        list.forEach(function (p) { if (p && p.name === "oneday-console") hit = p; });
        push("插件名册（dashboard 插件表）", !!hit, hit ? ("oneday-console 在册，来源 " + (hit.source || "?")) : "名册无 oneday-console");
        return Core.fetchPluginAssetOk();
      }).then(function (assetOk) {
        push("插件资产路由", !!assetOk, assetOk ? "dist/index.js 可达" : "不可达");
        return Core.fetchJobs();
      }).then(function (jobs) {
        var jl = (jobs && jobs.jobs) || [];
        push("定时任务投影（/api/jobs）", true, jl.length + " 个任务");
        setChk({ phase: "done", rows: rows });
      }).catch(function (err) {
        push("自检链中断", false, (err && err.message) || String(err));
        setChk({ phase: "done", rows: rows });
      });
    }

    // ---- pending-approval browser notifications (in-page poll) ----
    var supported = typeof window !== "undefined" && "Notification" in window;
    var ntPair = hooks.useState(function () {
      try { return localStorage.getItem("odc-notify") === "1"; } catch (e) { return false; }
    });
    var notifyOn = ntPair[0];
    var setNotifyOn = ntPair[1];
    var baseRef = hooks.useRef(null);
    hooks.useEffect(function () {
      if (!notifyOn) return undefined;
      var alive = true;
      function poll() {
        Core.fetchApprovals().then(function (appr) {
          if (!alive) return;
          var recs = (appr && appr.approvals) || [];
          var pend = recs.filter(function (r) { return r.status === "pending"; }).length;
          if (baseRef.current == null) { baseRef.current = pend; return; }
          if (pend > baseRef.current) {
            try {
              new Notification("OneDay 有新待批", { body: "现在有 " + pend + " 件待批，去批准面处理。" });
            } catch (e) { /* permission raced away; toggle stays on */ }
          }
          baseRef.current = pend;
        }).catch(function () { /* transient; next tick retries */ });
      }
      poll();
      var t = setInterval(poll, 30000);
      return function () { alive = false; clearInterval(t); };
    }, [notifyOn]);
    function toggleNotify() {
      if (!notifyOn) {
        if (!supported) return;
        Notification.requestPermission().then(function (perm) {
          if (perm === "granted") {
            try { localStorage.setItem("odc-notify", "1"); } catch (e) {}
            baseRef.current = null;
            setNotifyOn(true);
          }
        });
      } else {
        try { localStorage.setItem("odc-notify", "0"); } catch (e) {}
        setNotifyOn(false);
      }
    }

    var parts = [];
    // self-check block
    parts.push(h("p", { key: "chk-h", className: "odc-summary-head" }, "连接自检"));
    parts.push(h("span", { key: "chk-b", className: "odc-actions" },
      h("button", {
        className: "odc-btn odc-btn-primary", disabled: chk.phase === "running",
        onClick: runChecks
      }, chk.phase === "running" ? "自检中…" : "一键自检"),
      chk.phase === "done" ? h("span", { className: "odc-row-meta" }, "刚完成一轮，点按钮可重跑") : null));
    if (chk.rows.length) {
      parts.push(h("ul", { key: "chk-l", className: "odc-list" }, chk.rows.map(function (r, i) {
        return h("li", { key: "c" + i, className: "odc-row" },
          h("span", { className: "odc-row-title" }, r.name),
          h("span", { className: r.ok ? "odc-st odc-st-done" : "odc-st odc-st-failed" }, r.ok ? "通过" : "失败"),
          h("span", { className: "odc-row-meta" }, r.detail));
      })));
    }
    // notify block
    parts.push(h("p", { key: "nt-h", className: "odc-summary-head" }, "待批提醒（浏览器通知）"));
    if (!supported) {
      parts.push(h("p", { key: "nt-u", className: "odc-empty" }, "当前浏览器不支持通知 API，本项不可用。"));
    } else {
      parts.push(h("span", { key: "nt-b", className: "odc-actions" },
        h("button", { className: "odc-btn" + (notifyOn ? "" : " odc-btn-primary"), onClick: toggleNotify },
          notifyOn ? "关闭提醒" : "开启提醒"),
        h("span", { className: "odc-row-meta" },
          notifyOn ? "已开启：本页打开期间每 30 秒查一次待批，有新增就弹通知。" : "开启后本页打开期间有新待批会弹浏览器通知。")));
      parts.push(h("p", { key: "nt-n", className: "odc-preview" },
        "注：这是页内轮询提醒，关页即停；服务端 Web Push（关页也能推）需新后端，未接，记遗留（见盘点表）。"));
    }
    // crash reports block
    parts.push(h("p", { key: "cr-h", className: "odc-summary-head" }, "崩溃报告（App 上报，服务端脱敏留存）"));
    if (crash.phase === "loading") {
      parts.push(h("p", { key: "cr-l" }, "正在读取崩溃报告……"));
    } else if (crash.phase === "error") {
      parts.push(h("p", { key: "cr-e", className: "odc-error" }, "读取失败：" + crash.error));
    } else {
      var reports = (crash.data && crash.data.data) || [];
      if (!reports.length) {
        parts.push(h("p", { key: "cr-0", className: "odc-empty" }, "暂无崩溃报告。"));
      } else {
        parts.push(h("p", { key: "cr-c", className: "odc-count" }, "共 " + reports.length + " 条（最新在前）"));
        parts.push(h("ul", { key: "cr-l2", className: "odc-list" }, reports.map(function (r, i) {
          var meta = [];
          if (r.capturedAt) meta.push(fmtTs(r.capturedAt));
          if (r.appVersion) meta.push("App " + r.appVersion);
          if (r.osVersion) meta.push(r.osVersion);
          var kids = [
            h("span", { key: "t", className: "odc-row-title" },
              (CRASH_KIND_WORDS[r.kind] || r.kind || "其他") +
              (r.exceptionType ? " · " + r.exceptionType : "")),
            h("span", { key: "m", className: "odc-row-meta" }, meta.join(" · "))
          ];
          var det = [];
          if (r.exceptionSignal) det.push("信号 " + r.exceptionSignal);
          if (r.terminationNamespace || r.terminationCode) {
            det.push("终止 " + [r.terminationNamespace, r.terminationCode].filter(Boolean).join(" "));
          }
          if (det.length) kids.push(h("span", { key: "d", className: "odc-preview" }, det.join(" · ")));
          var syms = (r.faultingTopSymbols || []).slice(0, 3);
          if (syms.length) kids.push(h("code", { key: "s", className: "odc-cmd" }, syms.join(" / ")));
          return h("li", { key: "r" + i, className: "odc-row odc-row-card" }, kids);
        })));
      }
    }
    // leftover notes block
    parts.push(h("p", { key: "ln-h", className: "odc-summary-head" }, "本面未收的（结论在盘点表 BAR6-INVENTORY.md）"));
    parts.push(h("p", { key: "ln-1", className: "odc-preview" },
      "聊天诊断：网关与 dashboard 均无聊天诊断数据面，日志侧由 dashboard 的 Logs 页覆盖，本面不另造。"));
    parts.push(h("p", { key: "ln-2", className: "odc-preview" },
      "会话置顶：列表带 pinned 字段，但浏览器可达的会话编辑走上游修订围栏协议（桌面端协议），插件不硬接，写口记遗留。"));
    return faceShell("诊断", "连接自检＋崩溃报告＋待批提醒三块收尾件：自检只读探活、崩溃报告只读呈现、提醒只在本页打开期间工作。", crash, crashLoad, parts);
  }

  // ---------------- v1.0.0 Flagship Faces: Overview / Agents & Prompts / Skills & Plugins ----------------

  function safeText(v, fallback) {
    if (v == null || v === "") return fallback || "";
    if (typeof v === "string") return v;
    if (typeof v === "number" || typeof v === "boolean") return String(v);
    if (typeof v === "object") {
      if (v.display != null && v.display !== "") return String(v.display);
      if (v.human != null && v.human !== "") return String(v.human);
      if (v.label != null && v.label !== "") return String(v.label);
      if (v.expr != null && v.expr !== "") return String(v.expr);
      if (v.name != null && v.name !== "") return String(v.name);
      if (v.title != null && v.title !== "") return String(v.title);
      try { return JSON.stringify(v); } catch (e) { return fallback || ""; }
    }
    return String(v);
  }

  function ConsoleErrorBoundary(props) {
    React.Component.call(this, props);
    this.state = { err: null };
  }
  ConsoleErrorBoundary.prototype = Object.create(React.Component.prototype);
  ConsoleErrorBoundary.prototype.constructor = ConsoleErrorBoundary;
  ConsoleErrorBoundary.getDerivedStateFromError = function (err) {
    return { err: err };
  };
  ConsoleErrorBoundary.prototype.render = function () {
    var self = this;
    if (this.state && this.state.err) {
      return h("div", { className: "odc-card" },
        h("div", { className: "odc-face-head" },
          h("h3", null, "当前功能面渲染异常"),
          h("button", { type: "button", className: "odc-btn odc-btn-small odc-btn-primary", onClick: function () { self.setState({ err: null }); } }, "重试")),
        h("p", { className: "odc-error" }, safeText(this.state.err && this.state.err.message, String(this.state.err))));
    }
    return this.props.children;
  };

  function OverviewFace(props) {
    var onNavigate = props && props.onNavigate ? props.onNavigate : function () {};
    var st = React.useState({ phase: "loading", data: null, error: null });
    var state = st[0], setState = st[1];

    function load() {
      setState({ phase: "loading", data: state.data, error: null });
      Promise.all([
        Core.fetchHealth().catch(function () { return null; }),
        Core.fetchApprovals().catch(function () { return null; }),
        Core.fetchVaultRequests("pending").catch(function () { return null; }),
        Core.fetchLedgerSummary().catch(function () { return null; }),
        Core.fetchJobs().catch(function () { return null; }),
        Core.fetchProfiles().catch(function () { return null; })
      ]).then(function (res) {
        var health = res[0];
        var approvals = res[1];
        var vaultReqs = res[2];
        var ledger = res[3];
        var jobs = res[4];
        var profiles = res[5];
        var pendingApprovals = (approvals && Array.isArray(approvals.pending)) ? approvals.pending.length
          : (approvals && Array.isArray(approvals.data)) ? approvals.data.length : 0;
        var pendingVault = (vaultReqs && Array.isArray(vaultReqs.requests)) ? vaultReqs.requests.length
          : (vaultReqs && Array.isArray(vaultReqs.data)) ? vaultReqs.data.length : 0;
        var jobList = Array.isArray(jobs) ? jobs : ((jobs && (jobs.jobs || jobs.data)) || []);
        var profileList = Array.isArray(profiles) ? profiles : ((profiles && (profiles.profiles || profiles.data)) || []);
        var summary = (ledger && (ledger.summary || ledger)) || {};
        var payload = {
          healthy: !!(health && (health.status === "ok" || health.ok === true)),
          healthDetail: health && (health.version || health.status) ? String(health.version || health.status) : "未探测到",
          pendingApprovals: pendingApprovals,
          pendingVault: pendingVault,
          runningTasks: Number(summary.running || summary.in_progress || 0),
          completedToday: Number(summary.completed_today || summary.completed || 0),
          failedToday: Number(summary.failed_today || summary.failed || 0),
          jobs: jobList,
          profiles: profileList
        };
        setState({ phase: "ready", data: payload, error: null });
        if (props && props.onPulse) props.onPulse(payload);
      }).catch(function (err) {
        setState({ phase: "error", data: null, error: String(err && err.message || err) });
      });
    }

    React.useEffect(function () { load(); }, []);

    var d = state.data;
    var parts = [];
    if (d) {
      var totalPending = d.pendingApprovals + d.pendingVault;
      parts.push(h("div", { key: "kpis", className: "odc-kpi-grid" },
        h("button", {
          type: "button",
          className: "odc-kpi-card " + (d.healthy ? "odc-kpi-accent-ok" : "odc-kpi-accent-danger"),
          onClick: function () { onNavigate("odc-face-diag"); }
        },
          h("span", { className: "odc-kpi-label" }, "网关运行态"),
          h("span", { className: "odc-kpi-value" }, d.healthy ? "在线" : "异常"),
          h("span", { className: "odc-kpi-sub" }, "版本 / 状态：" + d.healthDetail)),
        h("button", {
          type: "button",
          className: "odc-kpi-card " + (totalPending > 0 ? "odc-kpi-accent-danger" : "odc-kpi-accent-ok"),
          onClick: function () { onNavigate(d.pendingApprovals > 0 ? "odc-face-approvals" : "odc-face-requests"); }
        },
          h("span", { className: "odc-kpi-label" }, "待你审批"),
          h("span", { className: "odc-kpi-value" }, String(totalPending)),
          h("span", { className: "odc-kpi-sub" }, "操作批准 " + d.pendingApprovals + " · 凭据请求 " + d.pendingVault)),
        h("button", {
          type: "button",
          className: "odc-kpi-card odc-kpi-accent-primary",
          onClick: function () { onNavigate("odc-face-hub"); }
        },
          h("span", { className: "odc-kpi-label" }, "任务台账"),
          h("span", { className: "odc-kpi-value" }, String(d.runningTasks)),
          h("span", { className: "odc-kpi-sub" }, "进行中 · 今日完成 " + d.completedToday + " / 失败 " + d.failedToday)),
        h("button", {
          type: "button",
          className: "odc-kpi-card",
          onClick: function () { onNavigate("odc-face-cron"); }
        },
          h("span", { className: "odc-kpi-label" }, "定时任务排期"),
          h("span", { className: "odc-kpi-value" }, String(d.jobs.length)),
          h("span", { className: "odc-kpi-sub" }, "查看时间表与运行状态")),
        h("button", {
          type: "button",
          className: "odc-kpi-card",
          onClick: function () { onNavigate("odc-face-agents"); }
        },
          h("span", { className: "odc-kpi-label" }, "专家分身档案"),
          h("span", { className: "odc-kpi-value" }, String(d.profiles.length)),
          h("span", { className: "odc-kpi-sub" }, "管理分身、模型与系统提示词"))
      ));

      parts.push(h("p", { key: "qh", className: "odc-summary-head" }, "高频管理入口"));
      parts.push(h("div", { key: "qg", className: "odc-quick-grid" },
        h("button", { type: "button", className: "odc-quick-card", onClick: function () { onNavigate("odc-face-agents"); } },
          h("span", { className: "odc-quick-title" }, "分身与提示词中心"),
          h("span", { className: "odc-quick-desc" }, "新建/切换专家分身，在线编辑主助手 Soul 与系统提示词")),
        h("button", { type: "button", className: "odc-quick-card", onClick: function () { onNavigate("odc-face-ideas"); } },
          h("span", { className: "odc-quick-title" }, "点子生成与内容池"),
          h("span", { className: "odc-quick-desc" }, "查看自动生成的灵感点子、状态流转与关联目标")),
        h("button", { type: "button", className: "odc-quick-card", onClick: function () { onNavigate("odc-face-cron"); } },
          h("span", { className: "odc-quick-title" }, "定时任务排期表"),
          h("span", { className: "odc-quick-desc" }, "核查每个定时任务几点跑、最近状态与关联项目")),
        h("button", { type: "button", className: "odc-quick-card", onClick: function () { onNavigate("odc-face-skills"); } },
          h("span", { className: "odc-quick-title" }, "技能与插件治理"),
          h("span", { className: "odc-quick-desc" }, "检索 Skills Hub、管理已装技能与插件启停状态")),
        h("button", { type: "button", className: "odc-quick-card", onClick: function () { onNavigate("odc-face-delegation"); } },
          h("span", { className: "odc-quick-title" }, "多模型委托路由"),
          h("span", { className: "odc-quick-desc" }, "配置不同分身与子任务使用的后端与模型映射")),
        h("button", { type: "button", className: "odc-quick-card", onClick: function () { onNavigate("odc-face-diag"); } },
          h("span", { className: "odc-quick-title" }, "六探针一键自检"),
          h("span", { className: "odc-quick-desc" }, "排查网关、能力位、凭据链、崩溃报告与浏览器提醒"))
      ));

      if (d.jobs.length) {
        parts.push(h("p", { key: "jh", className: "odc-summary-head" }, "定时任务排期快照（前 5 项）"));
        parts.push(h("ul", { key: "jl", className: "odc-list" }, d.jobs.slice(0, 5).map(function (j, idx) {
          var title = safeText(j && (j.name || j.title || j.id), "任务 " + (idx + 1));
          var sched = safeText(j && (j.schedule_human || j.schedule || j.cron), "未标排期");
          var status = (j && j.enabled === false) ? "已暂停" : safeText(j && j.last_status, "运行中");
          return h("li", { key: "ovj-" + idx, className: "odc-row" },
            h("span", { className: "odc-row-title" }, title),
            h("span", { className: "odc-row-meta" }, sched),
            h("span", { className: "odc-st " + ((j && j.enabled === false) ? "odc-st-pending" : "odc-st-done") }, status));
        })));
      }
    }

    return faceShell(
      "总览指挥台",
      "全局运行态实时汇总（全部直采服务端真源接口，无假数据）：一眼看清网关健康、待审批、任务进度、定时排期与专家分身。",
      state,
      load,
      parts
    );
  }

  function AgentsPromptsFace() {
    var st = React.useState({ phase: "loading", data: null, error: null });
    var state = st[0], setState = st[1];
    var formSt = React.useState({ name: "", model: "", provider: "", description: "" });
    var form = formSt[0], setForm = formSt[1];
    var soulSt = React.useState("");
    var soulText = soulSt[0], setSoulText = soulSt[1];
    var busySt = React.useState(false);
    var busy = busySt[0], setBusy = busySt[1];
    var msgSt = React.useState(null);
    var msg = msgSt[0], setMsg = msgSt[1];

    function load() {
      setState({ phase: "loading", data: state.data, error: null });
      Promise.all([
        Core.fetchProfiles().catch(function () { return []; }),
        Core.fetchSoul().catch(function () { return null; })
      ]).then(function (res) {
        var rawProfiles = res[0];
        var list = Array.isArray(rawProfiles) ? rawProfiles : ((rawProfiles && (rawProfiles.profiles || rawProfiles.data)) || []);
        var soulObj = res[1];
        var content = "";
        if (typeof soulObj === "string") content = soulObj;
        else if (soulObj && typeof soulObj.content === "string") content = soulObj.content;
        else if (soulObj && typeof soulObj.soul === "string") content = soulObj.soul;
        setSoulText(content);
        setState({ phase: "ready", data: { profiles: list, hasSoulApi: soulObj !== null }, error: null });
      }).catch(function (err) {
        setState({ phase: "error", data: null, error: String(err && err.message || err) });
      });
    }

    React.useEffect(function () { load(); }, []);

    function handleCreate(ev) {
      ev.preventDefault();
      var name = (form.name || "").trim();
      if (!name) return;
      setBusy(true);
      setMsg(null);
      Core.createProfile({
        name: name,
        model: (form.model || "").trim() || undefined,
        provider: (form.provider || "").trim() || undefined,
        description: (form.description || "").trim() || undefined
      }).then(function () {
        setForm({ name: "", model: "", provider: "", description: "" });
        setMsg("已创建专家分身「" + name + "」，iOS 端敲 @ 即可同步使用。");
        load();
      }).catch(function (err) {
        setMsg("创建失败：" + String(err && err.message || err));
      }).finally(function () { setBusy(false); });
    }

    function handleActivate(name) {
      setBusy(true);
      setMsg(null);
      Core.activateProfile(name).then(function () {
        setMsg("已将「" + name + "」设为当前激活分身档案。");
        load();
      }).catch(function (err) {
        setMsg("切换失败：" + String(err && err.message || err));
      }).finally(function () { setBusy(false); });
    }

    function handleDelete(name) {
      if (!window.confirm("确认删除分身档案「" + name + "」？")) return;
      setBusy(true);
      setMsg(null);
      Core.deleteProfile(name).then(function () {
        setMsg("已删除分身档案「" + name + "」。");
        load();
      }).catch(function (err) {
        setMsg("删除失败：" + String(err && err.message || err));
      }).finally(function () { setBusy(false); });
    }

    function handleSaveSoul() {
      setBusy(true);
      setMsg(null);
      Core.saveSoul(soulText).then(function () {
        setMsg("系统提示词（SOUL.md）已保存并同步服务端。");
      }).catch(function (err) {
        setMsg("保存提示词失败：" + String(err && err.message || err));
      }).finally(function () { setBusy(false); });
    }

    var parts = [];
    if (msg) {
      parts.push(h("div", { key: "msg", className: "odc-toast" },
        h("span", null, msg),
        h("button", { type: "button", className: "odc-btn odc-btn-small odc-btn-text", onClick: function () { setMsg(null); } }, "关闭")));
    }

    if (state.data) {
      var profiles = state.data.profiles || [];
      parts.push(h("div", { key: "split", className: "odc-split-grid" },
        h("div", { key: "col-p" },
          h("p", { className: "odc-summary-head" }, "专家分身档案（" + profiles.length + "）"),
          profiles.length ? h("ul", { className: "odc-list" }, profiles.map(function (p, i) {
            var pname = p.name || ("profile-" + i);
            var active = !!(p.is_active || p.isActive || p.active);
            return h("li", { key: pname, className: "odc-row odc-row-card" },
              h("div", { style: { display: "flex", justifyContent: "space-between", alignItems: "center", gap: "8px" } },
                h("span", { className: "odc-row-title" }, "@" + pname),
                h("span", { className: "odc-st " + (active ? "odc-st-done" : "") }, active ? "当前激活" : "待命")),
              h("span", { className: "odc-row-meta" }, [p.model || "默认模型", p.provider || "", p.description || ""].filter(Boolean).join(" · ")),
              h("div", { className: "odc-actions" },
                !active ? h("button", { type: "button", className: "odc-btn odc-btn-small odc-btn-primary", disabled: busy, onClick: function () { handleActivate(pname); } }, "设为激活") : null,
                !(p.is_default || p.isDefault) ? h("button", { type: "button", className: "odc-btn odc-btn-small odc-btn-text", disabled: busy, onClick: function () { handleDelete(pname); } }, "删除") : null));
          })) : h("p", { className: "odc-empty" }, "暂无自定义分身档案，可在下方一键创建。"),
          h("p", { className: "odc-summary-head" }, "新建专家分身"),
          h("form", { className: "odc-form", onSubmit: handleCreate },
            h("label", { className: "odc-field" }, "分身名称（如：编码架构师 / 深度研究员）",
              h("input", { value: form.name, onChange: function (e) { setForm(Object.assign({}, form, { name: e.target.value })); }, placeholder: "必填，例如 code-architect" })),
            h("label", { className: "odc-field" }, "指定模型（可选）",
              h("input", { value: form.model, onChange: function (e) { setForm(Object.assign({}, form, { model: e.target.value })); }, placeholder: "留空跟随默认模型，如 claude-sonnet-4" })),
            h("label", { className: "odc-field" }, "职责说明（可选）",
              h("input", { value: form.description, onChange: function (e) { setForm(Object.assign({}, form, { description: e.target.value })); }, placeholder: "例如：负责代码重构与架构把关" })),
            h("div", { className: "odc-actions" },
              h("button", { type: "submit", className: "odc-btn odc-btn-primary", disabled: busy || !form.name.trim() }, busy ? "提交中…" : "创建专家分身")))
        ),
        h("div", { key: "col-s" },
          h("p", { className: "odc-summary-head" }, "主助手提示词配置（SOUL.md）"),
          h("textarea", {
            className: "odc-prompt-editor",
            value: soulText,
            onChange: function (e) { setSoulText(e.target.value); },
            placeholder: "在此配置主助手人格、回复规范、工作原则与偏好……"
          }),
          h("div", { className: "odc-actions", style: { marginTop: "10px", justifyContent: "space-between" } },
            h("span", { className: "odc-row-meta" }, "当前字数：" + soulText.length + " 字符"),
            h("button", { type: "button", className: "odc-btn odc-btn-primary", disabled: busy, onClick: handleSaveSoul }, busy ? "保存中…" : "保存提示词"))
        )
      ));
    }

    return faceShell(
      "分身与提示词中心",
      "统一管理 Hermes 专家分身档案（/api/profiles）与主助手系统提示词（/api/soul），修改后立即与 iOS 端 @分身 协同同步。",
      state,
      load,
      parts
    );
  }

  function SkillsPluginsFace() {
    var st = React.useState({ phase: "loading", data: null, error: null });
    var state = st[0], setState = st[1];
    var qSt = React.useState("");
    var q = qSt[0], setQ = qSt[1];
    var hubSt = React.useState([]);
    var hubResults = hubSt[0], setHubResults = hubSt[1];
    var busySt = React.useState(false);
    var busy = busySt[0], setBusy = busySt[1];
    var msgSt = React.useState(null);
    var msg = msgSt[0], setMsg = msgSt[1];

    function load() {
      setState({ phase: "loading", data: state.data, error: null });
      Promise.all([
        Core.fetchSkills().catch(function () { return []; }),
        Core.fetchPlugins().catch(function () { return []; })
      ]).then(function (res) {
        var sk = Array.isArray(res[0]) ? res[0] : ((res[0] && (res[0].skills || res[0].data)) || []);
        var pl = Array.isArray(res[1]) ? res[1] : ((res[1] && (res[1].plugins || res[1].data)) || []);
        setState({ phase: "ready", data: { skills: sk, plugins: pl }, error: null });
      }).catch(function (err) {
        setState({ phase: "error", data: null, error: String(err && err.message || err) });
      });
    }

    React.useEffect(function () { load(); }, []);

    function handleSearchHub(ev) {
      ev.preventDefault();
      setBusy(true);
      setMsg(null);
      Core.searchSkillHub(q).then(function (res) {
        var list = Array.isArray(res) ? res : ((res && (res.skills || res.results || res.data)) || []);
        setHubResults(list);
        if (!list.length) setMsg("远程技能库未返回匹配项（请确认服务器可访问外部 Registry 或更换关键词）。");
      }).catch(function (err) {
        setMsg("搜索远程技能库失败：" + String(err && err.message || err));
      }).finally(function () { setBusy(false); });
    }

    function handleInstallSkill(identifier) {
      setBusy(true);
      setMsg(null);
      Core.installSkillHub(identifier).then(function () {
        setMsg("已提交技能「" + identifier + "」安装并刷新清单。");
        load();
      }).catch(function (err) {
        setMsg("安装失败：" + String(err && err.message || err));
      }).finally(function () { setBusy(false); });
    }

    function handleUninstallSkill(name) {
      setBusy(true);
      setMsg(null);
      Core.uninstallSkillHub(name).then(function () {
        setMsg("已卸载技能「" + name + "」。");
        load();
      }).catch(function (err) {
        setMsg("卸载失败：" + String(err && err.message || err));
      }).finally(function () { setBusy(false); });
    }

    function handleTogglePlugin(name, enabled) {
      setBusy(true);
      setMsg(null);
      Core.togglePlugin(name, enabled).then(function () {
        setMsg("插件「" + name + "」已" + (enabled ? "启用" : "停用") + "。");
        load();
      }).catch(function (err) {
        setMsg("切换插件失败：" + String(err && err.message || err));
      }).finally(function () { setBusy(false); });
    }

    var parts = [];
    if (msg) {
      parts.push(h("div", { key: "sp-msg", className: "odc-toast" },
        h("span", null, msg),
        h("button", { type: "button", className: "odc-btn odc-btn-small odc-btn-text", onClick: function () { setMsg(null); } }, "关闭")));
    }

    parts.push(h("form", { key: "hub-f", className: "odc-actions", onSubmit: handleSearchHub, style: { marginBottom: "10px" } },
      h("input", { className: "odc-search-input", value: q, onChange: function (e) { setQ(e.target.value); }, placeholder: "搜索远程 Skills Hub（如 pdf、browser、git）" }),
      h("button", { type: "submit", className: "odc-btn odc-btn-primary", disabled: busy }, busy ? "检索中…" : "搜索商店")));

    if (hubResults.length) {
      parts.push(h("p", { key: "hr-h", className: "odc-summary-head" }, "远程技能检索结果（" + hubResults.length + "）"));
      parts.push(h("ul", { key: "hr-l", className: "odc-list" }, hubResults.slice(0, 12).map(function (s, idx) {
        var id = s.identifier || s.name || ("skill-" + idx);
        return h("li", { key: id, className: "odc-row" },
          h("div", null,
            h("div", { className: "odc-row-title" }, s.name || id),
            s.description ? h("div", { className: "odc-row-meta" }, s.description) : null),
          h("button", { type: "button", className: "odc-btn odc-btn-small odc-btn-primary", disabled: busy, onClick: function () { handleInstallSkill(id); } }, "安装"));
      })));
    }

    if (state.data) {
      var skills = state.data.skills || [];
      var plugins = state.data.plugins || [];
      parts.push(h("div", { key: "sp-grid", className: "odc-split-grid" },
        h("div", { key: "sp-sk" },
          h("p", { className: "odc-summary-head" }, "已安装技能（" + skills.length + "）"),
          skills.length ? h("ul", { className: "odc-list" }, skills.map(function (s, idx) {
            var sname = s.name || ("skill-" + idx);
            return h("li", { key: sname, className: "odc-row" },
              h("div", null,
                h("div", { className: "odc-row-title" }, sname),
                s.description ? h("div", { className: "odc-row-meta" }, s.description) : null),
              h("button", { type: "button", className: "odc-btn odc-btn-small odc-btn-text", disabled: busy, onClick: function () { handleUninstallSkill(sname); } }, "卸载"));
          })) : h("p", { className: "odc-empty" }, "暂无已安装技能。")),
        h("div", { key: "sp-pl" },
          h("p", { className: "odc-summary-head" }, "已安装插件（" + plugins.length + "）"),
          plugins.length ? h("ul", { className: "odc-list" }, plugins.map(function (p, idx) {
            var pname = p.name || ("plugin-" + idx);
            var enabled = p.enabled !== false;
            return h("li", { key: pname, className: "odc-row" },
              h("div", null,
                h("div", { className: "odc-row-title" }, pname),
                p.description ? h("div", { className: "odc-row-meta" }, p.description) : null),
              h("button", {
                type: "button",
                className: "odc-btn odc-btn-small " + (enabled ? "" : "odc-btn-primary"),
                disabled: busy,
                onClick: function () { handleTogglePlugin(pname, !enabled); }
              }, enabled ? "停用" : "启用"));
          })) : h("p", { className: "odc-empty" }, "暂无已安装插件。"))
      ));
    }

    return faceShell(
      "技能与插件治理",
      "服务端统一检索 Skills Hub、安装/卸载技能包并管理 Agent 插件启停。",
      state,
      load,
      parts
    );
  }

  // ---------------- Flagship Two-Column Admin Console Shell ----------------
  var NAV_GROUPS = [
    {
      group: "指挥总览",
      items: [
        { id: "odc-face-overview", label: "总览指挥台", badgeKey: null },
        { id: "odc-face-approvals", label: "审批待办", badgeKey: "pendingApprovals" },
        { id: "odc-face-requests", label: "凭据请求", badgeKey: "pendingVault" },
        { id: "odc-face-entries", label: "凭据库", badgeKey: null }
      ]
    },
    {
      group: "智能体与提示词",
      items: [
        { id: "odc-face-agents", label: "分身与提示词", badgeKey: "profilesCount" },
        { id: "odc-face-delegation", label: "委托路由", badgeKey: null },
        { id: "odc-face-skills", label: "技能与插件", badgeKey: null },
        { id: "odc-face-toolsets", label: "工具集开关", badgeKey: null },
        { id: "odc-face-identity", label: "身份与形象", badgeKey: null }
      ]
    },
    {
      group: "点子与内容流水线",
      items: [
        { id: "odc-face-ideas", label: "点子生成池", badgeKey: null },
        { id: "odc-face-feed", label: "动态与流水", badgeKey: null },
        { id: "odc-face-goals", label: "目标管理", badgeKey: null },
        { id: "odc-face-memory", label: "记忆与图谱", badgeKey: null },
        { id: "odc-face-files", label: "文件交付库", badgeKey: null }
      ]
    },
    {
      group: "自动化与排期",
      items: [
        { id: "odc-face-cron", label: "定时任务排期", badgeKey: "jobsCount" },
        { id: "odc-face-hub", label: "枢纽工作台账", badgeKey: null },
        { id: "odc-face-monitors", label: "变化监测", badgeKey: null }
      ]
    },
    {
      group: "设备与语音生态",
      items: [
        { id: "odc-face-connectors", label: "MCP 连接器", badgeKey: null },
        { id: "odc-face-computer", label: "云电脑状态", badgeKey: null },
        { id: "odc-face-devices", label: "设备与会话", badgeKey: null },
        { id: "odc-face-speech", label: "语音播报", badgeKey: null },
        { id: "odc-face-dictation", label: "语音听写", badgeKey: null },
        { id: "odc-face-reactions", label: "消息反应", badgeKey: null }
      ]
    },
    {
      group: "安全审计与系统",
      items: [
        { id: "odc-face-audit", label: "写闸审计", badgeKey: null },
        { id: "odc-face-grants", label: "常驻授权规矩", badgeKey: null },
        { id: "odc-face-settings", label: "结构化设置", badgeKey: null },
        { id: "odc-face-search", label: "跨面搜索", badgeKey: null },
        { id: "odc-face-diag", label: "诊断与自检", badgeKey: null }
      ]
    }
  ];

  var ALL_NAV_ITEMS = [];
  NAV_GROUPS.forEach(function (g) {
    g.items.forEach(function (it) {
      ALL_NAV_ITEMS.push({ id: it.id, label: it.label, group: g.group, badgeKey: it.badgeKey });
    });
  });

  function renderFaceById(id, onNavigate, onPulse) {
    switch (id) {
      case "odc-face-overview": return h(OverviewFace, { onNavigate: onNavigate, onPulse: onPulse });
      case "odc-face-agents": return h(AgentsPromptsFace, null);
      case "odc-face-skills": return h(SkillsPluginsFace, null);
      case "odc-face-approvals": return h(ApprovalsFace, null);
      case "odc-face-entries": return h(VaultEntriesFace, null);
      case "odc-face-requests": return h(VaultRequestsFace, null);
      case "odc-face-feed": return h(FeedFace, null);
      case "odc-face-ideas": return h(IdeasFace, null);
      case "odc-face-goals": return h(GoalsFace, null);
      case "odc-face-hub": return h(HubFace, null);
      case "odc-face-audit": return h(AuditFace, null);
      case "odc-face-grants": return h(GrantsFace, null);
      case "odc-face-cron": return h(CronFace, null);
      case "odc-face-memory": return h(MemoryFace, null);
      case "odc-face-files": return h(FilesFace, null);
      case "odc-face-monitors": return h(MonitorsFace, null);
      case "odc-face-connectors": return h(ConnectorsFace, null);
      case "odc-face-delegation": return h(DelegationFace, null);
      case "odc-face-toolsets": return h(ToolsetsFace, null);
      case "odc-face-reactions": return h(ReactionsFace, null);
      case "odc-face-speech": return h(SpeechFace, null);
      case "odc-face-dictation": return h(DictationFace, null);
      case "odc-face-identity": return h(IdentityFace, null);
      case "odc-face-devices": return h(DevicesFace, null);
      case "odc-face-computer": return h(ComputerFace, null);
      case "odc-face-settings": return h(SettingsFace, null);
      case "odc-face-search": return h(SearchFace, null);
      case "odc-face-diag": return h(DiagFace, null);
      default: return h(OverviewFace, { onNavigate: onNavigate, onPulse: onPulse });
    }
  }

  function OneDayConsolePage() {
    var activeSt = React.useState("odc-face-overview");
    var activeId = activeSt[0], setActiveId = activeSt[1];
    var filterSt = React.useState("");
    var filter = filterSt[0], setFilter = filterSt[1];
    var modeSt = React.useState("focus");
    var viewMode = modeSt[0], setViewMode = modeSt[1];
    var pulseSt = React.useState({ healthy: null, pendingApprovals: 0, pendingVault: 0, jobsCount: 0, profilesCount: 0 });
    var pulse = pulseSt[0], setPulse = pulseSt[1];
    var filterInputRef = React.useRef(null);

    React.useEffect(function () {
      function onKeyDown(ev) {
        if ((ev.metaKey || ev.ctrlKey) && (ev.key === "k" || ev.key === "K")) {
          ev.preventDefault();
          if (filterInputRef.current) filterInputRef.current.focus();
        }
      }
      window.addEventListener("keydown", onKeyDown);
      return function () { window.removeEventListener("keydown", onKeyDown); };
    }, []);

    function handlePulse(payload) {
      if (!payload) return;
      setPulse({
        healthy: payload.healthy,
        pendingApprovals: payload.pendingApprovals || 0,
        pendingVault: payload.pendingVault || 0,
        jobsCount: (payload.jobs && payload.jobs.length) || 0,
        profilesCount: (payload.profiles && payload.profiles.length) || 0
      });
    }

    function navigateTo(id) {
      setActiveId(id);
      if (viewMode === "all") {
        setTimeout(function () {
          var el = document.getElementById(id);
          if (el && el.scrollIntoView) el.scrollIntoView({ behavior: "smooth", block: "start" });
        }, 20);
      } else {
        try { window.scrollTo({ top: 0, behavior: "smooth" }); } catch (e) {}
      }
    }

    var currentMeta = ALL_NAV_ITEMS.filter(function (x) { return x.id === activeId; })[0] || ALL_NAV_ITEMS[0];
    var q = (filter || "").trim().toLowerCase();

    var sidebarGroups = NAV_GROUPS.map(function (g) {
      var items = q ? g.items.filter(function (it) {
        return it.label.toLowerCase().indexOf(q) >= 0 || g.group.toLowerCase().indexOf(q) >= 0;
      }) : g.items;
      if (!items.length) return null;
      return h("div", { key: g.group, className: "odc-nav-group" },
        h("div", { className: "odc-nav-group-label" }, g.group),
        items.map(function (it) {
          var isAct = viewMode === "focus" && activeId === it.id;
          var badgeVal = it.badgeKey ? pulse[it.badgeKey] : 0;
          var isAlert = it.badgeKey === "pendingApprovals" || it.badgeKey === "pendingVault";
          return h("button", {
            key: it.id,
            type: "button",
            className: "odc-nav-item" + (isAct ? " odc-nav-item-active" : ""),
            onClick: function () { navigateTo(it.id); }
          },
            h("span", null, it.label),
            badgeVal > 0 ? h("span", { className: "odc-nav-badge" + (isAlert ? "" : " odc-nav-badge-muted") }, String(badgeVal)) : null);
        }));
    }).filter(Boolean);

    var healthDotCls = "odc-health-dot" + (pulse.healthy === true ? " odc-health-dot-ok" : (pulse.healthy === false ? " odc-health-dot-bad" : ""));
    var healthText = pulse.healthy === true ? "网关正常" : (pulse.healthy === false ? "网关异常" : "状态同步中");

    return h("div", { className: "odc-shell" },
      h("aside", { className: "odc-sidebar", "aria-label": "OneDay 后台导航" },
        h("div", { className: "odc-brand" },
          h("span", { className: "odc-brand-title" }, "OneDay 控制台"),
          h("span", { className: "odc-brand-ver" }, "v1.0")),
        h("input", {
          ref: filterInputRef,
          className: "odc-nav-filter",
          value: filter,
          onChange: function (e) { setFilter(e.target.value); },
          placeholder: "筛选功能面… (⌘K)"
        }),
        sidebarGroups),
      h("main", { className: "odc-main" },
        h("header", { className: "odc-topbar" },
          h("div", { className: "odc-topbar-left" },
            h("span", { className: "odc-topbar-crumb" }, "OneDay 服务端管理台 / " + currentMeta.group),
            h("h2", { className: "odc-topbar-title" }, viewMode === "all" ? "全部功能面（全览模式）" : currentMeta.label)),
          h("div", { className: "odc-topbar-right" },
            h("span", { className: "odc-health-pill" },
              h("span", { className: healthDotCls }),
              healthText),
            h("button", {
              type: "button",
              className: "odc-btn odc-btn-small" + (viewMode === "focus" ? " odc-btn-primary" : ""),
              onClick: function () { setViewMode(viewMode === "focus" ? "all" : "focus"); }
            }, viewMode === "focus" ? "切换全览" : "切回聚焦"))),
        viewMode === "focus"
          ? h("div", { key: activeId, id: activeId, className: "odc-anchor" }, h(ConsoleErrorBoundary, { key: "eb-" + activeId }, renderFaceById(activeId, navigateTo, handlePulse)))
          : ALL_NAV_ITEMS.map(function (n) {
              return h("div", { key: n.id, id: n.id, className: "odc-anchor" }, h(ConsoleErrorBoundary, { key: "eb-" + n.id }, renderFaceById(n.id, navigateTo, handlePulse)));
            })));
  }

  window.__HERMES_PLUGINS__.register("oneday-console", OneDayConsolePage);
})();
