-- Слежение за остатками в МЕ
-- Версия 1.0.0
-- Автор Rikenbacker

local component = require("component")
local sides = require("sides")
local event = require("event")
local json = require('json')
local thread = require("thread")
local raGui = require("ra_gui")
local gpu = component.gpu

local settings = {
  refreshInterval = 1.0,         -- Время обновления в секундах основного цикла
  refreshMonitorInterval = 0.4,  -- Время обновления экрана
  checkAllItems = false,         -- Проверять в интервал весь список предметов (true), либо по очереди (false)
  itemsFileName = "essentia.json"
}

local stages = {
    wait = "Waiting",
    checkItems = "Check Items",
    createItems = "Create Items"
}

local status = {
    stage = stages.wait,         -- Теущая стадия обработки
    recipeName = nil,            -- Имя опознаного рецепта (только для отображения)
    recipe = nil                 -- Распознаный рецепт
}

local textLines = {
    "Current status: $stage:s,%s$",
    "Recipe: $recipeName:s,%s$",
    "$message$",
    "$craftingName$"--[[,
    "$debugInfo$"
]]--
}

local Items = {}
function Items.new()
   local items = {}

   local f = io.open(settings.itemsFileName, "r")
   if f~=nil then 
        items = json.decode(f:read("*all"))
        io.close(f) 
    end    
    
    function items.getCount()
        return #items
    end
    
    return items
end

local Tools = {}
function Tools.new()
    local obj = {}
    local interface = "me_interface"
    local transposer = "transposer"
    local redstone = "redstone"

    for address, type in component.list() do
        if type == interface and obj[interface] == nil then
            obj[interface] = component.proxy(address)
        elseif type == transposer and obj[transposer] == nil then
            obj[transposer] = component.proxy(address)
        elseif type == redstone and obj[redstone] == nil then
            obj[redstone] = component.proxy(address)
        end
    end
    
    function obj.getInterface()
        return obj[interface]
    end
    
    function obj.getTransposer()
        return obj[transposer]
    end
    
    function obj.getRedstone()
        return obj[redstone]
    end    
    
    function obj.makeLabel(item)
        return item.name .. "/" .. item.damage
    end
    
    function obj.getInput()
        local items = {}
        local values = obj[transposer].getAllStacks(settings.inputSide).getAll()
        for i = 0, #values do
            if values[i].size ~= nil then
                table.insert(items, {name = obj.makeLabel(values[i]), size = values[i].size, position = i})
            end
        end
        
        return items
    end
    
    function obj.checkAltar()
        local values = obj[transposer].getAllStacks(settings.altarSide).getAll()
        for i = 0, #values do
            if values[i].size ~= nil then
                return true
            end
        end
        
        return false
    end 
    
    function obj.craftingAspect(aspect, count, essentia)
        if status.craft ~= nil then
            if status.craft.isCanceled() == true then 
                status.craftingName = "Can't craft " .. essentia.getLabel(aspect) .. ". Recipe canceled."
                status.craft = nil
            elseif status.craft.isDone() == true then 
                status.craftingName = nil
                status.craft = nil
            end
        else
            local craft = obj[interface].getCraftables({aspect = essentia.getAspect(aspect), name = "thaumicenergistics:crafting.aspect"})
            if craft[1] == nil then
                status.craftingName = "Can't craft " .. essentia.getLabel(aspect) .. ". No recipe."
                return nil
            end
        
            status.craft = craft[1].request(count)
            status.craftingName = "Crafting " .. essentia.getLabel(aspect) .. " (" .. count .. ")"
        end
    end
    
    function obj.checkAspects(recipe, essentia)
        local aspects = obj[interface].getEssentiaInNetwork()

        local fullMatch = true
        for i = 1, #recipe.aspects do
            local match = false
            local count = recipe.aspects[i].size
            for j = 1, #aspects do
            
                if aspects[j].name == recipe.aspects[i].name then
                    if aspects[j].amount >= recipe.aspects[i].size then
                        match = true
                    else
                        count = recipe.aspects[i].size - aspects[j].amount
                    end
                end
            end
            
            if match == false then
                fullMatch = false
                status.message = "&yellow;Not enought: " .. essentia.getLabel(recipe.aspects[i].name) .. " (" .. count .. ")"
                obj.craftingAspect(recipe.aspects[i].name, count, essentia)
            end
        end

        return fullMatch
    end
    
    function obj.transferItemsToAltar(inputItems)
        local itemName = inputItems[1].name

        obj[transposer].transferItem(settings.inputSide, settings.altarSide, 1, inputItems[1].position + 1, 1)        
        inputItems[1].size = inputItems[1].size - 1
        
        for i = 1, #inputItems do
            if inputItems[i].size > 0 then
                obj[transposer].transferItem(settings.inputSide, settings.piedestalSide, inputItems[i].size)
            end
        end
        
        obj[redstone].setOutput(settings.redstonePiedestalSide, 15)
        
        local notEmpty = true
        repeat 
            notEmpty = false
            local values = obj[transposer].getAllStacks(settings.altarSide).getAll()
            for i = 1, #values do
                if values[i].label ~= nil then
                    notEmpty = true
                end
            end
            os.sleep(settings.refreshPiedistalInterval)
        until (notEmpty == false)
        
        obj[redstone].setOutput(settings.redstonePiedestalSide, 0)
        
        return itemName
    end
    
    function obj.waitForInfusion(itemName)
        obj[redstone].setOutput(settings.redstoneInfusionSide, 15)
    
        local isDone = false
        if obj[transposer].getStackInSlot(settings.altarSide, 1) ~= nil then
            if obj.makeLabel(obj[transposer].getStackInSlot(settings.altarSide, 1)) ~= itemName then
                isDone = true
            end    
        else 
            status.message = "Error: Result is dissapeared"
            isDone = true
        end
        
        if isDone == true then
            obj[redstone].setOutput(settings.redstoneInfusionSide, 0)
            
            local notEmpty = true
            repeat 
                notEmpty = false
                
                local values = obj[transposer].getStackInSlot(settings.altarSide, 1)
                if values ~= nil then
                    notEmpty = true
                end
                
                obj[transposer].transferItem(settings.altarSide, settings.outputSide)
                
                os.sleep(settings.refreshPiedistalInterval)
            until (notEmpty == false)            
        end
        
        return isDone
    end    
    
    return obj
end

function mainLoop(tools, recipes, essentia)
    while status.shootDown == false do
        if status.stage == stages.waitInput then
            if tools.checkAltar() == true then
                status.message = "&red;ALtar is busy!"
            else
                status.inputItems = tools.getInput()
                if #status.inputItems > 0 then
                    status.recipe = recipes.findRecipe(status.inputItems)
                    if status.recipe == nil then
                        status.message = "&red;Error: Recipe not found!"
                    else
                        status.recipeName = "&green;" .. status.recipe.name
                        status.stage = stages.waitAspects
                    end
                else 
                    status.message = nil
                end
            end
        end
        
        if status.stage == stages.waitAspects then
            if tools.checkAspects(status.recipe, essentia) == true then
                status.stage = stages.transferItems
                status.crafting = nil
                status.message = nil
                status.craftingName = nil
            end
        end    
        
        if status.stage == stages.transferItems then
            status.itemName = tools.transferItemsToAltar(status.inputItems)
            status.stage = stages.waitInfusion
        end
        
        if status.stage == stages.waitInfusion then
            if tools.waitForInfusion(status.itemName) == true then
                status.stage = stages.waitInput
                status.recipe = nil
                status.message = nil
                status.recipeName = nil
            end
        end
        os.sleep(settings.refreshInterval)
    end
end

function main()
    local tools = Tools.new()
    local recipes = Recipes.new()
    local essentia = Essentia.new()

    if tools.getInterface() ~= nil then
        print("ME Interface found")
    else
        print("ERROR: ME Interface not found!")
        return 1
    end
    
    if tools.getTransposer() ~= nil then
        print("Transposer found")
    else
        print("ERROR: Transposer not found!")
        return 1
    end
    
    if tools.getRedstone() ~= nil then
        print("Redstone found")
    else
        print("ERROR: Redstone not found!")
        return 1
    end    
    
    print("Recipes loaded:", recipes.getCount())
    
    thread.create(
      function()
        mainLoop(tools, recipes, essentia)
      end
    ):detach()
    
    local screen = ScreenController.new(gpu, textLines)
    
    repeat
        screen.render(status)
    until event.pull(settings.refreshMonitorInterval, "interrupted")
    
    status.shootDown = true
    screen.resetScreen()
    
end

main()