local TitleScene = require("scenes/title")
local GameScene = require("scenes/game")

---------------------------

local game = {
    -- vars
    scenes = {},
    
    -- game state
    currentScene = nil,
    players = {
        --[[
        {
            joystickID = joystick:getID(),
            colour = "red" | "blue" | "green" | "yellow",
            score = 0,
            position = {x, y}, -- only matters for title screen
            velocity = {vx, vy}, -- only matters for title screen
        }
        ]]--
    },
    winners = {
        -- list of player colours who have won
    },
    pucks = {
        --[[
        {
            colour = "red" | "blue" | "green" | "yellow"
            position = {x, y},
            velocity = {vx, vy},
            radius = 15,
        }
        ]]--
    },

    -- assets
    images = {},
    fonts = {},

    -- constants
    constants = {
        MAX_DT = 1/30,
        PUCK_RADIUS = 35,
        JOYSTICK_DEADZONE = 0.2,
    },

    -- functions
    getJoystickByID = function(self, id)
        local joysticks = love.joystick.getJoysticks()
        for _, joystick in ipairs(joysticks) do
            if joystick:getID() == id then
                return joystick
            end
        end
        return nil
    end,
    getPlayerByJoystickID = function(self, id)
        for _, player in ipairs(self.players) do
            if player.joystickID == id then
                return player
            end
        end
        return nil
    end,
    setScene = function (self, scene)
        if self.currentScene and self.currentScene.unload then
            self.currentScene:unload()
        end
        self.currentScene = scene
        if self.currentScene and self.currentScene.load then
            self.currentScene:load()
        end
    end,
}

---------------------------

function love.load()
    love.window.setFullscreen(true)
    love.mouse.setVisible(false)

    game.images.pulp = love.graphics.newImage("assets/pulp.png")
    game.images.ownership_blue = love.graphics.newImage("assets/ownership_blue.png")
    game.images.ownership_green = love.graphics.newImage("assets/ownership_green.png")
    game.images.ownership_yellow = love.graphics.newImage("assets/ownership_yellow.png")
    game.images.ownership_red = love.graphics.newImage("assets/ownership_red.png")
    game.images.puck_sizer = love.graphics.newImage("assets/puck_sizer.png")
    game.images.puck_blue = love.graphics.newImage("assets/puck_blue.png")
    game.images.puck_green = love.graphics.newImage("assets/puck_green.png")
    game.images.puck_yellow = love.graphics.newImage("assets/puck_yellow.png")
    game.images.puck_red = love.graphics.newImage("assets/puck_red.png")
    game.images.rect = love.graphics.newImage("assets/rect.png")
    game.images.rrect = love.graphics.newImage("assets/rrect.png")
    game.images.up = love.graphics.newImage("assets/up.png")
    game.images.arrowhead = love.graphics.newImage("assets/arrowhead.png")

    game.fonts.titleFont = love.graphics.newFont("assets/font.ttf", 72)
    game.fonts.smallFont = love.graphics.newFont("assets/font.ttf", 36)

    game.scenes.title = TitleScene.new(game)
    game.scenes.game = GameScene.new(game)

    game:setScene(game.scenes.title)
end

function love.update(dt)
    if dt > game.constants.MAX_DT then
        dt = game.constants.MAX_DT
    end

    if game.currentScene and game.currentScene.update then
        game.currentScene:update(dt)
    end
end

function love.draw()
    love.graphics.setBackgroundColor(1, 1, 1, 1)
    -- Draw pulp background scaled to cover screen
    local pulpWidth = game.images.pulp:getWidth()
    local pulpHeight = game.images.pulp:getHeight()
    local screenWidth = love.graphics.getWidth()
    local screenHeight = love.graphics.getHeight()
    
    -- Calculate scale to cover the entire screen
    local scaleX = screenWidth / pulpWidth
    local scaleY = screenHeight / pulpHeight
    local scale = math.max(scaleX, scaleY) -- Use the larger scale to ensure coverage
    
    -- Calculate position to center the image
    local scaledWidth = pulpWidth * scale
    local scaledHeight = pulpHeight * scale
    local offsetX = (screenWidth - scaledWidth) / 2
    local offsetY = (screenHeight - scaledHeight) / 2
    
    love.graphics.draw(game.images.pulp, offsetX, offsetY, 0, scale, scale)

    if game.currentScene and game.currentScene.draw then
        game.currentScene:draw()
    end
end

function love.gamepadpressed(joystick, button)
    if game.currentScene and game.currentScene.gamepadpressed then
        local player = game:getPlayerByJoystickID(joystick:getID())
        if player then
            game.currentScene:gamepadpressed(joystick, button, player)
        end
    end
end

function love.joystickadded(joystick)
    if game.currentScene ~= game.scenes.title then
        -- Don't add new joysticks mid-game
        return
    end

    if game:getPlayerByJoystickID(joystick:getID()) then
        -- Player already added
        return
    end

    -- Take the next available colour [red, blue, green, yellow]
    local colours = {"red", "blue", "green", "yellow"}
    for _, player in ipairs(game.players) do
        for i, colour in ipairs(colours) do
            if player.colour == colour then
                table.remove(colours, i)
                break
            end
        end
    end

    local colour = colours[1]
    table.insert(game.players, {
        joystickID = joystick:getID(),
        colour = colour,
        puckCounter = 0,
        position = {x = love.math.random(100, love.graphics.getWidth() - 100), y = love.math.random(100, love.graphics.getHeight() - 100)},
        velocity = {x = 0, y = 0},
    })
end

function love.joystickremoved(joystick)
    -- If we are on the menu screen, remove the player
    if game.currentScene == game.scenes.title then
        for i, player in ipairs(game.players) do
            if player.joystickID == joystick:getID() then
                table.remove(game.players, i)
                break
            end
        end
    end
end