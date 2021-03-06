-- Credit: https://github.com/feldim2425/OC-Programs
local ws_tool = {};

ws_tool.upgrade = function(host,uri,port)
  req = "GET " .. uri .. " HTTP/1.1\r\n";
  req = req .. "Host: " .. host .. ":" .. port .."\r\n";
  req = req .. "Upgrade: websocket\r\n";
  req = req .. "Connection: Upgrade\r\n";
  -- Dirty hack but it makes the client compliant enough for aiohttp.
  req = req .. "Sec-WebSocket-Key: aSBhbSBhbiBlZ2cgbG9sLg==\r\n";
  req = req .. "Sec-WebSocket-Protocol: chat\r\n";
  req = req .. "Sec-WebSocket-Version: 13\r\n\r\n";
  
  return req, key;
end

ws_tool.verifyUpgrade = function(key,message)
  head = true;
  data = {};
  off = 0;
  for line in message:gmatch("[^\r\n]*\r\n") do
    off = off + line:len();
    if head then
      if line:find("101") then
        head = false;
      else
        return false, "Wrong HTTP-Code";
      end
    else
      hkey, hval = line:match("([^%s:]*): ([^%s:]*)");
      if hkey and hval then
	    data[hkey] = hval;
	  end
    end
  end
  
  if data["Upgrade"]:lower() ~= "websocket" or data["Connection"]:lower() ~= "upgrade" then
    return false, "Wrong Handshake. Server doesn't support Websocket";
  end
  
  if data["Sec-WebSocket-Protocol"] ~= "chat" and data["Sec-WebSocket-Protocol"] ~= nil then
    return false, "Server doesn't support \"chat\"-protocol";
  end
  
  remainLen = message:len() - off;
  remain = nil;
  if remainLen >= 2 then
    remain = ws_tool.toByteArray(message:sub(off+1));
  end
  
  return true, remain;
end

ws_tool.readFrame = function(data)
  frame = {};
  
  --1. byte
  msk_fin = data[1] & 0x80;
  if msk_fin ~= 0 then
    frame.fin = 1;
  else
    frame.fin = 0;
  end
  frame.opcode = data[1] & 0x0f;
  
  --2. byte
  mmask = 0;
  msk_mask = data[2] & 0x80;
  if msk_mask ~= 0 then
     mmask = 1;
  end
  len1 = data[2] & 0x7f;
  
  offset = 2;
  
  --(extendet len) 3, 4, 5, 6, 7, 8 byte 
  if len1 <= 125 then
    frame.len = len1;
  elseif len1 == 126 then
    frame.len = 0;
    for i=1, 2 do
       frame.len = (frame.len << 8) | data[offset+i];
    end
    offset = offset + 2;
  else
    frame.len = 0;
    for i=1, 8 do
       frame.len = (frame.len << 8) | data[offset+i];
    end
    offset = offset + 8;
  end
  
  msk = {0,0,0,0}
  if mmask == 1 then
    frame.mask = 0;
    for i = 1, 4 do
      mb = data[offset+i];
      msk[i] = mb;
      frame.mask = (frame.mask<<8) | mb;
    end
    offset = offset + 4;
  end
  
  --mask bytes
  frame.dat = {};
  for i=1, frame.len do
    table.insert(frame.dat, data[offset+i] ~ msk[((i-1)%4)+1]);
  end
  
  offset = offset + frame.len;
  remainLen = #data - offset;
  remain = nil;
  
  if remainLen >= 2 then
	remain = {};
	for i=0, remainLen do
	  remain[i] = data[i+offset];
	end
  end
  
  return frame, remain;
end

ws_tool.makeFrame = function(data)
  bytes = {};
  
  --1. byte
  m_fin = 0x00;
  if data.fin then
     m_fin = 0x80;
  end
  m_opcode = ( data.opcode or 0x00 ) & 0x0f;
  table.insert(bytes, m_fin | m_opcode);
  
  --2. byte
  m_mask = 0x00;
  if data.mask then
    m_mask = 0x80;
  end
  
  m_len1 = 0x00;
  if data.len <= 125 then
    m_len1 = data.len
  elseif data.len <= 0xffff then
    m_len1 = 126;
  else
    m_len1 = 127;
  end
  table.insert(bytes, m_mask | m_len1);
  
  --(extended len) 3, 4, 5, 6, 7, 8 byte 
  if m_len1 > 125 then
    if m_len1 == 126 then
      table.insert(bytes, (data.len >> 8) & 0xff)
      table.insert(bytes, data.len & 0xff);
    elseif m_len1 == 127 then
      table.insert(bytes, (data.len >> 56) & 0xff);
      table.insert(bytes, (data.len >> 48) & 0xff);
      table.insert(bytes, (data.len >> 40) & 0xff);
      table.insert(bytes, (data.len >> 32) & 0xff);
      table.insert(bytes, (data.len >> 24) & 0xff);
      table.insert(bytes, (data.len >> 16) & 0xff);
      table.insert(bytes, (data.len >> 8) & 0xff);
      table.insert(bytes, data.len & 0xff);
    end
  end
  
  --mask bytes
  msk = {0,0,0,0};
  if data.mask then
    msk[1] = (data.mask >> 24) & 0xff;
    msk[2] = (data.mask >> 16) & 0xff;
    msk[3] = (data.mask >> 8) & 0xff;
    msk[4] = data.mask & 0xff;
    table.insert(bytes, msk[1]);
    table.insert(bytes, msk[2]);
    table.insert(bytes, msk[3]);
    table.insert(bytes, msk[4]);
  end
  
  for i=1, data.len do
    table.insert(bytes, data.dat[i] ~ msk[((i-1)%4)+1]);
  end
  
  return bytes;
end

ws_tool.generateMask = function()
  return math.random(0xffffffff);
end

ws_tool.fromByteArray = function(bytes)
  str = '';
  for _,b in pairs(bytes) do
	str = str..string.char(b);
  end
  return str;
end

ws_tool.toByteArray = function(str)
  return { string.byte(str, 1, -1) };
end

return ws_tool;