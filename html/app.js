/* ════════════════════════════════════════════════════════════════════
   Distortionz Metrics — NUI controller
   ════════════════════════════════════════════════════════════════════ */

(function () {
    'use strict';

    const RESOURCE = (window.GetParentResourceName && window.GetParentResourceName()) || 'distortionz_metrics';
    const $  = (s, root = document) => root.querySelector(s);
    const $$ = (s, root = document) => Array.from(root.querySelectorAll(s));

    // ─── State ──────────────────────────────────────────────────────
    const state = {
        view: 'resources',
        resources: [],
        timeSeries: [],
        server: null,
        config: { refreshMs: 2000, highlightPrefixes: ['distortionz_', 'qbx_'] },
        filter: 'all',
        search: '',
        sort: { col: 'name', dir: 'asc' },
        refreshTimer: null,
        boot: null,
    };

    // ─── Util ──────────────────────────────────────────────────────
    function post(name, payload) {
        return fetch(`https://${RESOURCE}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(payload || {}),
        }).then(r => r.json()).catch(() => ({ ok: false, reason: 'NUI fetch failed' }));
    }

    function escapeHtml(s) {
        return String(s == null ? '' : s)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;').replace(/'/g, '&#039;');
    }

    function fmtUptime(s) {
        s = Math.max(0, Math.floor(s || 0));
        const d = Math.floor(s / 86400);
        const h = Math.floor((s % 86400) / 3600);
        const m = Math.floor((s % 3600) / 60);
        if (d > 0) return `${d}d ${h}h`;
        if (h > 0) return `${h}h ${m}m`;
        return `${m}m`;
    }

    function fmtMem(kb) {
        if (!kb || kb < 0) return '—';
        if (kb >= 1024 * 1024) return (kb / 1024 / 1024).toFixed(2) + ' GB';
        if (kb >= 1024) return (kb / 1024).toFixed(1) + ' MB';
        return Math.round(kb) + ' KB';
    }

    function fmtAgo(ms) {
        if (!ms || ms <= 0) return '—';
        const sec = Math.max(0, Math.floor((Date.now() - ms) / 1000));
        if (sec < 60)    return `${sec}s ago`;
        if (sec < 3600)  return `${Math.floor(sec / 60)}m ago`;
        if (sec < 86400) return `${Math.floor(sec / 3600)}h ago`;
        return `${Math.floor(sec / 86400)}d ago`;
    }

    function isHighlightedName(name) {
        const prefixes = state.config.highlightPrefixes || [];
        return prefixes.some(p => name.startsWith(p));
    }

    // ─── In-NUI toast (replaces alert) ─────────────────────────────
    let toastTimer = null;
    function showToast(message, type) {
        const t = $('#toast');
        t.textContent = message;
        t.className = 'toast ' + (type || 'info');
        void t.offsetWidth;
        t.classList.add('show');
        if (toastTimer) clearTimeout(toastTimer);
        toastTimer = setTimeout(() => {
            t.classList.remove('show');
            setTimeout(() => { if (!t.classList.contains('show')) t.classList.add('hidden'); }, 200);
        }, 4000);
        t.classList.remove('hidden');
    }

    // ─── In-NUI confirm (replaces window.confirm) ──────────────────
    let confirmResolver = null;
    function showConfirm(title, message, okLabel) {
        return new Promise(resolve => {
            $('#confirmTitle').textContent   = title || 'Are you sure?';
            $('#confirmMessage').innerHTML   = message || '';
            $('#confirmOk').textContent      = okLabel || 'Confirm';
            const m = $('#confirmModal');
            m.classList.remove('hidden');
            void m.offsetWidth;
            m.classList.add('show');
            confirmResolver = resolve;
        });
    }
    function resolveConfirm(v) {
        const m = $('#confirmModal');
        m.classList.remove('show');
        setTimeout(() => m.classList.add('hidden'), 180);
        if (confirmResolver) { const r = confirmResolver; confirmResolver = null; r(v); }
    }
    $('#confirmOk').addEventListener('click',     () => resolveConfirm(true));
    $('#confirmCancel').addEventListener('click', () => resolveConfirm(false));
    document.addEventListener('keydown', (e) => {
        if (e.key !== 'Escape') return;
        if ($('#confirmModal').classList.contains('show')) {
            e.stopPropagation();
            resolveConfirm(false);
        }
    });

    // ─── View switching ────────────────────────────────────────────
    function switchView(name) {
        state.view = name;
        $$('.tab').forEach(t => t.classList.toggle('active', t.dataset.view === name));
        $$('.view').forEach(v => v.classList.toggle('active', v.dataset.view === name));

        if (name === 'server') drawAllCharts();
        if (name === 'ticks')  renderTicks();
    }
    $$('.tab').forEach(t => t.addEventListener('click', () => switchView(t.dataset.view)));
    $('#close-btn').addEventListener('click', () => post('close'));

    // ─── Filters / search / sort ───────────────────────────────────
    $('#resource-search').addEventListener('input', e => {
        state.search = (e.target.value || '').toLowerCase().trim();
        renderResources();
    });
    $$('.filter-chip').forEach(chip => {
        chip.addEventListener('click', () => {
            $$('.filter-chip').forEach(c => c.classList.toggle('active', c === chip));
            state.filter = chip.dataset.stateFilter;
            renderResources();
        });
    });

    function applySort(col) {
        if (state.sort.col === col) {
            state.sort.dir = state.sort.dir === 'asc' ? 'desc' : 'asc';
        } else {
            state.sort.col = col;
            state.sort.dir = 'asc';
        }
        renderResources();
    }
    $$('.metrics-table thead th[data-sort]').forEach(th => {
        th.addEventListener('click', () => applySort(th.dataset.sort));
    });

    // ─── Resource table render ─────────────────────────────────────
    function filteredResources() {
        let rows = state.resources.slice();
        const f = state.filter;
        if (f === 'started')      rows = rows.filter(r => r.state === 'started');
        else if (f === 'stopped') rows = rows.filter(r => r.state === 'stopped');
        else if (f === 'distortionz') rows = rows.filter(r => r.name.startsWith('distortionz_'));
        else if (f === 'qbx')         rows = rows.filter(r => r.name.startsWith('qbx_'));

        const s = state.search;
        if (s) {
            rows = rows.filter(r =>
                (r.name && r.name.toLowerCase().includes(s)) ||
                (r.author && r.author.toLowerCase().includes(s))
            );
        }

        const { col, dir } = state.sort;
        const mult = dir === 'asc' ? 1 : -1;
        rows.sort((a, b) => {
            let va = a[col], vb = b[col];
            if (col === 'tick') {
                va = a.tick ? a.tick.avg : -1;
                vb = b.tick ? b.tick.avg : -1;
            }
            if (va == null && vb == null) return 0;
            if (va == null) return 1;
            if (vb == null) return -1;
            if (typeof va === 'number' && typeof vb === 'number') return (va - vb) * mult;
            return String(va).localeCompare(String(vb)) * mult;
        });
        return rows;
    }

    function renderResources() {
        const rows = filteredResources();
        $('#tab-count-resources').textContent = rows.length;

        // Sort indicator
        $$('.metrics-table thead th[data-sort]').forEach(th => {
            th.classList.remove('sort-asc', 'sort-desc');
            if (th.dataset.sort === state.sort.col) {
                th.classList.add(state.sort.dir === 'asc' ? 'sort-asc' : 'sort-desc');
            }
        });

        const tbody = $('#resources-body');
        if (rows.length === 0) {
            tbody.innerHTML = '<tr><td colspan="8" class="empty">No matching resources.</td></tr>';
            return;
        }

        tbody.innerHTML = rows.map(r => {
            const highlight = isHighlightedName(r.name) ? 'row-highlight' : '';
            const tickCell = r.tick
                ? `<span class="cell-mono">${r.tick.avg.toFixed(2)} / ${r.tick.p95.toFixed(2)}</span>`
                : '<span class="cell-mono" style="opacity:.4;">—</span>';
            const restartBtn = isAllowlisted(r.name)
                ? `<button class="btn ghost" data-restart="${escapeHtml(r.name)}">Restart</button>`
                : `<button class="btn" disabled title="Not in restart allowlist">—</button>`;
            return `
                <tr class="${highlight}">
                    <td class="cell-name">${escapeHtml(r.name)}</td>
                    <td><span class="state-pill ${r.state}">${r.state}</span></td>
                    <td class="cell-mono">${escapeHtml(r.version || '—')}</td>
                    <td class="cell-num">${r.depCount || 0}</td>
                    <td class="cell-num">${r.restartCount || 0}</td>
                    <td class="cell-mono">${fmtAgo(r.lastRestartMs)}</td>
                    <td class="cell-num">${tickCell}</td>
                    <td class="cell-actions">${restartBtn}</td>
                </tr>`;
        }).join('');
    }

    function isAllowlisted(name) {
        const list = (state.config && state.config.allowlist) || ['distortionz_'];
        return list.some(p => name.startsWith(p));
    }

    // Restart action (event delegation on tbody)
    $('#resources-body').addEventListener('click', async (e) => {
        const btn = e.target.closest('[data-restart]');
        if (!btn) return;
        const name = btn.dataset.restart;
        const ok = await showConfirm(
            `Restart ${name}?`,
            `This will <code>restart ${escapeHtml(name)}</code> on the server. Active sessions for that resource (open menus, live streams) will drop.`,
            'Restart'
        );
        if (!ok) return;
        btn.disabled = true;
        const res = await post('restart', { name });
        btn.disabled = false;
        if (res.ok) {
            showToast(`Restarted ${name}.`, 'success');
            // Refresh shortly so the new restart count shows up
            setTimeout(refreshSnapshot, 600);
        } else {
            showToast(res.reason || 'Restart failed.', 'error');
        }
    });

    // ─── Ticks table ────────────────────────────────────────────────
    function renderTicks() {
        const rows = state.resources
            .filter(r => r.tick)
            .sort((a, b) => (b.tick.avg || 0) - (a.tick.avg || 0));
        $('#tab-count-ticks').textContent = rows.length;

        const lp = (state.lastSnapshot && state.lastSnapshot.local_perf) || {};
        $('#local-fps').textContent   = (lp.fps || 0) + ' FPS';
        $('#local-frame').textContent = (lp.frameMs || 0).toFixed(2) + ' ms';
        $('#local-worst').textContent = (lp.worstMs || 0).toFixed(2) + ' ms';

        const tbody = $('#ticks-body');
        if (rows.length === 0) {
            tbody.innerHTML = `<tr><td colspan="7" class="empty">
                No opted-in resources yet. Have any of your scripts call
                <code>exports.distortionz_metrics:RegisterTick(deltaMs, label)</code>
                to start showing up here.
            </td></tr>`;
            return;
        }

        tbody.innerHTML = rows.map(r => {
            const t = r.tick;
            const ageStr = (t.ageS != null) ? `${t.ageS}s ago` : '—';
            return `
                <tr>
                    <td class="cell-name">${escapeHtml(r.name)}</td>
                    <td class="cell-mono">${escapeHtml(t.label || '—')}</td>
                    <td class="cell-num">${t.avg.toFixed(2)}</td>
                    <td class="cell-num">${t.p95.toFixed(2)}</td>
                    <td class="cell-num">${t.max.toFixed(2)}</td>
                    <td class="cell-num">${t.samples}</td>
                    <td class="cell-mono">${ageStr}</td>
                </tr>`;
        }).join('');
    }

    // ─── Charts (lightweight canvas — no external libs) ────────────
    function drawChart(canvasId, series, color, opts) {
        opts = opts || {};
        const canvas = document.getElementById(canvasId);
        if (!canvas || !canvas.getContext) return;
        const ctx = canvas.getContext('2d');
        const w = canvas.width, h = canvas.height;
        ctx.clearRect(0, 0, w, h);

        if (!series || series.length < 2) {
            ctx.fillStyle = '#6e7681';
            ctx.font = '12px "Segoe UI", sans-serif';
            ctx.textAlign = 'center';
            ctx.fillText('Collecting samples…', w / 2, h / 2);
            return;
        }

        const padding = 4;
        const min = opts.min != null ? opts.min : Math.min.apply(null, series);
        const max = opts.max != null ? opts.max : Math.max.apply(null, series);
        const range = Math.max(1, max - min);
        const stepX = (w - padding * 2) / Math.max(1, series.length - 1);

        // Faint grid (3 horizontal lines)
        ctx.strokeStyle = 'rgba(240, 246, 252, 0.05)';
        ctx.lineWidth = 1;
        for (let i = 1; i <= 3; i++) {
            const y = (h / 4) * i;
            ctx.beginPath();
            ctx.moveTo(padding, y);
            ctx.lineTo(w - padding, y);
            ctx.stroke();
        }

        // Area fill
        ctx.beginPath();
        ctx.moveTo(padding, h - padding);
        for (let i = 0; i < series.length; i++) {
            const x = padding + i * stepX;
            const y = h - padding - ((series[i] - min) / range) * (h - padding * 2);
            if (i === 0) ctx.lineTo(x, y); else ctx.lineTo(x, y);
        }
        ctx.lineTo(padding + (series.length - 1) * stepX, h - padding);
        ctx.closePath();
        ctx.fillStyle = color + '20';   // ~12% alpha
        ctx.fill();

        // Line
        ctx.beginPath();
        for (let i = 0; i < series.length; i++) {
            const x = padding + i * stepX;
            const y = h - padding - ((series[i] - min) / range) * (h - padding * 2);
            if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
        }
        ctx.strokeStyle = color;
        ctx.lineWidth = 2;
        ctx.stroke();

        // Last point dot
        const lx = padding + (series.length - 1) * stepX;
        const ly = h - padding - ((series[series.length - 1] - min) / range) * (h - padding * 2);
        ctx.beginPath();
        ctx.arc(lx, ly, 3, 0, Math.PI * 2);
        ctx.fillStyle = color;
        ctx.fill();
    }

    function drawAllCharts() {
        const ts = state.timeSeries || [];
        const memSeries     = ts.map(s => s.memoryKb);
        const playerSeries  = ts.map(s => s.players);
        const eventsSeries  = ts.map(s => (s.eventsIn || 0) + (s.eventsOut || 0));

        drawChart('chart-mem',     memSeries,    '#c8c828');
        drawChart('chart-players', playerSeries, '#3fb950', { min: 0 });
        drawChart('chart-events',  eventsSeries, '#58a6ff', { min: 0 });

        const last = ts[ts.length - 1] || {};
        $('#mem-current').textContent     = fmtMem(last.memoryKb);
        $('#players-current').textContent = String(last.players != null ? last.players : '—');
        $('#events-current').textContent  = `${last.eventsIn || 0} in / ${last.eventsOut || 0} out`;

        if (state.server) {
            $('#players-cap').textContent = `cap ${state.server.maxPlayers || '?'}`;
        }
    }

    // ─── Snapshot / refresh loop ───────────────────────────────────
    async function refreshSnapshot() {
        const data = await post('snapshot');
        if (!data || !data.ok) {
            $('#refresh-hint').textContent = data && data.reason ? data.reason : 'no permission';
            $('#refresh-hint').classList.remove('live');
            return;
        }
        state.resources  = data.resources || [];
        state.timeSeries = data.timeSeries || [];
        state.server     = data.server || null;
        state.config     = Object.assign(state.config, data.config || {});
        state.lastSnapshot = data;

        // Strip
        if (state.server) {
            $('#strip-uptime').textContent  = fmtUptime(state.server.uptimeS);
            $('#strip-players').textContent = `${state.server.players}/${state.server.maxPlayers || '?'}`;
            $('#strip-mem').textContent     = fmtMem(state.server.memoryKb);
            $('#strip-res').textContent     = String(state.resources.length);
        }
        if (data.local_perf) {
            $('#strip-fps').textContent = String(data.local_perf.fps);
        }

        $('#refresh-hint').textContent = `live · ${(state.config.refreshMs || 2000) / 1000}s`;
        $('#refresh-hint').classList.add('live');

        // Re-render the active view
        if (state.view === 'resources') renderResources();
        if (state.view === 'server')    drawAllCharts();
        if (state.view === 'ticks')     renderTicks();
    }

    function startRefreshLoop() {
        stopRefreshLoop();
        refreshSnapshot();
        const ms = (state.config.refreshMs || (state.boot && state.boot.refreshMs) || 2000);
        state.refreshTimer = setInterval(refreshSnapshot, ms);
    }
    function stopRefreshLoop() {
        if (state.refreshTimer) { clearInterval(state.refreshTimer); state.refreshTimer = null; }
    }

    // ─── Inbound from Lua ──────────────────────────────────────────
    window.addEventListener('message', (event) => {
        const msg = event.data || {};
        if (msg.action === 'open') {
            state.boot = msg.boot || {};
            if (state.boot.version) $('#brand-version').textContent = 'v' + state.boot.version;
            $('#root').classList.remove('hidden');
            switchView('resources');
            startRefreshLoop();
            return;
        }
        if (msg.action === 'closed') {
            stopRefreshLoop();
            $('#root').classList.add('hidden');
            return;
        }
    });

    // Hide on load — wait for 'open' from Lua
    $('#root').classList.add('hidden');
})();
