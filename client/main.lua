local drops = {} -- id -> drop
local scannerOn = false
local uiOpen = false
local inspectOn = false
local ownedDrops = {} -- id -> true (from server inspect response)
local lastInspectReq = 0

local lastShotAt = 0
local lastBloodAt = 0
local lastVehAt = 0
local lastUiLabCheck = 0

local function dbg(...)
  if Config.Debug then
    print("[TwoPoint_Evidence][Client]", ...)
  end
end


local function notify(msg)
  BeginTextCommandThefeedPost("STRING")
  AddTextComponentSubstringPlayerName(msg)
  EndTextCommandThefeedPostTicker(false, false)
end

local function drawTxt(x, y, scale, text)
  SetTextFont(4)
  SetTextProportional(0)
  SetTextScale(scale, scale)
  SetTextColour(255, 255, 255, 215)
  SetTextDropshadow(0, 0, 0, 0, 255)
  SetTextEdge(1, 0, 0, 0, 255)
  SetTextDropShadow()
  SetTextOutline()
  BeginTextCommandDisplayText("STRING")
  AddTextComponentSubstringPlayerName(text)
  EndTextCommandDisplayText(x, y)
end

local KEY_POOL = {
  { label = "W", control = 32 },
  { label = "A", control = 34 },
  { label = "S", control = 33 },
  { label = "D", control = 35 },
}

local function randomSequence(n)
  local seq = {}
  for i=1, n do
    seq[i] = KEY_POOL[math.random(1, #KEY_POOL)]
  end
  return seq
end

local function seqToString(seq, idx)
  local out = {}
  for i=idx, #seq do
    out[#out+1] = seq[i].label
  end
  return table.concat(out, " ")
end

local function runSequenceMinigame(nKeys, totalTime, title)
  nKeys = tonumber(nKeys) or 3
  totalTime = tonumber(totalTime) or 4.0
  title = title or "MINIGAME"

  local seq = randomSequence(nKeys)
  local i = 1
  local start = GetGameTimer()
  local endAt = start + math.floor(totalTime * 1000)

  while GetGameTimer() < endAt do
    Wait(0)

    local remaining = (endAt - GetGameTimer()) / 1000.0
    drawTxt(0.5 - 0.2, 0.85, 0.45, ("~b~%s~s~  Time: ~y~%.1fs~s~"):format(title, remaining))
    drawTxt(0.5 - 0.2, 0.89, 0.55, ("Press: ~g~%s~s~"):format(seqToString(seq, i)))

    -- accept the expected key
    if IsControlJustPressed(0, seq[i].control) then
      i = i + 1
      if i > #seq then
        return true
      end
    end
  end

  return false
end

local function hasAce()
  return IsAceAllowed(Config.AcePermission)
end

local function isOnDuty()
  if not Config.RequireOnDuty then return true end
  -- Uses the PoliceEMSActivity state bag set by the patched resource:
  -- LocalPlayer.state.pea_onDuty = true/false
  return LocalPlayer and LocalPlayer.state and LocalPlayer.state.pea_onDuty == true
end

local function canUse()
  if not hasAce() then return false end
  if Config.RequireOnDuty and not isOnDuty() then return false end
  return true
end

local function isRaining()
  return GetRainLevel()
end

local function vec3From(t)
  return vector3(t.x, t.y, t.z)
end


RegisterNetEvent("tp_evidence:dropUpdated", function(payload)
  if not payload or not payload.id then return end
  local d = drops[payload.id]
  if d then
    d.metadata = payload.metadata or d.metadata
  end
end)

RegisterNetEvent("tp_evidence:inspectResponse", function(reqId, ok, data, err)
  if not ok then
    if err then notify("~r~Inspect: " .. tostring(err)) end
    return
  end
  ownedDrops = {}
  if data and data.drops then
    for _, d in ipairs(data.drops) do
      ownedDrops[d.id] = true
      -- keep metadata up-to-date locally as well
      if drops[d.id] then
        drops[d.id].metadata = d.metadata
      end
    end
  end
end)

RegisterNetEvent("tp_evidence:cleanupResult", function(ok, msg)
  if ok then
    notify("~g~" .. tostring(msg or "Cleanup succeeded."))
  else
    notify("~r~" .. tostring(msg or "Cleanup failed."))
  end
end)

RegisterNetEvent("tp_evidence:dropsSnapshot", function(arr)
  drops = {}
  for _, d in ipairs(arr or {}) do
    drops[d.id] = {
      id = d.id,
      type = d.type,
      coords = vector3(d.x, d.y, d.z),
      meta = d.metadata or {},
      expiresAt = d.expiresAt
    }
  end
end)

RegisterNetEvent("tp_evidence:dropAdded", function(d)
  drops[d.id] = {
    id = d.id,
    type = d.type,
    coords = vector3(d.x, d.y, d.z),
    meta = d.metadata or {},
    expiresAt = d.expiresAt
  }
end)

RegisterNetEvent("tp_evidence:dropRemoved", function(id)
  drops[id] = nil
end)

RegisterNetEvent("tp_evidence:dropRemovedMany", function(ids)
  for _, id in ipairs(ids or {}) do
    drops[id] = nil
  end
end)

-- Wiretap alerts pushed from server (only when matched)
RegisterNetEvent("tp_evidence:wiretapAlert", function(payload)
  if not payload then return end
  -- If UI is open, forward to NUI
  if uiOpen then
    SendNUIMessage({ type = "wiretapAlert", payload = payload })
  else
    -- Light in-chat notify
    TriggerEvent('chat:addMessage', { args = { "^3Wiretap", ("Call %s (numbers: %s)"):format(payload.stage or "update", table.concat(payload.numbers or {}, ", ")) } })
  end
end)

-- Refresh wiretap UI state (used when wiretap targets are changed via chat commands).
RegisterNetEvent("tp_evidence:wiretapRefresh", function()
  if uiOpen then
    SendNUIMessage({ type = "wiretapRefresh" })
  end
end)

-- Commands
RegisterCommand(Config.ScannerCommand, function()
  if not canUse() then
    TriggerEvent('chat:addMessage', { args = { "^1Forensics", "Not authorized or not on duty." } })
    return
  end
  scannerOn = not scannerOn
  if scannerOn then
    TriggerServerEvent("tp_evidence:requestDrops")
  end
  TriggerEvent('chat:addMessage', { args = { "^3Forensics", scannerOn and "Scanner ON" or "Scanner OFF" } })
end, false)

RegisterCommand(Config.OpenUICommand, function()
  if not hasAce() then
    TriggerEvent('chat:addMessage', { args = { "^1Forensics", "Not authorized." } })
    return
  end
  uiOpen = true
  SetNuiFocus(true, true)
  SendNUIMessage({ type = "open" })
end, false)

RegisterNUICallback("close", function(_, cb)
  uiOpen = false
  SetNuiFocus(false, false)
  cb({})
end)

-- Evidence UI data requests routed via server events (so we can enforce lab/duty on server)
local reqId = 0
local pending = {}

local function sendUiRequest(action, payload)
  reqId = reqId + 1
  local id = reqId
  pending[id] = true
  TriggerServerEvent("tp_evidence:uiRequest", id, action, payload or {})
end

RegisterNetEvent("tp_evidence:uiResponse", function(id, ok, data, err)
  if not pending[id] then return end
  pending[id] = nil
  SendNUIMessage({ type = "uiResponse", id = id, ok = ok, data = data, err = err })
end)

RegisterNUICallback("bags", function(_, cb)
  sendUiRequest("bags", {})
  cb({ ok = true, reqId = reqId })
end)

RegisterNUICallback("viewBag", function(body, cb)
  sendUiRequest("view", { bagId = body and body.bagId })
  cb({ ok = true, reqId = reqId })
end)

RegisterNUICallback("analyzeBag", function(body, cb)
  sendUiRequest("analyze", { bagId = body and body.bagId })
  cb({ ok = true, reqId = reqId })
end)

RegisterNUICallback("deleteBag", function(body, cb)
  sendUiRequest("delete", { bagId = body and body.bagId })
  cb({ ok = true, reqId = reqId })
end)

-- Wiretap UI
local wReqId = 0
local wPending = {}

local function sendWiretap(action, payload)
  wReqId = wReqId + 1
  local id = wReqId
  wPending[id] = true
  TriggerServerEvent("tp_evidence:wiretapUi", id, action, payload or {})
end

RegisterNetEvent("tp_evidence:wiretapUiResp", function(id, ok, data, err)
  if not wPending[id] then return end
  wPending[id] = nil
  SendNUIMessage({ type = "wiretapResp", id = id, ok = ok, data = data, err = err })
end)

RegisterNUICallback("wiretapState", function(_, cb)
  sendWiretap("state", {})
  cb({ ok = true, reqId = wReqId })
end)

RegisterNUICallback("wiretapAdd", function(body, cb)
  sendWiretap("add", { number = body and body.number, label = body and body.label })
  cb({ ok = true, reqId = wReqId })
end)

RegisterNUICallback("wiretapRemove", function(body, cb)
  sendWiretap("remove", { number = body and body.number })
  cb({ ok = true, reqId = wReqId })
end)

-- Lab pill updates (client-side distance check)
local function inLab()
  local ped = PlayerPedId()
  local p = GetEntityCoords(ped)
  local bestLabel = nil
  for _, lab in ipairs(Config.Labs) do
    if lab.enabled ~= false then
      local dist = #(p - lab.coords)
      if dist <= (lab.radius or 25.0) then
        bestLabel = lab.label
        break
      end
    end
  end
  return bestLabel ~= nil, bestLabel
end

CreateThread(function()
  while true do
    Wait(500)
    if uiOpen then
      local inside, label = inLab()
      SendNUIMessage({ type = "labPill", inLab = inside, label = label or "" })
    end
  end
end)

-- Inspect mode (civilian cleanup)
local inspectReqId = 0
CreateThread(function()
  while true do
    if not inspectOn then
      Wait(800)
    else
      -- refresh list of your nearby drops periodically
      Wait(2000)
      local ped = PlayerPedId()
      local p = GetEntityCoords(ped)
      inspectReqId = inspectReqId + 1
      TriggerServerEvent("tp_evidence:inspectRequest", inspectReqId, Config.InspectRadius or 25.0, { x = p.x, y = p.y, z = p.z })
    end
  end
end)

CreateThread(function()
  while true do
    if not inspectOn then
      Wait(400)
    else
      Wait(0)
      local ped = PlayerPedId()
      local p = GetEntityCoords(ped)
      local nearest, nearestDist

      for id, _ in pairs(ownedDrops) do
        local d = drops[id]
        if d and d.coords then
          local dist = #(p - d.coords)
          if dist <= (Config.DrawDistance or 40.0) then
            -- slightly different marker so players can spot their evidence
            DrawMarker(2, d.coords.x, d.coords.y, d.coords.z + 0.15, 0.0,0.0,0.0, 0.0,0.0,0.0, 0.18, 0.18, 0.18, 255, 50, 50, 160, false, false, 2, nil, nil, false)
            if dist <= 2.0 and (not nearestDist or dist < nearestDist) then
              nearest = id
              nearestDist = dist
            end
          end
        end
      end

      if nearest then
        -- E = quick wipe (easy)
        if IsControlJustPressed(0, Config.CollectKey or 38) then
          local ok = runSequenceMinigame((Config.Minigame and Config.Minigame.CleanupEasy and Config.Minigame.CleanupEasy.keys) or 3, (Config.Minigame and Config.Minigame.CleanupEasy and Config.Minigame.CleanupEasy.totalTime) or 4.5, "WIPE")
          TriggerServerEvent("tp_evidence:attemptCleanup", nearest, "partial", ok)
        end

        -- H = thorough clean (hard)
        if IsControlJustPressed(0, 74) then
          local ok = runSequenceMinigame((Config.Minigame and Config.Minigame.CleanupHard and Config.Minigame.CleanupHard.keys) or 6, (Config.Minigame and Config.Minigame.CleanupHard and Config.Minigame.CleanupHard.totalTime) or 5.0, "CLEAN")
          TriggerServerEvent("tp_evidence:attemptCleanup", nearest, "full", ok)
        end
      end
    end
  end
end)

-- Blips
CreateThread(function()
  Wait(2000)
  if not (Config.Blips and Config.Blips.Enabled) then return end
  if (not Config.Blips.ShowToAll) and (not hasAce()) then return end

  for _, lab in ipairs(Config.Labs) do
    if lab.enabled ~= false then
      local blip = AddBlipForCoord(lab.coords.x, lab.coords.y, lab.coords.z)
      SetBlipSprite(blip, Config.Blips.Sprite or 361)
      SetBlipColour(blip, Config.Blips.Color or 3)
      SetBlipScale(blip, Config.Blips.Scale or 0.75)
      SetBlipAsShortRange(blip, Config.Blips.ShortRange ~= false)
      BeginTextCommandSetBlipName("STRING")
      AddTextComponentString((Config.Blips.LabelPrefix or "Forensics Lab: ") .. (lab.label or "Lab"))
      EndTextCommandSetBlipName(blip)
    end
  end
end)

-- Scanner draw + collect
CreateThread(function()
  while true do
    if not scannerOn then
      Wait(400)
    else
      Wait(0)
      local ped = PlayerPedId()
      local p = GetEntityCoords(ped)
      local nearest, nearestDist
      for id, d in pairs(drops) do
        local dist = #(p - d.coords)
        if dist <= (Config.DrawDistance or 40.0) then
          DrawMarker(Config.Marker.type or 20, d.coords.x, d.coords.y, d.coords.z + 0.25, 0.0,0.0,0.0, 0.0,0.0,0.0, Config.Marker.scale or 0.2, Config.Marker.scale or 0.2, Config.Marker.scale or 0.2, 255, 255, 255, 180, false, false, 2, nil, nil, false)
          if dist <= (Config.CollectDistance or 2.0) and (not nearestDist or dist < nearestDist) then
            nearest = id
            nearestDist = dist
          end
        end
      end

      if nearest and IsControlJustPressed(0, Config.CollectKey or 38) then
        local ok = runSequenceMinigame((Config.Minigame and Config.Minigame.Collect and Config.Minigame.Collect.keys) or 2, (Config.Minigame and Config.Minigame.Collect and Config.Minigame.Collect.totalTime) or 4.0, "COLLECT")
        local q = ok and 100 or 60
        TriggerServerEvent("tp_evidence:collectDrop", nearest, q)
      end
    end
  end
end)

-- Evidence generation
local function isSilenced(ped)
  return IsPedCurrentWeaponSilenced(ped)
end

local function randChance(p)
  return math.random() < p
end

local function weaponLabel(hash)
  return ("0x%X"):format(hash)
end

local function guessCaliber(hash)
  -- lightweight heuristic (you can expand later)
  return "Unknown"
end

local function hasGloves(ped)
  if not (Config.GloveCheck and Config.GloveCheck.Enabled) then
    return true
  end
  local arms = GetPedDrawableVariation(ped, 3)
  local model = GetEntityModel(ped)
  local freemodeMale = GetHashKey("mp_m_freemode_01")
  local freemodeFemale = GetHashKey("mp_f_freemode_01")

  local list = Config.GloveCheck.MaleNoGloves
  if model == freemodeFemale then list = Config.GloveCheck.FemaleNoGloves end
  for _, v in ipairs(list or {}) do
    if arms == v then
      return false
    end
  end
  return true
end

CreateThread(function()
  math.randomseed(GetGameTimer() % 2147483647)

  local lastHealth = GetEntityHealth(PlayerPedId())
  while true do
    Wait(150)

    if Config.Casings and Config.Casings.Enabled then
      local ped = PlayerPedId()
      if IsPedShooting(ped) then
        local now = GetGameTimer()
        if now - lastShotAt >= (Config.Casings.CooldownMs or 750) then
          lastShotAt = now
          local baseChance = (isSilenced(ped) and (Config.Casings.SilencedChance or 0.2)) or (Config.Casings.BaseChance or 0.75)
          if randChance(baseChance) then
            local coords = GetEntityCoords(ped)
            local w = GetSelectedPedWeapon(ped)
            local meta = {
              weapon = w,
              weaponLabel = weaponLabel(w),
              caliber = guessCaliber(w),
              silenced = isSilenced(ped)
            }
            TriggerServerEvent("tp_evidence:createDrop", "casing", coords, meta, Config.Casings.TTLSeconds or 2700, isRaining())
          end
        end
      end
    end

    if Config.Blood and Config.Blood.Enabled then
      local ped = PlayerPedId()
      local h = GetEntityHealth(ped)
      local delta = lastHealth - h
      if delta >= (Config.Blood.MinHealthDelta or 12) then
        local now = GetGameTimer()
        if now - lastBloodAt >= (Config.Blood.CooldownMs or 30000) then
          lastBloodAt = now
          if randChance(Config.Blood.Chance or 0.55) then
            local coords = GetEntityCoords(ped)
            local meta = { amount = delta }
            TriggerServerEvent("tp_evidence:createDrop", "blood", coords, meta, Config.Blood.TTLSeconds or 2100, isRaining())
          end
        end
      end
      lastHealth = h
    end

    if Config.Vehicles and Config.Vehicles.Enabled then
      local ped = PlayerPedId()
      if IsPedInAnyVehicle(ped, false) then
        local now = GetGameTimer()
        if now - lastVehAt >= (Config.Vehicles.CooldownMs or 45000) then
          lastVehAt = now
          local gloves = hasGloves(ped)
          local fpChance = gloves and (Config.Vehicles.FingerprintChance_Gloves or 0.10) or (Config.Vehicles.FingerprintChance_NoGloves or 0.75)
          local dnaChance = gloves and (Config.Vehicles.TouchDNAChance_Gloves or 0.25) or (Config.Vehicles.TouchDNAChance_NoGloves or 0.55)

          local coords = GetEntityCoords(ped)
          if randChance(fpChance) then
            TriggerServerEvent("tp_evidence:createDrop", "fingerprint", coords, { gloves = gloves }, Config.Vehicles.TTLSeconds or 3600, isRaining())
          end
          if randChance(dnaChance) then
            TriggerServerEvent("tp_evidence:createDrop", "touchdna", coords, { gloves = gloves }, Config.Vehicles.TTLSeconds or 3600, isRaining())
          end
        end
      end
    end
  end
end)
RegisterCommand("inspect", function()
  if not IsAceAllowed(Config.InspectAcePermission or "twopoint.evidence.inspect") then
    notify("~r~You are not allowed to inspect evidence.")
    return
  end
  inspectOn = not inspectOn
  if inspectOn then
    notify("~b~Inspect mode enabled.~s~ Look for your evidence and use ~y~E~s~ (quick wipe) or ~y~H~s~ (thorough clean).")
  else
    notify("~b~Inspect mode disabled.")
  end
end, false)

-- common typo alias
RegisterCommand("instpect", function()
  ExecuteCommand("inspect")
end, false)


