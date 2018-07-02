-- Imports --

local component = require("component")
local event = require("event")

if not component.isAvailable("tape_drive") then
    io.stderr:write("This program requires a tape drive to run.")
    return
end

local tape_drives = component.list("tape_drive")
local tape_drive_ids = {}
for k, v in pairs(tape_drives) do
    table.insert(tape_drive_ids, k)
end


if not component.isAvailable("internet") then
    io.stderr:write("This program requires an internet card to run.")
    return
end
local internet = require("internet")

local ws = require("websocket_client");
local json = require("json");

-- Global --
local send_info = false
local do_ack = false
local socket_host = "982ddf77.ngrok.io"

local do_play = false;
local load_chunk = false;
local tape_address = "";
local last_tape_address = "";
local last_tape_change = 0;

-- Sanity checks --

for k, _ in pairs(tape_drives) do
    local tape = component.proxy(k)
    if not tape.isReady() then
        io.stderr:write("A tape drive is missing a tape.")
        return
    end
end

-- Utility --

local function clean_state(reset_meta)
    for k, _ in pairs(tape_drives) do
        shell.execute("tape --address=" .. k .. " stop")
        shell.execute("tape --address=" .. k .. " rewind")
        if reset_meta then
            local tape = component.proxy(k)
            tape.setSpeed(1)
            tape.setVolume(1)
        end
    end
end

local function tick_epoch()
    return os.time() * (1000/60/60)
end

-- Main logic --

local function get_payload(payload_i, payload_address)
    print("Write payload before")
    shell.execute("time wget -f http://" .. socket_host .. "/chunk/" .. payload_i .. " nextchunk")
    -- shell.execute("tape write --b=8192 -y http://" .. socket_host .. "/chunk/" .. payload_i)
    print("Write payload after")
    if last_tape_address == "" then
        last_tape_address = payload_address
        tape_address = payload_address
    end

    last_tape_address = tape_address
    tape_address = payload_address
    do_play = true
end

local on_ws_event = function(event, payload)
    print("Got a " .. event .. " payload of length " .. string.len(payload))

    payload = json.decode(payload)

    if event:lower() == "text" then
        if payload["cmd"] == "ping" then
            print("Got ping.")
        elseif payload["cmd"] == "getinfo" then
            print("Got info request.")
            send_info = true
        elseif payload["cmd"] == "getchunk" then
            get_payload(payload["chunk_i"], payload["address"])
        end
    else
        print(event .. "->" .. payload)
    end
end


local function make_socket()
    local cl = ws.create(on_ws_event, false);
    cl:connect(socket_host, 80, "/", false);
    return cl
end

-- Clean the tape drive state before starting up
clean_state(true)

-- Main socket loop
local cl = make_socket()

local ping_timer = event.timer(0.50, function()
    if do_play then
        shell.execute("tape --address=" .. tape_address .. " write --b=8192 -y nextchunk")
        do_play = false
        load_chunk = true
    end

    if send_info then
        cl:send(json.encode({
            cmd = "drives",
            drives = tape_drive_ids
        }))
        send_info = false
    end

    cl:send(json.encode({
        cmd = "ping"
    }))
    cl:update()
end, math.huge)

local chunk_timer = event.timer(0.15, function()
    if not load_chunk then
        return
    end

    -- arbitary magic tick number
    print((tick_epoch() - (last_tape_change + 98)))
    if not (tick_epoch() > (last_tape_change + 98)) then
        return
    end

    -- Take over first to prevent race conditions.
    load_chunk = false
    last_tape_change = tick_epoch()

    -- Play the new tape and stop it after .75 seconds to compensate for tape delay.
    shell.execute("tape --address=" .. tape_address .. " volume 1")
    shell.execute("tape --address=" .. tape_address .. " play")
    if not (tape_address == last_tape_address) then
        event.timer(1.25, function()
            shell.execute("tape --address=" .. last_tape_address .. " volume 0")
            shell.execute("tape --address=" .. last_tape_address .. " stop")
        end, 1)
    end

    -- Send ACK to say we are ready for another chunk.
    cl:send(json.encode({
        cmd = "ack"
    }))
end, math.huge)

while true do
    local ev = {event.pull()}
    print(ev[1])

    if ev[1] == "interrupted" then
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
