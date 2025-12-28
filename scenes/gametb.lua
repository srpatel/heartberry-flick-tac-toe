local Scene = {}
Scene.__index = Scene

local RECHARGE_TIME = 1
local EXCLUSION_LIMIT = 2

function Scene.new(game)
    local self = setmetatable({}, Scene)

    self.game = game

    self.layout = {}
    self.playerStates = {}
    self.cells = {}
    self.gameWon = false
    self.winningPlayer = nil
    self.winFlashTimer = 0
    self.currentPlayerIndex = 1
    self.allPucksStopped = false

    return self
end

function Scene:update(dt)
    -- Update win flash timer
    if self.gameWon then
        self.winFlashTimer = self.winFlashTimer + dt
    end

    for i, player in ipairs(self.game.players) do
        local p = self.playerStates[i]
        p.drawnScore = p.drawnScore + (p.score - p.drawnScore) * dt * 5
    end
    
    -- Handle player charging and flicking (only if game not won)
    for i, player in ipairs(self.game.players) do
        if self.gameWon then
            goto continue -- Skip flicking if game is won
        end
        
        -- Only allow current player to flick
        if i ~= self.currentPlayerIndex then
            goto continue
        end
        
        if self.playerStates[i].puckCooldown > 0 then
            -- Only reduce this if all pucks have stopped moving!
            if self.allPucksStopped then
                self.playerStates[i].puckCooldown = self.playerStates[i].puckCooldown - dt * 2
            end
            goto continue
        end

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
            
            local charge = self.playerStates[i].playerCharge
            
            if charge.flickCooldown > 0 then
                charge.flickCooldown = charge.flickCooldown - dt
            end
            
            local flickThreshold = 0.3 -- How much the magnitude must drop to trigger a flick
            local flick = false

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

            if flick and charge.flickCooldown <= 0 then
                local velocityX = -charge.direction.x * self.flickStrength * charge.previousMagnitude
                local velocityY = -charge.direction.y * self.flickStrength * charge.previousMagnitude

                self.playerStates[i].puckCooldown = 1

                -- Create a new puck with the calculated velocity
                local newPuck = {
                    position = {
                        x = self.playerStates[i].puckStartPosition.x,
                        y = self.playerStates[i].puckStartPosition.y
                    },
                    velocity = {
                        x = velocityX,
                        y = velocityY
                    },
                    colour = player.colour,
                    playerIndex = i,
                    tooOld = false,
                    exclusionTimer = 0 -- Track time spent in exclusion zone
                }
                
                table.insert(self.pucks, newPuck)
                
                -- Clear charging state after flick
                charge.isCharging = false
                charge.flickCooldown = 0.5 -- Half a second cooldown between flicks

                self.calculatingPointsForPlayer = i
                self.hasCalculatedPoints = false
                
                -- Advance to next player
                self.currentPlayerIndex = (self.currentPlayerIndex % #self.game.players) + 1
                -- Reset the new current player's cooldown so they can flick immediately
                self.playerStates[self.currentPlayerIndex].puckCooldown = 1
            end
            
            -- Store current magnitude as previous for next frame
            charge.previousMagnitude = magnitude
        end
        ::continue::
    end
    
    self.allPucksStopped = true

    -- Update puck physics
    for i = #self.pucks, 1, -1 do
        local puck = self.pucks[i]
        
        -- Update position based on velocity
        puck.position.x = puck.position.x + puck.velocity.x * dt
        puck.position.y = puck.position.y + puck.velocity.y * dt
        
        -- Apply friction
        local friction = 0.98
        puck.velocity.x = puck.velocity.x * friction
        puck.velocity.y = puck.velocity.y * friction

        -- Check if puck is still moving
        if math.abs(puck.velocity.x) > 1 or math.abs(puck.velocity.y) > 1 then
            self.allPucksStopped = false
        end
    end

    -- Add points to player once all pucks have stopped
    if self.allPucksStopped then
        if not self.hasCalculatedPoints and self.calculatingPointsForPlayer then
            self.hasCalculatedPoints = true
            -- For each of my up arrows, give me a point!
            self.playerStates[self.calculatingPointsForPlayer].score = self.playerStates[self.calculatingPointsForPlayer].score + self.playerStates[self.calculatingPointsForPlayer].up * 10
            self:checkWinCondition()
        end
    end
    
    -- Handle puck-to-puck collisions
    local puckRadius = 35
    for i = 1, #self.pucks do
        for j = i + 1, #self.pucks do
            local puck1 = self.pucks[i]
            local puck2 = self.pucks[j]
            
            -- Calculate distance between pucks
            local dx = puck2.position.x - puck1.position.x
            local dy = puck2.position.y - puck1.position.y
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
                
                puck1.position.x = puck1.position.x - separationX
                puck1.position.y = puck1.position.y - separationY
                puck2.position.x = puck2.position.x + separationX
                puck2.position.y = puck2.position.y + separationY
                
                -- Calculate relative velocity
                local relativeVelX = puck2.velocity.x - puck1.velocity.x
                local relativeVelY = puck2.velocity.y - puck1.velocity.y
                
                -- Calculate relative velocity along collision normal
                local velAlongNormal = relativeVelX * nx + relativeVelY * ny
                
                -- Don't resolve if velocities are separating
                if velAlongNormal <= 0 then
                    -- Calculate restitution (bounciness)
                    local restitution = 0.8
                    local j = -(1 + restitution) * velAlongNormal
                    
                    -- Apply impulse
                    local impulseX = j * nx
                    local impulseY = j * ny
                    
                    puck1.velocity.x = puck1.velocity.x - impulseX * 0.5
                    puck1.velocity.y = puck1.velocity.y - impulseY * 0.5
                    puck2.velocity.x = puck2.velocity.x + impulseX * 0.5
                    puck2.velocity.y = puck2.velocity.y + impulseY * 0.5
                end
            end
        end
    end
    
    -- Handle wall collisions for all pucks
    for i, puck in ipairs(self.pucks) do
        local screenWidth = love.graphics.getWidth()
        local screenHeight = love.graphics.getHeight()
        
        -- Bounce off walls
        if puck.position.x < self.layout.rightAreaStart + puckRadius then
            puck.position.x = self.layout.rightAreaStart + puckRadius
            puck.velocity.x = -puck.velocity.x * 0.8
        elseif puck.position.x > screenWidth - puckRadius then
            puck.position.x = screenWidth - puckRadius
            puck.velocity.x = -puck.velocity.x * 0.8
        end
        
        if puck.position.y < puckRadius then
            puck.position.y = puckRadius
            puck.velocity.y = -puck.velocity.y * 0.8
        elseif puck.position.y > screenHeight - puckRadius then
            puck.position.y = screenHeight - puckRadius
            puck.velocity.y = -puck.velocity.y * 0.8
        end
    end
    
    -- Check exclusion zone and eliminate pucks that stay too long outside grid
    -- Also eliminate oldest pucks once you have 7+
    local exclusionMargin = 50
    local gridLeft = self.layout.gridStartX - exclusionMargin
    local gridRight = self.layout.gridStartX + self.layout.gridWidth + exclusionMargin
    local gridTop = self.layout.gridStartY - exclusionMargin
    local gridBottom = self.layout.gridStartY + self.layout.gridWidth + exclusionMargin
    
    for i = #self.pucks, 1, -1 do
        local puck = self.pucks[i]
        
        -- Check if puck is in exclusion zone (outside the expanded grid area)
        local inExclusionZone = puck.position.x < gridLeft or puck.position.x > gridRight or
                               puck.position.y < gridTop or puck.position.y > gridBottom
        
        if inExclusionZone or puck.tooOld then
            puck.exclusionTimer = puck.exclusionTimer + dt
            
            -- Eliminate puck if it's been in exclusion zone for more than EXCLUSION_LIMIT seconds
            if puck.exclusionTimer > EXCLUSION_LIMIT + 1 then
                table.remove(self.pucks, i)
            end
        else
            -- Reset timer if puck is back in the allowed area
            puck.exclusionTimer = 0
        end
    end

    for i, player in ipairs(self.game.players) do
        local myPucks = {}
        for j, puck in ipairs(self.pucks) do
            if puck.playerIndex == i then
                table.insert(myPucks, puck)
            end
        end
        if #myPucks > 6 then
            local numToRemove = #myPucks - 6
            for k = 1, numToRemove do
                myPucks[k].tooOld = true
            end
        end
    end

    -- Update self.cells[i].pucks
    for i, cell in ipairs(self.cells) do
        -- Clear current pucks in cell
        cell.pucks = {}
        
        -- Calculate cell position
        local row = math.floor((i - 1) / 3)
        local col = (i - 1) % 3
        local cellX = self.layout.gridStartX + col * (self.layout.squareSize + self.layout.gap)
        local cellY = self.layout.gridStartY + row * (self.layout.squareSize + self.layout.gap)
        
        -- Check which pucks are in this cell
        for j, puck in ipairs(self.pucks) do
            if puck.position.x > cellX and puck.position.x < (cellX + self.layout.squareSize) and
               puck.position.y > cellY and puck.position.y < (cellY + self.layout.squareSize) then
                table.insert(cell.pucks, puck)
            end
        end
        
        -- Determine current owner based on pucks in cell
        local ownerCounts = {}
        for _, puck in ipairs(cell.pucks) do
            ownerCounts[puck.playerIndex] = (ownerCounts[puck.playerIndex] or 0) + 1
        end
        
        local maxCount = 0
        local newOwner = nil
        local playersWithMaxCount = 0
        
        -- First pass: find the maximum count
        for playerIndex, count in pairs(ownerCounts) do
            if count > maxCount then
                maxCount = count
            end
        end
        
        -- Second pass: count how many players have the maximum count and find one if unique
        for playerIndex, count in pairs(ownerCounts) do
            if count == maxCount then
                playersWithMaxCount = playersWithMaxCount + 1
                newOwner = playerIndex
            end
        end
        
        -- Only set owner if exactly one player has the most pucks (strict majority)
        if playersWithMaxCount > 1 or maxCount == 0 then
            newOwner = nil
        end
        
        cell.actualOwner = newOwner
        if newOwner ~= cell.currentOwner then
            if cell.ownerSince > 0 then
                -- Need to reduce this to 0 before changing owner
                cell.ownerSince = math.max(0, cell.ownerSince - dt)
            else
                -- Change owner
                cell.currentOwner = newOwner
                cell.ownerSince = 0
            end
        else
            -- Same owner!
            cell.ownerSince = math.min(cell.ownerSince + dt, 1)
        end
    end
    
    -- Calculate each player's up value based on cell ownership
    -- Reset all players' up values first
    for i = 1, #self.game.players do
        self.playerStates[i].up = 0
    end
    
    -- Count cells owned by each player
    for i, cell in ipairs(self.cells) do
        if cell.actualOwner ~= nil then
            self.playerStates[cell.actualOwner].up = self.playerStates[cell.actualOwner].up + 1
        end
    end
    
    -- Check all 8 lines of 3 in a row and apply multipliers
    local lines = {
        -- Rows
        {1, 2, 3},
        {4, 5, 6},
        {7, 8, 9},
        -- Columns
        {1, 4, 7},
        {2, 5, 8},
        {3, 6, 9},
        -- Diagonals
        {1, 5, 9},
        {3, 5, 7}
    }
    
    -- Count lines for each player
    local playerLines = {}
    for i = 1, #self.game.players do
        playerLines[i] = 0
    end
    
    for _, line in ipairs(lines) do
        local lineOwner = nil
        local hasLine = true
        
        -- Check if all three cells in the line have the same owner
        for _, cellIndex in ipairs(line) do
            local cell = self.cells[cellIndex]
            if cell.actualOwner == nil then
                hasLine = false
                break
            elseif lineOwner == nil then
                lineOwner = cell.actualOwner
            elseif lineOwner ~= cell.actualOwner then
                hasLine = false
                break
            end
        end
        
        if hasLine and lineOwner ~= nil then
            playerLines[lineOwner] = playerLines[lineOwner] + 1
        end
    end
    
    -- Apply multipliers to up values
    for i = 1, #self.game.players do
        local multiplier = 1 + playerLines[i]
        self.playerStates[i].up = self.playerStates[i].up * multiplier
    end
end

function Scene:checkWinCondition()
    -- Check for win condition
    if not self.gameWon then
        local maxScore = 0
        local winner = nil
        
        for i = 1, #self.game.players do
            local score = self.playerStates[i].score
            if score >= 100 then
                if score > maxScore then
                    maxScore = score
                    winner = i
                end
            end
        end
        
        if winner then
            self.gameWon = true
            self.winningPlayer = winner
            -- increment that player's score
            table.insert(self.game.winners, self.game.players[winner].colour)
            self.winFlashTimer = 0
        end
    end
end

function Scene:draw()
    -- Set color to black with 13% opacity
    love.graphics.setColor(0, 0, 0, 0.13)
    
    -- Draw the 3x3 grid
    for row = 0, 2 do
        for col = 0, 2 do
            local cell = self.cells[row * 3 + col + 1]
            
            -- Set cell color based on owner and ownership strength
            if cell.currentOwner == nil or cell.ownerSince == 0 then
                love.graphics.setColor(0, 0, 0, 0.13)
            else
                local ownerColour = self.game.players[cell.currentOwner].colour
                local t = cell.ownerSince -- Interpolation factor (0 to 1)
                local alpha = 0.13 + (0.5 - 0.13) * t -- Interpolate alpha from 0.13 to 0.5
                
                -- Interpolate color from black (0,0,0) to target color
                local targetR, targetG, targetB = 0, 0, 0
                if ownerColour == "blue" then
                    targetR, targetG, targetB = 0x84/255, 0x9A/255, 0xCD/255
                elseif ownerColour == "red" then
                    targetR, targetG, targetB = 0xCE/255, 0x84/255, 0x84/255
                elseif ownerColour == "yellow" then
                    targetR, targetG, targetB = 0xCD/255, 0xBC/255, 0x84/255
                elseif ownerColour == "green" then
                    targetR, targetG, targetB = 0x83/255, 0xCD/255, 0xA9/255
                end
                
                -- Interpolate from black (0,0,0) to target color
                local r = 0 + targetR * t
                local g = 0 + targetG * t
                local b = 0 + targetB * t
                
                love.graphics.setColor(r, g, b, alpha)
            end
            
            local x = self.layout.gridStartX + col * (self.layout.squareSize + self.layout.gap)
            local y = self.layout.gridStartY + row * (self.layout.squareSize + self.layout.gap)
            love.graphics.draw(self.game.images.rect, x, y, 0, self.layout.squareSize / self.game.images.rect:getWidth(), self.layout.squareSize / self.game.images.rect:getHeight())
            
            -- Draw ownership overlay image if cell has an owner
            if cell.currentOwner ~= nil and cell.ownerSince > 0 then
                local ownerColour = self.game.players[cell.currentOwner].colour
                local ownershipImage = self.game.images["ownership_" .. ownerColour]
                
                if ownershipImage then
                    local t = cell.ownerSince -- Use ownership strength as alpha
                    love.graphics.setColor(1, 1, 1, t * 0.5) -- White color with alpha = t
                    
                    -- Calculate center position of the cell
                    local centerX = x + self.layout.squareSize / 2
                    local centerY = y + self.layout.squareSize / 2
                    
                    -- Draw image centered at 165px size
                    local imageSize = 165
                    local imageX = centerX - imageSize / 2
                    local imageY = centerY - imageSize / 2
                    
                    love.graphics.draw(ownershipImage, imageX, imageY, 0, imageSize / ownershipImage:getWidth(), imageSize / ownershipImage:getHeight())
                    
                    -- Reset color
                    love.graphics.setColor(1, 1, 1, 1)
                end
            end
        end
    end

    love.graphics.setColor(1, 1, 1, 1)

    -- Draw the static pucks at start positions (with rising animation)
    for i, player in ipairs(self.game.players) do
        -- Only draw the current player's puck
        if i ~= self.currentPlayerIndex then
            goto continue_puck_draw
        end
        
        local puckImage = self.game.images["puck_" .. player.colour]
        local sizerImage = self.game.images.puck_sizer
        
        if puckImage and sizerImage then
            local puckWidth = puckImage:getWidth()
            local puckHeight = puckImage:getHeight()
            local sizerWidth = sizerImage:getWidth()
            local sizerHeight = sizerImage:getHeight()
            
            -- Calculate puck position based on cooldown
            local cooldown = self.playerStates[i].puckCooldown
            local targetY = self.playerStates[i].puckStartPosition.y
            local screenHeight = love.graphics.getHeight()
            local bottomY = screenHeight + puckHeight -- Start below screen
            
            local currentY
            if cooldown <= 0 then
                -- Puck is ready, at target position
                currentY = targetY
            else
                -- Interpolate between bottom of screen and target position
                -- When cooldown = 1, puck is at bottom of screen
                -- When cooldown = 0, puck is at target position
                currentY = bottomY + (targetY - bottomY) * (1 - cooldown)
            end
            
            -- Draw colored puck bottom-aligned with the sizer
            local puckX = self.playerStates[i].puckStartPosition.x - puckWidth / 2
            local puckY = currentY + sizerHeight / 2 - puckHeight
            
            -- Only draw charge arrow if puck is ready (cooldown <= 0) and player is charging
            local charge = self.playerStates[i].playerCharge
            if cooldown <= 0 and charge.isCharging then
                -- Calculate arrow length based on magnitude (max length of 100 pixels)
                local maxLength = -150
                local arrowLength = charge.magnitude * maxLength
                
                -- Calculate end position of arrow (in direction of charge)
                local startX = self.playerStates[i].puckStartPosition.x
                local startY = currentY
                local endX = startX + charge.direction.x * arrowLength
                local endY = startY + charge.direction.y * arrowLength
                
                -- Draw thin black line
                love.graphics.setColor(0, 0, 0, 1) -- Black color
                love.graphics.setLineWidth(13)
                love.graphics.line(startX, startY, endX, endY)

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
        ::continue_puck_draw::
    end
    
    -- Draw all moving pucks
    for i, puck in ipairs(self.pucks) do
        local puckImage = self.game.images["puck_" .. puck.colour]
        local sizerImage = self.game.images.puck_sizer
        
        if puckImage and sizerImage then
            local puckWidth = puckImage:getWidth()
            local puckHeight = puckImage:getHeight()
            local sizerWidth = sizerImage:getWidth()
            local sizerHeight = sizerImage:getHeight()
            
            -- Check if puck should shrink (in danger of being eliminated)
            local scale = 1
            if puck.exclusionTimer > EXCLUSION_LIMIT then
                -- Start shrinking when at the elimination threshold
                local shrinkProgress = (puck.exclusionTimer - EXCLUSION_LIMIT) / 1 -- 1 second to shrink to nothing
                scale = math.max(0, 1 - shrinkProgress) -- Shrink from 1 to 0
            end
            
            if scale > 0 then
                -- Draw colored puck bottom-aligned with the sizer, scaled down if shrinking
                local puckX = puck.position.x - (puckWidth * scale) / 2
                local puckY = puck.position.y + sizerHeight / 2 - (puckHeight * scale)
                love.graphics.draw(puckImage, puckX, puckY, 0, scale, scale)
            end
        end
    end
    
    -- Draw the left-side UI for each player
    local screenHeight = love.graphics.getHeight()
    local numPlayers = #self.game.players
    local leftAreaWidth = self.layout.rightAreaStart
    local playerSlotWidth = (leftAreaWidth * 0.7) / numPlayers
    
    for i, player in ipairs(self.game.players) do
        local puckImage = self.game.images["puck_" .. player.colour]
        
        if puckImage then
            -- Calculate position for this player's slot (horizontal layout)
            local slotX = leftAreaWidth * 0.15 + (i - 1) * playerSlotWidth
            local slotCenterX = slotX + playerSlotWidth / 2
            local puckX = slotCenterX - (puckImage:getWidth() * 0.6) / 2 -- Account for mini scale
            local puckY = screenHeight - 120 -- Move pucks up from bottom
            
            -- Get player's color values
            local targetR, targetG, targetB = 0, 0, 0
            if player.colour == "blue" then
                targetR, targetG, targetB = 0x84/255, 0x9A/255, 0xCD/255
            elseif player.colour == "red" then
                targetR, targetG, targetB = 0xCE/255, 0x84/255, 0x84/255
            elseif player.colour == "yellow" then
                targetR, targetG, targetB = 0xCD/255, 0xBC/255, 0x84/255
            elseif player.colour == "green" then
                targetR, targetG, targetB = 0x83/255, 0xCD/255, 0xA9/255
            end
            
            -- Draw vertical progress bar above the puck
            local barWidth = 40
            local barHeight = screenHeight * 0.8
            local barX = slotCenterX - barWidth / 2
            local barY = puckY - barHeight - 20
            
            -- Progress bar background (washed out version)
            love.graphics.setColor(targetR * 0.3, targetG * 0.3, targetB * 0.3, 0.5)
            love.graphics.rectangle("fill", barX, barY, barWidth, barHeight)
            
            -- Progress bar foreground (based on score) - fills from bottom up
            local score = math.min(100, self.playerStates[i].drawnScore or 0)
            local progressHeight = (score / 100) * barHeight
            
            love.graphics.setColor(targetR, targetG, targetB, 1)
            love.graphics.rectangle("fill", barX, barY + barHeight - progressHeight, barWidth, progressHeight)
            
            -- Draw up arrows stacked at the bottom of the progress bar
            local upImage = self.game.images.up
            if upImage then
                local numArrows = self.playerStates[i].up or 0
                local arrowHeight = upImage:getHeight()
                local arrowWidth = upImage:getWidth()
                
                love.graphics.setColor(1, 1, 1, 0.5)
                for j = 1, numArrows do
                    local arrowX = slotCenterX - arrowWidth / 2
                    local arrowY = barY + barHeight - (j * arrowHeight) - 5
                    love.graphics.draw(upImage, arrowX, arrowY)
                end
            end
            
            -- Draw mini puck (scale it down)
            local miniAlpha = 1
            if self.gameWon then
                if self.winningPlayer == i then
                    -- Flash between 0.3 and 1.0 with a 1 second cycle
                    miniAlpha = 0.3 + 0.7 * (0.5 + 0.5 * math.sin(self.winFlashTimer * math.pi * 2))
                else
                    miniAlpha = 1
                end
            else
                if i == self.currentPlayerIndex then
                    miniAlpha = 1
                else
                    miniAlpha = 0.5
                end
            end
            
            love.graphics.setColor(1, 1, 1, miniAlpha)
            local miniScale = 0.6
            love.graphics.draw(puckImage, puckX, puckY, 0, miniScale, miniScale)
        end
    end
    
    -- Draw the right area border line
    love.graphics.setColor(0, 0, 0, 1) -- Black color
    love.graphics.setLineWidth(6)
    love.graphics.line(self.layout.rightAreaStart, 0, self.layout.rightAreaStart, love.graphics.getHeight())
    
    -- Draw "Press B to return menu" if game is over
    if self.gameWon then
        local instructionText = "Press B to return menu"
        love.graphics.setFont(self.game.fonts.smallFont)
        love.graphics.setColor(0x95/255, 0x95/255, 0x95/255, 1)
        
        local instructionWidth = self.game.fonts.smallFont:getWidth(instructionText)
        local rightAreaCenterX = self.layout.rightAreaStart + self.layout.rightAreaWidth / 2
        local instructionX = rightAreaCenterX - instructionWidth / 2
        local instructionY = 30 -- Top of the right area with some padding
        
        love.graphics.print(instructionText, instructionX, instructionY)
    end
    
    -- Reset color to white for other drawing operations
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
end

function Scene:load()
    self.layout = {}
    self.gameWon = false
    self.winningPlayer = nil
    self.winFlashTimer = 0
    self.currentPlayerIndex = math.random(1, #self.game.players)
    self.allPucksStopped = false
    self.calculatingPointsForPlayer = nil
    self.hasCalculatedPoints = false

    self.flickStrength = 2500 * (love.graphics.getHeight() / 1117) * (love.graphics.getHeight() / 1117)

    -- Layout vars
    local screenWidth = love.graphics.getWidth()
    local screenHeight = love.graphics.getHeight()
    
    -- Right area is 70% of the screen width, starting at 30%
    self.layout.rightAreaStart = screenWidth * 0.3
    self.layout.rightAreaWidth = screenWidth * 0.7
    
    -- Grid squares are 13.3% of the screen width
    self.layout.squareSize = screenWidth * 0.133
    self.layout.gap = 10 -- 10px gap between cells
    
    -- Calculate grid position to center it horizontally in the right area
    self.layout.gridWidth = self.layout.squareSize * 3 + self.layout.gap * 2 -- 3 squares + 2 gaps
    self.layout.gridStartX = self.layout.rightAreaStart + (self.layout.rightAreaWidth - self.layout.gridWidth) / 2
    self.layout.gridStartY = (screenHeight - self.layout.gridWidth) / 2 - 60

    self.playerStates = {}
    self.pucks = {}

    self.cells = {
        { pucks = {}, currentOwner = nil, ownerSince = 0, actualOwner = nil },
        { pucks = {}, currentOwner = nil, ownerSince = 0, actualOwner = nil },
        { pucks = {}, currentOwner = nil, ownerSince = 0, actualOwner = nil },
        { pucks = {}, currentOwner = nil, ownerSince = 0, actualOwner = nil },
        { pucks = {}, currentOwner = nil, ownerSince = 0, actualOwner = nil },
        { pucks = {}, currentOwner = nil, ownerSince = 0, actualOwner = nil },
        { pucks = {}, currentOwner = nil, ownerSince = 0, actualOwner = nil },
        { pucks = {}, currentOwner = nil, ownerSince = 0, actualOwner = nil },
        { pucks = {}, currentOwner = nil, ownerSince = 0, actualOwner = nil },
    }

    local puckLeft = self.layout.gridStartX + self.layout.squareSize * 0.5
    local puckRight = self.layout.gridStartX + self.layout.squareSize * 2.5 + self.layout.gap * 2
    local puckCentre = (puckLeft + puckRight) / 2
    
    for i, player in ipairs(self.game.players) do
        local numPlayers = #self.game.players
        
        self.playerStates[i] = {
            puckCooldown = 1,
            puckStartPosition = {
                x = puckCentre, 
                y = love.graphics.getHeight() - 100
            },
            playerCharge = {
                isCharging = false,
                direction = {x = 0, y = 0},
                magnitude = 0,
                previousMagnitude = 0,
                flickCooldown = 0
            },
            score = 0,
            drawnScore = 0,
            up = 0,
        }
    end
end

function Scene:gamepadpressed(joystick, button, player)
    if button == "b" and self.gameWon then
        self.game:setScene(self.game.scenes.title)
    end
end

return Scene