local function handleItem(item, redstone)
    if not item then
        return
    end

    if redstone and item.name ~= "minecraft:redstone_block" then
        turtle.dropUp()
    else
        turtle.drop()
    end
end

local function sanityCheck(allowStar)
    local bookslot = turtle.getItemDetail(1)
    local starslot = turtle.getItemDetail(2)

    local doFix = false

    if not bookslot then
        doFix = "book"
    elseif bookslot.name ~= "xreliquary:alkahestry_tome" then
        doFix = "book"
    elseif allowStar and not starslot then
        doFix = "star"
    elseif allowStar and bookslot.name ~= "minecraft:nether_star" then
        doFix = "star"
    end

    if doFix ~= "book" then
        if bookslot.damage < 800 then
            doFix = "star"
        end
    end

    if doFix then
        for slot=1,16 do
            turtle.select(17 - slot)
            local item =  turtle.getItemDetail()
            if item then
                if doFix == "book" then
                    if item.name == "xreliquary:alkahestry_tome" then
                        turtle.transferTo(1)
                        return true
                    end
                elseif allowStar and doFix == "star" then
                    if item.name == "minecraft:nether_star" then
                        turtle.transferTo(11)
                    end
                    return true
                end
            end
        end

        -- Could not fix the state.
        return false
    end

    return true
end

local function craft(craft_redstone)
    local finished = false;

    for slot=2,12 do
        if (slot % 4) ~= 0 then
            turtle.select(slot)
            handleItem(turtle.getItemDetail(), craft_redstone)
            if craft_redstone then
                turtle.suck()
            else
                if not finished and turtle.suckUp(1) then
                    finished = true
                end
            end
        end
    end



    while true do
        if not sanityCheck(not craft_redstone) then
            print("Broken state happened somehow.")
        end

        local crafted = turtle.craft()
        if not crafted then
            break
        end
    end
end

while true do
    craft(true)
    print("owo got redstone?")
    craft(false)
    print("take a look at all these stars")
end