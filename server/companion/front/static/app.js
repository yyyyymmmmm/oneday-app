'use strict';
var BASE = '/api/companion';
var csrf = '';
var currentPage = 'overview';
var infoCache = null;
var modulesCache = [];

var MODULE_ORDER = ['writeGate', 'overview', 'box', 'oneday', 'device'];
var MODULE_META = {
  writeGate: { name: '审批', sub: 'write-gate', desc: '智能体写入记忆和技能前，先在这里等你批准。',
    consequence: '关闭后，待审批在 App 里看不到、批不了；智能体的记忆/技能写入会停在待批状态，不会被绕过批准——Hermes 本体的暂存闸门还在。' },
  overview: { name: '总览通知', sub: 'overview', desc: '汇总铃铛通知和待审批数量。',
    consequence: '关闭后，铃铛通知与待审批计数停更。' },
  box: { name: '云电脑', sub: 'box', desc: '在 App 里查看云电脑状态、接管操作。',
    consequence: '关闭后，App 里看不到电脑状态、不能接管；智能体那条同名连接不受影响。' },
  oneday: { name: '目标点子', sub: 'oneday', desc: '支撑动态、点子、目标三页的数据。',
    consequence: '关闭后，动态、点子、目标三页会显示不可用，数据不删。' },
  device: { name: '手机设备', sub: 'device', desc: '让智能体在需要时调用你的手机能力。',
    consequence: '关闭后，智能体暂时调不了你的手机，App 里设备显示离线。' }
};
var STATE_WORD = { up: '正常', running: '运行中', degraded: '降级', down: '已停', 'crash-loop': '反复重启', disabled: '已关闭', stopped: '已停止', unknown: '未知' };

function $(id) { return document.getElementById(id); }
function esc(s) {
  if (s === null || s === undefined) return '';
  return String(s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; });
}
function fmtTime(v) {
  if (!v) return '—';
  var d = typeof v === 'number' ? new Date(v * (v < 1e12 ? 1000 : 1)) : new Date(v);
  if (isNaN(d.getTime())) return String(v);
  return d.toLocaleString('zh-CN', { hour12: false });
}
function fmtDur(sec) {
  if (sec === null || sec === undefined || isNaN(sec)) return null;
  sec = Math.floor(Number(sec));
  if (sec < 60) return sec + ' 秒';
  if (sec < 3600) return Math.floor(sec / 60) + ' 分钟';
  if (sec < 86400) return Math.floor(sec / 3600) + ' 小时 ' + Math.floor((sec % 3600) / 60) + ' 分';
  return Math.floor(sec / 86400) + ' 天 ' + Math.floor((sec % 86400) / 3600) + ' 小时';
}
function toast(msg) {
  var t = $('toast'); t.textContent = msg; t.classList.remove('hidden');
  setTimeout(function () { t.classList.add('hidden'); }, 2600);
}
function showLogin() {
  $('appView').classList.add('hidden'); $('loginView').classList.remove('hidden');
}
function showApp() {
  $('loginView').classList.add('hidden'); $('appView').classList.remove('hidden');
}
function api(path, opts) {
  opts = opts || {};
  var headers = { 'Content-Type': 'application/json' };
  if (opts.method && opts.method !== 'GET' && csrf) headers['X-Companion-CSRF'] = csrf;
  return fetch(BASE + path, { method: opts.method || 'GET', headers: headers, body: opts.body ? JSON.stringify(opts.body) : undefined })
    .then(function (res) {
      if (res.status === 401) { showLogin(); throw new Error('unauthorized'); }
      return res.text().then(function (txt) {
        var data = null;
        try { data = txt ? JSON.parse(txt) : {}; } catch (e) { data = {}; }
        data.__status = res.status;
        if (!res.ok && !data.needConfirm) { var err = new Error(data.detail || data.error || ('请求失败 ' + res.status)); err.status = res.status; err.data = data; throw err; }
        return data;
      });
    });
}

/* ---------- 登录 ---------- */
var loginMethod = 'password';
document.querySelectorAll('#loginSeg .seg-btn').forEach(function (btn) {
  btn.addEventListener('click', function () {
    loginMethod = btn.getAttribute('data-method');
    document.querySelectorAll('#loginSeg .seg-btn').forEach(function (b) {
      var on = b === btn; b.classList.toggle('is-active', on); b.setAttribute('aria-selected', on ? 'true' : 'false');
    });
    $('passwordField').classList.toggle('hidden', loginMethod !== 'password');
    $('keyField').classList.toggle('hidden', loginMethod !== 'key');
    $('loginError').classList.add('hidden');
  });
});
$('togglePassword').addEventListener('click', function () {
  var inp = $('loginPassword'); inp.type = inp.type === 'password' ? 'text' : 'password';
});
function loginFail(msg) {
  var card = $('loginCard'); card.classList.remove('shake'); void card.offsetWidth; card.classList.add('shake');
  var e = $('loginError'); e.textContent = msg; e.classList.remove('hidden');
}
$('loginForm').addEventListener('submit', function (ev) {
  ev.preventDefault();
  var body = loginMethod === 'password'
    ? { method: 'password', password: $('loginPassword').value }
    : { method: 'key', key: $('loginKey').value };
  $('loginBtn').disabled = true; $('loginSpinner').classList.remove('hidden'); $('loginBtnText').textContent = '正在登录…';
  $('loginError').classList.add('hidden');
  fetch(BASE + '/login', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })
    .then(function (res) {
      if (res.status === 429) { loginFail('尝试次数太多，请稍后再试。'); return null; }
      if (!res.ok) { loginFail('登录失败，请检查后重试'); return null; }
      return res.json();
    })
    .then(function (data) {
      if (!data) return;
      if (data.csrf) csrf = data.csrf;
      showApp(); loadOverview(); loadSelfcheckSummary();
    })
    .catch(function () { loginFail('登录失败，请检查后重试'); })
    .finally(function () {
      $('loginBtn').disabled = false; $('loginSpinner').classList.add('hidden'); $('loginBtnText').textContent = '登录';
    });
});
$('logoutBtn').addEventListener('click', function () {
  api('/logout', { method: 'POST', body: {} }).catch(function () {}).finally(function () { csrf = ''; showLogin(); });
});

/* ---------- 导航 ---------- */
document.querySelectorAll('#mainNav .nav-item').forEach(function (btn) {
  btn.addEventListener('click', function () { switchPage(btn.getAttribute('data-page')); });
});
function switchPage(page) {
  currentPage = page;
  document.querySelectorAll('#mainNav .nav-item').forEach(function (b) { b.classList.toggle('is-active', b.getAttribute('data-page') === page); });
  document.querySelectorAll('.page').forEach(function (s) { s.classList.toggle('is-active', s.id === 'page-' + page); });
  if (page === 'overview') loadOverview();
  if (page === 'selfcheck') loadSelfcheck();
  if (page === 'connections') loadConnections();
  if (page === 'modules') loadModulesPage();
  if (page === 'version') loadVersion();
}

/* ---------- 弹窗 ---------- */
function openModal(title, bodyHTML, footButtons) {
  $('modalTitle').textContent = title; $('modalBody').innerHTML = bodyHTML;
  var foot = $('modalFoot'); foot.innerHTML = '';
  (footButtons || []).forEach(function (b) {
    var btn = document.createElement('button'); btn.type = 'button';
    btn.className = 'btn ' + (b.primary ? 'btn-primary' : ''); btn.textContent = b.label;
    btn.addEventListener('click', function () { b.onClick(btn); });
    foot.appendChild(btn);
  });
  $('modalMask').classList.remove('hidden');
}
function closeModal() { $('modalMask').classList.add('hidden'); }
$('modalClose').addEventListener('click', closeModal);
$('modalMask').addEventListener('click', function (e) { if (e.target === $('modalMask')) closeModal(); });

/* ---------- 页一 总览 ---------- */
function stateDotClass(state) { return state || 'unknown'; }
function healthSummary(info) {
  var mods = info.modules || {};
  var bad = [], warn = [];
  MODULE_ORDER.forEach(function (id) {
    var m = mods[id]; if (!m) return;
    var meta = MODULE_META[id];
    var label = meta.name;
    var detail = m.detail || m.probeDetail || '';
    if (m.state === 'down' || m.state === 'crash-loop') bad.push(label + (detail ? '：' + detail : '不可用'));
    else if (m.state === 'degraded') warn.push(label + '降级' + (detail ? '：' + detail : ''));
  });
  if (bad.length) return { text: '有问题：' + bad.concat(warn).join('；'), level: 'bad' };
  if (warn.length) return { text: warn.join('；'), level: 'warn' };
  if (info.hermesUp === false) return { text: '伴生服务正常，但暂时连不上 Hermes 本体', level: 'warn' };
  return { text: '全部正常', level: 'ok' };
}
function renderOverview(info, modulesList) {
  infoCache = info;
  var ver = info.companionVersion || '';
  $('topVersion').textContent = ver ? 'v' + String(ver).replace(/^v/, '') : '';
  $('bannerVersion').textContent = ver ? '伴生服务 ' + ver : '';
  var h = healthSummary(info);
  $('healthText').textContent = h.text;
  var banner = $('healthBanner'); banner.className = 'status-banner' + (h.level === 'warn' ? ' warn' : h.level === 'bad' ? ' bad' : '');
  $('hermesUp').textContent = info.hermesUp === true ? '在线' : info.hermesUp === false ? '连不上' : '未知';
  var hb = $('hermesBadge'); hb.textContent = info.hermesUp ? '在线' : '离线'; hb.className = 'badge ' + (info.hermesUp ? 'ok' : 'bad');
  var lat = info.hermesLatencyMs !== undefined ? info.hermesLatencyMs : info.hermesLatency;
  if (lat !== undefined && lat !== null) { $('hermesLatencyRow').classList.remove('hidden'); $('hermesLatency').textContent = lat + ' 毫秒'; }
  else $('hermesLatencyRow').classList.add('hidden');

  var byId = {};
  (modulesList || []).forEach(function (m) { byId[m.id] = m; });
  var wrap = $('overviewModules'); wrap.innerHTML = '';
  MODULE_ORDER.forEach(function (id) {
    var fromInfo = (info.modules || {})[id] || {};
    var m = byId[id] || fromInfo;
    var meta = MODULE_META[id];
    var state = m.state || fromInfo.state || 'unknown';
    var row = document.createElement('div'); row.className = 'module-row';
    var metaParts = [];
    var dur = fmtDur(m.uptimeSec); if (dur) metaParts.push('已运行 ' + dur);
    if (m.restarts !== undefined && m.restarts !== null) metaParts.push('重启 ' + m.restarts + ' 次');
    if (m.rssMB !== undefined && m.rssMB !== null) metaParts.push('内存 ' + m.rssMB + ' MB');
    var detail = m.detail || m.probeDetail || fromInfo.detail || '';
    row.innerHTML = '<span class="dot ' + esc(stateDotClass(state)) + '"></span>' +
      '<div class="module-main"><div class="module-name">' + esc(meta.name) + '<span class="sub">' + esc(meta.sub) + '</span></div>' +
      (detail ? '<div class="module-desc">' + esc(detail) + '</div>' : '') +
      (metaParts.length ? '<div class="module-meta">' + metaParts.map(function (p) { return '<span>' + esc(p) + '</span>'; }).join('') + '</div>' : '') +
      '</div><span class="badge">' + esc(STATE_WORD[state] || state) + '</span>' +
      ((state === 'down' || state === 'crash-loop') ? '<button type="button" class="btn btn-ghost btn-sm log-btn" data-id="' + esc(id) + '">查看日志</button>' : '');
    wrap.appendChild(row);
  });
  wrap.querySelectorAll('.log-btn').forEach(function (b) {
    b.addEventListener('click', function () { loadLogs(b.getAttribute('data-id'), 'overview'); });
  });
  // 资源行：API 没给就不渲染，不编数字
  var resCard = $('resourceCard'), resList = $('resourceList'); resList.innerHTML = '';
  var hasRes = false;
  var candidates = [
    ['数据目录占用', info.dataDirSize || info.dataDirUsage || info.diskUsage],
    ['数据目录', info.dataDir]
  ];
  candidates.forEach(function (c) {
    if (c[1] !== undefined && c[1] !== null && c[1] !== '') {
      hasRes = true;
      var d = document.createElement('div'); d.className = 'kv';
      d.innerHTML = '<span>' + esc(c[0]) + '</span><strong>' + esc(c[1]) + '</strong>'; resList.appendChild(d);
    }
  });
  resCard.classList.toggle('hidden', !hasRes);
  $('overviewUpdated').textContent = info.generatedAt ? '更新时间：' + fmtTime(info.generatedAt) : '';
  $('overviewEmpty').classList.add('hidden');
}
function loadOverview() {
  Promise.all([
    api('/info').catch(function () { return null; }),
    api('/modules').catch(function () { return null; })
  ]).then(function (r) {
    if (!r[0]) { $('overviewEmpty').classList.remove('hidden'); $('healthText').textContent = '暂时取不到状态'; return; }
    renderOverview(r[0], r[1] ? (r[1].modules || []) : []);
  });
  loadSelfcheckSummary();
  loadSync();
  loadLedger();
}
$('refreshOverview').addEventListener('click', loadOverview);

/* ---------- 本地数据同步（只显状态，不显记录内容） ---------- */
function syncStateWord(d) {
  if (d.permission_state === 'revoked') return '权限已撤销';
  if (!d.synced) return '还没有同步';
  if (d.syncing) return '正在同步';
  if (d.expired) return '已过期';
  return '已同步';
}
function renderSync(datasets) {
  var wrap = $('syncList'); wrap.innerHTML = '';
  if (!datasets.length) { wrap.innerHTML = '<p class="empty-text">暂时取不到同步状态。</p>'; return; }
  datasets.forEach(function (d) {
    var row = document.createElement('div'); row.className = 'sync-row';
    var meta = [];
    if (d.synced) {
      meta.push('已同步 ' + d.item_count + ' 条 · ' + fmtTime(d.synced_at));
      meta.push(d.auth_range === 'limited' ? '部分授权' : '全部授权');
      if (d.pending_write) meta.push('有刚写入、还没同步的内容');
      if (d.last_error) meta.push(d.last_error);
    } else {
      meta.push('服务器上还没有这份副本');
    }
    row.innerHTML = '<div class="sync-main"><div class="sync-name">' + esc(d.label || d.dataset) + '</div>' +
      '<div class="sync-meta">' + esc(meta.join(' · ')) + '</div></div>' +
      '<span class="badge">' + esc(syncStateWord(d)) + '</span>';
    wrap.appendChild(row);
  });
}
function loadSync() {
  api('/sync').then(function (d) { renderSync((d && d.datasets) || []); })
    .catch(function () { renderSync([]); });
}
$('refreshSync').addEventListener('click', loadSync);
$('syncDeleteAll').addEventListener('click', function () {
  openModal('删除全部同步副本',
    '<p>删掉的是服务器上的同步副本：手机上的数据、你给的权限、这台手机的配对都不受影响。</p>' +
    '<p>如果 App 里的同步开关还开着，下次打开 App 同步时副本会重新生成。要彻底不再同步，先在 App 里关掉同步开关。</p>',
    [{ label: '取消', onClick: function () { closeModal(); } },
     { label: '确认删除', primary: true, onClick: function (btn) {
         btn.disabled = true;
         api('/sync/delete', { method: 'POST', body: {} }).then(function () {
           closeModal(); toast('同步副本已删除'); loadSync();
         }).catch(function () { btn.disabled = false; toast('删除没有成功，请重试'); });
       } }]);
});
/* ---------- 工作台账（只显计数，不显任务标题与内容） ---------- */
function renderLedger(d) {
  var wrap = $('ledgerSummary'); wrap.innerHTML = '';
  if (!d || d.error) { wrap.innerHTML = '<p class="empty-text">暂时取不到台账计数。</p>'; return; }
  var rows = [
    ['正在进行', d.inProgress],
    ['待审批', d.blockedApproval],
    ['失联待核', d.stale],
    ['今日完成', d.todayCompleted],
    ['今日失败', d.todayFailed]
  ];
  var list = document.createElement('div'); list.className = 'kv-list';
  rows.forEach(function (r) {
    var dEl = document.createElement('div'); dEl.className = 'kv';
    dEl.innerHTML = '<span>' + esc(r[0]) + '</span><strong>' + esc(r[1] === undefined || r[1] === null ? '—' : r[1]) + '</strong>';
    list.appendChild(dEl);
  });
  wrap.appendChild(list);
  var meta = [];
  if (d.collectorHeartbeatAt) meta.push('采集器心跳 ' + fmtTime(d.collectorHeartbeatAt));
  if (d.degraded) meta.push('台账处于降级模式');
  if (meta.length) {
    var p = document.createElement('p'); p.className = 'muted small';
    p.textContent = meta.join(' · ');
    wrap.appendChild(p);
  }
}
function loadLedger() {
  api('/ledger').then(function (d) { renderLedger(d); })
    .catch(function () { renderLedger(null); });
}
$('refreshLedger').addEventListener('click', loadLedger);

function loadSelfcheckSummary() {
  api('/selfcheck').then(function (d) {
    var chip = $('selfcheckChip');
    if (!d || !d.lastRun) { chip.classList.add('hidden'); return; }
    var run = d.lastRun;
    var fails = 0;
    ['readonly', 'probe', 'manual'].forEach(function (k) { (run[k] || []).forEach(function (it) { if (it.status === 'fail') fails++; }); });
    chip.textContent = '最近自检：' + fmtTime(run.runAt) + (fails ? ' · 有 ' + fails + ' 项需要处理' : ' · 没有红项') + '　点击查看 →';
    chip.classList.remove('hidden');
  }).catch(function () {});
}
$('selfcheckChip').addEventListener('click', function () { switchPage('selfcheck'); });
function loadLogs(id, where) {
  api('/modules/' + encodeURIComponent(id) + '/logs').then(function (d) {
    var lines = (d && d.lines) || [];
    var panel = where === 'overview' ? $('overviewLogPanel') : $('moduleLogPanel');
    var box = where === 'overview' ? $('overviewLogBox') : $('moduleLogBox');
    var title = where === 'overview' ? $('overviewLogTitle') : $('moduleLogTitle');
    var meta = MODULE_META[id];
    title.textContent = (meta ? meta.name : id) + ' · 最近日志';
    box.textContent = lines.length ? lines.join('\n') : '（暂无日志）';
    panel.classList.remove('hidden');
  }).catch(function () { toast('日志暂时取不到'); });
}
$('closeOverviewLog').addEventListener('click', function () { $('overviewLogPanel').classList.add('hidden'); });
$('closeModuleLog').addEventListener('click', function () { $('moduleLogPanel').classList.add('hidden'); });

/* ---------- 页二 自检 ---------- */
function renderSelfcheck(run) {
  var wrap = $('selfcheckResults'); wrap.innerHTML = '';
  if (!run) { $('selfcheckMeta').textContent = '还没有运行过自检。'; return; }
  $('selfcheckMeta').textContent = '上次自检：' + fmtTime(run.runAt);
  var groups = [
    ['readonly', '只读检查', '只看不改，不会影响正在运行的服务。'],
    ['probe', '真实探针', '会发出真实请求，用来确认确实能连通。'],
    ['manual', '需人工确认', '需要你本人看一眼确认，系统不能自动判断。']
  ];
  groups.forEach(function (g) {
    var items = run[g[0]] || [];
    if (!items.length && g[0] === 'probe') return;
    var div = document.createElement('div'); div.className = 'card check-group';
    var html = '<h3>' + esc(g[1]) + '</h3><p class="muted small">' + esc(g[2]) + '</p>';
    if (!items.length) html += '<p class="empty-text">暂无条目</p>';
    items.forEach(function (it) {
      var st = it.status || 'manual';
      var word = st === 'ok' ? '正常' : st === 'warn' ? '提醒' : st === 'fail' ? '有问题' : '需人工';
      html += '<div class="check-row"><span class="dot ' + (st === 'ok' ? 'up' : st === 'fail' ? 'down' : 'degraded') + '"></span>' +
        '<div class="module-main"><div>' + esc(it.label || it.id || '') + '</div>' +
        (it.detail ? '<div class="module-desc">' + esc(it.detail) + '</div>' : '') +
        (it.fix ? '<div class="fix-text">怎么修：' + esc(it.fix) + '</div>' : '') +
        '</div><span class="status-word ' + esc(st) + '">' + word + '</span></div>';
    });
    div.innerHTML = html; wrap.appendChild(div);
  });
}
function loadSelfcheck() {
  api('/selfcheck').then(function (d) { renderSelfcheck(d ? d.lastRun : null); }).catch(function () { $('selfcheckResults').innerHTML = '<div class="empty-state">暂时取不到自检结果。</div>'; });
}
$('runSelfcheckBtn').addEventListener('click', function () {
  var btn = $('runSelfcheckBtn'); btn.disabled = true; $('selfcheckSpinner').classList.remove('hidden');
  api('/selfcheck/run', { method: 'POST', body: { probes: $('probeToggle').checked } })
    .then(function (run) { renderSelfcheck(run); toast('自检完成'); })
    .catch(function () { toast('自检没有跑完，请重试'); })
    .finally(function () { btn.disabled = false; $('selfcheckSpinner').classList.add('hidden'); });
});

/* ---------- 页三 连接 ---------- */
function credFields(provider) {
  if (provider === 'github') return [{ key: 'token', label: '访问令牌', type: 'password', placeholder: '粘贴 GitHub 访问令牌' }];
  if (provider === 'simular_box') return [{ key: 'apiKey', label: '服务密钥', type: 'password', placeholder: '粘贴云电脑服务的密钥' }];
  if (provider === 'vps_agent') return [
    { key: 'endpointUrl', label: '电脑地址', type: 'text', placeholder: '填写这台服务器的地址' },
    { key: 'token', label: '连接令牌', type: 'password', placeholder: '粘贴这台电脑的连接令牌' }];
  return [{ key: 'token', label: '凭据', type: 'password', placeholder: '粘贴凭据' }];
}
function openCredModal(conn) {
  if (conn.provider === 'notion') {
    openModal('填写凭据', '<p>这个连接不用在这里填凭据，请按它自己的授权方式完成连接。</p>', [{ label: '知道了', primary: true, onClick: closeModal }]);
    return;
  }
  var fields = credFields(conn.provider);
  var html = '<p class="muted small">凭据只保存到你自己的服务器，不会显示出来。保存后页面只会告诉你“已配置”。</p>' +
    fields.map(function (f) { return '<div class="field"><label>' + esc(f.label) + '</label><input type="' + f.type + '" data-cred="' + esc(f.key) + '" placeholder="' + esc(f.placeholder) + '" autocomplete="off"></div>'; }).join('');
  openModal('填写凭据 · ' + (conn.name || conn.provider), html, [
    { label: '取消', onClick: closeModal },
    { label: '保存', primary: true, onClick: function (btn) {
        var body = {}; var ok = true;
        fields.forEach(function (f) {
          var v = document.querySelector('[data-cred="' + f.key + '"]').value.trim();
          if (!v) ok = false; body[f.key] = v;
        });
        if (!ok) { toast('请把内容填写完整'); return; }
        btn.disabled = true;
        api('/connections/' + encodeURIComponent(conn.id) + '/credential', { method: 'POST', body: body })
          .then(function () { closeModal(); toast('已保存'); loadConnections(); })
          .catch(function () { btn.disabled = false; toast('保存失败，请重试'); });
      } }
  ]);
}
function renderConnections(list) {
  var wrap = $('connectionsList'); wrap.innerHTML = '';
  var notes = $('connectionsNotes'); notes.innerHTML = '';
  if (!list.length) { wrap.innerHTML = '<p class="empty-text">还没有连接。可以点右上角添加一台云电脑。</p>'; return; }
  list.forEach(function (c) {
    var row = document.createElement('div'); row.className = 'conn-row';
    var verify = c.lastVerify ? ('最近测试：' + (c.lastVerify.ok ? '成功' : '失败') + ' · ' + fmtTime(c.lastVerify.at) + (c.lastVerify.detail ? ' · ' + c.lastVerify.detail : '')) : '还没有测试过';
    var eff = c.effective === true ? '已生效' : c.effective === false ? '尚未生效' : '';
    row.innerHTML = '<div class="conn-main"><div class="module-name">' + esc(c.name || c.provider || c.id) +
      '<span class="sub">' + esc(c.provider || '') + '</span></div>' +
      '<div class="module-meta"><span>' + (c.configured ? '已配置' : '未配置') + '</span><span>' + esc(verify) + '</span>' + (eff ? '<span>' + eff + '</span>' : '') + '</div>' +
      (c.note ? '<div class="fix-text">' + esc(c.note) + '</div>' : '') + '</div>';
    var acts = document.createElement('div'); acts.className = 'conn-actions';
    function mkBtn(label, fn, primary) {
      var b = document.createElement('button'); b.type = 'button'; b.className = 'btn btn-sm' + (primary ? ' btn-primary' : '');
      b.textContent = label; b.addEventListener('click', function () { fn(b); }); acts.appendChild(b);
    }
    if (c.provider !== 'notion') mkBtn(c.configured ? '更新凭据' : '填凭据', function () { openCredModal(c); }, !c.configured);
    mkBtn('测试连接', function (b) {
      b.disabled = true; b.textContent = '测试中…';
      api('/connections/' + encodeURIComponent(c.id) + '/verify', { method: 'POST', body: {} })
        .then(function (r) { toast(r && r.ok ? '连接正常' : '连接失败：' + ((r && r.detail) || '请检查凭据')); loadConnections(); })
        .catch(function () { toast('测试失败，请重试'); loadConnections(); });
    });
    if (c.configured) mkBtn('断开', function () {
      openModal('断开连接', '<p>断开后会删掉保存的凭据，智能体将不能再用这个连接。可以随时重新填写凭据再连上。</p>', [
        { label: '取消', onClick: closeModal },
        { label: '确认断开', primary: true, onClick: function (btn) {
            btn.disabled = true;
            api('/connections/' + encodeURIComponent(c.id) + '/disconnect', { method: 'POST', body: {} })
              .then(function () { closeModal(); toast('已断开'); loadConnections(); })
              .catch(function () { btn.disabled = false; toast('断开失败，请重试'); });
          } }
      ]);
    });
    row.appendChild(acts); wrap.appendChild(row);
    if (c.note) {
      var n = document.createElement('p'); n.className = 'muted small'; n.textContent = (c.name || c.provider) + '：' + c.note; notes.appendChild(n);
    }
  });
}
function loadConnections() {
  api('/connections').then(function (d) { renderConnections((d && d.connections) || []); })
    .catch(function () { $('connectionsList').innerHTML = '<p class="empty-text">暂时取不到连接列表。</p>'; });
}
$('addComputerBtn').addEventListener('click', function () {
  var html = '<div class="field"><label>云电脑类型</label>' +
    '<label class="radio-row"><input type="radio" name="pcType" value="simular_box" checked><span><strong>托管云电脑</strong><br><span class="muted small">服务商提供的云电脑，填密钥就能用。</span></span></label>' +
    '<label class="radio-row"><input type="radio" name="pcType" value="vps_agent"><span><strong>我的 VPS</strong><br><span class="muted small">你自己的服务器，装好配套程序后填地址和令牌。</span></span></label></div>' +
    '<div class="field"><label>显示名称</label><input type="text" id="newPcName" placeholder="例如：我的云电脑"></div>';
  openModal('添加云电脑', html, [
    { label: '取消', onClick: closeModal },
    { label: '添加', primary: true, onClick: function (btn) {
        var type = document.querySelector('input[name="pcType"]:checked').value;
        var name = $('newPcName').value.trim();
        if (!name) { toast('请填写显示名称'); return; }
        btn.disabled = true;
        api('/connections', { method: 'POST', body: { kind: 'cloud_computer', provider: type, name: name } })
          .then(function (created) {
            closeModal(); toast('已添加，接着填凭据就能用');
            loadConnections();
            var conn = created && created.id ? created : { id: created && created.connection && created.connection.id, provider: type, name: name };
            if (conn.id) setTimeout(function () { openCredModal(conn); }, 300);
          })
          .catch(function () { btn.disabled = false; toast('添加失败，请重试'); });
      } }
  ]);
});

/* ---------- 页四 开关 ---------- */
function renderModulesPage(list) {
  modulesCache = list;
  var byId = {}; list.forEach(function (m) { byId[m.id] = m; });
  var wrap = $('modulesList'); wrap.innerHTML = '';
  MODULE_ORDER.forEach(function (id) {
    var m = byId[id] || { id: id, state: 'unknown' };
    var meta = MODULE_META[id];
    var enabled = m.desired !== undefined ? !!m.desired : (m.state === 'running' || m.state === 'up');
    var row = document.createElement('div'); row.className = 'module-row';
    var metaParts = [];
    if (m.pid) metaParts.push('进程 ' + m.pid);
    var dur = fmtDur(m.uptimeSec); if (dur) metaParts.push('已运行 ' + dur);
    if (m.restarts !== undefined && m.restarts !== null) metaParts.push('重启 ' + m.restarts + ' 次');
    if (m.rssMB !== undefined && m.rssMB !== null) metaParts.push('内存 ' + m.rssMB + ' MB');
    if (m.probeDetail) metaParts.push(m.probeDetail);
    row.innerHTML = '<span class="dot ' + esc(m.state || 'unknown') + '"></span>' +
      '<div class="module-main"><div class="module-name">' + esc(m.name || meta.name) + '<span class="sub">' + esc(m.sub || meta.sub) + '</span></div>' +
      '<div class="module-desc">' + esc(m.desc || meta.desc) + '</div>' +
      '<div class="module-desc">关掉会怎样：' + esc(meta.consequence) + '</div>' +
      (metaParts.length ? '<div class="module-meta">' + metaParts.map(function (p) { return '<span>' + esc(p) + '</span>'; }).join('') + '</div>' : '') +
      '</div>';
    var label = document.createElement('label'); label.className = 'switch';
    var input = document.createElement('input'); input.type = 'checkbox'; input.checked = enabled;
    input.setAttribute('aria-label', meta.name + '开关');
    var track = document.createElement('span'); track.className = 'switch-track';
    label.appendChild(input); label.appendChild(track); row.appendChild(label);
    input.addEventListener('change', function () { toggleModule(id, input.checked, input, false); });
    var logBtn = document.createElement('button'); logBtn.type = 'button'; logBtn.className = 'btn btn-ghost btn-sm'; logBtn.textContent = '日志';
    logBtn.addEventListener('click', function () { loadLogs(id, 'modules'); });
    row.appendChild(logBtn);
    wrap.appendChild(row);
  });
  // API 里多出来的模块也渲染，不丢弃
  list.forEach(function (m) {
    if (MODULE_ORDER.indexOf(m.id) >= 0) return;
    var row = document.createElement('div'); row.className = 'module-row';
    row.innerHTML = '<span class="dot ' + esc(m.state || 'unknown') + '"></span><div class="module-main"><div class="module-name">' +
      esc(m.name || m.id) + '</div>' + (m.desc ? '<div class="module-desc">' + esc(m.desc) + '</div>' : '') + '</div>';
    wrap.appendChild(row);
  });
}
function toggleModule(id, enabled, inputEl, confirmed) {
  api('/modules/' + encodeURIComponent(id) + '/toggle', { method: 'POST', body: confirmed ? { enabled: enabled, confirm: true } : { enabled: enabled } })
    .then(function (d) {
      if (d && d.needConfirm) {
        openModal('确认关闭审批', '<p>' + esc(MODULE_META.writeGate.consequence) + '</p><p>确定要关吗？</p>', [
          { label: '先不关', onClick: function () { inputEl.checked = true; closeModal(); } },
          { label: '确认关闭', primary: true, onClick: function () { closeModal(); toggleModule(id, enabled, inputEl, true); } }
        ]);
        return;
      }
      toast(enabled ? '已开启' : '已关闭'); loadModulesPage();
    })
    .catch(function (err) {
      if (err && err.data && err.data.needConfirm) { toggleModule(id, enabled, inputEl, false); return; }
      inputEl.checked = !enabled; toast('操作失败，请重试');
    });
}
function loadModulesPage() {
  api('/modules').then(function (d) { renderModulesPage((d && d.modules) || []); })
    .catch(function () { $('modulesList').innerHTML = '<p class="empty-text">暂时取不到模块状态。</p>'; });
}
$('refreshModules').addEventListener('click', loadModulesPage);

/* ---------- 页五 版本 ---------- */
function versionRow(label, actual, need, ok) {
  var status = ok === null || ok === undefined ? '—' : ok ? '对齐' : '不一致';
  var cls = ok ? 'ok' : ok === false ? 'fail' : 'manual';
  return '<tr><td>' + esc(label) + '</td><td>' + esc(actual) + '</td><td>' + esc(need) + '</td><td><span class="status-word ' + cls + '">' + status + '</span></td></tr>';
}
function cmpOk(actual, expected) {
  if (!actual || !expected) return null;
  return String(actual).replace(/^v/, '') === String(expected).replace(/^v/, '');
}
function loadVersion() {
  api('/version').then(function (d) {
    if (!d) return;
    var comp = d.companion || {}, hermes = d.hermes || {};
    var hActual = hermes.actual ? hermes.actual : '未能自动检测';
    var hNeed = hermes.expected ? '≥ ' + hermes.expected : '≥ v0.23.0';
    var hOk = hermes.actual ? cmpOk(hermes.actual, hermes.expected || 'v0.23.0') : null;
    var cActual = comp.version || '—';
    $('versionBody').innerHTML =
      versionRow('Hermes 本体', hActual, hNeed, hOk) +
      versionRow('OneDay 伴生服务', cActual, '当前线', comp.version ? true : null);
    $('topVersion').textContent = comp.version ? 'v' + String(comp.version).replace(/^v/, '') : $('topVersion').textContent;
    var note = $('appCompatNote');
    if (comp.minAppVersion) note.textContent = 'App 兼容说明：OneDay App 需要 ' + comp.minAppVersion + ' 及以上版本才能配合这个伴生服务使用。';
    else note.textContent = '';
    var lkg = $('lastKnownGood');
    if (d.lastKnownGood) { lkg.textContent = '上一个确认可用的版本组合：' + (typeof d.lastKnownGood === 'string' ? d.lastKnownGood : JSON.stringify(d.lastKnownGood)); lkg.classList.remove('hidden'); }
    else lkg.classList.add('hidden');
    var hasCmd = false;
    if (d.upgradeCmd) { $('upgradeCmd').textContent = d.upgradeCmd; $('upgradeBlock').classList.remove('hidden'); hasCmd = true; } else $('upgradeBlock').classList.add('hidden');
    if (d.rollbackCmd) { $('rollbackCmd').textContent = d.rollbackCmd; $('rollbackBlock').classList.remove('hidden'); hasCmd = true; } else $('rollbackBlock').classList.add('hidden');
    $('cmdCard').classList.toggle('hidden', !hasCmd);
  }).catch(function () { $('versionBody').innerHTML = '<tr><td colspan="4" class="empty-text">暂时取不到版本信息。</td></tr>'; });
}
$('refreshVersion').addEventListener('click', loadVersion);
document.querySelectorAll('.copy-btn').forEach(function (b) {
  b.addEventListener('click', function () {
    var txt = $(b.getAttribute('data-copy')).textContent;
    if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(txt).then(function () { toast('已复制'); }).catch(function () { toast('复制失败，请长按选择'); });
    else toast('复制失败，请长按选择');
  });
});
$('passwordForm').addEventListener('submit', function (ev) {
  ev.preventDefault();
  var pwd = $('newPassword').value;
  if (!pwd) { $('passwordError').textContent = '请输入新密码'; $('passwordError').classList.remove('hidden'); return; }
  $('passwordError').classList.add('hidden');
  api('/password', { method: 'POST', body: { password: pwd } })
    .then(function () { $('passwordOk').classList.remove('hidden'); $('newPassword').value = ''; })
    .catch(function () { $('passwordError').textContent = '保存失败，请重试'; $('passwordError').classList.remove('hidden'); });
});

/* ---------- 启动 ---------- */
api('/session').then(function (d) {
  if (d && d.authenticated) { if (d.csrf) csrf = d.csrf; showApp(); loadOverview(); }
  else showLogin();
}).catch(function () { showLogin(); });
