local ADDON_NAME, ns = ...
local L = ns.L

-- Init, AceDB, Events, Slash-Befehle. Aufbau aus VoidAlert.

local issecret = issecretvalue or function() return false end

ns.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")) or "?"

-- Standardwerte laut SPEC 5. Der Sound-Standard hängt von Client-Sprache und vorhandenen
-- Sprachansagen ab (Sounds.lua, SPEC 4).
ns.defaults = {
  profile = {
    cast = { enabled = true, sound = ns.Sounds.DEFAULTS.cast },
    success = { enabled = true, sound = ns.Sounds.DEFAULTS.success, others = false },
    units = { target = true, focus = true, nameplate = false },
    channel = "Master",
    minGap = 0.5,          -- s, Mindestabstand zwischen zwei Zauberbeginn-Sounds (SPEC 3.1)
    combatOnly = false,
    instanceOnly = false,
    chatMessages = false,  -- Ladehinweis und Testmeldung im Chat (Antworten und Fehlerhinweise immer)
  },
  global = {
    debug = false,
  },
}

local function Print(msg)
  print("|cffff8000KickAlert|r: " .. msg)
end
ns.Print = Print

ns.inCombat = false

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
local handlers = {}

function handlers.ADDON_LOADED(name)
  if name ~= ADDON_NAME then return end
  events:UnregisterEvent("ADDON_LOADED")

  -- Ein gemeinsames Profil "Default" für den ganzen Account (SPEC 5). AceDB-3.0 setzt bei
  -- defaultProfile == true den Namen "Default" (AceDB-3.0.lua, initdb).
  ns.db = LibStub("AceDB-3.0"):New("KickAlertDB", ns.defaults, true)
  -- Slider-Wert absichern (0,2 bis 2,0 s, eine Nachkommastelle)
  ns.db.profile.minGap = ns.Options.RoundGap(ns.db.profile.minGap)
  ns.Debug:Init()
  ns.Options:Init()
end

function handlers.PLAYER_LOGIN()
  local okC, combat = pcall(InCombatLockdown)
  ns.inCombat = okC and not issecret(combat) and combat == true
  ns.loggedIn = true
  ns.Kicks:Update("login")
  ns.Debug:LogMeta()
  if ns.db.profile.chatMessages then Print(L["LOADED"]:format(ns.VERSION)) end
end

function handlers.PLAYER_SPECIALIZATION_CHANGED(unit)
  if not ns.loggedIn then return end
  if issecret(unit) or (unit ~= nil and unit ~= "player") then return end
  ns.Kicks:Update("specChanged")
end

function handlers.SPELLS_CHANGED()
  if not ns.loggedIn then return end
  ns.Kicks:Update("spellsChanged")
end

function handlers.PLAYER_REGEN_DISABLED()
  ns.inCombat = true
  ns.Debug:Add("combatStart")
end

function handlers.PLAYER_REGEN_ENABLED()
  ns.inCombat = false
  ns.Debug:Add("combatEnd")
end

-- Zauberbeginn (SPEC 3.1). Payload: unitTarget, castGUID, spellID (UnitDocumentation.lua);
-- castGUID und spellID sind geheim (SPEC 2) und werden nicht angefasst.
local function onCastStart(event, unit)
  if not ns.loggedIn then return end
  ns.Alerts:OnCastStart(event, unit)
end
handlers.UNIT_SPELLCAST_START = onCastStart
handlers.UNIT_SPELLCAST_CHANNEL_START = onCastStart
handlers.UNIT_SPELLCAST_EMPOWER_START = onCastStart

-- Erfolg (SPEC 3.2). Payload: unitTarget, castGUID, spellID, interruptedBy (UnitDocumentation.lua)
function handlers.UNIT_SPELLCAST_INTERRUPTED(_, unit, _, _, interruptedBy)
  if not ns.loggedIn then return end
  ns.Alerts:OnInterrupted(unit, interruptedBy)
end

-- Handler, die den Ereignisnamen als ersten Parameter brauchen
local WITH_EVENT = {
  UNIT_SPELLCAST_START = true,
  UNIT_SPELLCAST_CHANNEL_START = true,
  UNIT_SPELLCAST_EMPOWER_START = true,
  UNIT_SPELLCAST_INTERRUPTED = true,
}

local function dispatch(event, ...)
  local handler = handlers[event]
  if not handler then return end
  -- Vor ADDON_LOADED gibt es noch keine Datenbank
  if not ns.db and event ~= "ADDON_LOADED" then return end
  local ok, err
  if WITH_EVENT[event] then
    ok, err = pcall(handler, event, ...)
  else
    ok, err = pcall(handler, ...)
  end
  if not ok then
    if ns.db then ns.Debug:Error(event, err) end
    if event == "ADDON_LOADED" or event == "PLAYER_LOGIN" then
      geterrorhandler()(err)
    end
  end
end

events:SetScript("OnEvent", function(_, event, ...) dispatch(event, ...) end)

for event in pairs(handlers) do
  local ok = pcall(events.RegisterEvent, events, event)
  if not ok then Print("Event unknown: " .. event) end
end

-- Eigene Unterbrechung (SPEC 3.2): UNIT_SPELLCAST_SUCCEEDED nur für "player". RegisterUnitEvent
-- spart die Ereignisse aller anderen Einheiten; ohne die Funktion normal registrieren
-- (OnPlayerSpell prüft die Einheit ohnehin). Der Handler steht bewusst erst nach der
-- Registrierungsschleife oben, damit nur playerEvents dieses Ereignis empfängt.
local playerEvents = CreateFrame("Frame")
handlers.UNIT_SPELLCAST_SUCCEEDED = function(unit, _, spellID)
  if not ns.loggedIn then return end
  ns.Alerts:OnPlayerSpell(unit, spellID)
end
playerEvents:SetScript("OnEvent", function(_, event, ...) dispatch(event, ...) end)
do
  local ok = playerEvents.RegisterUnitEvent
    and pcall(playerEvents.RegisterUnitEvent, playerEvents, "UNIT_SPELLCAST_SUCCEEDED", "player")
  if not ok then
    ok = pcall(playerEvents.RegisterEvent, playerEvents, "UNIT_SPELLCAST_SUCCEEDED")
  end
  if not ok then Print("Event unknown: UNIT_SPELLCAST_SUCCEEDED") end
end

---------------------------------------------------------------------------
-- Slash-Befehle. /kickalert ohne Argument öffnet das Menü (SPEC 5).
---------------------------------------------------------------------------

local ALERTS = { cast = true, success = true }

local function onOff(value)
  return value and L["ON"] or L["OFF"]
end

local function printHelp()
  Print(L["HELP_HEADER"])
  for _, key in ipairs({ "HELP_OPEN", "HELP_HELP", "HELP_TEST", "HELP_STATUS", "HELP_DEBUG" }) do
    print("  " .. L[key])
  end
end

local commands = {}

function commands.help()
  printHelp()
end

function commands.test(arg)
  if arg ~= "" and not ALERTS[arg] then printHelp(); return end
  ns.Alerts:Test(arg ~= "" and arg or nil)
end

function commands.status()
  local p = ns.db.profile
  Print(L["STATUS_HEADER"]:format(ns.VERSION))
  print("  " .. L["STATUS_KICK"]:format(ns.Kicks:Describe() or L["STATUS_KICK_NONE"]))
  print("  " .. L["STATUS_ALERT"]:format(L["ALERT_cast"], onOff(p.cast.enabled), ns.Sounds:Label(p.cast.sound)))
  print("  " .. L["STATUS_ALERT"]:format(L["ALERT_success"], onOff(p.success.enabled), ns.Sounds:Label(p.success.sound)))
  print("  " .. L["STATUS_UNITS"]:format(onOff(p.units.target), onOff(p.units.focus), onOff(p.units.nameplate)))
  print("  " .. L["STATUS_OPTIONS"]:format(L["CHANNEL_" .. p.channel], p.minGap, onOff(p.combatOnly),
    onOff(p.instanceOnly), onOff(p.success.others), onOff(ns.Debug:IsEnabled())))
end

function commands.debug(arg)
  if arg == "on" then
    ns.Debug:SetEnabled(true)
    ns.Options:Notify()
    Print(L["DEBUG_ON"])
  elseif arg == "off" then
    ns.Debug:Add("debugOff")
    ns.Debug:SetEnabled(false)
    ns.Options:Notify()
    Print(L["DEBUG_OFF"])
  elseif arg == "clear" then
    ns.Debug:Clear()
    Print(L["DEBUG_CLEARED"])
  else
    Print(L["DEBUG_STATUS"]:format(onOff(ns.Debug:IsEnabled()), ns.Debug:Count()))
  end
end

SLASH_KICKALERT1 = "/kickalert"
SlashCmdList.KICKALERT = function(msg)
  if not ns.db or not ns.loggedIn then return end
  local cmd, arg = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
  cmd = cmd:lower()
  arg = arg:lower()
  if cmd == "" then
    -- Menü öffnen; ohne Menü (Bibliothek fehlt, Fehler) die Hilfe zeigen
    if not ns.Options:Open() then printHelp() end
  elseif commands[cmd] then
    local ok, err = pcall(commands[cmd], arg)
    if not ok then
      ns.Debug:Error("slash " .. cmd, err)
      geterrorhandler()(err)
    end
  else
    Print(L["UNKNOWN_COMMAND"])
  end
end
