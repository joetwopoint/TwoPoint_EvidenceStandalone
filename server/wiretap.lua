local function dbg(...)
  if Config.Debug then
    print("[TwoPoint_Evidence][Wiretap]", ...)
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

local function looksLikeNumber(s)
  if type(s) ~= "string" then return false end
  local digits = s:gsub("%D","")
  return #digits >= 4 and #digits <= 16
end

local function sanitizeNumber(s)
  if s == nil then return nil end
  local digits = tostring(s):gsub("%D", "")
  if #digits < 4 or #digits > 16 then return nil end
  return digits
end

local function sendChat(src, prefix, msg)
  if not src or src <= 0 then return end
  TriggerClientEvent('chat:addMessage', src, { args = { prefix, msg } })
end

local function extractNumbers(call)
  local found = {}
  local function add(v)
    if looksLikeNumber(v) then
      local digits = v:gsub("%D","")
      found[digits] = true
    end
  end
  if type(call) == "table" then
    for k,v in pairs(call) do
      if type(v) == "string" then add(v) end
    end
  end
  local out = {}
  for n,_ in pairs(found) do out[#out+1]=n end
  return out
end

local activeCalls = {} -- key -> {key, call, numbers, startedAt, answeredAt, endedAt, endedBySource}
local alerts = {} -- ring buffer
local ALERT_MAX = 80

local function pushAlert(entry)
  alerts[#alerts+1] = entry
  if #alerts > ALERT_MAX then
    table.remove(alerts, 1)
  end
end

local function getAllTappedNumbers()
  local rows = MySQL.query.await("SELECT DISTINCT target_number FROM tp_wiretap_targets", {})
  local set = {}
  for _, r in ipairs(rows or {}) do
    if r.target_number then
      local digits = tostring(r.target_number):gsub("%D","")
      set[digits] = true
    end
  end
  return set
end

local function notifyWatchersIfMatched(callKey, stage)
  local callObj = activeCalls[callKey]
  if not callObj then return end

  local tapped = getAllTappedNumbers()
  local matched = false
  for _, n in ipairs(callObj.numbers or {}) do
    if tapped[n] then matched = true break end
  end
  if not matched then return end

  local payload = {
    stage = stage,
    key = callKey,
    call = callObj.call,
    numbers = callObj.numbers,
    startedAt = callObj.startedAt,
    answeredAt = callObj.answeredAt,
    endedAt = callObj.endedAt,
  }

  -- Send to all online LEOs that are permitted/on-duty
  for _, sid in ipairs(GetPlayers()) do
    sid = tonumber(sid)
    if sid and hasPerm(sid) then
      TriggerClientEvent("tp_evidence:wiretapAlert", sid, payload)
    end
  end

  pushAlert(payload)
end

local function callKeyFrom(call)
  if type(call) ~= "table" then return tostring(os.time() .. "-" .. math.random(1000,9999)) end
  return tostring(call.id or call.callId or call.channelId or call.uuid or (os.time() .. "-" .. math.random(1000,9999)))
end

local phoneRes = Config.LBPhoneResource or "lb-phone"

if resStarted(phoneRes) then
  AddEventHandler("lb-phone:newCall", function(call)
    local key = callKeyFrom(call)
    local nums = extractNumbers(call)
    activeCalls[key] = { key = key, call = call, numbers = nums, startedAt = os.time() }
    notifyWatchersIfMatched(key, "new")
  end)

  AddEventHandler("lb-phone:callAnswered", function(call)
    local key = callKeyFrom(call)
    if not activeCalls[key] then
      activeCalls[key] = { key = key, call = call, numbers = extractNumbers(call), startedAt = os.time() }
    end
    activeCalls[key].call = call
    activeCalls[key].numbers = activeCalls[key].numbers or extractNumbers(call)
    activeCalls[key].answeredAt = os.time()
    notifyWatchersIfMatched(key, "answered")
  end)

  AddEventHandler("lb-phone:callEnded", function(call, endedBySource)
    local key = callKeyFrom(call)
    if not activeCalls[key] then
      activeCalls[key] = { key = key, call = call, numbers = extractNumbers(call), startedAt = os.time() }
    end
    activeCalls[key].call = call
    activeCalls[key].numbers = activeCalls[key].numbers or extractNumbers(call)
    activeCalls[key].endedAt = os.time()
    activeCalls[key].endedBySource = endedBySource
    notifyWatchersIfMatched(key, "ended")

    -- keep ended calls around briefly for UI
    SetTimeout(60 * 1000, function()
      activeCalls[key] = nil
    end)
  end)
else
  dbg("LB Phone not started; wiretap call events will be unavailable.")
end

-- UI handler actions
RegisterNetEvent("tp_evidence:wiretapUi", function(reqId, action, payload)
  local src = source
  if not IsAceAllowed(src, Config.AcePermission) then
    TriggerClientEvent("tp_evidence:wiretapUiResp", src, reqId, false, nil, "Not authorized.")
    return
  end
  if Config.RequireOnDuty and not hasPerm(src) then
    TriggerClientEvent("tp_evidence:wiretapUiResp", src, reqId, false, nil, "You must be on duty.")
    return
  end

  local ident = getIdentifier(src)

  if action == "state" then
    local targets = MySQL.query.await("SELECT target_number, label FROM tp_wiretap_targets WHERE officer_identifier = ? ORDER BY target_number ASC", { ident })
    local calls = {}
    for _, c in pairs(activeCalls) do
      calls[#calls+1] = {
        key = c.key,
        stage = (c.endedAt and "ended") or (c.answeredAt and "answered") or "new",
        numbers = c.numbers or {},
        startedAt = c.startedAt,
        answeredAt = c.answeredAt,
        endedAt = c.endedAt
      }
    end
    table.sort(calls, function(a,b) return (a.startedAt or 0) > (b.startedAt or 0) end)

    TriggerClientEvent("tp_evidence:wiretapUiResp", src, reqId, true, {
      targets = targets or {},
      calls = calls,
      alerts = alerts
    }, nil)
    return
  end

  if action == "add" then
    local num = sanitizeNumber(payload and payload.number)
    if not num then
      TriggerClientEvent("tp_evidence:wiretapUiResp", src, reqId, false, nil, "Invalid number.")
      return
    end
    local label = payload and payload.label
    MySQL.update.await([[
      INSERT INTO tp_wiretap_targets (officer_identifier, target_number, label)
      VALUES (?, ?, ?)
      ON DUPLICATE KEY UPDATE label = VALUES(label)
    ]], { ident, num, label })
    TriggerClientEvent("tp_evidence:wiretapUiResp", src, reqId, true, { ok = true }, nil)
    TriggerClientEvent("tp_evidence:wiretapRefresh", src)
    return
  end

  if action == "remove" then
    local num = sanitizeNumber(payload and payload.number)
    if not num then
      TriggerClientEvent("tp_evidence:wiretapUiResp", src, reqId, false, nil, "Invalid number.")
      return
    end
    MySQL.update.await("DELETE FROM tp_wiretap_targets WHERE officer_identifier = ? AND target_number = ?", { ident, num })
    TriggerClientEvent("tp_evidence:wiretapUiResp", src, reqId, true, { ok = true }, nil)
    TriggerClientEvent("tp_evidence:wiretapRefresh", src)
    return
  end

  TriggerClientEvent("tp_evidence:wiretapUiResp", src, reqId, false, nil, "Unknown action.")
end)

-- Chat commands (optional): /wiretap add|remove|list
RegisterCommand("wiretap", function(src, args)
  if not src or src <= 0 then
    print("[TwoPoint_Evidence][Wiretap] /wiretap is player-only")
    return
  end

  if not hasPerm(src) then
    sendChat(src, "^1Wiretap", "Not authorized or not on duty.")
    return
  end

  local sub = (args[1] or ""):lower()

  if sub == "add" then
    local num = sanitizeNumber(args[2])
    if not num then
      sendChat(src, "^1Wiretap", "Usage: /wiretap add <number> [label]")
      return
    end
    local label = nil
    if args[3] then
      label = table.concat(args, " ", 3)
      if label == "" then label = nil end
    end

    local ident = getIdentifier(src)
    MySQL.update.await([[
      INSERT INTO tp_wiretap_targets (officer_identifier, target_number, label)
      VALUES (?, ?, ?)
      ON DUPLICATE KEY UPDATE label = VALUES(label)
    ]], { ident, num, label })

    print(("[TwoPoint_Evidence][Wiretap] %s (%s) ADDED tap %s%s"):format(getDisplayName(src), ident, num, label and (" ("..label..")") or ""))
    sendChat(src, "^3Wiretap", ("Added tap: %s%s"):format(num, label and (" ("..label..")") or ""))
    TriggerClientEvent("tp_evidence:wiretapRefresh", src)
    return
  end

  if sub == "remove" or sub == "del" or sub == "delete" then
    local num = sanitizeNumber(args[2])
    if not num then
      sendChat(src, "^1Wiretap", "Usage: /wiretap remove <number>")
      return
    end

    local ident = getIdentifier(src)
    local affected = MySQL.update.await("DELETE FROM tp_wiretap_targets WHERE officer_identifier = ? AND target_number = ?", { ident, num })

    print(("[TwoPoint_Evidence][Wiretap] %s (%s) REMOVED tap %s (affected=%s)"):format(getDisplayName(src), ident, num, tostring(affected)))
    sendChat(src, "^3Wiretap", (affected and affected > 0) and ("Removed tap: %s"):format(num) or ("No tap found for %s"):format(num))
    TriggerClientEvent("tp_evidence:wiretapRefresh", src)
    return
  end

  if sub == "list" or sub == "ls" then
    local ident = getIdentifier(src)
    local rows = MySQL.query.await("SELECT target_number, label FROM tp_wiretap_targets WHERE officer_identifier = ? ORDER BY target_number ASC", { ident })
    if not rows or #rows == 0 then
      sendChat(src, "^3Wiretap", "You have no tapped numbers.")
      return
    end

    sendChat(src, "^3Wiretap", ("Tapped numbers (%d):"):format(#rows))
    for _, r in ipairs(rows) do
      local n = tostring(r.target_number)
      local l = (r.label and tostring(r.label) ~= "") and (" - "..tostring(r.label)) or ""
      sendChat(src, "^3Wiretap", ("- %s%s"):format(n, l))
    end
    return
  end

  sendChat(src, "^1Wiretap", "Usage: /wiretap add <number> [label] | /wiretap remove <number> | /wiretap list")
end, false)
