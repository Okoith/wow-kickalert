local ADDON_NAME, ns = ...

-- Unterbrechungszauber aller Klassen (SPEC 3.3). Liste aus docs/reference/InterruptTest.lua.
-- Im Spiel bestätigt ist nur Paladin 96231, die übrigen IDs sind ungeprüft. Darum:
-- Welche bekannt sind, wird zur Laufzeit geprüft und ins Debug-Log geschrieben.

local Kicks = {}
ns.Kicks = Kicks

local issecret = issecretvalue or function() return false end

Kicks.LIST = {
  1766,   -- Schurke: Tritt
  6552,   -- Krieger: Zuschlagen
  96231,  -- Paladin: Zurechtweisung (im Test bestätigt)
  47528,  -- Todesritter: Gedankenfrost
  2139,   -- Magier: Gegenzauber
  57994,  -- Schamane: Windstoß
  147362, -- Jäger: Gegenschuss
  187707, -- Jäger (Überleben): Maulkorb
  106839, -- Druide: Schädelstoß
  78675,  -- Druide (Gleichgewicht): Sonnenstrahl
  116705, -- Mönch: Speerhandstoß
  15487,  -- Priester (Schatten): Stille
  183752, -- Dämonenjäger: Unterbrechen
  351338, -- Rufer: Unterdrücken
  19647,  -- Hexenmeister (Wichtel/Teufelsjäger): Zauber sperren
  119910, -- Hexenmeister: Zauber sperren (Befehl)
  119914, -- Hexenmeister (Dämonologie): Axtwurf
}

-- Spell-ID -> true, für den schnellen Vergleich bei UNIT_SPELLCAST_SUCCEEDED
Kicks.SET = {}
for _, id in ipairs(Kicks.LIST) do Kicks.SET[id] = true end

Kicks.known = {}      -- Liste der bekannten IDs (Reihenfolge wie LIST)
Kicks.knownKey = ""   -- Text aus den IDs, erkennt Änderungen

-- Wie im Testaddon: drei APIs nacheinander, jede in pcall, nur lesbares true zählt.
-- C_SpellBook.IsSpellKnown laut SpellBookDocumentation.lua (wow-ui-source 12.1.0).
local function isKnown(id)
  if C_SpellBook and C_SpellBook.IsSpellKnown then
    local ok, v = pcall(C_SpellBook.IsSpellKnown, id)
    if ok and not issecret(v) and v == true then return true end
  end
  if IsPlayerSpell then
    local ok, v = pcall(IsPlayerSpell, id)
    if ok and not issecret(v) and v == true then return true end
  end
  if IsSpellKnownOrOverridesKnown then
    local ok, v = pcall(IsSpellKnownOrOverridesKnown, id)
    if ok and not issecret(v) and v == true then return true end
  end
  return false
end

function Kicks:SpellName(id)
  if not (C_Spell and C_Spell.GetSpellName) then return nil end
  local ok, name = pcall(C_Spell.GetSpellName, id)
  if ok and not issecret(name) and type(name) == "string" then return name end
  return nil
end

-- Bei PLAYER_LOGIN, PLAYER_SPECIALIZATION_CHANGED und SPELLS_CHANGED (SPEC 3.3).
-- Loggt nur, wenn sich etwas geändert hat, denn SPELLS_CHANGED kommt oft.
function Kicks:Update(why)
  local known = {}
  for _, id in ipairs(self.LIST) do
    if isKnown(id) then known[#known + 1] = id end
  end
  local key = table.concat(known, ",")
  local changed = key ~= self.knownKey
  self.known = known
  self.knownKey = key
  if changed then
    self:Log(why)
    ns.Options:Notify()
  end
  return changed
end

-- Anzeigetext für Menü und /kickcall status, z. B. "Zurechtweisung (96231)"
function Kicks:Describe()
  if #self.known == 0 then return nil end
  local parts = {}
  for _, id in ipairs(self.known) do
    parts[#parts + 1] = ("%s (%d)"):format(self:SpellName(id) or "?", id)
  end
  return table.concat(parts, ", ")
end

function Kicks:Log(why)
  if not ns.Debug:IsEnabled() then return end
  local specID, specName = ns.Debug:GetSpec()
  ns.Debug:Add("kicks", {
    why = why,
    specID = specID,
    specName = specName,
    found = #self.known > 0 and self.knownKey or "none",
    names = self:Describe() or "none",
  })
end
