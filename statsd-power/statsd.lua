local internet = require("internet")
local component = require("component")
local event = require("event")

local computerid = component.computer.address

local function gauge(name, value) 
    local handle, handle_err = internet.open("192.168.11.1", 8125)

    if handle_err then
        print("Failed to connect to statsd. " .. handle_err)
        return
    end

    handle:write(name .. ":" .. tostring(value) .. "|g\n")
    handle:close()
end

local push_timer = event.timer(1, function()
    event.push("push")
end, math.huge)

local function main()
    while true do
        local ev = {event.pull()}

        if ev[1] == "push" then
            local energy = component.draconic_rf_storage.getEnergyStored()
            gauge("rf_storage." .. computerid, energy)
            print(tostring(energy) .. " RF.")
        end
        -- Control events
        if ev[1] == "interrupted" then
            return
        end
    end
end

main()
event.cancel(push_timer)