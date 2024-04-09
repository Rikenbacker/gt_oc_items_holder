-- GUI OC
-- Author: CAHCAHbl4
-- Edit: Rikenbacker
-- License: MIT

local raGUI = { _version = "0.0.1" }

local palette = {
    white = 0xFFFFFF, -- white
    black = 0x000000, -- black
    red = 0xCC0000, -- red
    green = 0x009200, -- green
    blue = 0x0000C0, -- blue
    yellow = 0xFFDB00 -- yellow
}

local template = {
    width = 32,
    background = palette.black,
    foreground = palette.white,
    lines = {}
}

local formatters = {
    s = function(value, format)
        if (value == nil) then
            return ""
        else
            format = (format and format or "%.2f")
            return string.format(format, value)
        end
    end,

    si = function(value, unit, format)
        format = (format and format or "%.2f")
        local incPrefixes = {"k", "M", "G", "T", "P", "E", "Z", "Y"}
        local decPrefixes = {"m", "μ", "n", "p", "f", "a", "z", "y"}

        local prefix = ""
        local scaled = value

        if value ~= 0 then
            local degree = math.floor(math.log(math.abs(value), 10) / 3)
            scaled = value * 1000 ^ -degree
            if degree > 0 then
                prefix = incPrefixes[degree]
            elseif degree < 0 then
                prefix = decPrefixes[-degree]
            end
        end

        return string.format(format, scaled) .. " " .. prefix .. (unit and unit or "")
    end,

    t = function(secs, parts)
        parts = (parts and parts or 4)

        local units = {"d", "hr", "min", "sec"}
        local result = {}
        for i, v in ipairs({86400, 3600, 60}) do
            if secs >= v then
                result[i] = math.floor(secs / v)
                secs = secs % v
            end
        end
        result[4] = secs

        local resultString = ""
        local i = 1
        while parts ~= 0 and i ~= 5 do
            if result[i] and result[i] > 0 then
                if i > 1 then
                    resultString = resultString .. " "
                end
                resultString = resultString .. result[i] .. " " .. units[i]
                parts = parts - 1
            end
            i = i + 1
        end
        return resultString
    end
}

ScreenController = {}
function ScreenController.new(gpuIn, textLines)
    local obj = {}
    local gpu = gpuIn
    
    template.lines = textLines
    
    local width, height = template.width, #template.lines

    gpu.setResolution(width, height)

    function obj.split(string, delimiter)
        local splitted = {}
        for match in string:gmatch("([^" .. delimiter .. "]+)") do
            table.insert(splitted, match)
        end
        return splitted
    end

    function obj.evaluateConditions(line, values)
        return string.gsub(
            line,
            "?(.-)?",
            function(pattern)
                local condition, left, right = pattern:match("^(.*)|(.*)|(.*)$")
                local f = ""
                for key, value in pairs(values) do
                    f = f .. "local " .. key .. "="
                    if type(value) == "string" then
                        f = f .. "'" .. value .. "'\n"
                    else
                        f = f .. value .. "\n"
                end
            end
            f = f .. "return " .. condition
            f = load(f)
            if f then
                local result = f()
                return result and left or right
            end
        end
        )
    end

    function obj.evaluateValues(line, values)
        return string.gsub(
            line,
            "%$(.-)%$",
            function(pattern)
                local formatter
                local variable, args = pattern:match("^(.+):(.+)$")
                if not variable then
                    variable = pattern
                    formatter = "s"
                    args = {"%s"}
                else
                    args = obj.split(args, ",")
                    formatter = args[1]
                    table.remove(args, 1)
                end

                if formatter then
                    return formatters[formatter](values[variable], table.unpack(args))
                end
                    return values[variable]
                end
        )
    end

  function obj.evaluateWidgets(line, values, n)
    return string.gsub(
      line,
      "#(.-)#",
      function(pattern)
        local name, args = pattern:match("^(.+):(.+)$")

        if not name then
          name = pattern
          args = {}
        else
          args = split(args, ",")
        end

        if _widgets[n][name] then
          return _widgets[n][name](values, args)
        end
      end
    )
  end

    function obj.render(values)
        local buffer = gpu.allocateBuffer(width, height)
        gpu.setActiveBuffer(buffer)
        
        local i = 1
        for _, line in pairs(template.lines) do
            gpu.setBackground(template.background)
            gpu.setForeground(template.foreground)

            local rendered = obj.evaluateConditions(line, values)
            rendered = obj.evaluateValues(rendered, values)
            rendered = obj.evaluateWidgets(rendered, values, n)

            local j, k = 1, 1

            while j <= #rendered do
                local c = rendered:sub(j, j)
                if c == "&" then
                    local cstr = ""
                    local bg = false

                    if rendered:sub(j + 1, j + 1) == "&" then
                        bg = true
                        j = j + 1
                    end

                    repeat
                        j = j + 1
                        local next = rendered:sub(j, j)
                        if next ~= ";" then
                            cstr = cstr .. next
                        end
                    until next == ";"

                    local color
                    if palette[cstr] then
                        color = palette[cstr]
                    else
                        local hex = tonumber(cstr)
                        if hex then
                            color = hex
                        end
                    end

                    if color then
                        if bg then
                            gpu.setBackground(color)
                        else
                            gpu.setForeground(color)
                        end
                    end

                    j = j + 1
                else
                    gpu.set(k, i, c)
                    k = k + 1
                    j = j + 1
                end
            end
            
            i = i + 1
        end
        
        gpu.bitblt(0, 1, 1, width, height, buffer, 1, 1)

        gpu.freeAllBuffers()
    end

    function obj.resetScreen()
        local w, h = gpu.maxResolution()
        gpu.freeAllBuffers()
        gpu.setResolution(w, h)
        gpu.fill(1, 1, w, h, " ")
    end

    return obj
end

return raGUI