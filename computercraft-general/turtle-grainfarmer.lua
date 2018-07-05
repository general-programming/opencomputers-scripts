local function selectFlint(firstTry)
    if not firstTry then
        firstTry = true
    end

    for slot=1,16 do
        turtle.select(slot)
        local item = turtle.getItemDetail()
        if item and item.name == "minecraft:flint_and_steel" then
            return true
        end
    end

    --- Last ditch if we do not have flint and steels.
    if firstTry then
        local suckUp = turtle.suckUp(1)
        return selectFlint(false)
    end

    return false
end

local function makeFires()
    for i=1,4 do
        turtle.turnLeft()
        local inspectOk, inspectResult = turtle.inspect()
        if not inspectOk then
            turtle.place()
        end
    end
end

local function succ()
    for i=1,4 do
        turtle.turnLeft()
        turtle.suck()
    end
end

local function drop()
    for slot=1,16 do
        turtle.select(slot)
        local item = turtle.getItemDetail()
        if item and item.name == "enderio:item_material" then
            turtle.dropUp()
        end
    end
end

while true do
    local gotFlint = selectFlint()
    if not gotFlint then
        print("Unable to select flint.")
    else
        makeFires()
        print("Made fires.")
        os.sleep(4)
    end
    os.sleep(1)
    succ()
    print("succ succ bby")
    drop()
    print("get in da chest")
end