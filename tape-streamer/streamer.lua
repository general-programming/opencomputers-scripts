-- Imports --

local component = require("component")
local event = require("event")

if not component.isAvailable("tape_drive") then
    io.stderr:write("This program requires a tape drive to run.")
    return
end
local tape = component.tape_drive

if not component.isAvailable("internet") then
    io.stderr:write("This program requires an internet card to run.")
    return
end
local internet = require("internet")

local ws = require("websocket_client");

-- Sanity checks --

if not tape.isReady() then
    io.stderr:write("The tape drive does not contain a tape.")
    return
end

-- Utility --

local function rewind()
    tape.seek(-tape.getSize())
end

local function stop()
    tape.stop()
end

local function play()
    tape.play()
end

local function clean_state(reset_meta)
    stop()
    rewind()
    if reset_meta then
        tape.setSpeed(1)
        tape.setVolume(1)
    end
end

local function writeTape(path)
    local file, msg, _, y
    local block = 2048

    tape.stop()
    tape.seek(-tape.getSize())
    tape.stop() --Just making sure
  
    local bytery = 0
    local filesize = tape.getSize()

    local function setupConnection(url)
        local file, reason = internet.request(url)
        
        if not file then
            io.stderr:write("error requesting data from URL: " .. reason .. "\n")
            return false
        end
        
        local connected, reason = false, ""
        local timeout = 50
        
        for i = 1, timeout do
            connected, reason = file.finishConnect()
            os.sleep(.1)
            if connected or connected == nil then
                break
            end
        end
        
        if connected == nil then
            io.stderr:write("Could not connect to server: " .. reason)
            return false
        end
        
        local status, message, header = file.response()

        if header and header["Content-Length"] and header["Content-Length"][1] then
            filesize = tonumber(header["Content-Length"][1])
        end

        if filesize > tape.getSize() then
            io.stderr:write("Warning: File is too large for tape, shortening file\n")
            filesize = tape.getSize()
          end

        if status then
            status = string.format("%d", status)
            if status:sub(1,1) == "2" then
                return true, {
                    close = function(self, ...) return file.close(...) end,
                    read = function(self, ...) return file.read(...) end,
                }, header
            end
            return false
        end
        io.stderr:write("no valid HTTP response - no response")
        return false
    end
    
    local success, header
    success, file, header = setupConnection(path)
    if not success then
        if file then
            file:close()
        end
        return
    end
    
    repeat
        local bytes = file:read(block)
        if not tape.isReady() then
            io.stderr:write("\nError: Tape was removed during writing.\n")
            file:close()
            return
          end
        io.stderr:write(".")
        if bytes and #bytes > 0 then
            bytery = bytery + #bytes
            tape.write(bytes)
        end
    until not bytes or bytery > filesize
    file:close()
    print("\nFile closed.")
end

-- Main logic --

local function get_payload(payload_i)
    clean_state(false)
    clean_state(false)
    print("Write payload before")
    writeTape("http://96d60990.ngrok.io/chunk/" .. payload_i)
    print("Write payload after")
    cl:send("ack")
    play()
end

local on_ws_event = function(event, payload)
    print("Got a " .. event .. " payload of length " .. string.len(payload))
    
    if event:lower() == "text" then
        if payload == "ping" then
            print("Got ping payload.")
        elseif string.find(payload, "get:") then
            get_payload(string.sub(payload, 5))
        end
    else
        print(event .. "->" .. payload)
    end
end


local function make_socket()
    local cl = ws.create(on_ws_event, false);
    cl:connect("96d60990.ngrok.io", 80, "/", false);
    return cl
end

local function do_ping()
    cl:send("ping")
end

-- __init__ --
local args = { ... }

-- Clean the tape drive state before starting up
clean_state(true)

-- Main socket loop
local cl = make_socket()
local ping_timer = event.timer(1, function()
    cl:send("ping")
    cl:update()
end, math.huge)

while true do
    local ev = {event.pull()}

    if ev[1] == "interrupted" then
        cl:disconnect()
        event.cancel(ping_timer)
        return;
    end
end