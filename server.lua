-- ╔══════════════════════════════════════════════════════════════════╗
-- ║ Distortionz Metrics — server                                     ║
-- ║                                                                  ║
-- ║ Honest scope: FiveM does not expose per-resource ms-per-frame to ║
-- ║ Lua (resmon reads from the script-host directly). What we DO     ║
-- ║ provide:                                                         ║
-- ║   • Live resource roster (state, version, deps, restart count)   ║
-- ║   • Server health time-series (uptime, memory, players)          ║
-- ║   • Opt-in per-script tick samples via                           ║
-- ║       exports.distortionz_metrics:RegisterTick(deltaMs[, label]) ║
-- ║   • Allowlisted restart action (admin-tier + prefix gated)       ║
-- ╚══════════════════════════════════════════════════════════════════╝

local lib = lib

-- ─── State ──────────────────────────────────────────────────────────
local startedAt = os.time()

-- restartHistory[name] = { count = N, lastAtMs = ms timestamp }
local restartHistory = {}

-- tickSamples[resource] = { samples = { deltaMs, ... }, lastUpdated = ms, label = '...' }
local tickSamples = {}

-- Time-series ring buffer for the Server tab charts.
-- Each entry: { ts, memoryKb, players, eventsIn, eventsOut }
local timeSeries = {}

-- Lightweight event counters (reset between snapshots so the chart
-- shows a per-tick rate). These count OUR resource's traffic only —
-- a calibration baseline rather than server-wide telemetry, since
-- there's no native hook to count other resources' net events.
local netInCount  = 0
local netOutCount = 0
local origTriggerClientEvent  = TriggerClientEvent
local origTriggerLatentClient = TriggerLatentClientEvent
function TriggerClientEvent(...)        netOutCount = netOutCount + 1; return origTriggerClientEvent(...) end
function TriggerLatentClientEvent(...)  netOutCount = netOutCount + 1; return origTriggerLatentClient(...) end

-- We can hook our own RegisterNetEvent additions for in-counts.
local origRegisterNet = RegisterNetEvent
function RegisterNetEvent(name, cb)
    if cb then
        return origRegisterNet(name, function(...) netInCount = netInCount + 1; return cb(...) end)
    end
    return origRegisterNet(name)
end

-- ─── Helpers ────────────────────────────────────────────────────────
local function Debug(...)
    if Config.Debug then
        print(('[metrics:server] %s'):format(table.concat({...}, ' ')))
    end
end

local function isAtLeast(src, requiredTier)
    if not src or src == 0 then return true end
    if GetResourceState('distortionz_perms') ~= 'started' then return false end
    local ok, result = pcall(function()
        return exports.distortionz_perms:IsAtLeast(src, requiredTier)
    end)
    return ok and result == true
end

local function notify(src, message, notifyType, duration, title)
    notifyType = notifyType or 'primary'
    duration   = duration or 5000
    title      = title or Config.Notify.title
    if GetResourceState(Config.Notify.resource) == 'started' then
        TriggerClientEvent('distortionz_metrics:client:notify', src, message, notifyType, duration, title)
        return
    end
    TriggerClientEvent('ox_lib:notify', src, {
        title = title, description = message, type = notifyType, duration = duration,
    })
end

local function allowlistedForRestart(name)
    if type(name) ~= 'string' then return false end
    for _, prefix in ipairs(Config.RestartAllowlist or {}) do
        if name:sub(1, #prefix) == prefix then return true end
    end
    return false
end

local function nowMs() return os.time() * 1000 + math.floor(GetGameTimer() % 1000) end

-- ─── Resource enumeration ──────────────────────────────────────────
local function enumerateResources()
    local out = {}
    local total = GetNumResources()
    for i = 0, total - 1 do
        local name = GetResourceByFindIndex(i)
        if name then
            local state = GetResourceState(name)
            local rh    = restartHistory[name]
            local tick  = tickSamples[name]

            -- Tick stats: avg + p95 + max from the rolling samples
            local tickStats = nil
            if tick and tick.samples and #tick.samples > 0 then
                local arr = tick.samples
                local sum, mx = 0, 0
                local sorted = {}
                for _, v in ipairs(arr) do
                    sum = sum + v
                    if v > mx then mx = v end
                    sorted[#sorted + 1] = v
                end
                table.sort(sorted)
                local p95idx = math.max(1, math.ceil(#sorted * 0.95))
                tickStats = {
                    avg     = sum / #arr,
                    p95     = sorted[p95idx],
                    max     = mx,
                    samples = #arr,
                    label   = tick.label,
                    ageS    = tick.lastUpdated and math.floor((nowMs() - tick.lastUpdated) / 1000) or nil,
                }
            end

            out[#out + 1] = {
                name        = name,
                state       = state,
                version     = GetResourceMetadata(name, 'version', 0) or '',
                author      = GetResourceMetadata(name, 'author', 0)  or '',
                description = GetResourceMetadata(name, 'description', 0) or '',
                depCount    = (function()
                    local n = GetNumResourceMetadata(name, 'dependency') or 0
                    return n
                end)(),
                restartCount  = rh and rh.count or 0,
                lastRestartMs = rh and rh.lastAtMs or nil,
                tick          = tickStats,
            }
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- ─── Time-series sampler ───────────────────────────────────────────
CreateThread(function()
    while true do
        Wait(Config.Behavior.refreshIntervalMs or 2000)
        local sample = {
            ts        = os.time(),
            memoryKb  = math.floor(collectgarbage('count')),
            players   = #GetPlayers(),
            eventsIn  = netInCount,
            eventsOut = netOutCount,
        }
        netInCount, netOutCount = 0, 0
        timeSeries[#timeSeries + 1] = sample
        local cap = Config.Behavior.historySamples or 60
        while #timeSeries > cap do
            table.remove(timeSeries, 1)
        end
    end
end)

-- ─── Restart bookkeeping ───────────────────────────────────────────
AddEventHandler('onResourceStart', function(resource)
    local rh = restartHistory[resource] or { count = 0, lastAtMs = 0 }
    -- Don't count the very first start of a resource as a restart;
    -- we only know it's a restart if we've seen it stop+start.
    if rh.count > 0 or rh.lastAtMs > 0 then
        rh.count = rh.count + 1
    end
    rh.lastAtMs = nowMs()
    restartHistory[resource] = rh
end)

AddEventHandler('onResourceStop', function(resource)
    local rh = restartHistory[resource] or { count = 0, lastAtMs = 0 }
    rh.lastAtMs = nowMs()
    restartHistory[resource] = rh
end)

-- ─── Public exports ────────────────────────────────────────────────
-- Other distortionz_* scripts call this each tick (or every N ticks)
-- with the elapsed milliseconds since their last call. We aggregate
-- avg / p95 / max for the dashboard.
--
--   Example caller (in another resource's main.lua):
--     local last = GetGameTimer()
--     CreateThread(function()
--       while true do
--         Wait(0)
--         local now = GetGameTimer()
--         pcall(function() exports.distortionz_metrics:RegisterTick(now - last, 'main_loop') end)
--         last = now
--       end
--     end)
exports('RegisterTick', function(deltaMs, label)
    local resource = GetInvokingResource() or '?'
    if resource == GetCurrentResourceName() then return end
    deltaMs = tonumber(deltaMs)
    if not deltaMs or deltaMs < 0 or deltaMs > 60000 then return end

    local entry = tickSamples[resource]
    if not entry then
        entry = { samples = {}, lastUpdated = nowMs(), label = label }
        tickSamples[resource] = entry
    end
    entry.samples[#entry.samples + 1] = deltaMs
    entry.lastUpdated = nowMs()
    if label then entry.label = label end

    local cap = Config.Behavior.tickSamplesPerResource or 120
    while #entry.samples > cap do
        table.remove(entry.samples, 1)
    end
end)

-- Read-only export so other scripts can introspect the last snapshot
exports('GetSnapshot', function()
    return {
        uptimeS    = os.time() - startedAt,
        memoryKb   = math.floor(collectgarbage('count')),
        players    = #GetPlayers(),
        resources  = enumerateResources(),
        timeSeries = timeSeries,
    }
end)

-- ─── Callbacks (NUI bridge) ────────────────────────────────────────
lib.callback.register('distortionz_metrics:cb:snapshot', function(src)
    if not isAtLeast(src, Config.Perms.viewDashboard) then return nil end
    return {
        ok = true,
        server = {
            uptimeS    = os.time() - startedAt,
            memoryKb   = math.floor(collectgarbage('count')),
            players    = #GetPlayers(),
            maxPlayers = GetConvarInt('sv_maxclients', 32),
            hostname   = GetConvar('sv_hostname', '') or '',
            version    = Config.Script.version,
            ts         = os.time(),
        },
        resources  = enumerateResources(),
        timeSeries = timeSeries,
        config = {
            refreshMs        = Config.Behavior.refreshIntervalMs,
            historySamples   = Config.Behavior.historySamples,
            highlightPrefixes = Config.Display.highlightPrefixes,
            hideStopped      = Config.Display.hideStopped,
            allowlist        = Config.RestartAllowlist,
        },
    }
end)

-- Restart action — admin-tier AND target must be allowlisted.
lib.callback.register('distortionz_metrics:cb:restart', function(src, payload)
    if not isAtLeast(src, Config.Perms.restartResource) then
        return { ok = false, reason = 'Insufficient permission.' }
    end
    if type(payload) ~= 'table' or type(payload.name) ~= 'string' then
        return { ok = false, reason = 'Bad payload.' }
    end
    local name = payload.name
    if not allowlistedForRestart(name) then
        return { ok = false, reason = ('Resource "%s" is not in the restart allowlist.'):format(name) }
    end
    if GetResourceState(name) == 'missing' then
        return { ok = false, reason = ('Resource "%s" not found.'):format(name) }
    end

    -- Audit + perform
    print(('^3[distortionz_metrics]^7 %s requested restart of "%s"')
        :format(src == 0 and 'CONSOLE' or ('id ' .. tostring(src)), name))

    local ok = pcall(function()
        ExecuteCommand(('ensure %s'):format(name))   -- ensure handles start-if-stopped
        ExecuteCommand(('restart %s'):format(name))
    end)
    if not ok then
        return { ok = false, reason = 'Restart command failed.' }
    end
    return { ok = true }
end)

-- Convenience: just receive a fresh time-series tail (used by the
-- Server tab so the NUI doesn't keep re-fetching the resource list
-- when the player is on the chart view).
lib.callback.register('distortionz_metrics:cb:tail', function(src)
    if not isAtLeast(src, Config.Perms.viewDashboard) then return nil end
    return {
        ok         = true,
        server = {
            uptimeS  = os.time() - startedAt,
            memoryKb = math.floor(collectgarbage('count')),
            players  = #GetPlayers(),
            ts       = os.time(),
        },
        timeSeries = timeSeries,
    }
end)

-- ─── /metrics command ──────────────────────────────────────────────
RegisterCommand(Config.Open.command or 'metrics', function(src)
    if src == 0 then print('Run /metrics from in-game.'); return end
    if not isAtLeast(src, Config.Perms.viewDashboard) then
        notify(src, 'You do not have permission to open the metrics dashboard.', 'error')
        return
    end
    TriggerClientEvent('distortionz_metrics:client:open', src)
end, false)

-- ─── Startup banner ────────────────────────────────────────────────
CreateThread(function()
    Wait(500)
    print(('^5[distortionz_metrics:server]^7 v%s loaded — refresh=%dms historySamples=%d')
        :format(Config.Script.version or '?',
            Config.Behavior.refreshIntervalMs or 2000,
            Config.Behavior.historySamples or 60))
end)
