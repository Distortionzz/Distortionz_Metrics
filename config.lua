Config = Config or {}

-- ─── Script meta ────────────────────────────────────────────────────
Config.Script = {
    name    = 'Distortionz Metrics',
    version = '1.0.1',
}

Config.VersionCheck = {
    enabled      = true,
    checkOnStart = true,
    url          = 'https://raw.githubusercontent.com/Distortionzz/Distortionz_Metrics/main/version.json',
}
Config.CurrentVersion = '1.0.1'

-- ─── Notifications ──────────────────────────────────────────────────
Config.Notify = {
    title    = 'Metrics',
    resource = 'distortionz_notify',
}

-- ─── Open menu ──────────────────────────────────────────────────────
Config.Open = {
    command = 'metrics',     -- /metrics
    keybind = 'F4',
    keymap  = 'KEYBOARD',
}

-- ─── Permission gates (delegated to distortionz_perms) ──────────────
-- Note: viewing the dashboard requires `viewDashboard`; restarting a
-- resource requires `restartResource` AND the target name must match
-- one of the prefixes in Config.RestartAllowlist below.
Config.Perms = {
    viewDashboard   = 'admin',
    restartResource = 'admin',
}

-- ─── Behaviour ──────────────────────────────────────────────────────
Config.Behavior = {
    -- How often the open NUI re-polls the snapshot (milliseconds).
    -- Lower = more responsive but more wire traffic. 2000 is comfortable.
    refreshIntervalMs = 2000,

    -- Time-series ring-buffer length on the server (samples kept).
    -- 60 samples × 2s refresh = 2-minute history window in the charts.
    historySamples = 60,

    -- Max tick samples kept per opted-in resource for avg/p95 math.
    -- More samples = smoother numbers but more memory.
    tickSamplesPerResource = 120,
}

-- ─── Restart allowlist (prefix match) ───────────────────────────────
-- Only resources whose name STARTS WITH one of these prefixes can be
-- restarted from the dashboard. Hard guard against typos like
-- restarting "qbx_core" by accident.
Config.RestartAllowlist = {
    'distortionz_',
}

-- ─── Resource browser display ───────────────────────────────────────
Config.Display = {
    -- If true, the Resources tab hides resources whose state is 'stopped'.
    -- Stopped resources are usually noise (inactive maps, optional addons).
    hideStopped = false,

    -- Highlight rows whose name starts with one of these prefixes — useful
    -- for spotting your own scripts in a sea of stock resources.
    highlightPrefixes = {
        'distortionz_',
        'qbx_',
    },
}

-- ─── Debug ──────────────────────────────────────────────────────────
Config.Debug = false
