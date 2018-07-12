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

local function push()
    -- Draconic cap data
    if component.isAvailable("draconic_rf_storage") then
        for cell_address, _ in pairs(component.list("draconic_rf_storage")) do
            local cell = component.proxy(cell_address)
            local energy = cell.getEnergyStored()
            local tag = "rf_storage,type=draconic,computer=" .. computerid .. ",cell=" .. cell_address

            gauge(tag, energy)
            print(cell_address .. " - " .. tostring(energy) .. " RF.")
        end
    end
end

local function main()
    while true do
        local ev = {event.pull()}

        if ev[1] == "push" then
            push()
        end
        -- Control events
        if ev[1] == "interrupted" then
            return
        end
    end
end

main()
event.cancel(push_timer)