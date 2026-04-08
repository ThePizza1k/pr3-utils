--[[
The big "do" block defines buffer.serialize and buffer.deserialize.

buffer.serialize(buf : buffer, offset : int, value : *) : number
  - Writes the value to the buffer at the offset with type information for it to be read back by buffer.deserialize.
  - Returns an offset pointing to directly after the last byte of the data for the value.

buffer.deserialize(buf : buffer, offset : int) : *, number
  - Reads a value written by buffer.serialize from the buffer, starting at offset.
  - Returns the value, and the offset pointing to directly after the last byte of the data for the value.


Types that can be written:
  Boolean
  Buffer
  Number
  String
  Table

Warning: Currently, you just have to guess how much space the table will take up.
  
]]--

do
  local buf_writeu8 = buffer.writeu8 -- this is common so cache for perf
  local buf_writeu16 = buffer.writeu16
  local buf_writeu32 = buffer.writeu32
  local buf_writei8 = buffer.writei8
  local buf_writei16 = buffer.writei16
  local buf_writei32 = buffer.writei32
  local buf_writef64 = buffer.writef64
  local buf_writestring = buffer.writestring

  local buf_readu8 = buffer.readu8
  local buf_readu16 = buffer.readu16
  local buf_readu32 = buffer.readu32
  local buf_readi8 = buffer.readi8
  local buf_readi16 = buffer.readi16
  local buf_readi32 = buffer.readi32
  local buf_readf64 = buffer.readf64
  local buf_readstring = buffer.readstring

  local table_create = table.create

  local writeTable

  local types = {}

  types.null = 0x00
  types.byte = 0x01
  types.short = 0x02
  types.int = 0x03
  types.number = 0x04
  types.True = 0x05
  types.False = 0x06
  types.sString = 0x07 -- Short string (0-255 chars)
  types.lString = 0x08 -- Long string (256 - 65535 chars)
  types.uString = 0x09 -- Ultra long string (up to 4 billion chars)
  types.sBuffer = 0x0a -- Short buffer (0-255 bytes)
  types.lBuffer = 0x0b -- Long buffer (256 - 65535 bytes)
  types.uBuffer = 0x0c -- Ultra long buffer (up to max buffer length)
  types.sObj = 0x0d -- Small sequenceless table (up to 255 pairs)
  types.lObj = 0x0e -- Long sequenceless table (up to 65535 pairs)
  types.uObj = 0x0f -- Ultra long sequenceless table (up to 4 billion pairs)
  types.sArr = 0x10 -- Small sequence table (up to 255 entries)
  types.lArr = 0x11 -- Large sequence table (up to 65535 entries)
  types.uArr = 0x12 -- Ultra large sequence table (up to 4 billion entries)
  types.sTab = 0x13 -- Small mixed table (up to 255 entries in each part)
  types.lTab = 0x14 -- Large mixed table (up to 65535 entries in each part)
  types.uTab = 0x15 -- Ultra large mixed table (up to 4 billion entries in each part)

  local function distinguishNumber(num)
    if num%1 ~= 0 then return "number" end
    if num <= 127 and num >= -128 then return "byte" end
    if num <= 32767 and num >= -32768 then return "short" end
    if num <= 2147483647 and num >= -2147483648 then return "int" end
    return "number"
  end

  local function countPairs(t)
    local seq = 0
    local rec = 0
    local max = 0
    for k, _ in ipairs(t) do
      seq = seq + 1
      max = k
    end
    for k, _ in pairs(t) do
      local isRec = (type(k) ~= "number") or (k%1 ~= 0) or (k <= 0) or (k > max)
      if isRec then rec = rec + 1 end
    end
    return seq, rec
  end
  
  local function distinguishTable(t)
    local seq, rec = countPairs(t)
    if seq == 0 then
      if rec < 256 then return "sObj" end
      if rec < 65536 then return "lObj" end
      return "uObj"
    elseif rec == 0 then
      if seq < 256 then return "sArr" end
      if seq < 65536 then return "lArr" end
      return "uArr"
    else
      local mc = math.max(seq, rec)
      if mc < 256 then return "sTab" end
      if mc < 65536 then return "lTab" end
      return "uTab"
    end
  end

  local function distinguishString(str)
    local len = #str
    if len < 256 then return "sString" end
    if len < 65536 then return "lString" end
    return "uString"
  end

  local function distinguishBuffer(buf)
    local len = #buf
    if len < 256 then return "sBuffer" end
    if len < 65536 then return "lBuffer" end
    return "uBuffer"
  end

  local function distinguishBoolean(bool)
    if bool then return "True" else return "False" end
  end

  local supportedTypes = {
    ["nil"] = function() return "null" end,
    ["boolean"] = distinguishBoolean,
    ["buffer"] = distinguishBuffer,
    ["number"] = distinguishNumber,
    ["table"] = distinguishTable,
    ["string"] = distinguishString,
  }

  local function distinguishValue(val)
    local f = supportedTypes[type(val)]
    if not f then return nil end
    return f(val)
  end

  local typeWriters = {}

  local function writeValue(buf, pos, val) -- Return new pos.
    local t = distinguishValue(val)
    local tByte = types[t]
    buf_writeu8(buf,pos,tByte)
    pos = pos + 1
    return typeWriters[tByte](buf,pos,val)
  end

  local function writeObj(buf, pos, obj)
    -- Assume all of the object is with records.
    for k, v in pairs(obj) do
      pos = writeValue(buf, pos, k)
      pos = writeValue(buf, pos, v)
    end
    return pos
  end

  local function writeSeq(buf, pos, seq)
    for k, v in ipairs(seq) do
      pos = writeValue(buf, pos, v) -- we can infer K.
    end
    return pos
  end

  local function writeObjPart(buf, pos, tab, nseq)
    for k, v in pairs(tab) do
      local isRec = (type(k) ~= "number") or (k%1 ~= 0) or (k <= 0) or (k > nseq)
      if isRec then
        pos = writeValue(buf, pos, k)
        pos = writeValue(buf, pos, v)
      end
    end
    return pos
  end

  do
    typeWriters[types.null] = function(buf,pos,val) return pos end

    typeWriters[types.byte] = function(buf,pos,val)
      buf_writei8(buf,pos,val)
      return pos + 1
    end

    typeWriters[types.short] = function(buf,pos,val)
      buf_writei16(buf,pos,val)
      return pos + 2
    end

    typeWriters[types.int] = function(buf,pos,val)
      buf_writei32(buf,pos,val)
      return pos + 4
    end

    typeWriters[types.number] = function(buf,pos,val)
      buf_writef64(buf,pos,val)
      return pos + 8
    end

    typeWriters[types.True] = function(buf,pos,val) return pos end
    typeWriters[types.False] = function(buf,pos,val) return pos end

    typeWriters[types.sString] = function(buf,pos,val)
      local len = #val
      buf_writeu8(buf,pos,len)
      pos = pos + 1
      buf_writestring(buf,pos, val)
      return pos + len
    end

    typeWriters[types.lString] = function(buf,pos,val)
      local len = #val
      buf_writeu16(buf,pos,len)
      pos = pos + 2
      buf_writestring(buf,pos, val)
      return pos + len
    end

    typeWriters[types.uString] = function(buf,pos,val)
      local len = #val
      buf_writeu32(buf,pos,len)
      pos = pos + 4
      buf_writestring(buf,pos, val)
      return pos + len
    end

    typeWriters[types.sBuffer] = function(buf,pos,val)
      local len = #val
      buf_writeu8(buf,pos,len)
      pos = pos + 1
      buf:copy(pos, val)
      return pos + len
    end

    typeWriters[types.lBuffer] = function(buf,pos,val)
      local len = #val
      buf_writeu16(buf,pos,len)
      pos = pos + 2
      buf:copy(pos, val)
      return pos + len
    end

    typeWriters[types.uBuffer] = function(buf,pos,val)
      local len = #val
      buf_writeu32(buf,pos,len)
      pos = pos + 4
      buf:copy(pos, val)
      return pos + len
    end

    typeWriters[types.sObj] = function(buf, pos, val)
      local _, len = countPairs(val)
      buf_writeu8(buf, pos, len)
      pos = pos + 1
      pos = writeObj(buf,pos,val)
      return pos
    end

    typeWriters[types.lObj] = function(buf, pos, val)
      local _, len = countPairs(val)
      buf_writeu16(buf, pos, len)
      pos = pos + 2
      pos = writeObj(buf,pos,val)
      return pos
    end

    typeWriters[types.uObj] = function(buf, pos, val)
      local _, len = countPairs(val)
      buf_writeu32(buf, pos, len)
      pos = pos + 4
      pos = writeObj(buf,pos,val)
      return pos
    end

    typeWriters[types.sArr] = function(buf, pos, val)
      local len, _ = countPairs(val)
      buf_writeu8(buf, pos, len)
      pos = pos + 1
      pos = writeSeq(buf,pos,val)
      return pos
    end

    typeWriters[types.lArr] = function(buf, pos, val)
      local len, _ = countPairs(val)
      buf_writeu16(buf, pos, len)
      pos = pos + 2
      pos = writeSeq(buf,pos,val)
      return pos
    end

    typeWriters[types.uArr] = function(buf, pos, val)
      local len, _ = countPairs(val)
      buf_writeu32(buf, pos, len)
      pos = pos + 4
      pos = writeSeq(buf,pos,val)
      return pos
    end

    typeWriters[types.sTab] = function(buf, pos, val)
      local seq, rec = countPairs(val)
      buf_writeu8(buf, pos, seq)
      pos = pos + 1
      buf_writeu8(buf, pos, rec)
      pos = pos + 1
      pos = writeSeq(buf,pos,val)
      pos = writeObjPart(buf, pos, val, seq)
      return pos
    end

    typeWriters[types.lTab] = function(buf, pos, val)
      local seq, rec = countPairs(val)
      buf_writeu16(buf, pos, seq)
      pos = pos + 2
      buf_writeu16(buf, pos, rec)
      pos = pos + 2
      pos = writeSeq(buf,pos,val)
      pos = writeObjPart(buf, pos, val, seq)
      return pos
    end

    typeWriters[types.uTab] = function(buf, pos, val)
      local seq, rec = countPairs(val)
      buf_writeu32(buf, pos, seq)
      pos = pos + 4
      buf_writeu32(buf, pos, rec)
      pos = pos + 4
      pos = writeSeq(buf,pos,val)
      pos = writeObjPart(buf, pos, val, seq)
      return pos
    end

  end

  local typeReaders = {}

  local function readValue(buf, pos)
    local type = buf_readu8(buf, pos)
    pos = pos + 1
    local val
    val, pos = typeReaders[type](buf, pos)
    return val, pos
  end

  local function readInSeq(tab, buf, pos, len)
    local val
    for i = 1, len do
      val, pos = readValue(buf, pos)
      tab[i] = val
    end
    return pos
  end

  local function readInRec(tab, buf, pos, len)
    local key
    local val
    for i = 1, len do
      key, pos = readValue(buf, pos)
      val, pos = readValue(buf, pos)
      tab[key] = val
    end
    return pos
  end

  do -- type data already read
    typeReaders[types.null] = function(buf, pos) return nil, pos end

    typeReaders[types.byte] = function(buf, pos)
      local val = buf_readi8(buf,pos)
      return val, pos + 1
    end

    typeReaders[types.short] = function(buf, pos)
      local val = buf_readi16(buf,pos)
      return val, pos + 2
    end

    typeReaders[types.int] = function(buf, pos)
      local val = buf_readi32(buf,pos)
      return val, pos + 4
    end

    typeReaders[types.number] = function(buf, pos)
      local val = buf_readf64(buf,pos)
      return val, pos + 8
    end

    typeReaders[types.True] = function(buf, pos)
      return true, pos
    end

    typeReaders[types.False] = function(buf, pos)
      return false, pos
    end

    typeReaders[types.sString] = function(buf, pos)
      local len = buf_readu8(buf,pos)
      pos = pos + 1
      local str = buf_readstring(buf,pos,len)
      return str, pos + len
    end

    typeReaders[types.lString] = function(buf, pos)
      local len = buf_readu16(buf,pos)
      pos = pos + 2
      local str = buf_readstring(buf,pos,len)
      return str, pos + len
    end

    typeReaders[types.uString] = function(buf, pos)
      local len = buf_readu32(buf,pos)
      pos = pos + 4
      local str = buf_readstring(buf,pos,len)
      return str, pos + len
    end

    typeReaders[types.sBuffer] = function(buf, pos)
      local len = buf_readu8(buf,pos)
      pos = pos + 1
      local val = buffer.new(len)
      val:copy(0, buf, pos, len)
      return val, pos + len
    end

    typeReaders[types.lBuffer] = function(buf, pos)
      local len = buf:readu16(pos)
      pos = pos + 2
      local val = buffer.new(len)
      val:copy(0, buf, pos, len)
      return val, pos + len
    end

    typeReaders[types.uBuffer] = function(buf, pos)
      local len = buf:readu32(pos)
      pos = pos + 4
      local val = buffer.new(len)
      val:copy(0, buf, pos, len)
      return val, pos + len
    end

    typeReaders[types.sArr] = function(buf, pos)
      local len = buf_readu8(buf,pos)
      pos = pos + 1
      local val = table_create(len,0)
      pos = readInSeq(val, buf, pos, len)
      return val, pos
    end

    typeReaders[types.lArr] = function(buf, pos)
      local len = buf_readu16(buf,pos)
      pos = pos + 2
      local val = table_create(len,0)
      pos = readInSeq(val, buf, pos, len)
      return val, pos
    end

    typeReaders[types.uArr] = function(buf, pos)
      local len = buf_readu32(buf,pos)
      pos = pos + 4
      local val = table_create(len,0)
      pos = readInSeq(val, buf, pos, len)
      return val, pos
    end

    typeReaders[types.sObj] = function(buf, pos)
      local len = buf_readu8(buf,pos)
      pos = pos + 1
      local val = table_create(0, len)
      pos = readInRec(val, buf, pos, len)
      return val, pos
    end

    typeReaders[types.lObj] = function(buf, pos)
      local len = buf_readu16(buf,pos)
      pos = pos + 2
      local val = table_create(0, len)
      pos = readInRec(val, buf, pos, len)
      return val, pos
    end

    typeReaders[types.uObj] = function(buf, pos)
      local len = buf_readu32(buf,pos)
      pos = pos + 4
      local val = table_create(0, len)
      pos = readInRec(val, buf, pos, len)
      return val, pos
    end

    typeReaders[types.sTab] = function(buf, pos) -- first sequence, then record
      local seq = buf_readu8(buf,pos)
      pos = pos + 1
      local rec = buf_readu8(buf,pos)
      pos = pos + 1
      local val = {}
      pos = readInSeq(val, buf, pos, seq)
      pos = readInRec(val, buf, pos, rec)
      return val, pos
    end

    typeReaders[types.lTab] = function(buf, pos)
      local seq = buf_readu16(buf,pos)
      pos = pos + 2
      local rec = buf_readu16(buf,pos)
      pos = pos + 2
      local val = {}
      pos = readInSeq(val, buf, pos, seq)
      pos = readInRec(val, buf, pos, rec)
      return val, pos
    end

    typeReaders[types.uTab] = function(buf, pos)
      local seq = buf_readu32(buf,pos)
      pos = pos + 4
      local rec = buf_readu32(buf,pos)
      pos = pos + 4
      local val = {}
      pos = readInSeq(val, buf, pos, seq)
      pos = readInRec(val, buf, pos, rec)
      return val, pos
    end

  end
  
  buffer.serialize = writeValue
  buffer.deserialize = readValue

end

-- Test code

local buf = buffer.new(256)

local tab = {2, 6, 12, 24, 24, 12, 12, 12, 12, 12, 12, 12, 12, 0, 0, 0, 0, pair = {1, 2, 3, 4, 5, 6, 7, math.pi}, var = math.sin(3), query = "among us the video game (the movie)"}

local SCALE = 100

local v
local t0 = flash.gettimer()
for i = 1, SCALE do
  v = buffer.serialize(buf,0,tab)
end
local t1 = flash.gettimer()
print(v)
print(("Takes on average %.3fms to serialize"):format((t1-t0) / SCALE))

local tab2
t0 = flash.gettimer()
for i = 1, SCALE do
  tab2 = buffer.deserialize(buf, 0)
end
t1 = flash.gettimer()
print(("Takes on average %.3fms to deserialize"):format((t1-t0) / SCALE))

-- end test code

--[[ ideas:

  > reduce duplicate type information
    + common case for many items of similar typing to be near eachother
    + potentially huge savings in some cases (i.e, a large list of small integers)
    + does not seem to be covered much by an actual compression algorithm.
    - increases complexity.

  > separate obj type into dictionary and object
    ? pure object type where all keys are short strings.
    + can save some bytes for object types?
    - increases complexity a bit.

  > float type
    + would save 4 bytes in a few cases.
    - very rare that this would provide any benefit.

  > string number type
    ? in some situations, write number as a string if that representation is shorter.
    + may save a few bytes for numbers like 0.1
    + possibly improvable with more compressed decimal representation
    - these kinds of numbers wouldn't show up very naturally in many real use cases.

  > custom type
    ? set up system for user to define a custom type.
    + more specific setup can save lots of bytes (no need to save component keys or type info)
    + user can save additional bytes by choosing a more lossy representation if applicable.
    + does not complicate things much at all.
    - may expose type id implementation details.
    - requires getmetatable (to differentiate)

  > problem to solve: buffer sizing.
    ? bad ux to have to guess size of serialized table.
    > possible idea: pre-size everything w/ a table.
      + no need to guess buffer size.
      + may improve performance.
      - increases complexity

  > settings?
    ? could have settings for the serializer
    > 'fast' option
      ? skip some distinguishing to speed up serializing
      + may be faster?
      - would increase size
      - may not be that much faster
      - could be incompatible with buffer sizing solution
    > 'lossy' option
      ? write numbers as floats.
      + save 4 bytes per number.
 

]]--
