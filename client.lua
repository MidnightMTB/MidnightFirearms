local panelOpen = false
local lastWeapon = nil
local lastAllowed = nil
local lastNotifyAt = 0

local function notifyLocked()
  local now = GetGameTimer()
  if now - lastNotifyAt < 2500 then return end
  lastNotifyAt = now

  lib.notify({
    type = 'error',
    title = Config.LockTitle or 'Firearms Locked',
    description = Config.LockMessage or 'You are not authorized to use firearms.'
  })
end

local function isWeaponException(weaponHash)
  if not weaponHash or weaponHash == 0 then return true end
  if weaponHash == GetHashKey('WEAPON_UNARMED') then return true end

  local group = GetWeapontypeGroup(weaponHash)
  -- melee group hash commonly used by GTA
  if group == 2685387236 then return true end

  for weaponName, enabled in pairs(Config.WeaponExceptions or {}) do
    if enabled and weaponHash == GetHashKey(weaponName) then
      return true
    end
  end

  return false
end

local function setPanel(state)
  panelOpen = state
  SetNuiFocus(state, state)
  SetNuiFocusKeepInput(state)
  SendNUIMessage({
    type = 'setVisible',
    visible = state,
    brand = 'Ottawa Region Scripts',
    resource = GetCurrentResourceName()
  })
end

-- Command + keybind to open panel
RegisterCommand(Config.PanelCommand or 'mf_panel', function()
  local can = lib.callback.await('midnight_firearms:canOpenPanel', false)
  if not can then
    lib.notify({ type = 'error', title = 'No Permission', description = 'You do not have access to this panel.' })
    return
  end
  setPanel(true)
end, false)

RegisterKeyMapping(Config.PanelCommand or 'mf_panel', 'Open Midnight Firearms Panel', 'keyboard', Config.PanelKey or 'F7')

-- NUI callbacks
RegisterNUICallback('close', function(_, cb)
  setPanel(false)
  cb(true)
end)

RegisterNUICallback('fetchPlayers', function(_, cb)
  local res = lib.callback.await('midnight_firearms:getOnlinePlayers', false)
  cb(res or { ok = false, error = 'no_response' })
end)

RegisterNUICallback('applyOverride', function(data, cb)
  local res = lib.callback.await('midnight_firearms:applyOverride', false, data)
  cb(res or { ok = false, error = 'no_response' })
end)

RegisterNUICallback('refreshRole', function(data, cb)
  local res = lib.callback.await('midnight_firearms:refreshRole', false, data)
  cb(res or { ok = false, error = 'no_response' })
end)

-- Weapon gating thread
CreateThread(function()
  while true do
    Wait(250)

    local ped = PlayerPedId()
    if not ped or ped == 0 then goto continue end

    local weapon = GetSelectedPedWeapon(ped)
    if weapon == lastWeapon then goto continue end
    lastWeapon = weapon

    if isWeaponException(weapon) then
      lastAllowed = true
      goto continue
    end

    local res = lib.callback.await('midnight_firearms:isAllowed', false)
    local allowed = res and res.allowed == true
    lastAllowed = allowed

    if not allowed then
      SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true)

      if Config.BlockMode == 'block_firing' then
        DisablePlayerFiring(PlayerId(), true)
      end

      notifyLocked()
    end

    ::continue::
  end
end)

-- Optional hard block firing
CreateThread(function()
  while true do
    Wait(0)
    if lastAllowed == false and Config.BlockMode == 'block_firing' then
      DisablePlayerFiring(PlayerId(), true)
    end
  end
end)