local Scene = {}
Scene.__index = Scene

function Scene.new(game)
    local self = setmetatable({}, Scene)

    self.game = game

    return self
end

function Scene:update(dt)
    -- ...
end

function Scene:draw()
    -- ...
end

--[[
function Scene:load()
end

function Scene:unload()
end

function Scene:gamepadpressed(joystick, button, player)
end
]]--

return Scene