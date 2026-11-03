-- DuSplit : in-game speedrun splits for the 1.12 client (Turtle WoW / Lua 5.0)
-- Split types: "combat" (enter combat with mob), "kill" (mob dies), "pos" (within radius of a point)

local ROWS = 10
local running, startT, cur, times = false, 0, 1, {}
local armed = true -- waiting for the first split to auto-start the run
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

-- Position: UnitPosition (SuperWoW / ClassicAPI) gives world yards. Only the first two returns
-- are used and only 2D distance is compared, so the x/y order of the mod does not matter.
-- Otherwise fall back to map coords * mapscale.
local function GetPos()
  if UnitPosition then
    local x, y = UnitPosition("player")
    if x and y then return x, y end
  end
  local x, y = GetPlayerMapPosition("player")
  if x and (x ~= 0 or y ~= 0) then
    return x * DuSplitDB.mapscale, y * DuSplitDB.mapscale
  end
end

-------------------------------------------------------------------- UI
local f = CreateFrame("Frame", "DuSplitFrame", UIParent)
f:SetWidth(280); f:SetHeight(30 + ROWS * 16 + 40)
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
  r.name:SetWidth(140); r.name:SetJustifyH("LEFT")
  r.delta = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.delta:SetPoint("TOPLEFT", f, "TOPLEFT", 152, -24 - (i - 1) * 16)
  r.delta:SetWidth(50); r.delta:SetJustifyH("RIGHT")
  r.time = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.time:SetPoint("TOPLEFT", f, "TOPLEFT", 205, -24 - (i - 1) * 16)
  r.time:SetWidth(65); r.time:SetJustifyH("RIGHT")
  rows[i] = r
end

local timer = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
timer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 20)
local sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
sub:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 8)

-- Names never wrap: they are cut with "..." so that prefix..name..suffix fits maxW pixels.
local measure = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
measure:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
measure:SetAlpha(0)
local function Fit(prefix, name, suffix, maxW)
  name = (string.gsub(name or "", "[\r\n]+", " "))
  name = (string.gsub(name, "|n", " "))
  measure:SetText(prefix .. name .. suffix)
  if measure:GetStringWidth() <= maxW then return prefix .. name .. suffix end
  local n = string.len(name)
  while n > 0 do
    n = n - 1
    measure:SetText(prefix .. string.sub(name, 1, n) .. "..." .. suffix)
    if measure:GetStringWidth() <= maxW then break end
  end
  return prefix .. string.sub(name, 1, n) .. "..." .. suffix
end

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
      r.name:SetText(Fit("", s.name, "", 138))
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
  local extra = ""
  local pend = DuSplitDB.pending
  if pend and pend.route == DuSplitDB.current then extra = "   |cffffff00new PB: " .. Fmt(pend.total) .. "|r" end
  if armed and not running and DuSplitDB.autostart ~= false and n >= 2 then extra = extra .. "   |cff00ff00armed|r" end
  sub:SetText("PB: " .. Fmt(rt.pbTotal) .. extra)
end

-------------------------------------------------------------------- Logic
-- A new PB is kept "pending" after a run so the finished splits can still be compared to the old PB.
-- It is committed on Reset, on a new run, or on the next loading screen (reload / leaving the raid).
local function CommitPending()
  local p = DuSplitDB.pending
  if not p then return end
  DuSplitDB.pending = nil
  local rt = DuSplitDB.routes[p.route]
  if rt and (not rt.pbTotal or p.total < rt.pbTotal) then
    rt.pbTotal = p.total
    rt.pb = p.times
    msg("Personal best saved: " .. Fmt(p.total))
  end
end

local function Finish()
  local rt = Route()
  running = false
  armed = false
  local total = times[table.getn(rt.splits)]
  msg("Run finished: " .. Fmt(total))
  if not rt.pbTotal or total < rt.pbTotal then
    local t = {}
    for i = 1, table.getn(times) do t[i] = times[i] end
    DuSplitDB.pending = { route = DuSplitDB.current, total = total, times = t }
    msg("New personal best! It is saved on Reset, or when you zone/reload - until then splits are compared to the old PB.")
  end
  Refresh()
end

local function DoSplit(why)
  local rt = Route()
  if not rt then return end
  if not running then
    -- auto-start: the first split of the route is the start trigger (recorded at 0:00.00)
    if why == "manual" or not armed or DuSplitDB.autostart == false or table.getn(rt.splits) < 2 then return end
    running = true; startT = GetTime(); cur = 1; times = {}; lastPrev = 0
    armed = false
    msg("Run started.")
  end
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
  CommitPending()
  running = true; startT = GetTime(); cur = 1; times = {}; lastPrev = 0
  armed = false
  msg("Run started.")
  Refresh()
end

local function Reset()
  CommitPending()
  running = false; cur = 1; times = {}; lastPrev = 0
  armed = true
  timer:SetText("0:00.00")
  Refresh()
end

-- The route layout changed (split added/removed/moved): no time can be trusted anymore.
-- Wipes PB, best segments, pending PB and the times of the run currently shown.
local function ClearTimes(rt)
  rt.pb = nil; rt.pbTotal = nil; rt.best = nil
  DuSplitDB.pending = nil
  if running then msg("Run reset because the route changed.") end
  Reset()
end

local function NameMatch(text, name)
  if not text or not name then return false end
  return string.find(string.lower(text), string.lower(name), 1, true) ~= nil
end

-- GUID of a unit token (SuperWoW: UnitExists returns the guid as 2nd value)
local function GuidOf(unit)
  local ok, guid = UnitExists(unit)
  if type(guid) == "string" then return guid end
end

local function GuidEq(a, b)
  return a and b and string.lower(a) == string.lower(b)
end

-- Does this unit token / guid match the split's mob? GUID wins when the split has one.
local function UnitMatches(unit, s)
  if s.guid then
    return GuidEq(GuidOf(unit), s.guid)
  end
  return NameMatch(UnitName(unit), s.target)
end

-------------------------------------------------------------------- Events
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_ENTERING_WORLD") -- loading screen: reload, entering/leaving an instance
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH")
f:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
f:RegisterEvent("CHAT_MSG_COMBAT_SELF_MISSES")
f:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS")
f:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES")
f:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
f:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE")
-- nampower events (ignored by the client if nampower is not installed)
f:RegisterEvent("UNIT_DIED")                 -- arg1 = guid of the dead unit
f:RegisterEvent("SPELL_DAMAGE_EVENT_SELF")   -- arg1 = targetGuid, arg2 = casterGuid
f:RegisterEvent("SPELL_DAMAGE_EVENT_OTHER")
f:RegisterEvent("AUTO_ATTACK_SELF")          -- arg1 = attackerGuid, arg2 = targetGuid
f:RegisterEvent("AUTO_ATTACK_OTHER")

local function CurSplit()
  local rt = Route()
  if not rt then return end
  if running then return rt.splits[cur] end
  -- not running: while armed, the first split is watched as the auto-start trigger
  if armed and DuSplitDB.autostart ~= false and table.getn(rt.splits) >= 2 then return rt.splits[1] end
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

  if event == "PLAYER_ENTERING_WORLD" then
    if not running then CommitPending(); Refresh() end
    return
  end

  local s = CurSplit()
  if not s then return end

  if event == "UNIT_DIED" then
    if s.type == "kill" and s.guid and GuidEq(arg1, s.guid) then DoSplit("kill") end
  elseif event == "SPELL_DAMAGE_EVENT_SELF" or event == "SPELL_DAMAGE_EVENT_OTHER"
      or event == "AUTO_ATTACK_SELF" or event == "AUTO_ATTACK_OTHER" then
    -- a damage event involving the mob while we are in combat = we are in combat with it
    if s.type == "combat" and s.guid and UnitAffectingCombat("player")
        and (GuidEq(arg1, s.guid) or GuidEq(arg2, s.guid)) then
      DoSplit("combat")
    end
  elseif event == "PLAYER_REGEN_DISABLED" then
    if s.type == "combat" then
      if UnitMatches("target", s) or UnitMatches("targettarget", s) then DoSplit("combat") end
    end
  elseif event == "CHAT_MSG_COMBAT_HOSTILE_DEATH" then
    -- fallback without nampower: name only
    if s.type == "kill" and not s.guid and NameMatch(arg1, s.target) then DoSplit("kill") end
    -- GUID split but nampower missing (no GetUnitGUID): UNIT_DIED will never fire, use the name
    if s.type == "kill" and s.guid and not GetUnitGUID and NameMatch(arg1, s.target) then DoSplit("kill") end
  elseif s.type == "combat" and not s.guid and UnitAffectingCombat("player") then
    -- combat chat lines naming the mob (name-only fallback)
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
  if s and s.type == "combat" and s.guid and UnitAffectingCombat("player") then
    -- SuperWoW: a guid works as a unit token while the mob is loaded
    if UnitExists(s.guid) and UnitAffectingCombat(s.guid) then DoSplit("combat") end
  end
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
  s.name = (string.gsub(s.name, "[\r\n]+", " "))
  table.insert(rt.splits, s)
  ClearTimes(rt) -- route changed, old times invalid
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
    local guid = GuidOf("target")
    if guid then msg("Using GUID " .. guid) else msg("No GUID available (SuperWoW?) - matching by name.") end
    AddSplit({ name = label, type = (cmd == "addcombat") and "combat" or "kill", target = tn, guid = guid })
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
      msg(i .. ". " .. s.name .. " [" .. s.type .. (s.target and (": " .. s.target) or "")
        .. (s.guid and (" " .. s.guid) or "") .. "]")
    end
  elseif cmd == "del" then
    local rt, n = Route(), tonumber(rest)
    if rt and n and rt.splits[n] then
      table.remove(rt.splits, n)
      ClearTimes(rt)
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
  elseif cmd == "config" then DuSplit_ToggleConfig()
  elseif cmd == "show" then f:Show()
  elseif cmd == "hide" then f:Hide()
  else
    msg("/ds new <route> | load <route> | routes | list | del <n>")
    msg("/ds addcombat [label] | addkill [label]   (uses your current target)")
    msg("/ds addpos <radius> [label]               (uses your current position)")
    msg("/ds start | reset | split | skip | undo | show | hide | config")
  end
end

-------------------------------------------------------------------- Config window
local cfg = CreateFrame("Frame", "DuSplitConfig", UIParent)
cfg:SetWidth(310); cfg:SetHeight(512)
cfg:SetPoint("CENTER", UIParent, "CENTER", -250, 0)
cfg:SetFrameStrata("DIALOG")
cfg:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12,
  insets = { left = 3, right = 3, top = 3, bottom = 3 } })
cfg:SetBackdropColor(0, 0, 0, 0.9)
cfg:SetMovable(true); cfg:EnableMouse(true); cfg:EnableMouseWheel(true)
cfg:RegisterForDrag("LeftButton")
cfg:SetScript("OnDragStart", function() this:StartMoving() end)
cfg:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
cfg:Hide()
tinsert(UISpecialFrames, "DuSplitConfig") -- ESC closes it

local btnN, editN = 0, 0
local function MakeText(text, x, y, w, font)
  local t = cfg:CreateFontString(nil, "OVERLAY", font or "GameFontNormalSmall")
  t:SetPoint("TOPLEFT", cfg, "TOPLEFT", x, y)
  if w then t:SetWidth(w) end
  t:SetJustifyH("LEFT")
  t:SetText(text)
  return t
end
local function MakeButton(text, w, x, y, fn)
  btnN = btnN + 1
  local b = CreateFrame("Button", "DuSplitBtn" .. btnN, cfg, "UIPanelButtonTemplate")
  b:SetWidth(w); b:SetHeight(22)
  b:SetPoint("TOPLEFT", cfg, "TOPLEFT", x, y)
  b:SetText(text)
  b:SetScript("OnClick", fn)
  return b
end
local function MakeEdit(w, x, y, text)
  editN = editN + 1
  local e = CreateFrame("EditBox", "DuSplitEdit" .. editN, cfg, "InputBoxTemplate")
  e:SetWidth(w); e:SetHeight(20)
  e:SetPoint("TOPLEFT", cfg, "TOPLEFT", x, y)
  e:SetAutoFocus(false)
  e:SetText(text or "")
  e:SetScript("OnEscapePressed", function() this:ClearFocus() end)
  e:SetScript("OnEnterPressed", function() this:ClearFocus() end)
  return e
end

local CFG_ROWS = 10
local listRows, listOffset = {}, 0
local routeBox, labelBox, radiusBox, curRoute, targetText
local selected, addHeader, saveBtn, cancelBtn -- split currently being edited

local function RefreshConfig()
  getglobal("DuSplitRouteDropText"):SetText(DuSplitDB.current or "(no route)")
  local rt = Route()
  local n = rt and table.getn(rt.splits) or 0
  if listOffset > n - CFG_ROWS then listOffset = n - CFG_ROWS end
  if listOffset < 0 then listOffset = 0 end
  for i = 1, CFG_ROWS do
    local row = listRows[i]
    local idx = listOffset + i
    local s = rt and rt.splits[idx]
    if s then
      local kind = (s.type == "pos") and "pos" or ((s.type == "combat") and "combat start" or "combat end")
      row.text:SetText(Fit(idx .. ". ", s.name, " |cff999999[" .. kind .. "]|r", 192))
      row.del.idx = idx; row.up.idx = idx; row.down.idx = idx
      row.idx = idx
      if selected == idx then row.hl:Show() else row.hl:Hide() end
      row:Show()
    else
      row.idx = nil
      row:Hide()
    end
  end
end

local function UpdateTarget()
  local tn = UnitName("target")
  if tn then
    targetText:SetText("Target: |cffffff00" .. tn .. "|r" .. (GuidOf("target") and "" or " |cffff6666(no GUID)|r"))
  else
    targetText:SetText("Target: |cff999999none|r")
  end
end

local function EnsureRoute()
  if not Route() then
    DuSplitDB.routes["Default"] = DuSplitDB.routes["Default"] or { splits = {} }
    DuSplitDB.current = "Default"
  end
end

local function StopEdit()
  selected = nil
  labelBox:SetText("")
  radiusBox:SetText("10")
  addHeader:SetText("Add a split")
  saveBtn:Hide(); cancelBtn:Hide()
end

local function StartEdit(idx)
  local rt = Route()
  local s = rt and rt.splits[idx]
  if not s then return end
  selected = idx
  labelBox:SetText(s.name)
  radiusBox:SetText(s.type == "pos" and tostring(s.radius) or "")
  addHeader:SetText("Editing split #" .. idx .. " |cff999999(" ..
    ((s.type == "pos") and "position" or ((s.type == "combat") and "combat start" or "combat end")) .. ")|r")
  saveBtn:Show(); cancelBtn:Show()
  RefreshConfig()
end

local function SaveEdit()
  local rt = Route()
  local s = rt and selected and rt.splits[selected]
  if not s then return end
  local name = labelBox:GetText()
  name = (string.gsub(name, "[\r\n]+", " "))
  if name ~= "" then s.name = name end -- a rename does not affect any time
  local changedTrigger = false
  if s.type == "pos" then
    local r = tonumber(radiusBox:GetText())
    if r and r > 0 and r ~= s.radius then s.radius = r; changedTrigger = true end
  end
  if changedTrigger then ClearTimes(rt) end -- the trigger moved: old times make no sense anymore
  Refresh(); StopEdit(); RefreshConfig()
  msg("Split updated.")
end

local function MoveSplit(idx, dir)
  local rt = Route()
  if not rt then return end
  if running then msg("Reset the run before reordering splits."); return end
  local j = idx + dir
  if not rt.splits[idx] or not rt.splits[j] then return end
  StopEdit()
  rt.splits[idx], rt.splits[j] = rt.splits[j], rt.splits[idx]
  ClearTimes(rt) -- order changed, old times invalid
  Refresh(); RefreshConfig()
end

MakeText("DuSplit - Config", 0, -12, 310, "GameFontNormal"):SetJustifyH("CENTER")
local closeBtn = CreateFrame("Button", "DuSplitConfigClose", cfg, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", cfg, "TOPRIGHT", -2, -2)

-- route
MakeText("Route", 14, -40)
routeBox = MakeEdit(96, 60, -36, "")
MakeButton("New / Load", 76, 160, -35, function()
  local name = routeBox:GetText()
  if name == "" then msg("Enter a route name."); return end
  if DuSplitDB.routes[name] then
    msg("Route loaded: " .. name)
  else
    DuSplitDB.routes[name] = { splits = {} }
    msg("Route created: " .. name)
  end
  DuSplitDB.current = name
  StopEdit()
  Reset(); RefreshConfig()
end)
-- delete the currently selected route (with confirmation)
local deleteTarget
StaticPopupDialogs["DUSPLIT_DELETE_ROUTE"] = {
  text = "Delete route '%s' with all its splits and times?",
  button1 = YES,
  button2 = NO,
  OnAccept = function()
    local name = deleteTarget
    if not name or not DuSplitDB.routes[name] then return end
    DuSplitDB.routes[name] = nil
    if DuSplitDB.pending and DuSplitDB.pending.route == name then DuSplitDB.pending = nil end
    if DuSplitDB.current == name then DuSplitDB.current = nil end
    StopEdit(); Reset(); RefreshConfig()
    msg("Route deleted: " .. name)
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
}
MakeButton("Delete", 54, 240, -35, function()
  local name = DuSplitDB.current
  if not name or not DuSplitDB.routes[name] then msg("No route selected."); return end
  if running then msg("Reset the run before deleting the route."); return end
  deleteTarget = name
  StaticPopup_Show("DUSPLIT_DELETE_ROUTE", name)
end)

local routeDrop = CreateFrame("Frame", "DuSplitRouteDrop", cfg, "UIDropDownMenuTemplate")
routeDrop:SetPoint("TOPLEFT", cfg, "TOPLEFT", -2, -58)
-- width helper: argument order differs between client builds, so try both
if not pcall(UIDropDownMenu_SetWidth, 230, routeDrop) then pcall(UIDropDownMenu_SetWidth, routeDrop, 230) end

local function RouteDropSelect()
  local name = this.value
  if not (name and DuSplitDB.routes[name]) then return end
  if running then msg("Reset the run before switching route."); RefreshConfig(); return end
  DuSplitDB.current = name
  StopEdit()
  Reset(); RefreshConfig()
end
local function RouteDropInit()
  if not DuSplitDB or not DuSplitDB.routes then return end
  local names = {}
  for k in pairs(DuSplitDB.routes) do table.insert(names, k) end
  table.sort(names)
  for i = 1, table.getn(names) do
    local info = {}
    info.text = names[i]
    info.value = names[i]
    info.func = RouteDropSelect
    info.checked = (names[i] == DuSplitDB.current)
    UIDropDownMenu_AddButton(info)
  end
end

-- add split
addHeader = MakeText("Add a split", 14, -86, 280, "GameFontNormal")
MakeText("Name", 14, -110)
labelBox = MakeEdit(150, 60, -106, "")
MakeText("(optional)", 218, -110)
MakeText("Radius (yd)", 14, -134)
radiusBox = MakeEdit(50, 90, -130, "10")

MakeButton("Add current position", 282, 14, -156, function()
  local x, y = GetPos()
  if not x then msg("Cannot read your position here."); return end
  EnsureRoute()
  local radius = tonumber(radiusBox:GetText()) or 10
  local label = labelBox:GetText()
  if label == "" then label = "Point " .. (table.getn(Route().splits) + 1) end
  AddSplit({ name = label, type = "pos", x = x, y = y, radius = radius, zone = GetRealZoneText() })
  StopEdit(); RefreshConfig()
end)

targetText = MakeText("", 14, -190, 282)
local function AddFromTarget(kind)
  local tn = UnitName("target")
  if not tn then msg("Target a mob first."); return end
  EnsureRoute()
  local guid = GuidOf("target")
  if not guid then msg("No GUID available (SuperWoW?) - matching by name.") end
  local label = labelBox:GetText()
  if label == "" then label = ((kind == "combat") and "Pull: " or "Kill: ") .. tn end
  AddSplit({ name = label, type = kind, target = tn, guid = guid })
  StopEdit(); RefreshConfig()
end
MakeButton("Target: Combat Start", 138, 14, -208, function() AddFromTarget("combat") end)
MakeButton("Target: Combat End", 138, 158, -208, function() AddFromTarget("kill") end)
saveBtn = MakeButton("Save changes", 138, 14, -234, SaveEdit)
cancelBtn = MakeButton("Stop editing", 138, 158, -234, function() StopEdit(); RefreshConfig() end)
saveBtn:Hide(); cancelBtn:Hide()

-- split list
MakeText("Splits (click to edit, wheel to scroll)", 14, -262, 280, "GameFontNormal")
for i = 1, CFG_ROWS do
  local row = CreateFrame("Frame", nil, cfg)
  row:SetWidth(282); row:SetHeight(16)
  row:SetPoint("TOPLEFT", cfg, "TOPLEFT", 14, -280 - (i - 1) * 17)
  row:EnableMouse(true)
  row:SetScript("OnMouseUp", function() if this.idx then StartEdit(this.idx) end end)
  row.hl = row:CreateTexture(nil, "BACKGROUND")
  row.hl:SetAllPoints(row)
  row.hl:SetTexture(1, 1, 0, 0.18)
  row.hl:Hide()
  row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.text:SetPoint("LEFT", row, "LEFT", 0, 0)
  row.text:SetWidth(196); row.text:SetHeight(12); row.text:SetJustifyH("LEFT")
  btnN = btnN + 1
  row.del = CreateFrame("Button", "DuSplitBtn" .. btnN, row, "UIPanelButtonTemplate")
  row.del:SetWidth(22); row.del:SetHeight(16)
  row.del:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  row.del:SetText("X")
  row.del:SetScript("OnClick", function()
    local rt = Route()
    if running then msg("Reset the run before deleting splits."); return end
    if rt and rt.splits[this.idx] then
      StopEdit()
      table.remove(rt.splits, this.idx)
      ClearTimes(rt)
      Refresh(); RefreshConfig()
      msg("Split removed (PB cleared).")
    end
  end)
  btnN = btnN + 1
  row.down = CreateFrame("Button", "DuSplitBtn" .. btnN, row, "UIPanelButtonTemplate")
  row.down:SetWidth(20); row.down:SetHeight(16)
  row.down:SetPoint("RIGHT", row.del, "LEFT", -2, 0)
  row.down:SetText("v")
  row.down:SetScript("OnClick", function() MoveSplit(this.idx, 1) end)
  btnN = btnN + 1
  row.up = CreateFrame("Button", "DuSplitBtn" .. btnN, row, "UIPanelButtonTemplate")
  row.up:SetWidth(20); row.up:SetHeight(16)
  row.up:SetPoint("RIGHT", row.down, "LEFT", -2, 0)
  row.up:SetText("^")
  row.up:SetScript("OnClick", function() MoveSplit(this.idx, -1) end)
  listRows[i] = row
end

local autoCheck = CreateFrame("CheckButton", "DuSplitAutoStart", cfg, "UICheckButtonTemplate")
autoCheck:SetPoint("TOPLEFT", cfg, "TOPLEFT", 10, -452)
getglobal("DuSplitAutoStartText"):SetText("Auto-start when the first split triggers")
autoCheck:SetScript("OnClick", function()
  DuSplitDB.autostart = (this:GetChecked() and true or false)
  Refresh()
end)

MakeButton("Start", 90, 14, -482, function() Start() end)
MakeButton("Reset", 90, 110, -482, function() Reset() end)
MakeButton("Close", 90, 206, -482, function() cfg:Hide() end)

cfg:SetScript("OnMouseWheel", function()
  if arg1 > 0 then listOffset = listOffset - 1 else listOffset = listOffset + 1 end
  RefreshConfig()
end)
cfg:RegisterEvent("PLAYER_TARGET_CHANGED")
cfg:SetScript("OnEvent", function() if this:IsShown() then UpdateTarget() end end)
cfg:SetScript("OnShow", function()
  UIDropDownMenu_Initialize(routeDrop, RouteDropInit)
  UpdateTarget(); RefreshConfig()
  autoCheck:SetChecked(DuSplitDB.autostart ~= false)
end)

function DuSplit_ToggleConfig()
  if cfg:IsShown() then cfg:Hide() else cfg:Show() end
end

-------------------------------------------------------------------- Minimap button
local mb = CreateFrame("Button", "DuSplitMinimapButton", Minimap)
mb:SetWidth(31); mb:SetHeight(31)
mb:SetFrameStrata("MEDIUM"); mb:SetFrameLevel(8)
mb:RegisterForClicks("LeftButtonUp", "RightButtonUp")
mb:RegisterForDrag("LeftButton")
mb:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
local mbIcon = mb:CreateTexture(nil, "BACKGROUND")
mbIcon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")
mbIcon:SetWidth(20); mbIcon:SetHeight(20)
mbIcon:SetPoint("TOPLEFT", mb, "TOPLEFT", 7, -5)
local mbBorder = mb:CreateTexture(nil, "OVERLAY")
mbBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
mbBorder:SetWidth(53); mbBorder:SetHeight(53)
mbBorder:SetPoint("TOPLEFT", mb, "TOPLEFT", 0, 0)

local function PlaceMinimapButton()
  local a = (DuSplitDB and DuSplitDB.minimapAngle) or 220
  local r = math.rad(a)
  mb:ClearAllPoints()
  mb:SetPoint("CENTER", Minimap, "CENTER", math.cos(r) * 80, math.sin(r) * 80)
end
PlaceMinimapButton()

mb:SetScript("OnDragStart", function() this.dragging = true end)
mb:SetScript("OnDragStop", function() this.dragging = false end)
mb:SetScript("OnUpdate", function()
  if not this.dragging or not DuSplitDB then return end
  local mx, my = GetCursorPosition()
  local s = Minimap:GetEffectiveScale()
  local cx, cy = Minimap:GetCenter()
  DuSplitDB.minimapAngle = math.deg(math.atan2(my / s - cy, mx / s - cx))
  PlaceMinimapButton()
end)
mb:SetScript("OnClick", function()
  if arg1 == "RightButton" then
    DuSplit_ToggleConfig()
  elseif f:IsShown() then
    f:Hide()
  else
    f:Show()
  end
end)
mb:SetScript("OnEnter", function()
  GameTooltip:SetOwner(this, "ANCHOR_LEFT")
  GameTooltip:SetText("DuSplit")
  GameTooltip:AddLine("Left click: show/hide splits", 1, 1, 1)
  GameTooltip:AddLine("Right click: config", 1, 1, 1)
  GameTooltip:AddLine("Drag: move button", 0.6, 0.6, 0.6)
  GameTooltip:Show()
end)
mb:SetScript("OnLeave", function() GameTooltip:Hide() end)

local mbInit = CreateFrame("Frame")
mbInit:RegisterEvent("ADDON_LOADED")
mbInit:SetScript("OnEvent", function() if arg1 == "DuSplit" then PlaceMinimapButton() end end)
