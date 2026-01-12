local world = {}
local scannerOn = false

-- =========================
-- Lab blips
-- =========================
local labBlips = {}

local function clearLabBlips()
  for _, b in ipairs(labBlips) do
    if DoesBlipExist(b) then
      RemoveBlip(b)
    end
  end
  labBlips = {}
end

local function shouldShowLabBlips()
  if not (Config.Blips and Config.Blips.Enabled) then return false end
  if Config.Blips.ShowToAll then return true end
  local node = Config.AceNode or (Config.AceNodes and Config.AceNodes.police) or "twopoint.evidence"
  return node and IsAceAllowed(node) or false
end

local function makeLabBlips()
  clearLabBlips()
  if not shouldShowLabBlips() then return end

  for _, lab in ipairs(Config.Labs or {}) do
    if lab.enabled == false then
      goto continue
    end
    local c = lab.coords
    local blip = AddBlipForCoord(c.x, c.y, c.z)

    local sprite = lab.blipSprite
    local color = lab.blipColor
    local scale = lab.blipScale
    local shortRange = lab.blipShortRange

    if not sprite then
      if lab.category == 'HOSPITAL' then
        sprite = (Config.Blips and Config.Blips.HospitalSprite) or (Config.Blips and Config.Blips.DefaultSprite) or 1
      else
        sprite = (Config.Blips and Config.Blips.PoliceSprite) or (Config.Blips and Config.Blips.DefaultSprite) or 1
      end
    end
    if not color then
      if lab.category == 'HOSPITAL' then
        color = (Config.Blips and Config.Blips.HospitalColor) or (Config.Blips and Config.Blips.DefaultColor) or 0
      else
        color = (Config.Blips and Config.Blips.PoliceColor) or (Config.Blips and Config.Blips.DefaultColor) or 0
      end
    end
    if not scale then scale = (Config.Blips and Config.Blips.Scale) or 0.75 end
    if shortRange == nil then shortRange = (Config.Blips and Config.Blips.ShortRange) ~= false end

    SetBlipSprite(blip, sprite)
    SetBlipColour(blip, color)
    SetBlipScale(blip, scale)
    SetBlipAsShortRange(blip, shortRange)

    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(lab.blipName or lab.label or 'Evidence Lab')
    EndTextCommandSetBlipName(blip)

    table.insert(labBlips, blip)
    ::continue::
  end
end

AddEventHandler('onClientResourceStart', function(res)
  if res == GetCurrentResourceName() then
    CreateThread(function()
      Wait(1000)
      makeLabBlips()
    end)
  end
end)

AddEventHandler('onClientResourceStop', function(res)
  if res == GetCurrentResourceName() then
    clearLabBlips()
  end
end)

AddEventHandler('onResourceStop', function(res)
  if res == GetCurrentResourceName() then
    clearLabBlips()
  end
end)

local function notify(msg)
  TriggerEvent("chat:addMessage", { args = { "^3[Evidence]^7", msg } })
end

RegisterNetEvent("tp_evidence:notify", function(msg)
  notify(msg)
end)

RegisterNetEvent("tp_evidence:worldSnapshot", function(cache)
  world = cache or {}
end)

CreateThread(function()
  Wait(1500)
  TriggerServerEvent("tp_evidence:requestSnapshot")
end)

-- Utility
local function vec3Dist(a, b)
  local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
  return math.sqrt(dx*dx + dy*dy + dz*dz)
end

-- =========================
-- Realism helpers
-- =========================
local function isRainingNow()
  return (GetRainLevel() or 0.0) > 0.01
end

local function computeTTLMinutes(evType)
  local ttl = (Config.Realism and Config.Realism.TTLByType and Config.Realism.TTLByType[evType])
    or Config.WorldEvidenceTTLMinutes
    or 180

  if isRainingNow() and Config.Realism and Config.Realism.RainDecayMultiplier then
    ttl = math.floor(ttl * tonumber(Config.Realism.RainDecayMultiplier))
  end

  ttl = tonumber(ttl) or 180
  if ttl < 5 then ttl = 5 end
  return ttl
end

local function isWearingGloves(ped)
  local cfg = Config.Realism and Config.Realism.GloveCheck
  local arms = GetPedDrawableVariation(ped, 3)
  local model = GetEntityModel(ped)

  -- Default heuristic: freemode arms index 15 is usually bare hands
  if not cfg then
    return arms ~= 15
  end

  if model == joaat('mp_m_freemode_01') then
    return not (cfg.MaleNoGloves and cfg.MaleNoGloves[arms])
  end
  if model == joaat('mp_f_freemode_01') then
    return not (cfg.FemaleNoGloves and cfg.FemaleNoGloves[arms])
  end

  return (cfg.AssumeGlovesForNonFreemode ~= false)
end

local function getClosestEvidence(maxDist)
  local ped = PlayerPedId()
  local p = GetEntityCoords(ped)
  local bestId, best, bestD = nil, nil, maxDist or 2.0
  for id, ev in pairs(world) do
    local d = vec3Dist({x=p.x,y=p.y,z=p.z}, ev)
    if d < bestD then
      bestD = d
      bestId = id
      best = ev
    end
  end
  return bestId, best, bestD
end

-- Scanner toggle
RegisterCommand(Config.Scanner.Command or "forensic", function()
  scannerOn = not scannerOn
  if scannerOn then
    notify("Scanner ON. Walk near evidence and press E to collect.")
    TriggerServerEvent("tp_evidence:requestSnapshot")
  else
    notify("Scanner OFF.")
  end
end)

-- Draw + collect
CreateThread(function()
  while true do
    if not scannerOn then
      Wait(600)
    else
      local ped = PlayerPedId()
      local p = GetEntityCoords(ped)
      local maxDraw = (Config.Scanner.MaxDrawDistance or 25.0)
      for id, ev in pairs(world) do
        local d = vec3Dist({x=p.x,y=p.y,z=p.z}, ev)
        if d < maxDraw then
          DrawMarker(2, ev.x, ev.y, ev.z + 0.2, 0.0,0.0,0.0, 0.0,0.0,0.0, 0.25,0.25,0.25, 255,255,255,160, false,true,2,false,nil,nil,false)
        end
      end

      local closestId, closestEv, dist = getClosestEvidence(Config.Scanner.CollectDistance or 2.0)
      if closestId and closestEv then
        SetTextFont(4)
        SetTextScale(0.35, 0.35)
        SetTextProportional(1)
        SetTextCentre(true)
        SetTextEntry("STRING")
        AddTextComponentString(("Press ~INPUT_CONTEXT~ to collect %s"):format(closestEv.evidence_type or "EVIDENCE"))
        DrawText(0.5, 0.88)

        if IsControlJustPressed(0, Config.Scanner.CollectKey or 38) then
          TriggerServerEvent("tp_evidence:collect", closestId)
          Wait(500)
          TriggerServerEvent("tp_evidence:requestSnapshot")
        end
      end

      Wait(0)
    end
  end
end)

-- Evidence creation

local lastShot = 0
CreateThread(function()
  while true do
    if Config.Drop.ShellCasing.enabled then
      local ped = PlayerPedId()
      if IsPedShooting(ped) and IsPedArmed(ped, 4) then
        local now = GetGameTimer()
        if now - lastShot > (Config.Drop.ShellCasing.cooldownMs or 1200) then
          lastShot = now
          -- Realism: suppressed weapons drop fewer casings
          local silenced = IsPedCurrentWeaponSilenced(ped)
          if silenced and Config.Realism and Config.Realism.SuppressedShellChance then
            local chance = tonumber(Config.Realism.SuppressedShellChance) or 0.35
            if math.random() > chance then
              goto continue
            end
          end
          local c = GetEntityCoords(ped)
          TriggerServerEvent("tp_evidence:dropEvidence", {
            evidence_type = "SHELL",
            x = c.x + (math.random() * 0.4),
            y = c.y + (math.random() * 0.4),
            z = c.z - 0.95,
            weapon = tostring(GetSelectedPedWeapon(ped)),
            ttl_minutes = computeTTLMinutes("SHELL"),
            note = silenced and "Suppressed casing" or "Shell casing"
          })
        end
      end
    end
    ::continue::
    Wait(0)
  end
end)

local lastBlood = 0
local prevHealth = nil
CreateThread(function()
  while true do
    if Config.Drop.Blood.enabled then
      local ped = PlayerPedId()
      local hp = GetEntityHealth(ped)
      if not prevHealth then prevHealth = hp end
      local delta = prevHealth - hp
      if delta >= (Config.Drop.Blood.healthDelta or 10) and hp > 0 then
        local now = GetGameTimer()
        if now - lastBlood > (Config.Drop.Blood.cooldownMs or 7000) then
          lastBlood = now
          local c = GetEntityCoords(ped)
          TriggerServerEvent("tp_evidence:dropEvidence", {
            evidence_type = "BLOOD",
            x = c.x, y = c.y, z = c.z - 0.98,
            ttl_minutes = computeTTLMinutes("BLOOD"),
            note = "Blood drop"
          })
        end
      end
      prevHealth = hp
    end
    Wait(500)
  end
end)

local lastFP = 0
local lastVeh = 0
CreateThread(function()
  while true do
    if Config.Drop.Fingerprint.enabled and Config.Drop.Fingerprint.onVehicleEnter then
      local ped = PlayerPedId()
      local veh = GetVehiclePedIsIn(ped, false)
      local now = GetGameTimer()
      if veh ~= 0 and veh ~= lastVeh and now - lastFP > (Config.Drop.Fingerprint.cooldownMs or 12000) then
        lastVeh = veh
        lastFP = now
        local c = GetEntityCoords(ped)
        local plate = GetVehicleNumberPlateText(veh)
        -- Realism: gloves reduce prints/touch DNA
        local gloves = isWearingGloves(ped)
        if gloves and Config.Realism and Config.Realism.GlovesFingerprintChance then
          local chance = tonumber(Config.Realism.GlovesFingerprintChance) or 0.15
          if math.random() > chance then
            goto cont
          end
        end
        TriggerServerEvent("tp_evidence:dropEvidence", {
          evidence_type = "FINGERPRINT",
          x = c.x, y = c.y, z = c.z - 0.95,
          ttl_minutes = computeTTLMinutes("FINGERPRINT"),
          note = ("Vehicle plate: %s%s"):format(plate or "UNKNOWN", gloves and " (gloves)" or "")
        })
      elseif veh == 0 then
        lastVeh = 0
      end
    end
    ::cont::
    Wait(800)
  end
end)


-- =========================
-- NUI / Evidence UI
-- =========================
local uiOpen = false
local reqSeq = 0
local pending = {}
local lastLabState = nil

local function isPoliceAllowedClient()
  local node = Config.AceNode or (Config.AceNodes and Config.AceNodes.police) or "twopoint.evidence"
  if node and not IsAceAllowed(node) then return false end
  if not Config.RequireOnDuty then return true end
  -- Prefer statebag set by patched PoliceEMSActivity
  if LocalPlayer and LocalPlayer.state and LocalPlayer.state.pea_onDuty ~= nil then
    return LocalPlayer.state.pea_onDuty == true
  end
  return true
end

local function getCurrentLab()
  if not Config.Labs then return nil end
  local ped = PlayerPedId()
  local c = GetEntityCoords(ped)
  for _, lab in ipairs(Config.Labs) do
    if lab.enabled == false then
      goto continue
    end
    local lc = lab.coords
    local dx = c.x - lc.x
    local dy = c.y - lc.y
    local dz = c.z - lc.z
    local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
    if dist <= (lab.radius or 25.0) then
      return lab.label or "Lab"
    end
    ::continue::
  end
  return nil
end

RegisterNetEvent("tp_evidence:uiResponse", function(reqId, ok, data, err)
  local p = pending[reqId]
  if p then
    pending[reqId] = nil
    p:resolve({ ok = ok, data = data, err = err })
  end
end)

local function serverCall(action, payload)
  reqSeq = reqSeq + 1
  local id = reqSeq
  local p = promise.new()
  pending[id] = p
  TriggerServerEvent("tp_evidence:uiRequest", id, action, payload or {})
  return Citizen.Await(p)
end

local function pushLabStatus(force)
  if not uiOpen then return end
  local label = getCurrentLab()
  local state = label ~= nil
  local key = tostring(state) .. ":" .. tostring(label or "")
  if force or lastLabState ~= key then
    lastLabState = key
    SendNUIMessage({ type = "labStatus", inLab = state, label = label })
  end
end

local function openUI()
  if uiOpen then return end
  if not isPoliceAllowedClient() then
    notify("Not allowed (permissions or duty).")
    return
  end

  uiOpen = true
  SetNuiFocus(true, true)
  SendNUIMessage({ type = "open" })
  pushLabStatus(true)
end

local function closeUI()
  if not uiOpen then return end
  uiOpen = false
  SetNuiFocus(false, false)
  SendNUIMessage({ type = "close" })
end

RegisterNUICallback("tp_evidence_ui_close", function(_, cb)
  closeUI()
  cb({ ok = true })
end)

RegisterNUICallback("tp_evidence_ui_list", function(_, cb)
  local res = serverCall("list", {})
  if res and res.ok and res.data and res.data.inLab ~= nil then
    -- in case server truth differs, push a refresh
    pushLabStatus(true)
  end
  cb({ ok = res.ok, bags = res.data and res.data.bags or {}, err = res.err })
end)

RegisterNUICallback("tp_evidence_ui_view", function(data, cb)
  local res = serverCall("view", { id = data.id })
  cb({ ok = res.ok, data = res.data and res.data.data or nil, err = res.err })
end)

RegisterNUICallback("tp_evidence_ui_analyze", function(data, cb)
  local res = serverCall("analyze", { id = data.id })
  cb({ ok = res.ok, data = res.data and res.data.data or nil, err = res.err })
end)

RegisterNUICallback("tp_evidence_ui_delete", function(data, cb)
  local res = serverCall("delete", { id = data.id })
  cb({ ok = res.ok, err = res.err })
end)

RegisterCommand(Config.Commands.ui or "evidence", function()
  openUI()
end)

-- While UI is open, update lab status when it changes
CreateThread(function()
  while true do
    if uiOpen then
      pushLabStatus(false)
      Wait(500)
    else
      Wait(1000)
    end
  end
end)

-- Close UI if resource stops
AddEventHandler("onResourceStop", function(resName)
  if resName == GetCurrentResourceName() then
    closeUI()
  end
end)
