-- Imports --

local args, options = shell.parse(...)
local component = require("component")
local event = require("event")
local filesystem = require("filesystem")
inspect = require("inspect")

if not component.isAvailable("tape_drive") then
    io.stderr:write("This program requires a tape drive to run.")
    return
end

local tape_drives = component.list("tape_drive")
local tape_drive_ids = {}
for k, v in pairs(tape_drives) do
    table.insert(tape_drive_ids, k)
end

local ws = require("websocket_client");
local json = require("json");

-- Sanity checks --

shell.execute("ps")

for k, _ in pairs(tape_drives) do
    local tape = component.proxy(k)
    if not tape.isReady() then
        io.stderr:write("A tape drive is missing a tape.")
        return
    end
end

-- Global --

local do_ack = false
local socket_host = "e.mynetgear.com"

local do_play = false;
local load_chunk = false;
local tape_address = "";
local last_tape_address = "";
local last_tape_change = 0;
local last_chunk = "";
local set_chunk = options.chunk or ""

do_restart = false

-- Utility --

local function clean_state(reset_meta)
    for k, _ in pairs(tape_drives) do
        shell.execute("tape --address=" .. k .. " stop")
        shell.execute("tape --address=" .. k .. " rewind")
        if reset_meta then
            filesystem.remove("/nextchunk")
            local tape = component.proxy(k)
            tape.setSpeed(2)
            tape.setVolume(1)
        end
    end
end

local function tick_epoch()
    return os.time() * (1000/60/60)
end

local function debug_print(line)
    if options.debug then
        print(line)
    end
end

-- Main logic --

local function get_payload(chunk_id, payload_address)
    debug_print("Write payload before")
    last_chunk = chunk_id
    shell.execute("time wget -f http://" .. socket_host .. ":5000/chunk/" .. chunk_id .. " /nextchunk")
    debug_print("Write payload after")

    if last_tape_address == "" then
        last_tape_address = payload_address
        tape_address = payload_address
    end

    last_tape_address = tape_address
    tape_address = payload_address
    do_play = true
end

local on_ws_event = function(ws_event, payload)
    print("Got a " .. ws_event .. " payload of length " .. string.len(payload))

    payload = json.decode(payload)

    if ws_event:lower() == "text" then
        if payload["cmd"] == "ping" then
            print("Got ping.")
        elseif payload["cmd"] == "getinfo" then
            print("Got info request.")
            event.push("sendinfo")
        elseif payload["cmd"] == "getchunk" then
            get_payload(payload["chunk_id"], payload["address"])
        end
    else
        print(ws_event .. "->" .. payload)
    end
end

-- Clean the tape drive state before starting up
clean_state(true)

-- Main socket loop
local cl = ws.create(on_ws_event);
cl:connect(socket_host, 5000, "/");

local ping_timer = event.timer(1, function()
    -- Restart the program if we haven't outputted audio for a while.
    if last_tape_change ~= 0 and (tick_epoch() > (last_tape_change + 140)) then
        io.stderr:write((tick_epoch() - last_tape_change) .. "\n")
        io.stderr:write("No tape change for 140 ticks. Restarting!\n")
        event.push("restart")
    end

    if set_chunk ~= "" then
        cl:send(json.encode({
            cmd = "setchunk",
            i = set_chunk
        }))
        set_chunk = ""
    end

    if do_play then
        print("Write: " .. last_chunk)
        shell.execute("tape -y --b=8192 --address=" .. tape_address .. " write /nextchunk")
        -- No audio data size is 128 from observations.
        if filesystem.size("/nextchunk") == 128 then
            set_chunk = ""
        end
        do_play = false
        load_chunk = true
    end

    event.push("ping")
end, math.huge)

local chunk_timer = event.timer(0.15, function()
    event.push("updatesocket")

    if not load_chunk then
        return
    end

    -- arbitary magic tick number
    if not (tick_epoch() > (last_tape_change + 98)) then
        return
    end

    -- Take over first to prevent race conditions.
    load_chunk = false
    last_tape_change = tick_epoch()

    -- Play the new tape and stop it after .75 seconds to compensate for tape delay.
    print("Changing: " .. last_chunk)
    event.push("ack")
    shell.execute("tape --address=" .. tape_address .. " volume 1")
    shell.execute("tape --address=" .. tape_address .. " play")
    if not (tape_address == last_tape_address) then
        event.timer(1.25, function()
            shell.execute("tape --address=" .. last_tape_address .. " volume 0")
            shell.execute("tape --address=" .. last_tape_address .. " stop")
        end, 1)
    end
end, math.huge)

while true do
    local ev = {event.pull()}

    -- Socket push events
    if ev[1] == "updatesocket" then
        local ok, update_status = pcall(cl.update, cl)
        if not ok then
            io.stderr:write(update_status .. "\n")
            do_restart = true
            break;
        end
    elseif not cl:isConnected() then
        io.stderr:write(ev[1] .. ": Socket not connected! Things might not send!\n")
    elseif ev[1] == "sendinfo" then
        cl:send(json.encode({
            cmd = "drives",
            drives = tape_drive_ids
        }))
    elseif ev[1] == "ack" then
        cl:send(json.encode({
            cmd = "ack"
        }))
    elseif ev[1] == "ping" then
        cl:send(json.encode({
            cmd = "ping"
        }))
    else
        debug_print(ev[1])
    end

    -- Control events
    if ev[1] == "interrupted" then
        break;
    elseif ev[1] == "restart" then
        do_restart = true
        break;
    end
end

-- Cleanup
event.cancel(ping_timer)
event.cancel(chunk_timer)
cl:disconnect()
for k, _ in pairs(tape_drives) do
    shell.execute("tape --address=" .. k .. " stop")
end

-- Restart if applicable
if do_restart then
    extra_args = ""

    if options.debug then
        extra_args = extra_args .. " --debug"
    end

    print("Restarting with CLI " .. "streamer --chunk=" .. last_chunk .. extra_args)
    os.sleep(1)

    shell.execute("streamer --chunk=" .. last_chunk .. extra_args)
end