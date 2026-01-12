Config = {}

-- Permissions
-- You can allow these nodes to your DiscordAcePerms groups (group.LEO etc)
Config.AceNode = 'twopoint.evidence' -- allow this to group.LEO via DiscordAcePerms


-- Duty gating (PoliceEMSActivity_patched exports/statebags)
Config.RequireOnDuty = true
Config.DutyResource = "PoliceEMSActivity" -- resource name for exports

-- Lab locations (multiple). Analyze/Delete only works while inside a lab radius.
Config.Labs = {
  -- Police Stations (GTA V)
  { label = 'Mission Row PD Forensics',      coords = vector3(450.07,  -993.06, 30.00), radius = 30.0, category = 'POLICE' },
  { label = 'Davis PD Forensics',            coords = vector3(360.97, -1584.70, 29.29), radius = 30.0, category = 'POLICE' },
  { label = 'Vespucci PD Forensics',         coords = vector3(-1108.18, -845.18, 19.32), radius = 30.0, category = 'POLICE' },
  { label = 'Rockford Hills PD Forensics',   coords = vector3(-561.65,  -131.65, 38.21), radius = 30.0, category = 'POLICE' },
  { label = 'Vinewood PD Forensics',         coords = vector3(638.50,     1.75, 82.80),  radius = 30.0, category = 'POLICE' },
  { label = 'La Mesa PD Forensics',          coords = vector3(826.80, -1290.00, 28.24),  radius = 30.0, category = 'POLICE' },
  { label = 'Sandy Shores SO Forensics',     coords = vector3(1848.73, 3689.98, 34.27),  radius = 30.0, category = 'POLICE' },
  { label = 'Paleto Bay SO Forensics',       coords = vector3(-448.22, 6008.23, 31.72),  radius = 30.0, category = 'POLICE' },

  -- Police / Law Enforcement extras (toggle off if you don't want these)
  { label = 'Bolingbroke Forensics',         coords = vector3(1846.49, 2585.95, 45.67),  radius = 35.0, category = 'POLICE', enabled = true },
  { label = 'Ranger Station Forensics',      coords = vector3(379.31,   792.06, 190.41), radius = 35.0, category = 'POLICE', enabled = true },
  { label = 'LSIA Field Office Forensics',   coords = vector3(-864.61,-2408.92, 14.03),  radius = 35.0, category = 'POLICE', enabled = true },

  -- Hospitals / Medical Facilities
  { label = 'Pillbox Hill Medical Lab',              coords = vector3(319.20,  -580.80, 43.32), radius = 35.0, category = 'HOSPITAL' },
  { label = 'Central LS Medical Lab',                coords = vector3(338.80, -1394.50, 31.50), radius = 35.0, category = 'HOSPITAL' },
  { label = 'Mount Zonah Medical Lab',               coords = vector3(-449.80,  -341.00, 33.70), radius = 35.0, category = 'HOSPITAL' },
  { label = 'Portola Trinity Medical Lab',           coords = vector3(-874.70,  -307.50, 38.50), radius = 35.0, category = 'HOSPITAL' },
  { label = 'Eclipse Medical Tower Lab',             coords = vector3(-676.70,   311.50, 82.50), radius = 35.0, category = 'HOSPITAL' },
  { label = 'St Fiacre Medical Lab',                 coords = vector3(1152.20, -1528.00, 34.80), radius = 35.0, category = 'HOSPITAL' },
  { label = 'Sandy Shores Medical Lab',              coords = vector3(1839.50,  3672.50, 33.20), radius = 35.0, category = 'HOSPITAL' },
  { label = 'Paleto Bay Medical Lab',                coords = vector3(-246.90,  6330.50, 31.40), radius = 35.0, category = 'HOSPITAL' },
}

-- Map blips for labs (configurable)
Config.Blips = {
  Enabled = true,
  ShowToAll = true,         -- if false, only players with Config.AceNode see them
  ShortRange = true,
  Scale = 0.75,

  -- You can override per-lab with lab.blipSprite / lab.blipColor / lab.blipScale / lab.blipShortRange
  DefaultSprite = 498,      -- "Police Station" style
  DefaultColor = 3,

  PoliceSprite = 498,
  PoliceColor  = 29,

  HospitalSprite = 61,
  HospitalColor  = 2,
}

-- BigDaddy chat integration
Config.BigDaddyChatResource = "BigDaddy-Chat"
Config.ChatnameCommand = "chatname"  -- intercept /chatname <name> if chatMessage event fires
Config.NamePollSeconds = 30          -- fallback polling of BigDaddy chat export

-- Evidence generation (client)
Config.Drop = {
  ShellCasing = { enabled = true, cooldownMs = 1200, radius = 0.8 }, -- per-shot cooldown
  Blood       = { enabled = true, healthDelta = 10, cooldownMs = 7000, radius = 0.8 },
  Fingerprint = { enabled = true, onVehicleEnter = true, cooldownMs = 12000, radius = 1.2 }
}

-- Evidence cleanup
Config.WorldEvidenceTTLMinutes = 180  -- default/fallback TTL (minutes) if no per-evidence TTL is provided

-- Realism tuning (all optional)
Config.Realism = {
  -- Shell casings
  SuppressedShellChance = 0.35, -- if weapon is silenced, chance to still drop a casing

  -- Fingerprints / touch DNA
  GlovesFingerprintChance = 0.15, -- wearing gloves reduces chance of leaving prints/touch DNA

  -- Weather decay
  RainDecayMultiplier = 0.60, -- if raining, TTL is multiplied by this number

  -- Per evidence TTL (minutes). Used to compute expires_at in SQL for each drop.
  TTLByType = {
    SHELL = 240,
    BLOOD = 180,
    FINGERPRINT = 360,
  }

  -- Optional: better glove detection (expand these lists if you use lots of custom clothing)
  -- These are "arms" drawable indexes (component 3). The default 15 is commonly bare hands for freemode.
  ,GloveCheck = {
    MaleNoGloves = { [15] = true },
    FemaleNoGloves = { [15] = true },
    AssumeGlovesForNonFreemode = true,
  }
}

-- Scanner/collection
Config.Scanner = {
  Command = "forensic",
  CollectKey = 38, -- E
  MaxDrawDistance = 25.0,
  CollectDistance = 2.0
}

-- Commands
Config.Commands = {
  ui = 'evidence',
  list = 'evidencelist',
  view = 'evidenceview',
  delete = 'evidencedelete',
  analyze = 'evidenceanalyze'
}


-- Debug
Config.Debug = false
