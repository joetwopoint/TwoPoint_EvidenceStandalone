local function dbg(...)
  if Config.Debug then
    print("[TwoPoint_Evidence]", ...)
  end
end

local function resStarted(name)
  return name and GetResourceState(name) == "started"
end

local function getIdentifier(src)
  local license = GetPlayerIdentifierByType(src, "license")
  return license or tostring(src)
end

local function getDisplayName(src)
  local default = GetPlayerName(src) or "Unknown"
  local res = Config.BigDaddyChatResource
  if resStarted(res) then
    local ok, name = pcall(function()
      return exports[res]:getPlayerName(src)
    end)
    if ok and type(name) == "string" and name ~= "" then
      return name
    end
  end
  return default
end


local function shortHash(str)
  if type(str) ~= "string" then return "??????" end
  local sum = 0
  for i = 1, #str do
    sum = (sum + string.byte(str, i) * i) % 0xFFFFFF
  end
  return string.format("%06X", sum)
end

local function hasPerm(src)
  if not IsAceAllowed(src, Config.AcePermission) then return false end
  if Config.RequireOnDuty then
    local res = Config.DutyResource
    if not resStarted(res) then return false end
    local ok, onDuty = pcall(function()
      return exports[res]:IsOnDuty(src)
    end)
    return ok and onDuty == true
  end
  return true
end

local function isInLab(coords)
  for _, lab in ipairs(Config.Labs) do
    if lab.enabled ~= false then
      local dist = #(coords - lab.coords)
      if dist <= (lab.radius or 25.0) then
        return true, lab.label
      end
    end
  end
  return false, nil
end

local function ensureTables()
  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS tp_evidence_profiles (
      identifier VARCHAR(64) PRIMARY KEY,
      display_name VARCHAR(128) NOT NULL,
      updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    )
  ]])

  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS tp_evidence_drops (
      id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
      type VARCHAR(24) NOT NULL,
      x DOUBLE NOT NULL,
      y DOUBLE NOT NULL,
      z DOUBLE NOT NULL,
      metadata LONGTEXT,
      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      expires_at TIMESTAMP NULL DEFAULT NULL
    )
  ]])

  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS tp_evidence_bags (
      id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
      owner_identifier VARCHAR(64) NOT NULL,
      drop_type VARCHAR(24) NOT NULL,
      data LONGTEXT,
      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      collected_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      collected_by VARCHAR(128) NOT NULL,
      analyzed_at TIMESTAMP NULL DEFAULT NULL,
      analyzed_by VARCHAR(128) NULL DEFAULT NULL
    )
  ]])

  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS tp_wiretap_targets (
      id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
      officer_identifier VARCHAR(64) NOT NULL,
      target_number VARCHAR(32) NOT NULL,
      label VARCHAR(64) NULL DEFAULT NULL,
      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      UNIQUE KEY uniq_officer_target (officer_identifier, target_number)
    )
  ]])
end

local drops = {} -- id -> {id,type,coords,metadata,expiresAtUnix}
local function loadDrops()
  local rows = MySQL.query.await("SELECT id, type, x, y, z, metadata, UNIX_TIMESTAMP(expires_at) AS exp FROM tp_evidence_drops", {})
  drops = {}
  for _, r in ipairs(rows or {}) do
    drops[r.id] = {
      id = r.id,
      type = r.type,
      coords = vector3(r.x, r.y, r.z),
      metadata = r.metadata and json.decode(r.metadata) or {},
      expiresAt = tonumber(r.exp) or nil
    }
  end
  dbg("Loaded drops:", (rows and #rows) or 0)
end

local function broadcastDrops(target)
  local arr = {}
  for _, d in pairs(drops) do
    arr[#arr+1] = {
      id = d.id,
      type = d.type,
      x = d.coords.x, y = d.coords.y, z = d.coords.z,
      metadata = d.metadata,
      expiresAt = d.expiresAt
    }
  end
  TriggerClientEvent("tp_evidence:dropsSnapshot", target or -1, arr)
end

local function rainAdjustedTTL(ttlSeconds, src)
  -- client sends its rain state, but we still keep a server-side multiplier option via metadata
  return ttlSeconds
end

local function pruneDrops()
  local now = os.time()
  local toDelete = {}
  for id, d in pairs(drops) do
    if d.expiresAt and now >= d.expiresAt then
      toDelete[#toDelete+1] = id
    end
  end
  if #toDelete > 0 then
    for _, id in ipairs(toDelete) do
      drops[id] = nil
      MySQL.update.await("DELETE FROM tp_evidence_drops WHERE id = ?", { id })
    end
    TriggerClientEvent("tp_evidence:dropRemovedMany", -1, toDelete)
  end
end

CreateThread(function()
  ensureTables()
  loadDrops()
  broadcastDrops(-1)

  -- periodic cleanup
  while true do
    Wait((Config.DropCleanupSeconds or 60) * 1000)
    pruneDrops()
  end
end)

-- Name sync (BigDaddy Chat /chatname -> profile display)
CreateThread(function()
  while true do
    Wait((Config.NameSyncIntervalSeconds or 10) * 1000)
    local players = GetPlayers()
    for _, sid in ipairs(players) do
      sid = tonumber(sid)
      if sid then
        local ident = getIdentifier(sid)
        local name  = getDisplayName(sid)
        if name and ident then
          MySQL.update.await([[
            INSERT INTO tp_evidence_profiles (identifier, display_name)
            VALUES (?, ?)
            ON DUPLICATE KEY UPDATE display_name = VALUES(display_name)
          ]], { ident, name })
        end
      end
    end
  end
end)

RegisterNetEvent("tp_evidence:requestDrops", function()
  local src = source
  broadcastDrops(src)
end)

RegisterNetEvent("tp_evidence:createDrop", function(dropType, coords, meta, ttlSeconds, clientRainLevel)
  local src = source
  if type(dropType) ~= "string" or type(coords) ~= "table" then return end
  if not Config[dropType:sub(1,1):upper()..dropType:sub(2)] and not (dropType == "casing" or dropType == "blood" or dropType == "fingerprint" or dropType == "touchdna") then
    -- allow list of types we use
  end

  -- Safety: prevent infinite growth
  local count = 0
  for _ in pairs(drops) do count = count + 1 end
  if count >= (Config.MaxActiveDrops or 800) then return end

  local ident = getIdentifier(src)
  local dname = getDisplayName(src)

  meta = meta or {}

  -- Track who created the evidence (used for /inspect cleanup)
  meta.ownerIdent = meta.ownerIdent or ident
  meta.ownerName = meta.ownerName or dname
  meta.ownerChatName = meta.ownerChatName or dname
  meta.partial = meta.partial or false
  meta.quality = meta.quality or 100
  meta.profileFragment = meta.profileFragment or shortHash(meta.ownerIdent)

  meta.actorIdentifier = ident
  meta.actorName = dname
  meta.createdBy = src

  local x, y, z = coords.x, coords.y, coords.z
  ttlSeconds = tonumber(ttlSeconds) or 1800

  -- rain wash
  local rain = tonumber(clientRainLevel) or 0.0
  if rain and rain > 0.15 then
    ttlSeconds = math.floor(ttlSeconds * (Config.RainWashMultiplier or 0.45))
    meta.rainWashed = true
    meta.rainLevel = rain
  end

  local expiresAtUnix = os.time() + ttlSeconds
  local id = MySQL.insert.await([[
    INSERT INTO tp_evidence_drops (type, x, y, z, metadata, expires_at)
    VALUES (?, ?, ?, ?, ?, FROM_UNIXTIME(?))
  ]], { dropType, x, y, z, json.encode(meta), expiresAtUnix })

  if not id then return end

  drops[id] = {
    id = id,
    type = dropType,
    coords = vector3(x, y, z),
    metadata = meta,
    expiresAt = expiresAtUnix
  }

  TriggerClientEvent("tp_evidence:dropAdded", -1, {
    id = id, type = dropType, x=x,y=y,z=z, metadata = meta, expiresAt = expiresAtUnix
  })
end)

RegisterNetEvent("tp_evidence:collectDrop", function(dropId, extractionQuality)
  local src = source
  if not hasPerm(src) then return end
  dropId = tonumber(dropId)
  if not dropId then return end
  local d = drops[dropId]
  if not d then return end

  local q = tonumber(extractionQuality) or 100
  d.metadata = d.metadata or {}
  d.metadata.extractionQuality = math.max(10, math.min(100, q))

  drops[dropId] = nil
  MySQL.update.await("DELETE FROM tp_evidence_drops WHERE id = ?", { dropId })
  TriggerClientEvent("tp_evidence:dropRemoved", -1, dropId)

  local ownerIdent = getIdentifier(src)
  local collectorName = getDisplayName(src)

  local bagData = {
    dropId = dropId,
    type = d.type,
    coords = { x = d.coords.x, y = d.coords.y, z = d.coords.z },
    meta = d.metadata,
    collectedAt = os.time(),
  }

  MySQL.insert.await([[
    INSERT INTO tp_evidence_bags (owner_identifier, drop_type, data, collected_by)
    VALUES (?, ?, ?, ?)
  ]], { ownerIdent, d.type, json.encode(bagData), collectorName })
end)

-- =========================================================
-- Inspect / Cleanup (civilian)
-- =========================================================
RegisterNetEvent("tp_evidence:inspectRequest", function(reqId, radius, coords)
  local src = source
  if not IsAceAllowed(src, Config.InspectAcePermission or "twopoint.evidence.inspect") then
    TriggerClientEvent("tp_evidence:inspectResponse", src, reqId, false, nil, "Not authorized.")
    return
  end

  radius = tonumber(radius) or (Config.InspectRadius or 25.0)
  if radius > 60.0 then radius = 60.0 end

  if type(coords) ~= "table" then
    local ped = GetPlayerPed(src)
    local p = GetEntityCoords(ped)
    coords = { x = p.x, y = p.y, z = p.z }
  end

  local ident = getIdentifier(src)
  local center = vector3(coords.x, coords.y, coords.z)

  local out = {}
  for id, d in pairs(drops) do
    if d and d.coords and #(d.coords - center) <= radius then
      local owner = d.metadata and d.metadata.ownerIdent or nil
      if owner == ident then
        out[#out+1] = {
          id = id,
          type = d.type,
          x = d.coords.x, y = d.coords.y, z = d.coords.z,
          metadata = d.metadata,
          expiresAt = d.expiresAt
        }
      end
    end
  end

  TriggerClientEvent("tp_evidence:inspectResponse", src, reqId, true, { drops = out }, nil)
end)

RegisterNetEvent("tp_evidence:attemptCleanup", function(dropId, mode, passedMinigame)
  local src = source
  if not IsAceAllowed(src, Config.InspectAcePermission or "twopoint.evidence.inspect") then
    TriggerClientEvent("tp_evidence:cleanupResult", src, false, "Not authorized.")
    return
  end

  dropId = tonumber(dropId)
  if not dropId then
    TriggerClientEvent("tp_evidence:cleanupResult", src, false, "Invalid evidence.")
    return
  end

  local d = drops[dropId]
  if not d then
    TriggerClientEvent("tp_evidence:cleanupResult", src, false, "That evidence is gone.")
    return
  end

  local ident = getIdentifier(src)
  if not (d.metadata and d.metadata.ownerIdent == ident) then
    TriggerClientEvent("tp_evidence:cleanupResult", src, false, "You can only clean up your own evidence.")
    return
  end

  local ped = GetPlayerPed(src)
  local pcoords = GetEntityCoords(ped)
  if #(pcoords - d.coords) > 3.0 then
    TriggerClientEvent("tp_evidence:cleanupResult", src, false, "Move closer to the evidence.")
    return
  end

  mode = tostring(mode or "partial")
  if mode ~= "full" and mode ~= "partial" then mode = "partial" end

  -- If they fail the minigame, nothing changes.
  if passedMinigame ~= true then
    if mode == "full" then
      TriggerClientEvent("tp_evidence:cleanupResult", src, false, "You failed the thorough clean. Evidence remains.")
    else
      TriggerClientEvent("tp_evidence:cleanupResult", src, false, "You failed the quick wipe. Evidence remains.")
    end
    return
  end

  local roll = math.random()
  if mode == "full" then
    local chance = (Config.CleanupChances and Config.CleanupChances.Full) or 0.50
    if roll <= chance then
      drops[dropId] = nil
      MySQL.update.await("DELETE FROM tp_evidence_drops WHERE id = ?", { dropId })
      TriggerClientEvent("tp_evidence:dropRemoved", -1, dropId)
      TriggerClientEvent("tp_evidence:cleanupResult", src, true, "You thoroughly cleaned up the evidence.")
      return
    else
      TriggerClientEvent("tp_evidence:cleanupResult", src, false, "You tried to fully clean it, but it didn't work.")
      return
    end
  else
    local chance = (Config.CleanupChances and Config.CleanupChances.Partial) or 0.35
    if roll <= chance then
      d.metadata = d.metadata or {}
      d.metadata.partial = true
      local qmin = (Config.Partial and Config.Partial.QualityMin) or 30
      local qmax = (Config.Partial and Config.Partial.QualityMax) or 60
      d.metadata.quality = math.random(qmin, qmax)
      d.metadata.profileFragment = shortHash(d.metadata.ownerIdent or "")
      MySQL.update.await("UPDATE tp_evidence_drops SET metadata = ? WHERE id = ?", { json.encode(d.metadata), dropId })
      TriggerClientEvent("tp_evidence:dropUpdated", -1, { id = dropId, metadata = d.metadata })
      TriggerClientEvent("tp_evidence:cleanupResult", src, true, "You wiped it down, but some evidence still remains.")
      return
    else
      TriggerClientEvent("tp_evidence:cleanupResult", src, false, "You wiped it down, but didn't remove anything.")
      return
    end
  end
end)


-- UI: open + data
RegisterNetEvent("tp_evidence:uiRequest", function(reqId, action, payload)
  local src = source
  if not IsAceAllowed(src, Config.AcePermission) then
    TriggerClientEvent("tp_evidence:uiResponse", src, reqId, false, nil, "Not authorized.")
    return
  end

  local ped = GetPlayerPed(src)
  local coords = GetEntityCoords(ped)
  local inLab, labLabel = isInLab(coords)

  local ident = getIdentifier(src)
  local name  = getDisplayName(src)

  if action == "bags" then
    local rows = MySQL.query.await([[
      SELECT id, drop_type, data, collected_at, analyzed_at, analyzed_by, collected_by
      FROM tp_evidence_bags
      WHERE owner_identifier = ?
      ORDER BY id DESC
      LIMIT 250
    ]], { ident })

    local out = {}
    for _, r in ipairs(rows or {}) do
      local data = r.data and json.decode(r.data) or {}
      out[#out+1] = {
        id = r.id,
        type = r.drop_type,
        collected_at = r.collected_at,
        collected_by = r.collected_by,
        analyzed_at = r.analyzed_at,
        analyzed_by = r.analyzed_by,
        summary = {
          weapon = data.meta and data.meta.weaponLabel or nil,
          caliber = data.meta and data.meta.caliber or nil,
          rainWashed = data.meta and data.meta.rainWashed or false,
        }
      }
    end

    TriggerClientEvent("tp_evidence:uiResponse", src, reqId, true, { bags = out, inLab = inLab, labLabel = labLabel }, nil)
    return
  end

  if action == "view" or action == "analyze" or action == "delete" then
    if Config.RequireOnDuty and not hasPerm(src) then
      TriggerClientEvent("tp_evidence:uiResponse", src, reqId, false, nil, "You must be on duty.")
      return
    end

    local bagId = tonumber(payload and payload.bagId)
    if not bagId then
      TriggerClientEvent("tp_evidence:uiResponse", src, reqId, false, nil, "Invalid bag.")
      return
    end

    local row = MySQL.single.await([[
      SELECT id, drop_type, data, collected_at, collected_by, analyzed_at, analyzed_by
      FROM tp_evidence_bags
      WHERE id = ? AND owner_identifier = ?
    ]], { bagId, ident })

    if not row then
      TriggerClientEvent("tp_evidence:uiResponse", src, reqId, false, nil, "Bag not found.")
      return
    end

    local data = row.data and json.decode(row.data) or {}

    if action == "view" then
      TriggerClientEvent("tp_evidence:uiResponse", src, reqId, true, { bag = data, inLab = inLab, labLabel = labLabel }, nil)
      return
    end

    if action == "analyze" then
      -- If evidence was partially cleaned, redact identifying fields and provide a fragment + confidence.
      if data.meta and data.meta.partial then
        data.meta.profileFragment = data.meta.profileFragment or shortHash(data.meta.ownerIdent or "")
        local q = tonumber(data.meta.quality) or 50
        data.meta.matchConfidence = math.max(5, math.min(95, q))
        data.meta.ownerIdent = nil
        data.meta.ownerName = nil
        data.meta.ownerChatName = nil
      end

      if not inLab then
        TriggerClientEvent("tp_evidence:uiResponse", src, reqId, false, nil, "Analyze requires being inside a lab.")
        return
      end

      MySQL.update.await([[
        UPDATE tp_evidence_bags
        SET analyzed_at = CURRENT_TIMESTAMP, analyzed_by = ?
        WHERE id = ? AND owner_identifier = ?
      ]], { name, bagId, ident })

      data.analysis = data.analysis or {}
      data.analysis.analyzedBy = name
      data.analysis.analyzedAt = os.time()

      TriggerClientEvent("tp_evidence:uiResponse", src, reqId, true, { bag = data, inLab = true, labLabel = labLabel }, nil)
      return
    end

    if action == "delete" then
      if not inLab then
        TriggerClientEvent("tp_evidence:uiResponse", src, reqId, false, nil, "Delete requires being inside a lab.")
        return
      end

      MySQL.update.await("DELETE FROM tp_evidence_bags WHERE id = ? AND owner_identifier = ?", { bagId, ident })
      TriggerClientEvent("tp_evidence:uiResponse", src, reqId, true, { ok = true, inLab = true, labLabel = labLabel }, nil)
      return
    end
  end

  TriggerClientEvent("tp_evidence:uiResponse", src, reqId, false, nil, "Unknown action.")
end)
