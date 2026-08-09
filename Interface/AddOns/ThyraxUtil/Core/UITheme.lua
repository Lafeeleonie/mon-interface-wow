local _, ns = ...

ns.UI = ns.UI or {}
local UI = ns.UI

if type(UI._themedFrames) ~= "table" then
    UI._themedFrames = setmetatable({}, { __mode = "k" })
end

-- Shared color helper from Core/Color.lua (loaded before UITheme in the TOC).
local Clamp = ns.Color.Clamp

local function EnsureTexture(frame, key, layer)
    local texture = frame[key]
    if not texture then
        texture = frame:CreateTexture(nil, layer or "BACKGROUND")
        frame[key] = texture
    end
    texture:SetAllPoints(frame)
    return texture
end

local function EnsureBorder(frame)
    local border = frame._thyraxThemeBorder
    if border then
        return border
    end

    border = {
        top = frame:CreateTexture(nil, "BORDER"),
        right = frame:CreateTexture(nil, "BORDER"),
        bottom = frame:CreateTexture(nil, "BORDER"),
        left = frame:CreateTexture(nil, "BORDER"),
    }

    border.top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    border.top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    border.top:SetHeight(1)

    border.bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    border.bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    border.bottom:SetHeight(1)

    border.left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    border.left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    border.left:SetWidth(1)

    border.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    border.right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    border.right:SetWidth(1)

    frame._thyraxThemeBorder = border
    return border
end

local function SetBorderColor(border, r, g, b, a)
    border.top:SetTexture("Interface\\Buttons\\WHITE8x8")
    border.right:SetTexture("Interface\\Buttons\\WHITE8x8")
    border.bottom:SetTexture("Interface\\Buttons\\WHITE8x8")
    border.left:SetTexture("Interface\\Buttons\\WHITE8x8")

    border.top:SetVertexColor(r, g, b, a)
    border.right:SetVertexColor(r, g, b, a)
    border.bottom:SetVertexColor(r, g, b, a)
    border.left:SetVertexColor(r, g, b, a)
end

local function ResolvePalette(theme, opts)
    local transparent = opts and opts.transparent
    local borderEnabled = not (opts and opts.border == false)

    -- Pull the active accent so themed frames (AH overlay border etc.) follow
    -- the global accent preset. Falls back to gold tones when UI:GetAccentPalette
    -- isn't available yet (very early init).
    local accent
    if UI.GetAccentPalette then
        accent = UI:GetAccentPalette()
    end

    if theme == "Modern" then
        local borderR, borderG, borderB = 0.68, 0.57, 0.26
        local bgR, bgG, bgB = 0.12, 0.09, 0.05
        if accent and accent.accent and accent.surface then
            -- Use accentSoft as the border tone; if it's missing fall back to
            -- accent. Surface gives the bg.
            local edge = accent.accentSoft or accent.accent
            borderR, borderG, borderB = edge[1], edge[2], edge[3]
            bgR, bgG, bgB = accent.surface[1], accent.surface[2], accent.surface[3]
        end
        return {
            bgR = bgR,
            bgG = bgG,
            bgB = bgB,
            bgA = transparent and 0 or 0.92,
            borderR = borderR,
            borderG = borderG,
            borderB = borderB,
            borderA = borderEnabled and 0.95 or 0,
        }
    end

    return {
        bgR = 0.10,
        bgG = 0.10,
        bgB = 0.10,
        bgA = transparent and 0 or 0.90,
        borderR = 0,
        borderG = 0,
        borderB = 0,
        borderA = borderEnabled and 1 or 0,
    }
end

function UI:GetTheme()
    if ns.Settings and ns.Settings.GetTheme then
        return ns.Settings:GetTheme()
    end
    return "Modern"
end

-- Accent presets are independent of the Modern / Classic style: the style
-- selects which widget *template* (ElvUI-look vs Blizzard-look) is used,
-- the accent selects the highlight *color* applied across switches, sliders,
-- window borders and header buttons. Keeping them orthogonal means a user
-- who likes the Modern switches but dislikes gold can pick e.g. "Blue"
-- without losing the modern controls.
local ACCENT_PRESETS = {
    Gold   = {
        accent       = { 0.95, 0.78, 0.30, 1 },
        accentSoft   = { 0.72, 0.62, 0.28, 1 },
        accentEdge   = { 0.55, 0.45, 0.18, 0.90 },
        surface      = { 0.18, 0.13, 0.07, 0.95 },
        surfaceDark  = { 0.14, 0.11, 0.05, 1 },
        header       = { 1.00, 0.82, 0.30, 1 },
    },
    Silver = {
        accent       = { 0.82, 0.82, 0.86, 1 },
        accentSoft   = { 0.55, 0.55, 0.60, 1 },
        accentEdge   = { 0.40, 0.40, 0.45, 0.90 },
        surface      = { 0.11, 0.11, 0.13, 0.95 },
        surfaceDark  = { 0.07, 0.07, 0.09, 1 },
        header       = { 0.92, 0.92, 0.96, 1 },
    },
    Blue   = {
        accent       = { 0.36, 0.68, 1.00, 1 },
        accentSoft   = { 0.24, 0.50, 0.85, 1 },
        accentEdge   = { 0.18, 0.36, 0.62, 0.90 },
        surface      = { 0.06, 0.10, 0.18, 0.95 },
        surfaceDark  = { 0.04, 0.07, 0.13, 1 },
        header       = { 0.50, 0.78, 1.00, 1 },
    },
    Green  = {
        accent       = { 0.40, 0.90, 0.50, 1 },
        accentSoft   = { 0.28, 0.65, 0.36, 1 },
        accentEdge   = { 0.18, 0.45, 0.24, 0.90 },
        surface      = { 0.06, 0.13, 0.08, 0.95 },
        surfaceDark  = { 0.04, 0.09, 0.05, 1 },
        header       = { 0.55, 1.00, 0.65, 1 },
    },
    Red    = {
        accent       = { 0.96, 0.36, 0.36, 1 },
        accentSoft   = { 0.75, 0.26, 0.26, 1 },
        accentEdge   = { 0.55, 0.18, 0.18, 0.90 },
        surface      = { 0.16, 0.06, 0.06, 0.95 },
        surfaceDark  = { 0.11, 0.04, 0.04, 1 },
        header       = { 1.00, 0.50, 0.50, 1 },
    },
    Purple = {
        accent       = { 0.74, 0.50, 0.96, 1 },
        accentSoft   = { 0.55, 0.36, 0.78, 1 },
        accentEdge   = { 0.36, 0.22, 0.55, 0.90 },
        surface      = { 0.10, 0.06, 0.16, 0.95 },
        surfaceDark  = { 0.07, 0.04, 0.11, 1 },
        header       = { 0.85, 0.62, 1.00, 1 },
    },
    Teal   = {
        accent       = { 0.30, 0.85, 0.85, 1 },
        accentSoft   = { 0.20, 0.65, 0.65, 1 },
        accentEdge   = { 0.12, 0.42, 0.42, 0.90 },
        surface      = { 0.04, 0.13, 0.13, 0.95 },
        surfaceDark  = { 0.03, 0.09, 0.09, 1 },
        header       = { 0.45, 0.95, 0.95, 1 },
    },
}

UI.ACCENT_PRESETS = ACCENT_PRESETS

function UI:GetAccentPreset()
    if ns.Settings and ns.Settings.GetAccentPreset then
        return ns.Settings:GetAccentPreset()
    end
    return "Gold"
end

function UI:SetAccentPreset(name)
    if ns.Settings and ns.Settings.SetAccentPreset then
        ns.Settings:SetAccentPreset(name)
    end
    self:ReapplyAll()
    -- Module windows (Accounting ledger, AH filter overlay, ...) read their
    -- palette on-demand via WindowPalette / GetChipPalette, but they don't
    -- automatically repaint when the global accent changes. Re-applying each
    -- module's settings triggers their RefreshWindow / RefreshOverlay path
    -- so a non-Gold preset propagates through without a /reload.
    if ns.ModuleRegistry and ns.ModuleRegistry.GetModuleIDs and ns.ModuleRegistry.ApplyModuleSettings then
        for _, moduleID in ipairs(ns.ModuleRegistry:GetModuleIDs()) do
            ns.ModuleRegistry:ApplyModuleSettings(moduleID)
        end
    end
end

function UI:SetTheme(theme)
    if ns.Settings and ns.Settings.SetTheme then
        ns.Settings:SetTheme(theme)
    end
    self:ReapplyAll()
    -- Same reason as SetAccentPreset: module-owned windows need a nudge to
    -- repaint when the global theme (Modern / Classic) flips.
    if ns.ModuleRegistry and ns.ModuleRegistry.GetModuleIDs and ns.ModuleRegistry.ApplyModuleSettings then
        for _, moduleID in ipairs(ns.ModuleRegistry:GetModuleIDs()) do
            ns.ModuleRegistry:ApplyModuleSettings(moduleID)
        end
    end
end

function UI:GetAccentPalette()
    local presetName = self:GetAccentPreset()
    local palette
    if presetName == "Custom" then
        -- Build a palette from the user's two color choices. Accent drives
        -- accent / accentSoft / accentEdge / header; Surface drives the dark
        -- background variants. We derive softer / darker variants by tinting
        -- the inputs so the whole palette stays internally consistent without
        -- making the user pick six separate colors.
        local accent = (ns.Settings and ns.Settings.GetCustomAccentColor and ns.Settings:GetCustomAccentColor())
            or { 0.95, 0.78, 0.30, 1 }
        local surface = (ns.Settings and ns.Settings.GetCustomSurfaceColor and ns.Settings:GetCustomSurfaceColor())
            or { 0.18, 0.13, 0.07, 0.95 }
        palette = {
            accent      = { accent[1], accent[2], accent[3], 1 },
            accentSoft  = { accent[1] * 0.75, accent[2] * 0.75, accent[3] * 0.75, 1 },
            accentEdge  = { accent[1] * 0.55, accent[2] * 0.55, accent[3] * 0.55, 0.90 },
            surface     = { surface[1], surface[2], surface[3], surface[4] or 0.95 },
            surfaceDark = { surface[1] * 0.78, surface[2] * 0.78, surface[3] * 0.78, 1 },
            header      = { math.min(1, accent[1] * 1.05), math.min(1, accent[2] * 1.05), math.min(1, accent[3] * 1.05), 1 },
        }
    else
        palette = ACCENT_PRESETS[presetName] or ACCENT_PRESETS.Gold
    end
    -- Global font override (General -> Global Settings -> Custom Font Colors).
    -- When enabled, the user's primary font tone replaces palette.header so
    -- every consumer that already paints text from .header (toggle labels,
    -- tab text, window titles, accounting column headers) follows the new
    -- color without per-site changes. headerSoft carries the secondary tone
    -- for consumers that want a dimmer body-text color (accounting dim text).
    if ns.Settings and ns.Settings.IsCustomFontEnabled and ns.Settings:IsCustomFontEnabled() then
        local primary = ns.Settings:GetCustomFontPrimary()
        local secondary = ns.Settings:GetCustomFontSecondary()
        -- Shallow-clone so a write to palette.header at a call site can't
        -- mutate the shared ACCENT_PRESETS table.
        palette = {
            accent      = palette.accent,
            accentSoft  = palette.accentSoft,
            accentEdge  = palette.accentEdge,
            surface     = palette.surface,
            surfaceDark = palette.surfaceDark,
            header      = { primary[1], primary[2], primary[3], primary[4] or 1 },
            headerSoft  = { secondary[1], secondary[2], secondary[3], secondary[4] or 1 },
        }
    end
    return palette
end

function UI:ApplyTheme(frame, opts)
    if type(frame) ~= "table" or type(frame.CreateTexture) ~= "function" then
        return
    end

    opts = opts or {}
    self._themedFrames[frame] = opts

    local theme = self:GetTheme()
    local palette = ResolvePalette(theme, opts)

    if frame.SetBackdrop then
        if theme == "Modern" then
            frame:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
                insets = { left = 1, right = 1, top = 1, bottom = 1 },
            })
        else
            frame:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                edgeSize = 16,
                insets = { left = 5, right = 5, top = 5, bottom = 5 },
            })
        end

        frame:SetBackdropColor(palette.bgR, palette.bgG, palette.bgB, palette.bgA)
        frame:SetBackdropBorderColor(palette.borderR, palette.borderG, palette.borderB, palette.borderA)
    else
        local fill = EnsureTexture(frame, "_thyraxThemeFill", "BACKGROUND")
        fill:SetTexture("Interface\\Buttons\\WHITE8x8")
        fill:SetVertexColor(palette.bgR, palette.bgG, palette.bgB, palette.bgA)

        local border = EnsureBorder(frame)
        SetBorderColor(border, palette.borderR, palette.borderG, palette.borderB, palette.borderA)
    end

    if opts and type(opts.alpha) == "number" then
        frame:SetAlpha(Clamp(opts.alpha, 0, 1))
    end
end

function UI:ReapplyAll()
    for frame, opts in pairs(self._themedFrames) do
        if frame and frame.IsObjectType and frame:IsObjectType("Frame") then
            self:ApplyTheme(frame, opts)
        end
    end
end
