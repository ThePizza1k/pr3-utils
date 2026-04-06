--[[ 
This code converts a table to a human readable string.

To use this, you can put it anywhere as long as the code runs.
After this code runs, you can use the function table.tostring to create a readable string version of a table.
]]--

do
  local writeTable = {}
  local visited = {}

  local function write(...)
    local wl = #writeTable
    local arg = {...}
    for i = 1, #arg do
      writeTable[wl + i] = arg[i]
    end
  end

  local INDENT_SPACE = 2
  local function printPrimitive(p,indent)
    local ispace = (" "):rep(indent)
    if type(p) == "string" then
      write(ispace,'"',p,'"')
    elseif type(p) == "number" then
      write(ispace,p)
    elseif type(p) == "boolean" then
      write(ispace,tostring(p))
    else
      write(ispace,tostring(p))
    end
  end

  local function isDenseArray(tab)
    local len = #tab
    for k in pairs(tab) do
      if type(k) ~= "number" then return false end
      if k > len or k < 1 then return false end
    end
    return true
  end

  local function canPrintDensely(tab)
    for i = 1,#tab do
      if type(tab[i]) == "table" or (type(tab[i]) == "string" and tab[i]:find("\n")) then return false end
    end
    return true
  end

  local function printTable(tab,indent) -- may not work properly for weirdly built tables.
    if visited[tab] then
      write("{Recursive Table}")
      return
    end
    visited[tab] = true
    indent = indent or 0
    local ispace = (" "):rep(indent)
    local ispace2 = (" "):rep(indent + INDENT_SPACE)
    write("{") -- Assume we begin on a line
    if isDenseArray(tab) then -- treat as array
      if canPrintDensely(tab) then
        for i = 1,#tab do
          printPrimitive(tab[i],0)
          if i ~= #tab then write(", ") end
        end
        write("}")
        return
      else
        write("\n")
        for i = 1,#tab do
          local v = tab[i]
          if type(v) == "table" then
            write(ispace2)
            printTable(v, indent + INDENT_SPACE)
          else
            printPrimitive(v,indent + INDENT_SPACE)
          end
          if i ~= #tab then write(",") end
          write("\n")
        end
      end
    else -- treat as object
      write("\n")
      local writeComma = false
      for k,v in pairs(tab) do
        if writeComma then write(",\n") end
        if type(k) == "string" then
          write(ispace2,k," = ")
        else
          write(ispace2,"[")
          printPrimitive(k,0)
          write("] = ")
        end
        if type(v) == "table" then
          printTable(v, indent + INDENT_SPACE)
        else
          printPrimitive(v,0)
        end
        writeComma = true
      end
      write("\n")
    end
    write(ispace,"}")
    visited[tab] = nil
  end

  function table.tostring(tab)
    printTable(tab)
    local str = table.concat(writeTable)
    writeTable = {}
    return str
  end

end
