-- DuSplit : in-game speedrun splits for the 1.12 client (Turtle WoW / Lua 5.0)
-- Split types: "combat" (enter combat with mob), "kill" (mob dies), "pos" (within radius of a point)

local ROWS = 10
local running, startT, cur, times = false, 0, 1, {}
local lastPrev = 0
local inCombatChat = false

local function msg(t) DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffDuSplit:|r " .. t) end

local function Fmt(t, sign)
  if not t then return "--" end
  local s = ""
  if t < 0 then s = "-"; t = -t elseif sign then s = "+" end
  local m = math.floor(t / 60)
  return s .. string.format("%d:%05.2f", m, t - m * 60)
end

local function Route()
  return DuSplitDB.routes[DuSplitDB.current]
end

-- Position: UnitPosition exists with SuperWoW (yards). Otherwise fall back to map coords * mapscale.
local function GetPos()
  if UnitPosition then
    local x, y = UnitPosition("player")
    if x then return x, y end
  end
  local x, y = GetPlayerMapPosition("player")
  if x and (x ~= 0 or y ~= 0) then
    return x * DuSplitDB.mapscale, y * DuSplitDB.mapscale
  end
end

-------------------------------------------------------------------- UI
local f = CreateFrame("Frame", "DuSplitFrame", UIParent)
f:SetWidth(240); f:SetHeight(30 + ROWS * 16 + 40)
f:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12,
  insets = { left = 3, right = 3, top = 3, bottom = 3 } })
f:SetBackdropColor(0, 0, 0, 0.7)
f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", function() this:StartMoving() end)
f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)

local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -8)

local rows = {}
for i = 1, ROWS do
  local r = {}
  r.name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.name:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -24 - (i - 1) * 16)
  r.name:SetWidth(100); r.name:SetJustifyH("LEFT")
  r.delta = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.delta:SetPoint("TOPLEFT", f, "TOPLEFT", 112, -24 - (i - 1) * 16)
  r.delta:SetWidth(50); r.delta:SetJustifyH("RIGHT")
  r.time = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.time:SetPoint("TOPLEFT", f, "TOPLEFT", 165, -24 - (i - 1) * 16)
  r.time:SetWidth(65); r.time:SetJustifyH("RIGHT")
  rows[i] = r
end

local timer = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
timer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 20)
local sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
sub:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 8)

local function Refresh()
  local rt = Route()
  if not rt then
    title:SetText("DuSplit - no route (/ds new <name>)")
    for i = 1, ROWS do rows[i].name:SetText(""); rows[i].delta:SetText(""); rows[i].time:SetText("") end
    return
  end
  title:SetText(DuSplitDB.current)
  local n = table.getn(rt.splits)
  local first = cur - 3
  if first > n - ROWS + 1 then first = n - ROWS + 1 end
  if first < 1 then first = 1 end
  for i = 1, ROWS do
    local idx = first + i - 1
    local r = rows[i]
    local s = rt.splits[idx]
    if s then
      r.name:SetText(s.name)
      if idx < cur and times[idx] then
        r.time:SetText(Fmt(times[idx]))
        if rt.pb and rt.pb[idx] then
          local d = times[idx] - rt.pb[idx]
          r.delta:SetText(Fmt(d, true))
          if d <= 0 then r.delta:SetTextColor(0, 1, 0) else r.delta:SetTextColor(1, 0.3, 0.3) end
        else
          r.delta:SetText("")
        end
      else
        r.delta:SetText("")
        r.time:SetText(Fmt(rt.pb and rt.pb[idx]))
      end
      if idx == cur and running then r.name:SetTextColor(1, 1, 0) else r.name:SetTextColor(1, 1, 1) end
    else
      r.name:SetText(""); r.delta:SetText(""); r.time:SetText("")
    end
  end
  sub:SetText("PB: " .. Fmt(rt.pbTotal))
end

-------------------------------------------------------------------- Logic
local function Finish()
  local rt = Route()
  running = false
  local total = times[table.getn(rt.splits)]
  msg("Run finished: " .. Fmt(total))
  if not rt.pbTotal or total < rt.pbTotal then
    rt.pbTotal = total
    rt.pb = {}
    for i = 1, table.getn(times) do rt.pb[i] = times[i] end
    msg("New personal best!")
  end
  Refresh()
end

local function DoSplit(why)
  local rt = Route()
  if not running or not rt then return end
  local s = rt.splits[cur]
  if not s then return end
  local t = GetTime() - startT
  times[cur] = t
  local seg = t - lastPrev
  lastPrev = t
  rt.best = rt.best or {}
  if not rt.best[cur] or seg < rt.best[cur] then rt.best[cur] = seg end
  local d = ""
  if rt.pb and rt.pb[cur] then d = " (" .. Fmt(t - rt.pb[cur], true) .. ")" end
  msg(s.name .. " - " .. Fmt(t) .. d)
  if cur >= table.getn(rt.splits) then
    Finish()
  else
    cur = cur + 1
    Refresh()
  end
end

local function Start()
  local rt = Route()
  if not rt or table.getn(rt.splits) == 0 then msg("No route or empty route."); return end
  running = true; startT = GetTime(); cur = 1; times = {}; lastPrev = 0
  msg("Run started.")
  Refresh()
end

local function Reset()
  running = false; cur = 1; times = {}; lastPrev = 0
  timer:SetText("0:00.00")
  Refresh()
end

local function NameMatch(text, name)
  if not text or not name then return false end
  return string.find(string.lower(text), string.lower(name), 1, true) ~= nil
end

-------------------------------------------------------------------- Events
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH")
f:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
f:RegisterEvent("CHAT_MSG_COMBAT_SELF_MISSES")
f:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS")
f:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES")
f:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
f:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE")

local function CurSplit()
  local rt = Route()
  if running and rt then return rt.splits[cur] end
end

f:SetScript("OnEvent", function()
  if event == "ADDON_LOADED" then
    if arg1 ~= "DuSplit" then return end
    DuSplitDB = DuSplitDB or {}
    DuSplitDB.routes = DuSplitDB.routes or {}
    DuSplitDB.mapscale = DuSplitDB.mapscale or 3000
    Refresh()
    return
  end

  local s = CurSplit()
  if not s then return end

  if event == "PLAYER_REGEN_DISABLED" then
    if s.type == "combat" then
      -- check target / target of target
      if NameMatch(UnitName("target"), s.target) or NameMatch(UnitName("targettarget"), s.target) then
        DoSplit("combat")
      end
    end
  elseif event == "CHAT_MSG_COMBAT_HOSTILE_DEATH" then
    if s.type == "kill" and NameMatch(arg1, s.target) then DoSplit("kill") end
  elseif s.type == "combat" and UnitAffectingCombat("player") then
    -- combat chat lines naming the mob (covers pulls where the target was not selected)
    if NameMatch(arg1, s.target) then DoSplit("combat") end
  end
end)

local acc = 0
f:SetScript("OnUpdate", function()
  if running then timer:SetText(Fmt(GetTime() - startT)) end
  acc = acc + arg1
  if acc < 0.1 then return end
  acc = 0
  local s = CurSplit()
  if s and s.type == "pos" then
    local x, y = GetPos()
    if x and (not s.zone or s.zone == GetRealZoneText()) then
      local dx, dy = x - s.x, y - s.y
      if math.sqrt(dx * dx + dy * dy) <= s.radius then DoSplit("pos") end
    end
  end
end)

-------------------------------------------------------------------- Commands
local function AddSplit(s)
  local rt = Route()
  if not rt then msg("Create a route first: /ds new <name>"); return end
  table.insert(rt.splits, s)
  rt.pb = nil; rt.pbTotal = nil; rt.best = nil -- route changed, old times invalid
  msg("Added split #" .. table.getn(rt.splits) .. ": " .. s.name)
  Refresh()
end

SLASH_DUSPLIT1 = "/ds"
SLASH_DUSPLIT2 = "/dusplit"
SlashCmdList["DUSPLIT"] = function(input)
  local _, _, cmd, rest = string.find(input or "", "^(%S*)%s*(.*)$")
  cmd = string.lower(cmd or "")

  if cmd == "new" and rest ~= "" then
    DuSplitDB.routes[rest] = { splits = {} }
    DuSplitDB.current = rest
    Reset(); msg("Route created: " .. rest)
  elseif cmd == "load" then
    if DuSplitDB.routes[rest] then DuSplitDB.current = rest; Reset() else msg("Unknown route.") end
  elseif cmd == "routes" then
    for k in pairs(DuSplitDB.routes) do msg(k) end
  elseif cmd == "addcombat" or cmd == "addkill" then
    local tn = UnitName("target")
    if not tn then msg("Target the mob first."); return end
    local label = rest ~= "" and rest or tn
    AddSplit({ name = label, type = (cmd == "addcombat") and "combat" or "kill", target = tn })
  elseif cmd == "addpos" then
    local _, _, radius, label = string.find(rest, "^(%d+)%s*(.*)$")
    radius = tonumber(radius) or 10
    local x, y = GetPos()
    if not x then msg("Cannot read your position here."); return end
    if label == "" then label = "Point " .. (table.getn(Route().splits) + 1) end
    AddSplit({ name = label, type = "pos", x = x, y = y, radius = radius, zone = GetRealZoneText() })
  elseif cmd == "list" then
    local rt = Route()
    if not rt then return end
    for i = 1, table.getn(rt.splits) do
      local s = rt.splits[i]
      msg(i .. ". " .. s.name .. " [" .. s.type .. (s.target and (": " .. s.target) or "") .. "]")
    end
  elseif cmd == "del" then
    local rt, n = Route(), tonumber(rest)
    if rt and n and rt.splits[n] then
      table.remove(rt.splits, n)
      rt.pb = nil; rt.pbTotal = nil; rt.best = nil
      Refresh(); msg("Split removed (PB cleared).")
    end
  elseif cmd == "start" then Start()
  elseif cmd == "reset" then Reset()
  elseif cmd == "split" then DoSplit("manual")
  elseif cmd == "skip" then
    local rt = Route()
    if running and rt and cur < table.getn(rt.splits) then cur = cur + 1; Refresh() end
  elseif cmd == "undo" then
    if running and cur > 1 then cur = cur - 1; times[cur] = nil; lastPrev = times[cur - 1] or 0; Refresh() end
  elseif cmd == "mapscale" and tonumber(rest) then
    DuSplitDB.mapscale = tonumber(rest); msg("Map scale set (fallback mode only).")
  elseif cmd == "show" then f:Show()
  elseif cmd == "hide" then f:Hide()
  else
    msg("/ds new <route> | load <route> | routes | list | del <n>")
    msg("/ds addcombat [label] | addkill [label]   (uses your current target)")
    msg("/ds addpos <radius> [label]               (uses your current position)")
    msg("/ds start | reset | split | skip | undo | show | hide")
  end
end
