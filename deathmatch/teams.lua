-- Define your teams here. Format for a team is { team name, team color }
local TEAMS = {
  {"Red",0xFF0000},
  {"Orange",0xFF8000},
  {"Yellow",0xFFFF00},
  {"Green",0x00FF00},
  {"Cyan",0x00FFFF},
  {"Blue",0x0000FF},
  {"Purple",0x8000FF},
  {"Pink",0xFF00FF},
  {"Grey",0x808080},
  {"White",0xFFFFFF},
  {"Black",0x000000},
  {"Dark Red",0x800000},
  {"Dark Yellow",0x808000},
  {"Dark Green",0x008000},
  {"Dark Cyan",0x008080},
  {"Dark Blue",0x0000AA},
  {"Dark Pink",0x660066},
}

-- Number of players on one team
local TEAM_SIZE = 2

-- Player FOV
local BASE_FOV = 0.8

--[[
 Multiply player health by this much for a team with this many players.
 Use this to try to balance around players being alone.
 If a value is not present for a team size, defaults to 1.
]]--
local HP_MULT = {
  [1] = 1.6,
  [2] = 1,
}

--[[ Code is below ]]--

local playerTeamSize = TEAM_SIZE

local playerTeamID = -1

local function onPlayerStart()
  player.team = TEAMS[playerTeamID][1]
  player.fov = BASE_FOV

  local multiplier = HP_MULT[playerTeamSize] or 1
  local hp = math.round(player.maxhealth * multiplier)
  player.maxhealth = hp
  player.health = hp
end


local function onGameStart()
  local playerArray = game.getAllPlayers()
  local currentTeam = 1
  local currentTeamPlayers = 0

  for index, p in ipairs(playerArray) do -- Loop over all players
    if currentTeamPlayers >= TEAM_SIZE then
      currentTeam = currentTeam + 1
      currentTeamPlayers = 0
    end
    currentTeamPlayers = currentTeamPlayers + 1
    p.outline = TEAMS[currentTeam][2]
    p.outlinethickness = 2.5
    if p == player then
      playerTeamID = currentTeam
    end
  end

  if currentTeam == playerTeamID then -- In this case, we might not have filled out this team.
    playerTeamSize = currentTeamPlayers
  end

  player.newTimer(1, 1, onPlayerStart) -- create a timer that runs once
end


game.start.addListener(onGameStart)
