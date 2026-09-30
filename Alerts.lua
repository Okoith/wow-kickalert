local ADDON_NAME, ns = ...
local L = ns.L

-- Erkennung (SPEC 3). Auslöser sind nur:
--   UNIT_SPELLCAST_START / _CHANNEL_START / _EMPOWER_START  -> Sound "Zauberbeginn"
--   UNIT_SPELLCAST_SUCCEEDED (player, Spell-ID aus Kicks.SET) -> eigene Unterbrechung merken
--   UNIT_SPELLCAST_INTERRUPTED                                -> Sound "Erfolg"
-- Keine Filter über geheime Werte (Spell-ID, Name, notInterruptible, startTime/duration der
-- Abklingzeit). Die Option "Nur wenn meine Unterbrechung bereit ist" nutzt nur isActive und
-- isOnGCD, die lesbar sind (SPEC 2, Kicks:ReadyState).

local Alerts = {}
ns.Alerts = Alerts

local issecret = issecretvalue or function() return false end

Alerts.ORDER = { "cast", "success" }
Alerts.KICK_WINDOW = 1.0      -- s: INTERRUPTED zählt als eigene Unterbrechung (SPEC 3.2)
Alerts.SUCCESS_LOCKOUT = 0.5  -- s: eigene Sperre für den Erfolg-Sound (SPEC 3.2)

local lastCast = nil      -- GetTime() des letzten Zauberbeginn-Sounds
local lastSuccess = nil   -- GetTime() des letzten Erfolg-Sounds
local lastKick = nil      -- GetTime() der letzten eigenen Unterbrechung
local lastKickID = nil
local seenSpells = {}     -- nur im Debugmodus: eigene Spell-IDs, die schon geloggt wurden

---------------------------------------------------------------------------
-- Hilfsfunktionen
---------------------------------------------------------------------------

-- "target", "focus", "nameplate" oder nil. Der Aufrufer hat issecretvalue(unit) schon geprüft.
-- Dieser Filter läuft vor allen anderen Aufrufen (SPEC 7, Leistung).
local function unitKind(unit)
  if type(unit) ~= "string" then return nil end
  if unit == "target" then return "target" end
  if unit == "focus" then return "focus" end
  if unit:match("^nameplate%d+$") then return "nameplate" end
  return nil
end

-- Nur Gegner (SPEC 3.1): UnitCanAttack in pcall, nur lesbares true zählt.
-- Rückgabe: nil, wenn feindlich, sonst der Grund fürs Debug-Log.
local function notHostileReason(unit)
  local ok, canAttack = pcall(UnitCanAttack, "player", unit)
  if not ok then
    ns.Debug:Error("UnitCanAttack", canAttack)
    return "canAttackError"
  end
  if issecret(canAttack) then return "canAttackSecret" end
  if canAttack ~= true then return "notHostile" end
  return nil
end

-- true/false; nil, wenn nicht lesbar
local function inInstance()
  local ok, inInst = pcall(IsInInstance)
  if not ok or issecret(inInst) then return nil end
  return inInst and true or false
end

-- Allgemeine Filter aus SPEC 5 (Einheit, nur im Kampf, nur in Instanzen).
-- Rückgabe: nil, wenn alles passt, sonst der Grund.
local function commonReason(p, kind)
  if not p.units[kind] then return "unitOff" end
  if p.combatOnly and not ns.inCombat then return "notInCombat" end
  if p.instanceOnly then
    local inst = inInstance()
    if inst == nil then return "instanceUnknown" end
    if not inst then return "notInInstance" end
  end
  return nil
end

local function round2(x)
  return math.floor(x * 100 + 0.5) / 100
end

-- Nur fürs Debug-Log: Wurde laut Ereignis vom Spieler unterbrochen? (interruptedBy laut
-- UnitDocumentation.lua, wow-ui-source 12.1.0; ob lesbar, ist nicht getestet)
local function interruptedByMe(guid)
  if issecret(guid) then return "<SECRET>" end
  if type(guid) ~= "string" then return type(guid) end
  local ok, me = pcall(UnitGUID, "player")
  if not ok or issecret(me) or type(me) ~= "string" then return "unknown" end
  return guid == me
end

---------------------------------------------------------------------------
-- Abspielen
---------------------------------------------------------------------------

-- Spielt den Sound eines Alarms ("cast" oder "success"). Ist der gewählte Schlüssel nicht
-- auflösbar (z. B. Sprachansage fehlt, LSM-Addon entfernt), wird der Standard verwendet.
-- Scheitert das Abspielen einer Datei, folgt der WoW-Sound aus SPEC 4.
function Alerts:Play(alert, why)
  local p = ns.db.profile
  local Sounds = ns.Sounds
  local key = p[alert].sound
  local fallbackFrom
  if not Sounds:Resolve(key) then
    fallbackFrom = key
    key = Sounds.DEFAULTS[alert]
  end
  local result = Sounds:Play(key, p.channel)
  result.alert = alert
  result.why = why
  result.fallbackFrom = fallbackFrom
  local fallback = Sounds.FALLBACK[alert]
  if result.failed and key ~= fallback then
    local second = Sounds:Play(fallback, p.channel)
    result.fallbackSound = fallback
    result.fallbackOk = second.ok
    result.fallbackWillPlay = second.willPlay
  end
  ns.Debug:Add("sound", result)
  return result
end

---------------------------------------------------------------------------
-- Zauberbeginn (SPEC 3.1)
---------------------------------------------------------------------------

function Alerts:OnCastStart(event, unit)
  if issecret(unit) then
    if ns.Debug:IsEnabled() then
      ns.Debug:Add("cast", { event = event, unit = unit, decision = "skip", reason = "secretUnit" })
    end
    return
  end
  local kind = unitKind(unit)
  if not kind then return end

  local p = ns.db.profile
  local now = GetTime()
  local reason
  if not p.cast.enabled then
    reason = "castOff"
  else
    reason = commonReason(p, kind)
  end
  if not reason and lastCast and now - lastCast < p.minGap then
    reason = "lockout"
  end
  if not reason then
    reason = notHostileReason(unit)
  end
  -- Nach allen anderen Filtern: Abklingzeit der eigenen Unterbrechung. Im Zweifel abspielen;
  -- kickCheck nennt dann den Grund (kickUnknown, cdSecret, cdError, ...).
  local kickCheck, kickID, isActive, isOnGCD
  if not reason and p.cast.readyOnly then
    local ready
    ready, kickCheck, kickID, isActive, isOnGCD = ns.Kicks:ReadyState()
    if not ready then reason = "kickOnCooldown" end
  end

  if reason then
    if ns.Debug:IsEnabled() then
      ns.Debug:Add("cast", {
        event = event, unit = unit, decision = "skip", reason = reason,
        sinceLast = lastCast and round2(now - lastCast),
        kickCheck = kickCheck, kickID = kickID, isActive = isActive, isOnGCD = isOnGCD,
      })
    end
    return
  end

  -- Doppelsperre erst hier, also nur wenn wirklich ein Sound gespielt wird
  lastCast = now
  if ns.Debug:IsEnabled() then
    ns.Debug:Add("cast", {
      event = event, unit = unit, decision = "play",
      kickCheck = kickCheck, kickID = kickID, isActive = isActive, isOnGCD = isOnGCD,
    })
  end
  self:Play("cast", event)
end

---------------------------------------------------------------------------
-- Eigene Unterbrechung (SPEC 3.2): UNIT_SPELLCAST_SUCCEEDED für "player"
---------------------------------------------------------------------------

function Alerts:OnPlayerSpell(unit, spellID)
  if issecret(unit) or unit ~= "player" then return end
  if issecret(spellID) then
    if ns.Debug:IsEnabled() and not seenSpells.secret then
      seenSpells.secret = true
      ns.Debug:Add("playerSpell", { spellID = spellID })   -- als "<SECRET>"
    end
    return
  end
  if not ns.Kicks.SET[spellID] then
    -- Nur im Debugmodus, jede ID einmal pro Sitzung: hilft, falsche Kick-IDs zu finden
    if ns.Debug:IsEnabled() and type(spellID) == "number" and not seenSpells[spellID] then
      seenSpells[spellID] = true
      ns.Debug:Add("playerSpell", { spellID = spellID, name = ns.Kicks:SpellName(spellID) })
    end
    return
  end
  lastKick = GetTime()
  lastKickID = spellID
  if ns.Debug:IsEnabled() then
    ns.Debug:Add("ownKick", { spellID = spellID, name = ns.Kicks:SpellName(spellID), known = ns.Kicks.knownKey })
  end
end

---------------------------------------------------------------------------
-- Erfolg (SPEC 3.2): UNIT_SPELLCAST_INTERRUPTED eines Gegners
---------------------------------------------------------------------------

function Alerts:OnInterrupted(unit, interruptedBy)
  if issecret(unit) then
    if ns.Debug:IsEnabled() then
      ns.Debug:Add("interrupted", { unit = unit, decision = "skip", reason = "secretUnit" })
    end
    return
  end
  local kind = unitKind(unit)
  if not kind then return end

  local p = ns.db.profile
  local now = GetTime()
  local sinceKick = lastKick and (now - lastKick)
  local own = sinceKick ~= nil and sinceKick <= self.KICK_WINDOW
  local reason
  if not p.success.enabled then
    reason = "successOff"
  else
    reason = commonReason(p, kind)
  end
  if not reason and not own and not p.success.others then
    reason = "notOwnKick"
  end
  if not reason and lastSuccess and now - lastSuccess < self.SUCCESS_LOCKOUT then
    reason = "lockout"
  end
  if not reason then
    reason = notHostileReason(unit)
  end

  -- Jeden Fall mit Abstand zur eigenen Unterbrechung loggen (SPEC 3.2 und 6)
  if ns.Debug:IsEnabled() then
    ns.Debug:Add("interrupted", {
      unit = unit, decision = reason and "skip" or "play", reason = reason,
      sinceKick = sinceKick and round2(sinceKick), kickID = lastKickID, own = own,
      byMe = interruptedByMe(interruptedBy),
    })
  end
  if reason then return end

  lastSuccess = now
  self:Play("success", own and "ownKick" or "other")
end

---------------------------------------------------------------------------
-- Test: spielt einen oder beide Sounds, unabhängig von an/aus, Einheiten, Kampf und Sperre.
-- Beide nacheinander, damit sie sich nicht überlagern.
---------------------------------------------------------------------------

local TEST_GAP = 2

function Alerts:Test(which)
  local list = which and { which } or self.ORDER
  for i, alert in ipairs(list) do
    C_Timer.After((i - 1) * TEST_GAP, function()
      local ok, err = pcall(function()
        local result = self:Play(alert, "test")
        if ns.db.profile.chatMessages then
          ns.Print(L["TEST_PLAYING"]:format(L["ALERT_" .. alert], ns.Sounds:Label(result.sound)))
        end
      end)
      if not ok then ns.Debug:Error("Test", err) end
    end)
  end
end
