-- InterruptTest v0.3.0
-- Testaddon: Was ist in Midnight (12.1) im Kampf lesbar, um bei einem
-- unterbrechbaren gegnerischen Zauber einen Sound zu spielen?
--
-- Geprueft wird:
--   1. UNIT_SPELLCAST_* Ereignisse fuer target, focus, nameplateN (kommen sie, ist die Spell-ID geheim?)
--   2. UnitCastingInfo / UnitChannelInfo: Name, Spell-ID, notInterruptible geheim?
--   3. UNIT_SPELLCAST_INTERRUPTIBLE / NOT_INTERRUPTIBLE
--   4. UnitCanAttack fuer die zaubernde Einheit
--   5. Eigene Unterbrechung: C_Spell.GetSpellCooldown im Kampf geheim?
--   6. Vorhandene neue APIs (C_Secrets, C_CurveUtil, C_DurationUtil, ...) und ob
--      SetShown / SetAlphaFromBoolean einen geheimen Wert annehmen
-- Wenn notInterruptible lesbar und false ist, spielt das Addon sofort einen Sound (Versuch).
--
-- Log: WTF\Account\<ACCOUNT>\SavedVariables\InterruptTest.lua (bei /reload oder Logout)
-- Befehle: /itest

local ADDON_NAME = ...
local VERSION = "0.3.0"
local MAX_ENTRIES = 8000
local ALERT_LOCK = 0.5  -- gleicher Zauber kommt als target, focus und nameplateN gleichzeitig

local issecret = issecretvalue or function() return false end
local loginNo = 0

-- Alle API-Funktionen, deren Name "Important" enthaelt (zur Laufzeit gesucht)
local IMPORTANT_FUNCS = {}
local function collectImportant()
  wipe(IMPORTANT_FUNCS)
  local names = {}
  for _, nsName in ipairs({ "C_Spell", "C_UnitAuras", "C_Secrets", "C_NamePlate", "C_SpellBook" }) do
    local t = _G[nsName]
    if type(t) == "table" then
      for k, v in pairs(t) do
        if type(k) == "string" and type(v) == "function" and (k:find("Important") or k:find("Interrupt")) then
          IMPORTANT_FUNCS[#IMPORTANT_FUNCS + 1] = { name = nsName .. "." .. k, f = v }
          names[#names + 1] = nsName .. "." .. k
        end
      end
    end
  end
  for k, v in pairs(_G) do
    if type(k) == "string" and type(v) == "function" and k:find("Important") then
      IMPORTANT_FUNCS[#IMPORTANT_FUNCS + 1] = { name = k, f = v }
      names[#names + 1] = k
    end
  end
  table.sort(names)
  return table.concat(names, ", ")
end
local lastAlert = 0
local myKick -- { id = ..., name = ... }

local function Print(msg) print("|cffff8000InterruptTest|r: " .. msg) end

local function S(v)
  if issecret(v) then return "<SECRET>" end
  if v == nil then return "nil" end
  local t = type(v)
  if t == "number" or t == "string" or t == "boolean" then return v end
  return "<" .. t .. ">"
end

local function add(kind, data)
  local db = InterruptTestLog
  if not db then return end
  data = data or {}
  data.kind = kind
  data.t = math.floor(GetTime() * 100 + 0.5) / 100
  data.login = loginNo
  local okC, c = pcall(InCombatLockdown)
  data.combat = okC and c and true or false
  local e = db.entries
  e[#e + 1] = data
  if #e > MAX_ENTRIES then
    local keep = {}
    for i = #e - (MAX_ENTRIES - 1000) + 1, #e do keep[#keep + 1] = e[i] end
    db.entries = keep
  end
end

local function call(func, ...)
  if not func then return false, "noAPI" end
  return pcall(func, ...)
end

---------------------------------------------------------------------------
-- Eigene Unterbrechung finden (alle Klassen)
---------------------------------------------------------------------------

-- Bekannte Unterbrechungszauber. Welcher bekannt ist, wird zur Laufzeit geprueft und geloggt.
local KICKS = {
  1766,   -- Schurke: Tritt
  6552,   -- Krieger: Zuschlagen
  96231,  -- Paladin: Zurechtweisung
  47528,  -- Todesritter: Gedankenfrost
  2139,   -- Magier: Gegenzauber
  57994,  -- Schamane: Windstoss
  147362, -- Jaeger: Gegenschuss
  187707, -- Jaeger (Ueberleben): Maulkorb
  106839, -- Druide: Schaedelstoss
  78675,  -- Druide (Gleichgewicht): Sonnenstrahl
  116705, -- Moench: Speerhandstoss
  15487,  -- Priester (Schatten): Stille
  183752, -- Daemonenjaeger: Unterbrechen
  351338, -- Rufer: Unterdruecken
  19647,  -- Hexenmeister (Wichtel/Teufelsjaeger): Zauber sperren
  119910, -- Hexenmeister: Zauber sperren (Befehl)
  119914, -- Hexenmeister (Daemonologie): Axtwurf
}

local function isKnown(id)
  if C_SpellBook and C_SpellBook.IsSpellKnown then
    local ok, v = pcall(C_SpellBook.IsSpellKnown, id)
    if ok and not issecret(v) and v then return true end
  end
  if IsPlayerSpell then
    local ok, v = pcall(IsPlayerSpell, id)
    if ok and not issecret(v) and v then return true end
  end
  if IsSpellKnownOrOverridesKnown then
    local ok, v = pcall(IsSpellKnownOrOverridesKnown, id)
    if ok and not issecret(v) and v then return true end
  end
  return false
end

local function findKick(why)
  myKick = nil
  local known = {}
  for _, id in ipairs(KICKS) do
    if isKnown(id) then
      local okN, info = pcall(C_Spell.GetSpellInfo, id)
      local name = okN and info and S(info.name) or "?"
      known[#known + 1] = id .. " " .. tostring(name)
      if not myKick then myKick = { id = id, name = name } end
    end
  end
  add("kick", { why = why, found = myKick and myKick.id or "none", known = table.concat(known, ", ") })
end

local function probeKick(out)
  if not myKick then out.kick = "none"; return end
  out.kickID = myKick.id
  local ok, cd = call(C_Spell.GetSpellCooldown, myKick.id)
  if not ok then out.kickCD = "err:" .. tostring(cd)
  elseif issecret(cd) then out.kickCD = "<SECRET table>"
  elseif type(cd) ~= "table" then out.kickCD = S(cd)
  else
    out.kickStart = S(cd.startTime)
    out.kickDur = S(cd.duration)
    out.kickEnabled = S(cd.isEnabled)
    out.kickOnGCD = S(cd.isOnGCD)
    -- Bereit? Nur wenn lesbar
    if not issecret(cd.duration) and type(cd.duration) == "number" then
      out.kickReady = cd.duration <= 1.5
    end
  end
  local okU, usable = call(C_Spell.IsSpellUsable, myKick.id)
  out.kickUsable = okU and S(usable) or "err"
  if C_Spell.GetSpellCooldownDuration then
    local okD, d = pcall(C_Spell.GetSpellCooldownDuration, myKick.id)
    out.kickDurObj = okD and S(d) or ("err:" .. tostring(d))
  end
end

---------------------------------------------------------------------------
-- Versuch: nimmt SetShown / SetAlphaFromBoolean einen geheimen Wert an?
---------------------------------------------------------------------------

local probeFrame = CreateFrame("Frame", nil, UIParent)
probeFrame:Hide()
local onShowCount = 0
probeFrame:SetScript("OnShow", function() onShowCount = onShowCount + 1 end)
local probeTex = probeFrame:CreateTexture()
local triedSecretUI = false

local function trySecretUI(secretBool)
  if triedSecretUI then return end
  triedSecretUI = true
  local out = {}
  local before = onShowCount
  local ok1, e1 = pcall(probeFrame.SetShown, probeFrame, secretBool)
  out.setShownOk = ok1
  out.setShownErr = ok1 and nil or tostring(e1)
  out.onShowFired = onShowCount > before
  local okS, shown = pcall(probeFrame.IsShown, probeFrame)
  out.isShownAfter = okS and S(shown) or "err"
  pcall(probeFrame.Hide, probeFrame)
  if probeTex.SetAlphaFromBoolean then
    local ok2, e2 = pcall(probeTex.SetAlphaFromBoolean, probeTex, secretBool, 1, 0)
    out.alphaFromBoolOk = ok2
    out.alphaFromBoolErr = ok2 and nil or tostring(e2)
  else
    out.alphaFromBool = "noAPI"
  end
  add("secretUI", out)
end

---------------------------------------------------------------------------
-- Gegnerische Zauber
---------------------------------------------------------------------------

local function wanted(unit)
  if issecret(unit) or type(unit) ~= "string" then return false end
  return unit == "target" or unit == "focus" or unit:match("^nameplate%d+$") ~= nil
end

-- Welche Einheiten den Sound ausloesen (/itest units ...)
local ALERT_UNITS = { target = true, focus = true, nameplate = false }

local function playAlert(via, unit)
  local now = GetTime()
  if now - lastAlert < ALERT_LOCK then return end
  lastAlert = now
  local ok = pcall(PlaySound, SOUNDKIT.RAID_WARNING, "Master")
  add("ALERT", { via = via, unit = unit, soundOk = ok })
end

local function probeCast(event, unit, channel)
  local out = { event = event, unit = unit }
  local func = channel and UnitChannelInfo or UnitCastingInfo
  local ok, name, _, _, startMs, endMs, _, a7, a8, a9 = pcall(func, unit)
  if not ok then
    out.castErr = tostring(name)
  else
    local notInt, spellID
    if channel then notInt, spellID = a7, a8 else notInt, spellID = a8, a9 end
    out.name = S(name)
    out.spellID = S(spellID)
    out.notInt = S(notInt)
    out.startMs = issecret(startMs) and "<SECRET>" or (startMs and "ok" or "nil")
    out.endMs = issecret(endMs) and "<SECRET>" or (endMs and "ok" or "nil")
    -- Versuch: Sound, wenn lesbar unterbrechbar
    local okA, canAttack = pcall(UnitCanAttack, "player", unit)
    out.canAttack = okA and S(canAttack) or "err"
    -- Variante 1 (v0.2.0): Sound bei jedem Zauberbeginn einer gewaehlten, angreifbaren Einheit
    local hostile = okA and not issecret(canAttack) and canAttack
    local chosen = ALERT_UNITS[unit] or (ALERT_UNITS.nameplate and unit:match("^nameplate%d+$"))
    if issecret(notInt) then
      out.decision = "secret"
      trySecretUI(notInt)
    elseif notInt == false then
      out.decision = "interruptible"
    else
      out.decision = "notInterruptible"
    end
    out.hostile = hostile and true or false
    out.chosen = chosen and true or false
    if hostile and chosen then
      playAlert(event, unit)
    end
  end
  -- v0.3.0: "wichtige" Zauber. Alle Funktionen mit "Important" in C_Spell/C_UnitAuras/C_Secrets aufrufen
  if ok then
    local nret = select("#", pcall(func, unit)) - 1
    out.castReturns = nret
    local spellID
    if channel then spellID = a8 else spellID = a9 end
    for _, fn in ipairs(IMPORTANT_FUNCS) do
      local okI, v = pcall(fn.f, spellID)
      out["imp_" .. fn.name] = okI and S(v) or ("err:" .. tostring(v))
      local okU, vu = pcall(fn.f, unit)
      out["impUnit_" .. fn.name] = okU and S(vu) or ("err:" .. tostring(vu))
    end
    if C_Secrets and C_Secrets.GetSpellCastSecrecy then
      local okS, v = pcall(C_Secrets.GetSpellCastSecrecy, spellID)
      out.castSecrecy = okS and S(v) or ("err:" .. tostring(v))
    end
    if C_Secrets and C_Secrets.ShouldUnitSpellCastBeSecret then
      local okS, v = pcall(C_Secrets.ShouldUnitSpellCastBeSecret, unit)
      out.unitCastSecret = okS and S(v) or ("err:" .. tostring(v))
    end
  end
  local okN, n = pcall(UnitName, unit)
  out.unitName = okN and S(n) or "err"
  local okC, c = pcall(UnitClassification, unit)
  out.classification = okC and S(c) or "err"
  probeKick(out)
  add("cast", out)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local UNIT_EVENTS = {
  UNIT_SPELLCAST_START = "cast",
  UNIT_SPELLCAST_CHANNEL_START = "channel",
  UNIT_SPELLCAST_EMPOWER_START = "channel",
  UNIT_SPELLCAST_INTERRUPTIBLE = "flag",
  UNIT_SPELLCAST_NOT_INTERRUPTIBLE = "flag",
  UNIT_SPELLCAST_INTERRUPTED = "end",
  UNIT_SPELLCAST_STOP = "end",
  UNIT_SPELLCAST_CHANNEL_STOP = "end",
}

local f = CreateFrame("Frame")
f:SetScript("OnEvent", function(self, event, ...)
  if event == "ADDON_LOADED" then
    if ... ~= ADDON_NAME then return end
    InterruptTestLog = InterruptTestLog or {}
    local db = InterruptTestLog
    if db.version ~= VERSION then db.entries = {}; db.logins = 0; db.version = VERSION end
    db.entries = db.entries or {}
    db.logins = (db.logins or 0) + 1
    loginNo = db.logins
    Print("v" .. VERSION .. " geladen. /itest fuer Hilfe")

  elseif event == "PLAYER_LOGIN" then
    local version, build, _, toc = GetBuildInfo()
    local specOk, specID, specName = pcall(function() return GetSpecializationInfo(GetSpecialization()) end)
    local apis = {}
    for _, ns in ipairs({ "C_Secrets", "C_CurveUtil", "C_DurationUtil", "C_SpellActivationOverlay" }) do
      local t = _G[ns]
      if type(t) == "table" then
        local keys = {}
        for k in pairs(t) do keys[#keys + 1] = k end
        table.sort(keys)
        apis[ns] = table.concat(keys, ", ")
      else
        apis[ns] = "missing"
      end
    end
    add("meta", {
      addonVersion = VERSION, gameVersion = S(version), build = S(build), toc = S(toc),
      class = select(2, UnitClass("player")), specID = specOk and S(specID) or "err",
      specName = specOk and S(specName) or "err",
      C_Secrets = apis.C_Secrets, C_CurveUtil = apis.C_CurveUtil, C_DurationUtil = apis.C_DurationUtil,
      hasGetSpellCooldownDuration = C_Spell.GetSpellCooldownDuration and true or false,
      hasAlphaFromBoolean = probeTex.SetAlphaFromBoolean and true or false,
      hasStatusBarSetTimer = (CreateFrame("StatusBar").SetTimer) and true or false,
      importantFuncs = collectImportant(),
    })
    findKick("login")

  elseif event == "PLAYER_SPECIALIZATION_CHANGED" or event == "SPELLS_CHANGED" then
    if event == "SPELLS_CHANGED" and myKick then return end
    findKick(event)

  elseif event == "PLAYER_REGEN_DISABLED" then
    local out = {}
    probeKick(out)
    add("combatStart", out)
  elseif event == "PLAYER_REGEN_ENABLED" then
    add("combatEnd")

  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    local unit, castGUID, spellID = ...
    if unit == "player" then
      if not issecret(spellID) and myKick and spellID == myKick.id then
        local out = { spellID = spellID }
        C_Timer.After(0.2, function() probeKick(out); add("kickUsed", out) end)
      end
    end

  elseif event == "ZONE_CHANGED_NEW_AREA" or event == "CHALLENGE_MODE_START" then
    local okI, inInst, instType = pcall(IsInInstance)
    add("zone", { event = event, inInstance = okI and S(inInst) or "err", instType = okI and S(instType) or "err" })

  elseif UNIT_EVENTS[event] then
    local unit, castGUID, spellID = ...
    if not wanted(unit) then return end
    local kind = UNIT_EVENTS[event]
    if kind == "cast" then
      probeCast(event, unit, false)
    elseif kind == "channel" then
      probeCast(event, unit, true)
    else
      add("ev", { event = event, unit = unit, spellID = S(spellID), castGUID = S(castGUID) })
    end
  end
end)

local EVENTS = { "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_SPECIALIZATION_CHANGED", "SPELLS_CHANGED",
  "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UNIT_SPELLCAST_SUCCEEDED",
  "ZONE_CHANGED_NEW_AREA", "CHALLENGE_MODE_START" }
for e in pairs(UNIT_EVENTS) do EVENTS[#EVENTS + 1] = e end
for _, e in ipairs(EVENTS) do
  if not pcall(f.RegisterEvent, f, e) then Print("Event unbekannt: " .. e) end
end

SLASH_INTERRUPTTEST1 = "/itest"
SlashCmdList.INTERRUPTTEST = function(msg)
  msg = strlower(strtrim(msg or ""))
  if msg == "clear" then
    wipe(InterruptTestLog.entries); Print("Log geleert")
  elseif msg == "sound" then
    lastAlert = 0; playAlert("test", "none"); Print("Testsound gespielt")
  elseif msg:match("^units") then
    local arg = msg:match("^units%s+(%S+)")
    if arg == "target" then ALERT_UNITS = { target = true }
    elseif arg == "focus" then ALERT_UNITS = { focus = true }
    elseif arg == "both" then ALERT_UNITS = { target = true, focus = true }
    elseif arg == "all" then ALERT_UNITS = { target = true, focus = true, nameplate = true }
    end
    local list = {}
    for k, v in pairs(ALERT_UNITS) do if v then list[#list + 1] = k end end
    table.sort(list)
    add("units", { units = table.concat(list, ",") })
    Print("Sound bei Zauberbeginn von: " .. table.concat(list, ", ") .. "  (/itest units target|focus|both|all)")
  elseif msg == "kick" then
    findKick("manual"); local o = {}; probeKick(o); add("kickSnap", o)
    Print("Unterbrechung: " .. (myKick and (myKick.id .. " " .. tostring(myKick.name)) or "keine gefunden"))
  else
    Print("/itest sound | units target|focus|both|all | kick | clear. Log wird bei /reload gespeichert.")
  end
end
