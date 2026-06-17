controls = {}
controls.settings = {}

controls.settings.left = {"key", {"left"}}
controls.settings.right = {"key", {"right"}}
controls.settings.up = {"key", {"up"}}
controls.settings.down = {"key", {"down"}}
controls.settings["return"] = {"key", {"return", "kpenter"}}
controls.settings.escape = {"key", {"escape"}}
controls.settings.rotateleft = {"key", {"z"}}
controls.settings.rotateright = {"key", {"x"}}

controls.settings.p1left = {"key", {"a"}}
controls.settings.p1right = {"key", {"d"}}
controls.settings.p1down = {"key", {"s"}}
controls.settings.p1rotateleft = {"key", {"g"}}
controls.settings.p1rotateright = {"key", {"h"}}

controls.settings.p2left = {"key", {"left"}}
controls.settings.p2right = {"key", {"right"}}
controls.settings.p2down = {"key", {"down"}}
controls.settings.p2rotateleft = {"key", {"kp1"}}
controls.settings.p2rotateright = {"key", {"kp2"}}

function controls.check(t, key)
	if controls.settings[t][1] == "key" then
		for i = 1, #controls.settings[t][2] do
			if key == controls.settings[t][2][i] then
				return true
			end
		end
		return false
	end
end

function controls.isDown(t)
	if controls.settings[t][1] == "key" then
		for i = 1, #controls.settings[t][2] do
			if love.keyboard.isDown(controls.settings[t][2][i]) then
				return true
			end
		end
		return false
	end
end

local function parseKeyToken(token)
	local t = token:match("^%s*(.-)%s*$")
	if t == "comma" then return "," end
	if t == "period" then return "." end
	return t
end

function controls.setBinding(action, keys_str)
	local keys = {}
	for token in string.gmatch(keys_str, "([^,]+)") do
		local realKey = parseKeyToken(token)
		if #realKey > 0 then
			table.insert(keys, realKey)
		end
	end
	controls.settings[action] = {"key", keys}
end

function controls.getBinding(action)
    if controls.settings[action] and controls.settings[action][1] == "key" then
        local parts = {}
        for i, k in ipairs(controls.settings[action][2]) do
            if k == "," then
                parts[i] = "comma"
            elseif k == "." then
                parts[i] = "period"
            else
                parts[i] = k
            end
        end
        return table.concat(parts, ",")
    end
    return ""
end