Config = {}

-- =========================================================
-- Core / Permissions
-- =========================================================
Config.Debug = false

-- Single node for everything (you'll give this to group.LEO via DiscordAcePerms):
--   add_ace group.LEO twopoint.evidence allow
Config.AcePermission = "twopoint.evidence"

-- Duty requirement (PoliceEMSActivity patched export)
Config.RequireOnDuty = true
Config.DutyResource = "PoliceEMSActivity" -- exports[res]:IsOnDuty(src)

-- BigDaddy Chat integration (for /chatname)
Config.BigDaddyChatResource = "BigDaddy-Chat"
Config.NameSyncIntervalSeconds = 10

-- LB Phone integration for wiretap (optional)
Config.LBPhoneResource = "lb-phone"

-- =========================================================
-- Evidence behavior
-- =========================================================
Config.ScannerCommand = "forensic"
Config.OpenUICommand  = "evidence"
Config.ChatListCommand = "evidencelist"

Config.CollectKey = 38 -- E
Config.CollectDistance = 2.0

Config.DrawDistance = 40.0
Config.Marker = { type = 20, scale = 0.20 } -- small marker for scanner mode

-- Cleanup
Config.DropCleanupSeconds = 60
Config.MaxActiveDrops = 800 -- safety

-- Rain washing
Config.RainWashMultiplier = 0.45 -- evidence expires faster when raining (lower = faster)

-- Casings
Config.Casings = {
  Enabled = true,
  BaseChance = 0.75,
  SilencedChance = 0.20,
  CooldownMs = 750,
  TTLSeconds = 45 * 60, -- 45 minutes
}

-- Blood
Config.Blood = {
  Enabled = true,
  MinHealthDelta = 12,
  Chance = 0.55,
  CooldownMs = 30 * 1000,
  TTLSeconds = 35 * 60,
}

-- Fingerprints / Touch DNA (vehicle entry)
Config.Vehicles = {
  Enabled = true,
  FingerprintChance_NoGloves = 0.75,
  FingerprintChance_Gloves   = 0.10,
  TouchDNAChance_NoGloves    = 0.55,
  TouchDNAChance_Gloves      = 0.25,
  CooldownMs = 45 * 1000,
  TTLSeconds = 60 * 60,
}

-- Simple glove detection (common approach):
-- If the player's "arms" component drawable is in this list, treat it as NO gloves.
-- Otherwise treat as wearing gloves.
Config.GloveCheck = {
  Enabled = true,
  MaleNoGloves = {
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
    11, 12, 13, 14, 15, 16, 17, 18, 19,
    20, 21, 22, 23, 24, 25, 26, 27, 28, 29,
    30, 31, 32, 33, 34, 35
  },
  FemaleNoGloves = {
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
    11, 12, 13, 14, 15, 16, 17, 18, 19,
    20, 21, 22, 23, 24, 25, 26, 27, 28, 29,
    30, 31, 32, 33, 34, 35
  }
}

-- =========================================================
-- Labs (multiple locations)
-- Analyze/Delete only works inside one of these radiuses.
-- NOTE: Coordinates are GTA V vanilla locations (major hospitals & PD stations).
-- Adjust any that differ for your map.
-- =========================================================
Config.Labs = {
  -- Police Stations
  { enabled = true, label = "Mission Row PD Forensics", coords = vector3(441.1, -981.9, 30.7), radius = 35.0 },
  { enabled = true, label = "Vespucci PD Forensics",   coords = vector3(-1082.2, -823.1, 19.3), radius = 35.0 },
  { enabled = true, label = "Davis PD Forensics",      coords = vector3(373.7, -1608.4, 29.3), radius = 35.0 },
  { enabled = true, label = "Sandy Shores SO Forensics",coords = vector3(1853.2, 3686.0, 34.2), radius = 45.0 },
  { enabled = true, label = "Paleto Bay SO Forensics", coords = vector3(-449.7, 6015.0, 31.7), radius = 45.0 },

  -- Hospitals / Medical
  { enabled = true, label = "Pillbox Medical Forensics", coords = vector3(307.6, -1433.1, 29.9), radius = 60.0 },
  { enabled = true, label = "Mount Zonah Forensics",     coords = vector3(-449.5, -340.9, 34.5), radius = 60.0 },
  { enabled = true, label = "Central LS Medical Forensics", coords = vector3(340.7, -585.9, 28.8), radius = 60.0 },
  { enabled = true, label = "Sandy Medical Forensics",   coords = vector3(1839.6, 3672.9, 34.3), radius = 70.0 },
  { enabled = true, label = "Paleto Clinic Forensics",   coords = vector3(-256.0, 6322.2, 32.4), radius = 70.0 },
  { enabled = true, label = "St Fiacre Hospital Forensics", coords = vector3(1151.2, -1529.6, 34.9), radius = 60.0 },
}

-- =========================================================
-- Blips
-- =========================================================
Config.Blips = {
  Enabled = true,
  ShowToAll = true,  -- if false, only players with ACE permission see them
  Sprite = 361,      -- generic "science/forensics" vibe; change as desired
  Color = 3,
  Scale = 0.75,
  ShortRange = true,
  LabelPrefix = "Forensics Lab: "
}


-- =========================================================
-- Inspect / Cleanup (Civilian)
-- =========================================================
-- Allow regular members to inspect for evidence they personally created and attempt cleanup.
-- Give this to group.member:
--   add_ace group.member twopoint.evidence.inspect allow
Config.InspectAcePermission = "twopoint.evidence.inspect"

-- How far the inspect mode searches for your evidence drops (meters)
Config.InspectRadius = 25.0

-- Cleanup chances (only applied if the minigame is passed)
Config.CleanupChances = {
  Full = 0.50,    -- 50% chance to fully remove evidence (hard minigame)
  Partial = 0.35, -- 35% chance to downgrade evidence to partial (easy minigame)
}

-- Minigame tuning
Config.Minigame = {
  Collect = { keys = 2, totalTime = 4.0 },   -- not too difficult
  CleanupEasy = { keys = 3, totalTime = 4.5 },
  CleanupHard = { keys = 6, totalTime = 5.0 },
}

-- Partial evidence tuning
Config.Partial = {
  QualityMin = 30, -- after partial cleanup, quality will be reduced into this range
  QualityMax = 60,
}
