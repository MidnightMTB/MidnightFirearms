Config = {}

-- Framework: 'auto', 'qb', 'esx', 'standalone'
Config.Framework = 'auto'

-- Discord gating
Config.GuildId = 'PUT_GUILD_ID_HERE'
Config.AllowedRoleId = 'PUT_ROLE_ID_HERE'
Config.BotToken = 'PUT_BOT_TOKEN_HERE' 
Config.DiscordApiVersion = 10

-- Debug
Config.Debug = false
Config.RefreshSeconds = 300

-- Overrides persistence
Config.OverrideTable = 'discord_weapon_overrides'

-- Admin ACE
Config.AdminAce = 'midnight_firearms.admin'

-- Panel
Config.PanelCommand = 'mf_panel'
Config.PanelKey = 'F7'

-- Weapon gating
Config.BlockMode = 'disarm' -- 'disarm' or 'block_firing'
Config.WeaponExceptions = {
  WEAPON_KNIFE = true,
  WEAPON_BAT = true,
  WEAPON_FLASHLIGHT = true,
  WEAPON_NIGHTSTICK = true,
  WEAPON_STUNGUN = true,
}

-- Notification text
Config.LockTitle = 'Firearms Locked'
Config.LockMessage = 'You are not authorized to use firearms.'