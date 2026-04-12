--[[
This code goes in level lua.

It adds two functions to the global environment: 'require' and 'provide'

The require function requests a given module. If the module ran, what it gave to 'provide' is returned. If it did not run, execution is stopped there, and the requested module code is run.

The provide function is used to indicate that a module ran successfully, and determine what should return from a require call.

In each module, except for your main one, you should have a 'provide' call at the end with what you want 'require' to return.
Every module should be in a block, where code can be ran by bumping the block.
You should fill in the 'DATA' table, to map from names to the X position of your module block.
Your 'main' module block should be at (0, -3). Every other module block should also be at y = -3, with an x value matching their respective entry in the 'DATA' table.

Example use in module:
local vector = require("vector")
local quaternion = require("quaternion")

-- define stuff

provide(library_table)
]]--
game.start.addListener(function()

  local DATA = {
    main = 0,
    --vector = 1, -- Example
    --quaternion = 2,
  }

  local current = 1
  local currentTree = {"main"}

  local function runName(name)
    player.xpos = DATA[name] + 0.5
    player.ypos = -1
    player.yvelocity = -1
  end

  local requireTable = {}

  function require(name)
    if requireTable[name] then return requireTable[name].data end
    if DATA[name] then
      current = current + 1
      currentTree[current] = name
      runName(currentTree[current])
      error("Error to force execution end. No action is needed.")
    else
      player.chat("Non-existent module of name ".. name .. " requested!",0xFF0000)
      error("Non-existent module of name ".. name .. " requested!",2)
    end
  end

  function provide(data)
    requireTable[currentTree[current]] = {data = data}
    current = current - 1
    runName(currentTree[current])
  end

  player.newTimer(0,1,function()
    runName(currentTree[current])
    player.stiffness = 0
    player.disableleft(2147483647)
    player.disableright(2147483647)
    player.disableup(2147483647)
    player.disabledown(2147483647)
    player.minimap = false
  end)

end)
