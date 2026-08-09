local _, ns = ...

-- ns.Color: shared color-handling helpers. Several modules each had their own
-- local NormalizeColor / MixColor / Clamp / ToHex variations (5+ duplicates).
-- This module is the canonical version; existing local copies stay for now
-- so the migration can be done file-by-file without regression risk.

ns.Color = ns.Color or {}
local Color = ns.Color

local unpack = unpack or table.unpack

function Color.Clamp(value, lo, hi)
    lo = lo or 0
    hi = hi or 1
    if value < lo then return lo end
    if value > hi then return hi end
    return value
end

-- Normalises a color value into a sanitised {r, g, b, a} table. Accepts:
--   * already-valid {r, g, b[, a]} tables -> returned with components clamped
--   * nil / malformed input -> returns the fallback (or {1,1,1,1})
function Color.Normalize(color, fallback)
    fallback = fallback or { 1, 1, 1, 1 }
    if type(color) ~= "table" then
        return { fallback[1], fallback[2], fallback[3], fallback[4] or 1 }
    end
    local r = tonumber(color[1])
    local g = tonumber(color[2])
    local b = tonumber(color[3])
    local a = tonumber(color[4])
    if not r or not g or not b then
        return { fallback[1], fallback[2], fallback[3], fallback[4] or 1 }
    end
    return {
        Color.Clamp(r, 0, 1),
        Color.Clamp(g, 0, 1),
        Color.Clamp(b, 0, 1),
        Color.Clamp(a or fallback[4] or 1, 0, 1),
    }
end

-- Linear blend of two colors. weight goes from 0 (= a) to 1 (= b).
-- Optional `alpha` override replaces the blended alpha component.
function Color.Mix(a, b, weight, alpha)
    weight = weight or 0.5
    local invW = 1 - weight
    local rr = (a[1] or 0) * invW + (b[1] or 0) * weight
    local gg = (a[2] or 0) * invW + (b[2] or 0) * weight
    local bb = (a[3] or 0) * invW + (b[3] or 0) * weight
    local aa = alpha or ((a[4] or 1) * invW + (b[4] or 1) * weight)
    return { rr, gg, bb, aa }
end

-- Returns the 4 RGBA components of a color table as a multi-return value.
-- Convenient for direct SetColorTexture / SetVertexColor / etc. call sites:
--   tex:SetColorTexture(ns.Color.RGBA(myColor))
function Color.RGBA(color)
    if type(color) ~= "table" then
        return 1, 1, 1, 1
    end
    return color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1
end

-- Multi-return convenience: sanitised r, g, b, a components in one call, for
-- call sites that want `local r, g, b, a = ...` (the shape several per-module
-- NormalizeColor locals used). Equivalent to Color.RGBA(Color.Normalize(...)).
function Color.NormalizeRGBA(color, fallback)
    local c = Color.Normalize(color, fallback)
    return c[1], c[2], c[3], c[4]
end

-- WoW color escape sequence ("|cffRRGGBB") for use inside FontString text:
--   text:SetText(ns.Color.ToHex(myColor) .. "value|r")
function Color.ToHex(color)
    if type(color) ~= "table" then
        return "|cffffffff"
    end
    return string.format("|cff%02x%02x%02x",
        math.floor((color[1] or 1) * 255 + 0.5),
        math.floor((color[2] or 1) * 255 + 0.5),
        math.floor((color[3] or 1) * 255 + 0.5))
end

-- Copies a color table; returns a fresh {r,g,b,a} so caller mutations do not
-- affect the original (avoids subtle bugs when shared palette entries are
-- accidentally mutated in place).
function Color.Copy(color)
    if type(color) ~= "table" then
        return { 1, 1, 1, 1 }
    end
    return { color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1 }
end
