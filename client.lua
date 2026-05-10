-- ╔══════════════════════════════════════════════════════════════════╗
-- ║ Distortionz Metrics — client                                     ║
-- ║ NUI bridge + /metrics command + F4 keybind + local FPS sampler.  ║
-- ╚══════════════════════════════════════════════════════════════════╝

local lib = lib

local nuiOpen = false

-- Local FPS measurement (rolling average over the last second)
local fpsSamples = {}
local lastFrameMs = 0

-- ─── Helpers ────────────────────────────────────────────────────────
local function Notify(message, notifyType, duration, title)
    notifyType = notifyType or 'primary'
    duration   = duration or 5000
    title      = title or Config.Notify.title
    if notifyType == 'inform' then notifyType = 'info' end
    if GetResourceState(Config.Notify.resource) == 'started' then
        exports[Config.Notify.resource]:Notify(message, notifyType, duration, title)
        return
    end
    lib.notify({ title = title, description = message, type = notifyType, duration = duration })
end

RegisterNetEvent('distortionz_metrics:client:notify', function(message, notifyType, duration, title)
    Notify(message, notifyType, duration, title)
end)

local function setNuiOpen(open)
    nuiOpen = open
    SetNuiFocus(open, open)
    SetNuiFocusKeepInput(false)
end

-- ─── Local FPS sampler ─────────────────────────────────────────────
CreateThread(function()
    lastFrameMs = GetGameTimer()
    while true do
        Wait(0)
        local now = GetGameTimer()
        local dt = now - lastFrameMs
        lastFrameMs = now
        if dt > 0 and dt < 1000 then
            fpsSamples[#fpsSamples + 1] = dt
            -- Keep ~last second of frames
            if #fpsSamples > 240 then table.remove(fpsSamples, 1) end
        end
    end
end)

local function localPerf()
    if #fpsSamples == 0 then return { fps = 0, frameMs = 0 } end
    local sum, mx = 0, 0
    for _, v in ipairs(fpsSamples) do
        sum = sum + v
        if v > mx then mx = v end
    end
    local avg = sum / #fpsSamples
    return {
        fps        = avg > 0 and math.floor(1000 / avg + 0.5) or 0,
        frameMs    = math.floor(avg * 100) / 100,
        worstMs    = math.floor(mx * 100) / 100,
        sampleCount = #fpsSamples,
    }
end

-- ─── Open / close ──────────────────────────────────────────────────
local function openDashboard()
    if nuiOpen then return end
    setNuiOpen(true)
    SendNUIMessage({
        action = 'open',
        boot = {
            version    = Config.Script.version,
            refreshMs  = Config.Behavior.refreshIntervalMs or 2000,
        },
    })
end

RegisterNetEvent('distortionz_metrics:client:open', openDashboard)

RegisterCommand(Config.Open.command or 'metrics', function() openDashboard() end, false)

lib.addKeybind({
    name        = 'distortionz_metrics_open',
    description = 'Open Distortionz Metrics Dashboard',
    defaultKey  = Config.Open.keybind or 'F4',
    defaultMapper = Config.Open.keymap or 'KEYBOARD',
    onPressed   = function() openDashboard() end,
})

-- ─── NUI callbacks ─────────────────────────────────────────────────
RegisterNUICallback('close', function(_, cb)
    setNuiOpen(false)
    SendNUIMessage({ action = 'closed' })
    cb({ ok = true })
end)

RegisterNUICallback('snapshot', function(_, cb)
    local data = lib.callback.await('distortionz_metrics:cb:snapshot', false)
    if not data then cb({ ok = false, reason = 'No permission or perms not started.' }); return end
    data.local_perf = localPerf()
    cb(data)
end)

RegisterNUICallback('tail', function(_, cb)
    local data = lib.callback.await('distortionz_metrics:cb:tail', false)
    if not data then cb({ ok = false }); return end
    data.local_perf = localPerf()
    cb(data)
end)

RegisterNUICallback('restart', function(d, cb)
    cb(lib.callback.await('distortionz_metrics:cb:restart', false, { name = d.name }) or { ok = false })
end)

-- ─── ESC closes UI ─────────────────────────────────────────────────
CreateThread(function()
    while true do
        Wait(0)
        if nuiOpen then
            if IsControlJustReleased(0, 200) then   -- ESC
                setNuiOpen(false)
                SendNUIMessage({ action = 'closed' })
            end
        else
            Wait(500)
        end
    end
end)

-- ─── Cleanup on resource stop ──────────────────────────────────────
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if nuiOpen then SetNuiFocus(false, false) end
end)
