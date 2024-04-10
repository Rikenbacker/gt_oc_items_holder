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
    shootDown = false,           -- Пора вырубаться
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

    for address, type in component.list() do
        if type == interface and obj[interface] == nil then
            obj[interface] = component.proxy(address)
        end
    end
    
    function obj.getInterface()
        return obj[interface]
    end
    
    
    function obj.makeLabel(item)
        return item.name .. "/" .. item.damage
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
    
    function obj.checkItem(type, item, count)
        if type == "Esentia" then
            local aspects = obj[interface].getEssentiaInNetwork()

            local match = false
            for j = 1, #aspects do            
                if aspects[j].name == item then
                    if aspects[j].amount >= count then
                        return true
                    end
                end
            end

            if match == false then
                fullMatch = false
                status.message = "&yellow;Not enought: " .. essentia.getLabel(recipe.aspects[i].name) .. " (" .. count .. ")"
                obj.craftingAspect(recipe.aspects[i].name, count, essentia)
            end
        end

        return false
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
    local items = Items.new()

    if tools.getInterface() ~= nil then
        print("ME Interface found")
    else
        print("ERROR: ME Interface not found!")
        return 1
    end
    
    print("Items loaded:", items.getCount())
    
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