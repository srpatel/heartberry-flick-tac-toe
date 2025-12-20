local Scene = {}
Scene.__index = Scene

function Scene.new(game)
    local self = setmetatable({}, Scene)

    self.game = game
    
    -- Track charging state for each player
    self.playerCharge = {}
    
    -- Countdown state
    self.countdown = {
        active = false,
        timeLeft = 5,
        timer = 0
    }

    return self
end

function Scene:load()
    -- Reset joysticks!
    for i, player in ipairs(self.game.players) do
        local joystick = self.game:getJoystickByID(player.joystickID)
        if not joystick or not joystick:isConnected() then
            table.remove(self.game.players, i)
        end
    end

    local joysticks = love.joystick.getJoysticks()
    for i, joystick in ipairs(joysticks) do
        local player = self.game:getPlayerByJoystickID(joystick:getID())
        if not player then
            love.joystickadded(joystick)
        end
    end
end

function Scene:update(dt)    
    -- Update countdown if active
    if self.countdown.active then
        self.countdown.timer = self.countdown.timer + dt
        if self.countdown.timer >= 1.0 then
            self.countdown.timer = 0
            self.countdown.timeLeft = self.countdown.timeLeft - 1
            
            if self.countdown.timeLeft <= 0 then
                -- Start the game
                self.game:setScene(self.game.scenes.game)
                return
            end
        end
    end

    for i, player in ipairs(self.game.players) do
        local joystick = self.game:getJoystickByID(player.joystickID)
        if joystick and joystick:isConnected() then
            local leftX = joystick:getGamepadAxis("leftx")
            local leftY = joystick:getGamepadAxis("lefty")

            local rightX = joystick:getGamepadAxis("rightx")
            local rightY = joystick:getGamepadAxis("righty")

            -- Check if stick is moved beyond deadzone
            local magnitude1 = math.sqrt(leftX * leftX + leftY * leftY)
            local magnitude2 = math.sqrt(rightX * rightX + rightY * rightY)
            
            local magnitude = math.max(magnitude1, magnitude2)

            if magnitude2 > magnitude1 then
                leftX = rightX
                leftY = rightY
            end

            -- Initialize player charge data if needed
            if not self.playerCharge[player.joystickID] then
                self.playerCharge[player.joystickID] = {
                    isCharging = false,
                    direction = {x = 0, y = 0},
                    magnitude = 0,
                    previousMagnitude = 0,
                    flickCooldown = 0
                }
            end

            if self.playerCharge[player.joystickID].flickCooldown > 0 then
                self.playerCharge[player.joystickID].flickCooldown = self.playerCharge[player.joystickID].flickCooldown - dt
            end
            
            local flickCooldown = self.playerCharge[player.joystickID].flickCooldown
            local charge = self.playerCharge[player.joystickID]
            local flickThreshold = 0.3 -- How much the magnitude must drop to trigger a flick
            local flick = false

            if magnitude > self.game.constants.JOYSTICK_DEADZONE then
                -- Check if magnitude dropped drastically (flick detected)
                if charge.isCharging and charge.previousMagnitude > 0.4 and 
                   (charge.previousMagnitude - magnitude) > flickThreshold then
                    flick = true
                else
                    -- Start/update charging
                    charge.isCharging = true
                    charge.direction = {x = leftX, y = leftY}
                    charge.magnitude = magnitude
                end
            else
                -- Check if we were charging and now released to deadzone
                if charge.isCharging then
                    -- Apply velocity in opposite direction (flick effect)
                    flick = true
                end
                
                -- Clear charging state
                charge.isCharging = false
            end

            if flick then
                if flickCooldown <= 0 then
                    local flickStrength = 2500 -- Adjust this value to change flick power
                    player.velocity.x = -charge.direction.x * flickStrength * charge.previousMagnitude
                    player.velocity.y = -charge.direction.y * flickStrength * charge.previousMagnitude
                    
                    -- Clear charging state after flick
                    charge.isCharging = false
                    flickCooldown = 0.5 -- Half a second cooldown between flicks
                end
            end
            
            -- Store current magnitude as previous for next frame
            charge.previousMagnitude = magnitude
        end
        
        -- Update player position based on velocity
        player.position.x = player.position.x + player.velocity.x * dt
        player.position.y = player.position.y + player.velocity.y * dt
        
        -- Apply friction
        local friction = 0.98
        player.velocity.x = player.velocity.x * friction
        player.velocity.y = player.velocity.y * friction
    end
    
    -- Handle puck-to-puck collisions
    local puckRadius = 35
    for i = 1, #self.game.players do
        for j = i + 1, #self.game.players do
            local player1 = self.game.players[i]
            local player2 = self.game.players[j]
            
            -- Calculate distance between pucks
            local dx = player2.position.x - player1.position.x
            local dy = player2.position.y - player1.position.y
            local distance = math.sqrt(dx * dx + dy * dy)
            local minDistance = puckRadius * 2
            
            -- Check if pucks are colliding
            if distance < minDistance and distance > 0 then
                -- Normalize collision vector
                local nx = dx / distance
                local ny = dy / distance
                
                -- Separate the pucks
                local overlap = minDistance - distance
                local separationX = nx * overlap * 0.5
                local separationY = ny * overlap * 0.5
                
                player1.position.x = player1.position.x - separationX
                player1.position.y = player1.position.y - separationY
                player2.position.x = player2.position.x + separationX
                player2.position.y = player2.position.y + separationY
                
                -- Calculate relative velocity
                local relativeVelX = player2.velocity.x - player1.velocity.x
                local relativeVelY = player2.velocity.y - player1.velocity.y
                
                -- Calculate relative velocity along collision normal
                local velAlongNormal = relativeVelX * nx + relativeVelY * ny
                
                -- Don't resolve if velocities are separating
                if velAlongNormal > 0 then
                    goto continue
                end
                
                -- Calculate restitution (bounciness)
                local restitution = 0.8
                local j = -(1 + restitution) * velAlongNormal
                
                -- Apply impulse
                local impulseX = j * nx
                local impulseY = j * ny
                
                player1.velocity.x = player1.velocity.x - impulseX * 0.5
                player1.velocity.y = player1.velocity.y - impulseY * 0.5
                player2.velocity.x = player2.velocity.x + impulseX * 0.5
                player2.velocity.y = player2.velocity.y + impulseY * 0.5
            end
            
            ::continue::
        end
    end
    
    -- Handle wall collisions for all players
    for i, player in ipairs(self.game.players) do
        
        -- Keep player on screen
        local screenWidth = love.graphics.getWidth()
        local screenHeight = love.graphics.getHeight()
        local puckRadius = 35 -- Actual puck radius
        
        -- Bounce off walls instead of just stopping
        if player.position.x < puckRadius then
            player.position.x = puckRadius
            player.velocity.x = -player.velocity.x * 0.8 -- Bounce with some energy loss
        elseif player.position.x > screenWidth - puckRadius then
            player.position.x = screenWidth - puckRadius
            player.velocity.x = -player.velocity.x * 0.8 -- Bounce with some energy loss
        end
        
        if player.position.y < puckRadius then
            player.position.y = puckRadius
            player.velocity.y = -player.velocity.y * 0.8 -- Bounce with some energy loss
        elseif player.position.y > screenHeight - puckRadius then
            player.position.y = screenHeight - puckRadius
            player.velocity.y = -player.velocity.y * 0.8 -- Bounce with some energy loss
        end
    end
end

function Scene:draw()
    -- Title in the middle
    local screenWidth = love.graphics.getWidth()
    local screenHeight = love.graphics.getHeight()
    local title = "Flick-Tac-Toe"
    
    love.graphics.setFont(self.game.fonts.titleFont)
    
    local titleWidth = self.game.fonts.titleFont:getWidth(title)
    local titleHeight = self.game.fonts.titleFont:getHeight()
    
    local x = (screenWidth - titleWidth) / 2
    local y = (screenHeight - titleHeight) / 2
    
    -- Draw shadow/base layer in darker color (#797979)
    love.graphics.setColor(0x79/255, 0x79/255, 0x79/255, 1)
    love.graphics.print(title, x, y)
    
    -- Draw main title a few pixels above in lighter color (#959595)
    love.graphics.setColor(0x95/255, 0x95/255, 0x95/255, 1)
    love.graphics.print(title, x, y - 3)
    
    -- Draw winners rrect underneath the title
    if #self.game.winners > 0 then
        local winnersY = y + titleHeight + 20
        local puckWidth = self.game.images.puck_red:getWidth() * 0.5
        local padding = 10
        local spacing = 50
        
        -- Calculate rrect dimensions
        local numWinners = #self.game.winners
        local rrectX = (screenWidth - self.game.images.rrect:getWidth()) / 2
        local rrectY = winnersY

        if numWinners > 5 then
            spacing = (self.game.images.rrect:getWidth() - 50) / (numWinners - 1)
        end
        
        -- Draw the rrect background
        love.graphics.setColor(0, 0, 0, 0.13)
        love.graphics.draw(self.game.images.rrect, rrectX, rrectY)
        
        -- Draw winner pucks inside the rrect
        love.graphics.setColor(1, 1, 1, 1) -- Reset to white for puck images
        local startX = rrectX + self.game.images.rrect:getWidth() / 2
        if numWinners > 1 then
            local totalWidth = (numWinners - 1) * (spacing)
            startX = startX - totalWidth / 2
        end
        for i, winnerColor in ipairs(self.game.winners) do
            local puckImage = self.game.images["puck_" .. winnerColor]
            if puckImage then
                local puckX = startX - puckWidth * 0.5 + (i - 1) * (spacing)
                local puckY = rrectY + (self.game.images.rrect:getHeight() - puckImage:getHeight() * 0.5) * 0.5
                love.graphics.draw(puckImage, puckX, puckY, 0, 0.5, 0.5)
            end
        end
    end
    
    -- Draw instructions or countdown
    if self.countdown.active then
        -- Calculate position below winners or title
        local baseY = y + titleHeight + 20
        if #self.game.winners > 0 then
            local puckSize = 50
            local padding = 10
            baseY = baseY + puckSize + padding * 2 + 20 -- Add space for winners display
        end
        
        -- Draw countdown
        local countdownText = tostring(self.countdown.timeLeft)
        love.graphics.setFont(self.game.fonts.titleFont)
        local countdownWidth = self.game.fonts.titleFont:getWidth(countdownText)
        local countdownX = (screenWidth - countdownWidth) / 2
        local countdownY = baseY
        
        love.graphics.setColor(0x95/255, 0x95/255, 0x95/255, 1) -- Same color as title
        love.graphics.print(countdownText, countdownX, countdownY)
        
        -- Draw cancel instruction at bottom of screen
        local cancelText = "Press B to cancel"
        love.graphics.setFont(self.game.fonts.smallFont)
        local cancelWidth = self.game.fonts.smallFont:getWidth(cancelText)
        local cancelHeight = self.game.fonts.smallFont:getHeight()
        local cancelX = (screenWidth - cancelWidth) / 2
        local cancelY = screenHeight - cancelHeight - 20 -- 20px padding from bottom
        
        love.graphics.setColor(0x95/255, 0x95/255, 0x95/255, 1)
        love.graphics.print(cancelText, cancelX, cancelY)
    else
        -- Draw start instruction at bottom of screen
        local instructionText = "Press A to start"
        love.graphics.setFont(self.game.fonts.smallFont)
        local instructionWidth = self.game.fonts.smallFont:getWidth(instructionText)
        local instructionHeight = self.game.fonts.smallFont:getHeight()
        local instructionX = (screenWidth - instructionWidth) / 2
        local instructionY = screenHeight - instructionHeight - 20 -- 20px padding from bottom
        
        love.graphics.setColor(0x95/255, 0x95/255, 0x95/255, 1)
        love.graphics.print(instructionText, instructionX, instructionY)
    end
    
    -- Reset color
    love.graphics.setColor(1, 1, 1, 1)

    for i, player in ipairs(self.game.players) do
        local puckImage = self.game.images["puck_" .. player.colour]
        local sizerImage = self.game.images.puck_sizer
        
        if puckImage and sizerImage then
            local puckWidth = puckImage:getWidth()
            local puckHeight = puckImage:getHeight()
            local sizerWidth = sizerImage:getWidth()
            local sizerHeight = sizerImage:getHeight()
            
            -- Draw colored puck bottom-aligned with the sizer
            local puckX = player.position.x - puckWidth / 2
            local puckY = player.position.y + sizerHeight / 2 - puckHeight
            
            -- Draw sizer centered on player position (on top)
            local sizerX = player.position.x - sizerWidth / 2
            local sizerY = player.position.y - sizerHeight / 2
            -- love.graphics.draw(sizerImage, sizerX, sizerY)
            
            -- Draw charge arrow if player is charging
            if self.playerCharge[player.joystickID] and self.playerCharge[player.joystickID].isCharging then
                local charge = self.playerCharge[player.joystickID]
                
                -- Calculate arrow length based on magnitude (max length of 100 pixels)
                local maxLength = -100
                local arrowLength = charge.magnitude * maxLength
                
                -- Calculate end position of arrow (in direction of charge)
                local endX = player.position.x + charge.direction.x * arrowLength
                local endY = player.position.y + charge.direction.y * arrowLength
                
                -- Draw thin black line
                love.graphics.setColor(0, 0, 0, 1) -- Black color
                love.graphics.setLineWidth(13)
                love.graphics.line(player.position.x, player.position.y, endX, endY)

                -- Draw arrowhead
                local arrowheadImage = self.game.images.arrowhead
                if arrowheadImage then
                    -- Calculate angle of arrow direction
                    local angle = math.atan2(charge.direction.y, charge.direction.x) - math.pi / 2
                    
                    -- Get arrowhead dimensions for centering
                    local arrowWidth = arrowheadImage:getWidth()
                    local arrowHeight = arrowheadImage:getHeight()
                    
                    -- Draw arrowhead centered at end of line, rotated to face arrow direction
                    love.graphics.draw(arrowheadImage, endX, endY, angle, 1, 1, arrowWidth/2, arrowHeight/2)
                end
                
                -- Reset color and line width
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.setLineWidth(1)
            end

            love.graphics.draw(puckImage, puckX, puckY)
        end
    end
end

function Scene:gamepadpressed(joystick, button, player)
    if button == "a" and not self.countdown.active then
        -- Start countdown
        self.countdown.active = true
        self.countdown.timeLeft = 5
        self.countdown.timer = 0
    elseif button == "b" and self.countdown.active then
        -- Cancel countdown
        self.countdown.active = false
        self.countdown.timeLeft = 5
        self.countdown.timer = 0
    end
end

return Scene