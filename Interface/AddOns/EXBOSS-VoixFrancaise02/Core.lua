---@diagnostic disable: undefined-global
local ADDON_NAME, NS = ...
local function Trim(t) return tostring(t or ""):gsub("^%s+",""):gsub("%s+$","") end
NS = type(NS)=="table" and NS or {}
local info = type(NS.AuthorInfo)=="table" and NS.AuthorInfo or {}
NS.Plugin = NS.Plugin or {}
local P = NS.Plugin
P.pluginKey  = Trim(info.pluginKey);  if P.pluginKey==""  then P.pluginKey=Trim(ADDON_NAME) end
P.authorKey  = Trim(info.authorKey);  if P.authorKey==""  then P.authorKey="TEMPLATE" end
P.authorName = Trim(info.authorName); if P.authorName=="" then P.authorName=P.authorKey end
