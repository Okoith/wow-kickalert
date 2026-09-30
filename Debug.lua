local ADDON_NAME, ns = ...

-- Debug-Log in der SavedVariable KickCallDebugLog (Ringpuffer), übernommen aus VoidAlert.
-- Regel: Secret Values werden nie gespeichert, nur als "<SECRET>" markiert (SPEC 6).

local Debug = {}
ns.Debug = Debug

local MAX_ENTRIES = 5000
local ERROR_REPEAT_SECONDS = 5

local issecret = issecretvalue or function() return false end

local loginNo = 0
local lastErrors = {}   -- Meldungstext -> Zeitpunkt, drosselt identische Fehler

-- Wandelt einen Wert in etwas Speicherbares um. Secret Values -> "<SECRET>".
local function S(v)
  if issecret(v) then return "<SECRET>" end
  if v == nil then return "nil" end
  local t = type(v)
  if t == "number" or t == "string" or t == "boolean" then return v end
  return "<" .. t .. ">"
end
Debug.S = S

function Debug:Init()
  if type(KickCallDebugLog) ~= "table" then KickCallDebugLog = {} end
  local log = KickCallDebugLog
  if type(log.entries) ~= "table" then log.entries = {} end
  log.logins = (tonumber(log.logins) or 0) + 1
  loginNo = log.logins
end

-- Schnelle Prüfung vor dem Anlegen von Tabellen (SPEC 7: keine Tabellen pro Ereignis, wenn Debug aus ist)
function Debug:IsEnabled()
  return ns.db ~= nil and ns.db.global.debug == true
end

function Debug:SetEnabled(enabled)
  ns.db.global.debug = enabled and true or false
  if enabled then self:LogMeta() end
end

function Debug:Count()
  local log = KickCallDebugLog
  return (log and log.entries) and #log.entries or 0
end

function Debug:Clear()
  local log = KickCallDebugLog
  if log and log.entries then wipe(log.entries) end
end

-- data: flache Tabelle mit festen String-Schlüsseln; jeder Wert wird mit S() bereinigt.
function Debug:Add(kind, data)
  if not self:IsEnabled() then return end
  local log = KickCallDebugLog
  if not log or not log.entries then return end

  local entry = {}
  if data then
    for k, v in pairs(data) do entry[k] = S(v) end
  end
  entry.kind = kind
  entry.t = math.floor(GetTime() * 100 + 0.5) / 100
  entry.time = date("%H:%M:%S")
  entry.login = loginNo
  entry.combat = ns.inCombat and true or false

  local e = log.entries
  e[#e + 1] = entry
  while #e > MAX_ENTRIES do table.remove(e, 1) end
end

-- Fehler aus pcall. Gleiche Meldungen höchstens alle paar Sekunden.
function Debug:Error(where, err)
  if not self:IsEnabled() then return end
  local msg = S(err)
  if type(msg) ~= "string" then msg = tostring(msg) end
  local key = where .. ":" .. msg
  local now = GetTime()
  if lastErrors[key] and now - lastErrors[key] < ERROR_REPEAT_SECONDS then return end
  lastErrors[key] = now
  self:Add("error", { where = where, err = msg })
end

-- Aktuelle Spezialisierung: specID, specName (nil, wenn nicht ermittelbar). Aus VoidAlert.
function Debug:GetSpec()
  local ok, index = pcall(GetSpecialization)
  if not ok or issecret(index) or type(index) ~= "number" then return nil, nil end
  local okInfo, specID, specName = pcall(GetSpecializationInfo, index)
  if not okInfo or issecret(specID) or type(specID) ~= "number" then return nil, nil end
  if issecret(specName) then specName = nil end
  return specID, specName
end

-- Version, Build, Sprache, Klasse, Spezialisierung, Einstellungen, Soundquellen (SPEC 6)
function Debug:LogMeta()
  if not self:IsEnabled() then return end
  local okB, gameVersion, build, buildDate, toc = pcall(GetBuildInfo)
  if not okB then gameVersion = "err" end
  local okC, _, class = pcall(UnitClass, "player")
  local specID, specName = self:GetSpec()
  local p = ns.db.profile
  local out = {
    addonVersion = ns.VERSION,
    gameVersion = gameVersion, build = build, buildDate = buildDate, toc = toc,
    locale = GetLocale(),
    class = okC and class or "err",
    specID = specID,
    specName = specName,
    profile = ns.db:GetCurrentProfile(),
    castEnabled = p.cast.enabled,
    castSound = p.cast.sound,
    successEnabled = p.success.enabled,
    successSound = p.success.sound,
    successOthers = p.success.others,
    unitTarget = p.units.target,
    unitFocus = p.units.focus,
    unitNameplate = p.units.nameplate,
    channel = p.channel,
    minGap = p.minGap,
    combatOnly = p.combatOnly,
    instanceOnly = p.instanceOnly,
    chatMessages = p.chatMessages,
    hasIsSecretValue = issecretvalue ~= nil,
    hasIsSpellKnown = (C_SpellBook and C_SpellBook.IsSpellKnown) ~= nil,
    hasIsPlayerSpell = IsPlayerSpell ~= nil,
    hasIsKnownFile = (C_UIFileAsset and C_UIFileAsset.IsKnownFile) ~= nil,
    hasLSM = ns.Sounds.LSM ~= nil,
  }
  self:Add("meta", out)
  self:Add("sounds", ns.Sounds:DebugInfo())
  ns.Kicks:Log("meta")
end
