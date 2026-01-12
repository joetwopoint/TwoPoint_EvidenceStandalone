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

local function getChatName(src)
  local res = Config.BigDaddyChatResource
  if res and resStarted(res) then
    local ok, name = pcall(function()
      return exports[res]:getPlayerName(src)
    end)
    if ok and type(name) == "string" and name ~= "" and not name:lower():find("change your name") then
      return name
    end
  end
  return GetPlayerName(src) or ("Player " .. tostring(src))
end

local function isPoliceAllowed(src)
  local node = Config.AceNode or (Config.AceNodes and Config.AceNodes.police)
  if node and not IsPlayerAceAllowed(src, node) then return false end
  if not Config.RequireOnDuty then return true end

  local dutyRes = Config.DutyResource
  if dutyRes and resStarted(dutyRes) then
    local ok, onDuty = pcall(function()
      return exports[dutyRes]:IsOnDuty(src)
    end)
    return ok and onDuty == true
  end
  return true
end

local function getLabAtCoords(coords)
  if not Config.Labs then return nil end
  for _, lab in ipairs(Config.Labs) do
    if lab.enabled == false then
      goto continue
    end
    local c = lab.coords
    local dx = coords.x - c.x
    local dy = coords.y - c.y
    local dz = coords.z - c.z
    local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
    if dist <= (lab.radius or 25.0) then
      return lab.label or "Lab"
    end
    ::continue::
  end
  return nil
end

local function isInLab(src)
  local ped = GetPlayerPed(src)
  if ped == 0 then return false end
  local coords = GetEntityCoords(ped)
  return getLabAtCoords(coords) ~= nil
end

local function isLabAllowed(src)
  return isPoliceAllowed(src) and isInLab(src)
end


-- SQL setup
MySQL.query.await([[
CREATE TABLE IF NOT EXISTS tp_evidence_profiles (
  identifier VARCHAR(64) PRIMARY KEY NOT NULL,
  character_name VARCHAR(128) NOT NULL,
  fingerprint VARCHAR(16) UNIQUE NOT NULL,
  dna VARCHAR(16) UNIQUE NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
)
]])

MySQL.query.await([[
CREATE TABLE IF NOT EXISTS tp_evidence_world (
  id INT AUTO_INCREMENT PRIMARY KEY,
  evidence_type VARCHAR(32) NOT NULL,
  owner_identifier VARCHAR(64) NOT NULL,
  owner_name VARCHAR(128) NOT NULL,
  fingerprint VARCHAR(16) NOT NULL,
  dna VARCHAR(16) NOT NULL,
  weapon VARCHAR(64) NULL,
  serial VARCHAR(32) NULL,
  note TEXT NULL,
  x DOUBLE NOT NULL,
  y DOUBLE NOT NULL,
  z DOUBLE NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  expires_at TIMESTAMP NULL DEFAULT NULL,
  INDEX(owner_identifier),
  INDEX(evidence_type),
  INDEX(created_at),
  INDEX(expires_at)
)
]])

-- Add expires_at to existing installs (safe to ignore failures)
pcall(function()
  MySQL.query.await("ALTER TABLE tp_evidence_world ADD COLUMN expires_at TIMESTAMP NULL DEFAULT NULL")
end)
pcall(function()
  MySQL.query.await("ALTER TABLE tp_evidence_world ADD INDEX(expires_at)")
end)

MySQL.query.await([[
CREATE TABLE IF NOT EXISTS tp_evidence_bags (
  id INT AUTO_INCREMENT PRIMARY KEY,
  bag_label VARCHAR(64) NOT NULL,
  collector_identifier VARCHAR(64) NOT NULL,
  collector_name VARCHAR(128) NOT NULL,
  evidence_type VARCHAR(32) NOT NULL,
  owner_identifier VARCHAR(64) NOT NULL,
  owner_name VARCHAR(128) NOT NULL,
  fingerprint VARCHAR(16) NOT NULL,
  dna VARCHAR(16) NOT NULL,
  weapon VARCHAR(64) NULL,
  serial VARCHAR(32) NULL,
  note TEXT NULL,
  x DOUBLE NOT NULL,
  y DOUBLE NOT NULL,
  z DOUBLE NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  collected_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX(collector_identifier),
  INDEX(owner_identifier),
  INDEX(evidence_type),
  INDEX(collected_at)
)
]])

local function randomFingerprint()
  local a = ("fp_%s_%s"):format(GetGameTimer(), math.random(1, 1e9))
  local h1 = joaat(a .. "_1")
  local h2 = joaat(a .. "_2")
  local fp = tostring(h1):sub(1, 8) .. tostring(h2):sub(1, 8)
  return fp:sub(1, 16)
end

local function randomDNA()
  local bases = { "A", "T", "G", "C" }
  local s = {}
  for i=1,16 do
    s[i] = bases[math.random(1, #bases)]
  end
  return table.concat(s)
end

local function ensureProfile(src)
  local identifier = getIdentifier(src)
  local name = getChatName(src)

  local row = MySQL.single.await("SELECT identifier, character_name, fingerprint, dna FROM tp_evidence_profiles WHERE identifier = ?", {identifier})
  if row then
    if row.character_name ~= name then
      MySQL.update("UPDATE tp_evidence_profiles SET character_name = ? WHERE identifier = ?", {name, identifier})
      row.character_name = name
    end
    return row
  end

  local fp, dna = randomFingerprint(), randomDNA()
  MySQL.insert.await("INSERT INTO tp_evidence_profiles (identifier, character_name, fingerprint, dna) VALUES (?, ?, ?, ?)", {identifier, name, fp, dna})
  dbg("created profile", identifier, name, fp, dna)

  return { identifier = identifier, character_name = name, fingerprint = fp, dna = dna }
end

local function updateProfileName(src, newName)
  if not newName or newName:gsub("%s+", "") == "" then return end
  local identifier = getIdentifier(src)
  MySQL.update([[
    INSERT INTO tp_evidence_profiles (identifier, character_name, fingerprint, dna)
    VALUES (?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE character_name = VALUES(character_name)
  ]], {identifier, newName, randomFingerprint(), randomDNA()})
end

-- Best-effort: catch /chatname changes
AddEventHandler("chatMessage", function(src, _, msg)
  if type(msg) ~= "string" then return end
  local cmd = "/" .. tostring(Config.ChatnameCommand or "chatname")
  if msg:sub(1, #cmd):lower() == cmd:lower() then
    local newName = msg:sub(#cmd + 2)
    updateProfileName(src, newName)
  end
end)

AddEventHandler("playerJoining", function()
  ensureProfile(source)
end)

-- Poll BigDaddy chat export periodically (fallback)
CreateThread(function()
  while true do
    Wait((Config.NamePollSeconds or 30) * 1000)
    if not (Config.BigDaddyChatResource and resStarted(Config.BigDaddyChatResource)) then
      goto continue
    end
    for _, sid in ipairs(GetPlayers()) do
      local src = tonumber(sid)
      if src then
        local identifier = getIdentifier(src)
        local name = getChatName(src)
        local row = MySQL.single.await("SELECT character_name FROM tp_evidence_profiles WHERE identifier = ?", {identifier})
        if row and row.character_name ~= name then
          MySQL.update("UPDATE tp_evidence_profiles SET character_name = ? WHERE identifier = ?", {name, identifier})
        end
      end
    end
    ::continue::
  end
end)

-- World evidence cache for scanner
local worldCache = {}

local function broadcastWorldEvidence()
  TriggerClientEvent("tp_evidence:worldSnapshot", -1, worldCache)
end

local function rebuildCache()
  worldCache = {}
  local rows = MySQL.query.await([[
    SELECT id, evidence_type, owner_name, x, y, z,
           UNIX_TIMESTAMP(created_at) AS created_ts,
           UNIX_TIMESTAMP(expires_at) AS expires_ts
    FROM tp_evidence_world
    WHERE (expires_at IS NOT NULL AND expires_at >= NOW())
       OR (expires_at IS NULL AND created_at >= (NOW() - INTERVAL ? MINUTE))
  ]], { Config.WorldEvidenceTTLMinutes or 180 })

  for _, r in ipairs(rows or {}) do
    worldCache[r.id] = {
      id = r.id,
      evidence_type = r.evidence_type,
      owner_name = r.owner_name,
      x = r.x, y = r.y, z = r.z,
      created_ts = r.created_ts,
      expires_ts = r.expires_ts
    }
  end
end

rebuildCache()

-- Cleanup old evidence
CreateThread(function()
  while true do
    Wait(5 * 60 * 1000)
    local ttl = Config.WorldEvidenceTTLMinutes or 180
    MySQL.update([[
      DELETE FROM tp_evidence_world
      WHERE (expires_at IS NOT NULL AND expires_at < NOW())
         OR (expires_at IS NULL AND created_at < (NOW() - INTERVAL ? MINUTE))
    ]], {ttl})
    rebuildCache()
    broadcastWorldEvidence()
  end
end)

-- Evidence drops from clients
RegisterNetEvent("tp_evidence:dropEvidence", function(payload)
  local src = source
  if type(payload) ~= "table" then return end

  local profile = ensureProfile(src)
  local evType = tostring(payload.evidence_type or "UNKNOWN"):upper()
  local x, y, z = payload.x, payload.y, payload.z
  if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then return end

  local weapon = payload.weapon and tostring(payload.weapon) or nil
  local serial = payload.serial and tostring(payload.serial) or nil
  local note = payload.note and tostring(payload.note) or nil

  local ttl = tonumber(payload.ttl_minutes) or (Config.WorldEvidenceTTLMinutes or 180)
  ttl = math.floor(ttl)
  if ttl < 5 then ttl = 5 end
  if ttl > 10080 then ttl = 10080 end -- clamp to 7 days

  local id = MySQL.insert.await([[
    INSERT INTO tp_evidence_world
      (evidence_type, owner_identifier, owner_name, fingerprint, dna, weapon, serial, note, x, y, z, expires_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL ? MINUTE))
  ]], { evType, profile.identifier, profile.character_name, profile.fingerprint, profile.dna, weapon, serial, note, x, y, z, ttl })

  worldCache[id] = { id = id, evidence_type = evType, owner_name = profile.character_name, x = x, y = y, z = z, created_ts = os.time(), expires_ts = os.time() + (ttl * 60) }
  broadcastWorldEvidence()
end)

RegisterNetEvent("tp_evidence:requestSnapshot", function()
  TriggerClientEvent("tp_evidence:worldSnapshot", source, worldCache)
end)

local function chatMsg(src, msg)
  TriggerClientEvent("chat:addMessage", src, { args = { "^3[Evidence]^7", msg } })
end

RegisterNetEvent("tp_evidence:collect", function(worldEvidenceId)
  local src = source
  if not isPoliceAllowed(src) then
    TriggerClientEvent("tp_evidence:notify", src, "Not allowed (permissions or duty).")
    return
  end

  worldEvidenceId = tonumber(worldEvidenceId)
  if not worldEvidenceId then return end

  local row = MySQL.single.await([[
    SELECT id, evidence_type, owner_identifier, owner_name, fingerprint, dna, weapon, serial, note, x, y, z, UNIX_TIMESTAMP(created_at) AS created_ts
    FROM tp_evidence_world
    WHERE id = ?
  ]], { worldEvidenceId })

  if not row then
    TriggerClientEvent("tp_evidence:notify", src, "Evidence not found.")
    worldCache[worldEvidenceId] = nil
    broadcastWorldEvidence()
    return
  end

  local collector = ensureProfile(src)
  local bagLabel = ("EV-%06d"):format(worldEvidenceId)

  MySQL.insert.await([[
    INSERT INTO tp_evidence_bags
      (bag_label, collector_identifier, collector_name, evidence_type, owner_identifier, owner_name, fingerprint, dna, weapon, serial, note, x, y, z, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, FROM_UNIXTIME(?))
  ]], {
    bagLabel, collector.identifier, collector.character_name,
    row.evidence_type, row.owner_identifier, row.owner_name,
    row.fingerprint, row.dna, row.weapon, row.serial, row.note,
    row.x, row.y, row.z,
    row.created_ts or os.time()
  })

  MySQL.update("DELETE FROM tp_evidence_world WHERE id = ?", {worldEvidenceId})

  worldCache[worldEvidenceId] = nil
  broadcastWorldEvidence()
  TriggerClientEvent("tp_evidence:notify", src, ("Collected %s (%s)"):format(bagLabel, row.evidence_type))
end)

-- /evidence -> list
RegisterCommand(Config.Commands.list or "evidence", function(src)
  if src == 0 then return end
  if not isPoliceAllowed(src) then
    chatMsg(src, "Not allowed (permissions or duty).")
    return
  end
  local collectorId = getIdentifier(src)

  local rows = MySQL.query.await([[
    SELECT id, bag_label, evidence_type, owner_name, collected_at
    FROM tp_evidence_bags
    WHERE collector_identifier = ?
    ORDER BY collected_at DESC
    LIMIT 50
  ]], { collectorId })

  if not rows or #rows == 0 then
    chatMsg(src, "No collected evidence.")
    return
  end

  chatMsg(src, ("Collected evidence (%d):"):format(#rows))
  for _, r in ipairs(rows) do
    chatMsg(src, ("%s | BagID:%d | %s | Owner: %s"):format(r.bag_label, r.id, r.evidence_type, r.owner_name))
  end
  chatMsg(src, ("Use /%s <BagID> to view."):format(Config.Commands.view or "evidenceview"))
end, false)

-- /evidenceview <bagId>
RegisterCommand(Config.Commands.view or "evidenceview", function(src, args)
  if src == 0 then return end
  if not isPoliceAllowed(src) then
    chatMsg(src, "Not allowed (permissions or duty).")
    return
  end
  local bagId = tonumber(args[1])
  if not bagId then
    chatMsg(src, "Usage: /evidenceview <BagID>")
    return
  end

  local row = MySQL.single.await([[
    SELECT bag_label, evidence_type, owner_name, weapon, serial, note, x, y, z, created_at, collected_at
    FROM tp_evidence_bags
    WHERE id = ?
  ]], { bagId })

  if not row then
    chatMsg(src, "Bag not found.")
    return
  end

  chatMsg(src, ("Bag %s (%s)"):format(row.bag_label, row.evidence_type))
  chatMsg(src, ("Collected: %s"):format(row.collected_at))
  chatMsg(src, ("Crime Scene: %.2f, %.2f, %.2f"):format(row.x, row.y, row.z))
  if row.weapon then chatMsg(src, ("Weapon: %s"):format(row.weapon)) end
  if row.serial then chatMsg(src, ("Serial: %s"):format(row.serial)) end
  if row.note then chatMsg(src, ("Note: %s"):format(row.note)) end
  chatMsg(src, ("Use /%s <BagID> for full lab analysis (lab perms)."):format(Config.Commands.analyze or "evidenceanalyze"))
end, false)

-- /evidenceanalyze <bagId> (lab)
RegisterCommand(Config.Commands.analyze or "evidenceanalyze", function(src, args)
  if src == 0 then return end
  if not isLabAllowed(src) then
    chatMsg(src, "Not allowed (lab permission + duty).")
    return
  end
  local bagId = tonumber(args[1])
  if not bagId then
    chatMsg(src, "Usage: /evidenceanalyze <BagID>")
    return
  end

  local row = MySQL.single.await([[
    SELECT bag_label, evidence_type, owner_identifier, owner_name, fingerprint, dna, weapon, serial, note, x, y, z, created_at, collected_at
    FROM tp_evidence_bags
    WHERE id = ?
  ]], { bagId })

  if not row then
    chatMsg(src, "Bag not found.")
    return
  end

  chatMsg(src, ("LAB ANALYSIS: %s (%s)"):format(row.bag_label, row.evidence_type))
  chatMsg(src, ("Owner: %s"):format(row.owner_name))
  chatMsg(src, ("Fingerprint: %s | DNA: %s"):format(row.fingerprint, row.dna))
  if row.weapon then chatMsg(src, ("Weapon: %s"):format(row.weapon)) end
  if row.serial then chatMsg(src, ("Serial: %s"):format(row.serial)) end

  -- Also show identifier match for admin-level review
  chatMsg(src, ("Owner Identifier: %s"):format(row.owner_identifier))
end, false)

-- /evidencedelete <bagId> (lab)
RegisterCommand(Config.Commands.delete or "evidencedelete", function(src, args)
  if src == 0 then return end
  if not isLabAllowed(src) then
    chatMsg(src, "Not allowed (lab permission + duty).")
    return
  end
  local bagId = tonumber(args[1])
  if not bagId then
    chatMsg(src, "Usage: /evidencedelete <BagID>")
    return
  end

  local affected = MySQL.update.await("DELETE FROM tp_evidence_bags WHERE id = ?", { bagId })
  chatMsg(src, affected > 0 and ("Deleted bag %d"):format(bagId) or "Bag not found.")
end, false)


-- NUI / UI API (client -> server -> client)
RegisterNetEvent("tp_evidence:uiRequest", function(reqId, action, payload)
  local src = source
  if src == 0 then return end
  if not isPoliceAllowed(src) then
    TriggerClientEvent("tp_evidence:uiResponse", src, reqId, false, nil, "Not allowed (permissions or duty).")
    return
  end

  payload = payload or {}
  if action == "list" then
    local collectorId = getIdentifier(src)
    local rows = MySQL.query.await([[
      SELECT id, bag_label, evidence_type, owner_name, UNIX_TIMESTAMP(collected_at) AS collected_ts
      FROM tp_evidence_bags
      WHERE collector_identifier = ?
      ORDER BY id DESC
      LIMIT 250
    ]], { collectorId }) or {}
    TriggerClientEvent("tp_evidence:uiResponse", src, reqId, true, { bags = rows, inLab = isInLab(src) }, nil)
    return
  end

  local bagId = tonumber(payload.id)
  if not bagId then
    TriggerClientEvent("tp_evidence:uiResponse", src, reqId, false, nil, "Invalid bag id.")
    return
  end

  if action == "view" then
    local row = MySQL.single.await([[
      SELECT bag_label, evidence_type, owner_name, weapon, serial, note, x, y, z, created_at, collected_at
      FROM tp_evidence_bags
      WHERE id = ?
    ]], { bagId })
    if not row then
      TriggerClientEvent("tp_evidence:uiResponse", src, reqId, false, nil, "Bag not found.")
      return
    end
    TriggerClientEvent("tp_evidence:uiResponse", src, reqId, true, { data = row, inLab = isInLab(src) }, nil)
    return
  end

  if action == "analyze" then
    if not isLabAllowed(src) then
      TriggerClientEvent("tp_evidence:uiResponse", src, reqId, false, nil, "Analyze requires being inside a lab.")
      return
    end
    local row = MySQL.single.await([[
      SELECT bag_label, evidence_type, owner_identifier, owner_name, fingerprint, dna, weapon, serial, note, x, y, z, created_at, collected_at
      FROM tp_evidence_bags
      WHERE id = ?
    ]], { bagId })
    if not row then
      TriggerClientEvent("tp_evidence:uiResponse", src, reqId, false, nil, "Bag not found.")
      return
    end
    TriggerClientEvent("tp_evidence:uiResponse", src, reqId, true, { data = row, inLab = true }, nil)
    return
  end

  if action == "delete" then
    if not isLabAllowed(src) then
      TriggerClientEvent("tp_evidence:uiResponse", src, reqId, false, nil, "Delete requires being inside a lab.")
      return
    end
    MySQL.update.await("DELETE FROM tp_evidence_bags WHERE id = ?", { bagId })
    TriggerClientEvent("tp_evidence:uiResponse", src, reqId, true, { ok = true, inLab = true }, nil)
    return
  end

  TriggerClientEvent("tp_evidence:uiResponse", src, reqId, false, nil, "Unknown action.")
end)
