local ADDON_NAME, ns = ...
local L = ns.L

-- Einstellungsmenü (SPEC 5) mit AceConfig-3.0 / AceConfigDialog-3.0, Aufbau aus VoidAlert.
-- Eingetragen unter Einstellungen > AddOns > KickAlert; /kickalert öffnet dasselbe Menü als
-- eigenständiges AceConfigDialog-Fenster. Keine Profilseite.

local Options = {}
ns.Options = Options

local AceConfig = LibStub("AceConfig-3.0", true)
local AceConfigDialog = LibStub("AceConfigDialog-3.0", true)

---------------------------------------------------------------------------
-- Zugriff auf Profilwerte über info.arg = { "pfad", "zum", "schlüssel" }
---------------------------------------------------------------------------

local function resolve(path)
  local t = ns.db.profile
  for i = 1, #path - 1 do t = t[path[i]] end
  return t, path[#path]
end

local function get(info)
  local t, k = resolve(info.arg)
  return t[k]
end

local function set(info, value)
  local t, k = resolve(info.arg)
  t[k] = value
  ns.Debug:Add("option", { name = table.concat(info.arg, "."), value = value })
end

---------------------------------------------------------------------------
-- Soundauswahl: Werte und Reihenfolge aus ns.Sounds:List() (mitgeliefert, eigene, WoW, LSM).
-- Ein gespeicherter Schlüssel, der nicht mehr in der Liste ist (z. B. LSM-Addon entfernt),
-- erscheint als "<Name> (fehlt)", damit das Dropdown nicht leer ist. Er wird nicht überschrieben.
---------------------------------------------------------------------------

local function missingLabel(key)
  local name = tostring(key):match("^%a+:(.+)$") or tostring(key)
  return L["SOUND_MISSING"]:format(name)
end

local function soundValues(alert)
  local values, sorting = {}, {}
  for _, entry in ipairs(ns.Sounds:List()) do
    values[entry.key] = entry.label
    sorting[#sorting + 1] = entry.key
  end
  local current = ns.db.profile[alert].sound
  if current ~= nil and values[current] == nil then
    values[current] = missingLabel(current)
    sorting[#sorting + 1] = current
  end
  return values, sorting
end

local function soundSelect(alert, order)
  return {
    type = "select", order = order, name = L["OPT_SOUND"], width = "double",
    values = function() return (soundValues(alert)) end,
    sorting = function() return select(2, soundValues(alert)) end,
    arg = { alert, "sound" }, get = get, set = set,
  }
end

-- AceConfig kennt für "range" keinen formatter (AceConfigDialog-3.0, Ace3 trunk). Der Slider
-- zeigt höchstens zwei Nachkommastellen (AceGUIWidget-Slider, UpdateText); gespeichert wird
-- auf eine Nachkommastelle gerundet (SPEC 5).
local function roundGap(value)
  if type(value) ~= "number" then return 0.5 end
  value = math.floor(value * 10 + 0.5) / 10
  if value < 0.2 then value = 0.2 elseif value > 2 then value = 2 end
  return value
end
Options.RoundGap = roundGap

---------------------------------------------------------------------------
-- Optionstabelle
---------------------------------------------------------------------------

local function buildOptions()
  local channels = {}
  for _, channel in ipairs(ns.Sounds.CHANNELS) do channels[channel] = L["CHANNEL_" .. channel] end

  return {
    type = "group",
    name = "KickAlert",
    args = {
      -- SPEC 3.1: klar sagen, dass jeder gegnerische Zauber den Sound auslöst
      note = {
        type = "description", order = 0, fontSize = "medium", width = "full",
        name = L["OPT_NOTE"] .. "\n",
      },
      kick = {
        type = "description", order = 1, width = "full",
        name = function()
          local names = ns.Kicks:Describe()
          if names then return L["OPT_KICK_FOUND"]:format(names) .. "\n" end
          return "|cffff8020" .. L["OPT_KICK_NONE"] .. "|r\n"
        end,
      },

      cast = {
        type = "group", order = 10, inline = true, name = L["ALERT_cast"],
        args = {
          enabled = {
            type = "toggle", order = 1, name = L["OPT_ENABLED"],
            arg = { "cast", "enabled" }, get = get, set = set,
          },
          sound = soundSelect("cast", 2),
          test = {
            type = "execute", order = 3, name = L["OPT_TEST"],
            func = function() ns.Alerts:Test("cast") end,
          },
        },
      },

      units = {
        type = "group", order = 20, inline = true, name = L["OPT_UNITS"],
        args = {
          target = {
            type = "toggle", order = 1, name = L["UNIT_target"],
            arg = { "units", "target" }, get = get, set = set,
          },
          focus = {
            type = "toggle", order = 2, name = L["UNIT_focus"],
            arg = { "units", "focus" }, get = get, set = set,
          },
          nameplate = {
            type = "toggle", order = 3, name = L["UNIT_nameplate"], desc = L["OPT_NAMEPLATE_DESC"],
            arg = { "units", "nameplate" }, get = get, set = set,
          },
        },
      },

      success = {
        type = "group", order = 30, inline = true, name = L["ALERT_success"],
        args = {
          enabled = {
            type = "toggle", order = 1, name = L["OPT_ENABLED"],
            arg = { "success", "enabled" }, get = get, set = set,
          },
          sound = soundSelect("success", 2),
          test = {
            type = "execute", order = 3, name = L["OPT_TEST"],
            func = function() ns.Alerts:Test("success") end,
          },
          others = {
            type = "toggle", order = 4, name = L["OPT_OTHERS"], desc = L["OPT_OTHERS_DESC"], width = "full",
            arg = { "success", "others" }, get = get, set = set,
          },
        },
      },

      general = {
        type = "group", order = 40, inline = true, name = L["OPT_GENERAL"],
        args = {
          channel = {
            type = "select", order = 1, name = L["OPT_CHANNEL"], desc = L["OPT_CHANNEL_DESC"],
            values = channels, sorting = ns.Sounds.CHANNELS,
            arg = { "channel" }, get = get, set = set,
          },
          minGap = {
            type = "range", order = 2, name = L["OPT_MIN_GAP"], desc = L["OPT_MIN_GAP_DESC"],
            min = 0.2, max = 2, step = 0.1,
            arg = { "minGap" }, get = get,
            set = function(info, value) set(info, roundGap(value)) end,
          },
          combatOnly = {
            type = "toggle", order = 3, name = L["OPT_COMBAT_ONLY"], desc = L["OPT_COMBAT_ONLY_DESC"],
            arg = { "combatOnly" }, get = get, set = set,
          },
          instanceOnly = {
            type = "toggle", order = 4, name = L["OPT_INSTANCE_ONLY"], desc = L["OPT_INSTANCE_ONLY_DESC"],
            arg = { "instanceOnly" }, get = get, set = set,
          },
          chatMessages = {
            type = "toggle", order = 5, name = L["OPT_CHAT"], desc = L["OPT_CHAT_DESC"],
            arg = { "chatMessages" }, get = get, set = set,
          },
          testBoth = {
            type = "execute", order = 6, name = L["OPT_TEST_BOTH"],
            func = function() ns.Alerts:Test() end,
          },
        },
      },

      custom = {
        type = "group", order = 50, inline = true, name = L["OPT_CUSTOM"],
        args = {
          note = {
            type = "description", order = 1, width = "full",
            name = function() return L["OPT_CUSTOM_NOTE"]:format(ns.Sounds.CUSTOM_FOLDER) end,
          },
        },
      },

      debug = {
        type = "group", order = 90, inline = true, name = L["OPT_DEBUG"],
        args = {
          debug = {
            type = "toggle", order = 1, name = L["OPT_DEBUG"], desc = L["OPT_DEBUG_DESC"],
            get = function() return ns.Debug:IsEnabled() end,
            set = function(_, value)
              if value then
                ns.Debug:SetEnabled(true)
                ns.Debug:Add("option", { name = "debug", value = true })
              else
                ns.Debug:Add("option", { name = "debug", value = false })
                ns.Debug:SetEnabled(false)
              end
            end,
          },
          clear = {
            type = "execute", order = 2, name = L["OPT_DEBUG_CLEAR"],
            desc = function() return L["DEBUG_COUNT"]:format(ns.Debug:Count()) end,
            func = function()
              ns.Debug:Clear()
              ns.Print(L["DEBUG_CLEARED"])
            end,
          },
        },
      },
    },
  }
end

---------------------------------------------------------------------------
-- Registrieren und Öffnen
---------------------------------------------------------------------------

function Options:Init()
  if not (AceConfig and AceConfigDialog) then
    ns.Debug:Error("Options", "AceConfig-3.0 missing")
    return
  end
  local ok, err = pcall(function()
    AceConfig:RegisterOptionsTable(ADDON_NAME, buildOptions())
    local _, categoryID = AceConfigDialog:AddToBlizOptions(ADDON_NAME, "KickAlert")
    self.categoryID = categoryID
  end)
  if not ok then ns.Debug:Error("Options:Init", err) end
  self.ready = ok
end

-- Eigenständiges AceConfigDialog-Fenster (SPEC 5). Settings.OpenToCategory zeigte bei OwnDPS
-- nicht zuverlässig ein Fenster (aus VoidAlert). Rückgabe true, wenn das Fenster geöffnet wurde.
function Options:Open()
  if not (self.ready and AceConfigDialog) then return false end
  local ok, err = pcall(AceConfigDialog.Open, AceConfigDialog, ADDON_NAME)
  ns.Debug:Add("optionsOpen", { ok = ok, err = err })
  if not ok then ns.Debug:Error("AceConfigDialog:Open", err) end
  return ok
end

-- Offenes Menü aktualisieren, wenn sich etwas außerhalb davon ändert (Slash-Befehl, Unterbrechung)
function Options:Notify()
  if not self.ready then return end
  local registry = LibStub("AceConfigRegistry-3.0", true)
  if registry then pcall(registry.NotifyChange, registry, ADDON_NAME) end
end
