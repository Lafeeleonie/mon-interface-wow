local _, Addon = ...

local DATA = Addon.Data.PVE_DARKMOON
local Detector = {
    cacheValue = nil,
    cacheExpiresAt = 0,
    knownStartAt = 0,
    knownEndAt = 0,
    calendarRequestedAt = 0,
}
Addon.DarkmoonDetector = Detector

local function now()
    return type(time) == "function" and time() or 0
end

local function copyCalendarTime(value)
    if type(value) ~= "table" then
        return nil
    end
    return {
        year = tonumber(value.year),
        month = tonumber(value.month),
        day = tonumber(value.monthDay or value.day),
        hour = tonumber(value.hour) or 0,
        min = tonumber(value.minute or value.min) or 0,
        sec = tonumber(value.second or value.sec) or 0,
    }
end

local function toEpoch(value)
    local copy = copyCalendarTime(value)
    if not copy or not copy.year or not copy.month or not copy.day or type(time) ~= "function" then
        return nil
    end
    local ok, epoch = pcall(time, copy)
    return ok and tonumber(epoch) or nil
end

local function fallbackResetKey()
    if C_DateAndTime and type(C_DateAndTime.GetCurrentCalendarTime) == "function" then
        local ok, value = pcall(C_DateAndTime.GetCurrentCalendarTime)
        if ok and type(value) == "table" and value.year and value.month then
            return string.format("darkmoon:%d:%02d", value.year, value.month)
        end
    end
    if type(date) == "function" then
        return "darkmoon:" .. date("%Y:%m")
    end
    return "darkmoon:unknown"
end

function Detector:GetResetKey()
    if self.knownStartAt > 0 and self.knownEndAt > 0 then
        return string.format("darkmoon:%d:%d", self.knownStartAt, self.knownEndAt)
    end
    return fallbackResetKey()
end

function Detector:RequestCalendar()
    if not C_Calendar or type(C_Calendar.OpenCalendar) ~= "function" then
        return false
    end
    local current = now()
    if self.calendarRequestedAt > 0 and current - self.calendarRequestedAt < 30 then
        return false
    end
    self.calendarRequestedAt = current
    return pcall(C_Calendar.OpenCalendar)
end

function Detector:ClearCache()
    self.cacheValue = nil
    self.cacheExpiresAt = 0
end

function Detector:IsPlayerOnIsland()
    if not C_Map or type(C_Map.GetBestMapForUnit) ~= "function" then
        return false
    end
    local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    return ok and DATA.mapIDs[tonumber(mapID)] == true or false
end

function Detector:ScanCalendar()
    if not C_Calendar
        or not C_DateAndTime
        or type(C_DateAndTime.GetCurrentCalendarTime) ~= "function"
        or type(C_Calendar.SetAbsMonth) ~= "function"
        or type(C_Calendar.GetNumDayEvents) ~= "function"
        or type(C_Calendar.GetHolidayInfo) ~= "function"
    then
        return false, nil, nil, "calendar-unavailable"
    end

    local ok, calendarNow = pcall(C_DateAndTime.GetCurrentCalendarTime)
    local currentEpoch = ok and toEpoch(calendarNow) or nil
    if not currentEpoch then
        return false, nil, nil, "calendar-unavailable"
    end

    if self.knownStartAt > 0 and self.knownEndAt > 0 then
        if currentEpoch >= self.knownStartAt and currentEpoch <= self.knownEndAt then
            return true, self.knownStartAt, self.knownEndAt, "known-window"
        end
        self.knownStartAt = 0
        self.knownEndAt = 0
    end

    local openMonth, openYear
    if CalendarFrame and type(CalendarFrame.IsShown) == "function" and CalendarFrame:IsShown()
        and type(C_Calendar.GetMonthInfo) == "function"
    then
        local monthOk, monthInfo = pcall(C_Calendar.GetMonthInfo)
        if monthOk and type(monthInfo) == "table" then
            openMonth, openYear = monthInfo.month, monthInfo.year
        end
    end

    pcall(C_Calendar.SetAbsMonth, calendarNow.month, calendarNow.year)
    local countOk, count = pcall(C_Calendar.GetNumDayEvents, 0, calendarNow.monthDay or calendarNow.day)
    count = countOk and math.max(0, tonumber(count) or 0) or 0
    local active, startAt, endAt = false, nil, nil
    for index = 1, count do
        local holidayOk, holiday = pcall(
            C_Calendar.GetHolidayInfo,
            0,
            calendarNow.monthDay or calendarNow.day,
            index
        )
        local texture = holidayOk and type(holiday) == "table" and tonumber(holiday.texture) or nil
        if texture and DATA.calendarTextures[texture] then
            startAt = toEpoch(holiday.startTime)
            endAt = toEpoch(holiday.endTime)
            if startAt and endAt then
                self.knownStartAt = startAt
                self.knownEndAt = endAt
                active = currentEpoch >= startAt and currentEpoch <= endAt
            else
                active = true
            end
            break
        end
    end

    if openMonth and openYear then
        pcall(C_Calendar.SetAbsMonth, openMonth, openYear)
    end
    return active, startAt, endAt, active and "calendar" or "calendar-inactive"
end

function Detector:GetState()
    local current = now()
    if self:IsPlayerOnIsland() then
        return {
            active = true,
            source = "darkmoon-island",
            startAt = self.knownStartAt > 0 and self.knownStartAt or nil,
            endAt = self.knownEndAt > 0 and self.knownEndAt or nil,
            resetKey = self:GetResetKey(),
        }
    end
    if self.cacheValue ~= nil and current < self.cacheExpiresAt then
        return {
            active = self.cacheValue == true,
            source = "cache",
            startAt = self.knownStartAt > 0 and self.knownStartAt or nil,
            endAt = self.knownEndAt > 0 and self.knownEndAt or nil,
            resetKey = self:GetResetKey(),
        }
    end

    self:RequestCalendar()
    local active, startAt, endAt, source = self:ScanCalendar()
    self.cacheValue = active == true
    self.cacheExpiresAt = self.cacheValue and endAt and endAt > current
        and math.min(endAt, current + 3600)
        or current + 300
    return {
        active = self.cacheValue,
        source = source,
        startAt = startAt or (self.knownStartAt > 0 and self.knownStartAt or nil),
        endAt = endAt or (self.knownEndAt > 0 and self.knownEndAt or nil),
        resetKey = self:GetResetKey(),
    }
end
