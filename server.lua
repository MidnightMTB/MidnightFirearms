local allowedCache = {}      -- [src] = boolean
local overrideByDiscord = {} -- [discordId] = { allow=bool, deny=bool }

local function log(fmt, ...)
  if not Config.Debug then return end
  print(('[%s] ' .. fmt):format('MidnightFirearms', ...))
end

local function isAdmin(src)
  return src == 0 or IsPlayerAceAllowed(src, Config.AdminAce)
end

local function getDiscordId(src)
  if GetPlayerIdentifierByType then
    local did = GetPlayerIdentifierByType(src, 'discord')
    if did then return did:gsub('discord:', '') end
  end

  for _, id in ipairs(GetPlayerIdentifiers(src)) do
    if id:sub(1, 8) == 'discord:' then
      return id:sub(9)
    end
  end

  return nil
end

local function jsonDecode(str)
  if not str or str == '' then return nil end
  if json and json.decode then
    local ok, res = pcall(json.decode, str)
    if ok then return res end
  end
  if lib and lib.json and lib.json.decode then
    local ok, res = pcall(lib.json.decode, str)
    if ok then return res end
  end
  return nil
end

-- DB compat
local function dbQuery(query, params)
  params = params or {}
  if exports.oxmysql and exports.oxmysql.query_async then
    return exports.oxmysql:query_async(query, params)
  end
  if MySQL and MySQL.query and MySQL.query.await then
    return MySQL.query.await(query, params)
  end
  if exports.oxmysql and exports.oxmysql.query then
    local p = promise.new()
    exports.oxmysql:query(query, params, function(result) p:resolve(result) end)
    return Citizen.Await(p)
  end
  error('[MidnightFirearms] No compatible MySQL interface. Ensure oxmysql is started before this resource.')
end

local function dbUpdate(query, params)
  params = params or {}
  if exports.oxmysql and exports.oxmysql.update_async then
    return exports.oxmysql:update_async(query, params)
  end
  if MySQL and MySQL.update and MySQL.update.await then
    return MySQL.update.await(query, params)
  end
  if exports.oxmysql and exports.oxmysql.execute then
    local p = promise.new()
    exports.oxmysql:execute(query, params, function(affected) p:resolve(affected) end)
    return Citizen.Await(p)
  end
  if exports.oxmysql and exports.oxmysql.update then
    local p = promise.new()
    exports.oxmysql:update(query, params, function(affected) p:resolve(affected) end)
    return Citizen.Await(p)
  end
  error('[MidnightFirearms] No compatible MySQL update interface. Ensure oxmysql is started.')
end

-- Overrides
local function loadOverridesFromDB()
  local q = ('SELECT discord_id, allow_firearms, deny_firearms FROM %s'):format(Config.OverrideTable)
  local rows = dbQuery(q, {}) or {}

  overrideByDiscord = {}
  for _, r in ipairs(rows) do
    overrideByDiscord[tostring(r.discord_id)] = {
      allow = tonumber(r.allow_firearms) == 1,
      deny = tonumber(r.deny_firearms) == 1
    }
  end

  print(('[MidnightFirearms] Loaded %d override rows from DB (%s)'):format(#rows, Config.OverrideTable))
end

local function saveOverrideToDB(discordId, allow, deny)
  local q = (('INSERT INTO %s (discord_id, allow_firearms, deny_firearms) VALUES (?, ?, ?) ' ..
             'ON DUPLICATE KEY UPDATE allow_firearms=VALUES(allow_firearms), deny_firearms=VALUES(deny_firearms)'))
             :format(Config.OverrideTable)

  dbUpdate(q, { tostring(discordId), allow and 1 or 0, deny and 1 or 0 })
  overrideByDiscord[tostring(discordId)] = { allow = allow == true, deny = deny == true }
  log('Override saved discord=%s allow=%s deny=%s', tostring(discordId), tostring(allow), tostring(deny))
end

local function clearOverrideInDB(discordId)
  local q = ('DELETE FROM %s WHERE discord_id = ?'):format(Config.OverrideTable)
  dbUpdate(q, { tostring(discordId) })
  overrideByDiscord[tostring(discordId)] = nil
  log('Override cleared discord=%s', tostring(discordId))
end

local function getOverride(discordId)
  local entry = discordId and overrideByDiscord[tostring(discordId)] or nil
  if not entry then return false, false end
  return entry.allow == true, entry.deny == true
end

-- Discord role check
local function hasDiscordRole(discordUserId)
  if not Config.GuildId or Config.GuildId == '' then return false end
  if not Config.AllowedRoleId or Config.AllowedRoleId == '' then return false end
  if not Config.BotToken or Config.BotToken == '' then return false end

  local token = tostring(Config.BotToken)
  token = token:gsub('^%s+', ''):gsub('%s+$', '')
  if token:sub(1, 4):lower() ~= 'bot ' then
    token = 'Bot ' .. token
  end

  local apiVer = tonumber(Config.DiscordApiVersion or 10) or 10
  local url = ('https://discord.com/api/v%d/guilds/%s/members/%s'):format(apiVer, Config.GuildId, discordUserId)

  local p = promise.new()
  PerformHttpRequest(url, function(status, body)
    if status ~= 200 then
      log('Discord role check failed user=%s status=%s body=%s', tostring(discordUserId), tostring(status), tostring(body and body:sub(1, 200) or 'nil'))
      p:resolve(false)
      return
    end

    local data = jsonDecode(body)
    if not data or not data.roles then
      log('Discord decode failed user=%s', tostring(discordUserId))
      p:resolve(false)
      return
    end

    for _, roleId in ipairs(data.roles) do
      if tostring(roleId) == tostring(Config.AllowedRoleId) then
        p:resolve(true)
        return
      end
    end

    p:resolve(false)
  end, 'GET', '', {
    ['Authorization'] = token,
    ['Content-Type'] = 'application/json',
    ['User-Agent'] = 'Ottawa Region Scripts (MidnightMTB)'
  })

  return Citizen.Await(p)
end

local function refreshRoleCache(src)
  local discordId = getDiscordId(src)
  if not discordId then
    allowedCache[src] = false
    log('No discord identifier src=%s name=%s', tostring(src), tostring(GetPlayerName(src)))
    return false
  end

  local ok = hasDiscordRole(discordId)
  allowedCache[src] = ok
  log('Role cache src=%s discord=%s allowed=%s', tostring(src), tostring(discordId), tostring(ok))
  return ok
end

local function decision(src)
  local discordId = getDiscordId(src)
  local allowOvr, denyOvr = getOverride(discordId)

  if allowOvr then return true, discordId, 'OVERRIDE_ALLOW' end
  if denyOvr then return false, discordId, 'OVERRIDE_DENY' end

  if allowedCache[src] == nil then
    refreshRoleCache(src)
  end

  return allowedCache[src] == true, discordId, 'DISCORD_ROLE'
end

-- Public callback for client gate
lib.callback.register('midnight_firearms:isAllowed', function(src)
  local ok, discordId, mode = decision(src)
  return { allowed = ok == true, discordId = discordId, mode = mode }
end)

-- Panel callbacks
lib.callback.register('midnight_firearms:canOpenPanel', function(src)
  return isAdmin(src)
end)

lib.callback.register('midnight_firearms:getOnlinePlayers', function(src)
  if not isAdmin(src) then return { ok = false, error = 'no_permission' } end

  local players = {}
  for _, sid in ipairs(GetPlayers()) do
    local id = tonumber(sid)
    local ok, discordId, mode = decision(id)
    local allowOvr, denyOvr = getOverride(discordId)

    players[#players + 1] = {
      id = id,
      name = GetPlayerName(id) or ('ID %s'):format(id),
      discordId = discordId,
      allowed = ok == true,
      mode = mode,
      overrideAllow = allowOvr,
      overrideDeny = denyOvr
    }
  end

  table.sort(players, function(a, b)
    return (a.name or ''):lower() < (b.name or ''):lower()
  end)

  return { ok = true, players = players }
end)

lib.callback.register('midnight_firearms:applyOverride', function(src, data)
  if not isAdmin(src) then return { ok = false, error = 'no_permission' } end
  if type(data) ~= 'table' then return { ok = false, error = 'bad_request' } end

  local action = tostring(data.action or '')
  local discordId = tostring(data.discordId or '')

  if discordId == '' then return { ok = false, error = 'missing_discord' } end

  if action == 'allow' then
    saveOverrideToDB(discordId, true, false)
  elseif action == 'deny' then
    saveOverrideToDB(discordId, false, true)
  elseif action == 'clear' then
    clearOverrideInDB(discordId)
  else
    return { ok = false, error = 'bad_action' }
  end

  -- Bust cache for any online player with that discord ID
  for _, sid in ipairs(GetPlayers()) do
    local id = tonumber(sid)
    if getDiscordId(id) == discordId then
      allowedCache[id] = nil
    end
  end

  return { ok = true }
end)

lib.callback.register('midnight_firearms:refreshRole', function(src, data)
  if not isAdmin(src) then return { ok = false, error = 'no_permission' } end
  if type(data) ~= 'table' then return { ok = false, error = 'bad_request' } end

  local target = tonumber(data.id)
  if not target or not GetPlayerName(target) then
    return { ok = false, error = 'invalid_player' }
  end

  refreshRoleCache(target)
  return { ok = true }
end)

-- Lifecycle
CreateThread(function()
  while GetResourceState('oxmysql') ~= 'started' and not (MySQL and MySQL.ready) do
    Wait(250)
  end

  if MySQL and MySQL.ready then
    local p = promise.new()
    MySQL.ready(function() p:resolve(true) end)
    Citizen.Await(p)
  end

  loadOverridesFromDB()
end)

AddEventHandler('playerJoining', function()
  refreshRoleCache(source)
end)

AddEventHandler('playerDropped', function()
  allowedCache[source] = nil
end)

if Config.RefreshSeconds and Config.RefreshSeconds > 0 then
  CreateThread(function()
    while true do
      Wait(Config.RefreshSeconds * 1000)
      for _, sid in ipairs(GetPlayers()) do
        refreshRoleCache(tonumber(sid))
      end
    end
  end)
end