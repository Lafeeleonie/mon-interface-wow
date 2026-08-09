local _, ns = ...

-- ns.Format: shared number / string formatting. Several modules had local
-- FormatNumber / FormatPercent / StripColorCodes copies; this is the
-- canonical implementation. Local copies remain in place to avoid regression
-- risk while modules migrate one-by-one.

ns.Format = ns.Format or {}
local Format = ns.Format

-- Rounds to integer or fixed decimals. Returns "-" for nil / non-numeric
-- inputs so callers can render the result directly without nil checks.
function Format.Number(value, decimals)
    value = tonumber(value)
    if not value then return "-" end
    if decimals and decimals > 0 then
        return string.format("%." .. tostring(decimals) .. "f", value)
    end
    return tostring(math.floor(value + 0.5))
end

-- "12.3%" style. Always one decimal place to keep the column right-aligned
-- consistently across stat panels.
function Format.Percent(value)
    value = tonumber(value)
    if not value then return "-" end
    return string.format("%.1f%%", value)
end

-- Strips WoW colour-escape sequences ("|cffRRGGBB...|r"). Useful when the
-- caller needs the raw text (e.g. tooltip line matching) without colour tags.
function Format.StripCodes(text)
    text = tostring(text or "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    return text
end

-- Compact "1.2k" / "3.4M" style for chart axis labels etc. Returns the
-- formatted string and the suffix used so callers can position the unit if
-- they prefer.
function Format.Short(value)
    value = tonumber(value)
    if not value then return "-" end
    local absV = math.abs(value)
    if absV >= 1e9 then
        return string.format("%.1fB", value / 1e9)
    elseif absV >= 1e6 then
        return string.format("%.1fM", value / 1e6)
    elseif absV >= 1e3 then
        return string.format("%.1fk", value / 1e3)
    end
    return string.format("%d", math.floor(value + 0.5))
end
