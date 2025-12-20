local Scene = {}
Scene.__index = Scene

function Scene.new(game)
    local self = setmetatable({}, Scene)

    self.game = game

    return self
end

function Scene:update(dt)
    --
end

function Scene:draw()
    local screenWidth = love.graphics.getWidth()
    local screenHeight = love.graphics.getHeight()
    
    -- Right area is 70% of the screen width, starting at 30%
    local rightAreaStart = screenWidth * 0.3
    local rightAreaWidth = screenWidth * 0.7
    
    -- Grid squares are 13.3% of the screen width
    local squareSize = screenWidth * 0.133
    local gap = 10 -- 10px gap between cells
    
    -- Calculate grid position to center it horizontally in the right area
    local gridWidth = squareSize * 3 + gap * 2 -- 3 squares + 2 gaps
    local gridStartX = rightAreaStart + (rightAreaWidth - gridWidth) / 2
    local gridStartY = (screenHeight - gridWidth) / 2 -- Center vertically on screen
    
    -- Set color to black with 13% opacity
    love.graphics.setColor(0, 0, 0, 0.13)
    
    -- Draw the 3x3 grid
    for row = 0, 2 do
        for col = 0, 2 do
            local x = gridStartX + col * (squareSize + gap)
            local y = gridStartY + row * (squareSize + gap)
            love.graphics.draw(self.game.images.rect, x, y, 0, squareSize / self.game.images.rect:getWidth(), squareSize / self.game.images.rect:getHeight())
        end
    end
    
    -- Reset color to white for other drawing operations
    love.graphics.setColor(1, 1, 1, 1)
end

function Scene:load()
    --
end

function Scene:gamepadpressed(joystick, button, player)
    --
end

return Scene