-- gameAmulti.lua
-- Multiplayer A-type: physics fields share one world.
-- P1 field worldX: 228..548,  P2 field worldX: 548..868  (body offset 32,-64)
-- 18 cut lines at worldY = k*32 (k=1..18)
-- Display: worldX * physicsmpscale = worldX * mpscale/4

-- Field X boundaries in world coords
AMULTI_P1_LEFT  = 228
AMULTI_P1_RIGHT = 548
AMULTI_P2_LEFT  = 548
AMULTI_P2_RIGHT = 868

amulti_lineclearduration     = 1.2
amulti_lineclearblinks       = 7
amulti_linecleartreshold     = 5.1
amulti_densityupdateinterval = 1/30

-- ─────────────────────────────────────────────────────────────────────────────
function gameAmulti_load()
	if musicno < 4 then love.audio.stop(music[musicno]) end

	gamestate   = "gameAmulti"
	gamestarted = false
	beeped = {false, false, false}

	mpscale = scale
	while 274*mpscale > desktopwidth do mpscale = mpscale - 1 end
	physicsmpscale = mpscale/4

	mpfullscreenoffsetX = (desktopwidth  - 274*mpscale) / 2
	mpfullscreenoffsetY = (desktopheight - 144*mpscale) / 2

	if not fullscreen then
		love.graphics.setMode(274*mpscale, 144*mpscale, fullscreen, vsync, 16)
	end

	nextpieceimgmp = {}
	for i = 1, 7 do
		nextpieceimgmp[i] = newPaddedImage("graphics/pieces/"..i..".png", mpscale)
	end

	difficulty_speed = 100
	p1fail = false
	p2fail = false
	p1_control_enabled = true
	p2_control_enabled = true
	p1color = {255, 50, 50}
	p2color = {50, 255, 50}

	scorescorep1 = 0;  linesscorep1 = 0
	scorescorep2 = 0;  linesscorep2 = 0
	counterp1 = 0;     counterp2 = 0

	tetrikindp1       = {};  tetriimagedatap1 = {};  tetriimagesp1 = {}
	tetrikindp2       = {};  tetriimagedatap2 = {};  tetriimagesp2 = {}
	tetrishapesp1     = {};  tetribodiesp1    = {}
	tetrishapesp2     = {};  tetribodiesp2    = {}

	randomtable  = {}
	nextpiecep1  = nil
	nextpiecep2  = nil
	nextpiecerot = 0

	-- Cut / animation state
	amulti_cuttingtimer   = amulti_lineclearduration
	amulti_linesremovedp1 = {}
	amulti_linesremovedp2 = {}
	amulti_cutsnapshot    = {}   -- [{x,y,angle,kind,img}, ...]

	-- Fill-gauge areas (req #12: per-player, settled pieces only)
	amulti_linereap1 = {};  amulti_linereap2 = {}
	for i = 1, 18 do amulti_linereap1[i] = 0;  amulti_linereap2[i] = 0 end

	amulti_densityupdatetimer = 0
	amulti_newblockp1 = false
	amulti_newblockp2 = false

	-- internal guard to prevent recursive forced endblock calls
	amulti_forced_endblock = false

	-- deferred endblock flags (set by collision callback, processed in update)
	pending_endblock_p1 = false
	pending_endblock_p2 = false

	-- Physics
	meter = 30
	world = love.physics.newWorld(0, -720, 960, 1050, 0, 500, true)

	wallshapesp1 = {};  wallshapesp2 = {}

	-- Walls P1
	wallbodiesp1 = love.physics.newBody(world, 32, -64, 0, 0)
	wallshapesp1[0] = love.physics.newPolygonShape(wallbodiesp1, 164,0, 164,672, 196,672, 196,0)
	wallshapesp1[0]:setData("leftp1");  wallshapesp1[0]:setFriction(0.0001)
	wallshapesp1[1] = love.physics.newPolygonShape(wallbodiesp1, 516,0, 516,672, 548,672, 548,0)
	wallshapesp1[1]:setData("rightp1"); wallshapesp1[1]:setCategory(2); wallshapesp1[1]:setFriction(0.0001)
	wallshapesp1[2] = love.physics.newPolygonShape(wallbodiesp1, 196,640, 196,672, 516,672, 516,640)
	wallshapesp1[2]:setData("groundp1")

	-- Walls P2
	wallbodiesp2 = love.physics.newBody(world, 32, -64, 0, 0)
	wallshapesp2[0] = love.physics.newPolygonShape(wallbodiesp2, 484,0, 484,672, 516,672, 516,0)
	wallshapesp2[0]:setData("leftp2");  wallshapesp2[0]:setCategory(3); wallshapesp2[0]:setFriction(0.0001)
	wallshapesp2[1] = love.physics.newPolygonShape(wallbodiesp2, 836,0, 836,672, 868,672, 868,0)
	wallshapesp2[1]:setData("rightp2"); wallshapesp2[1]:setFriction(0.0001)
	wallshapesp2[2] = love.physics.newPolygonShape(wallbodiesp2, 516,640, 516,672, 836,672, 836,640)
	wallshapesp2[2]:setData("groundp2")

	world:setCallbacks(collideAmulti)   -- own callback, does NOT redefine collideBmulti

	randomtable[1] = math.random(7)
	starttimer = love.timer.getTime()
end

-- ─────────────────────────────────────────────────────────────────────────────
-- DRAW
-- ─────────────────────────────────────────────────────────────────────────────
function gameAmulti_draw()
	if fullscreen then
		love.graphics.translate(mpfullscreenoffsetX, mpfullscreenoffsetY)
		love.graphics.setScissor(mpfullscreenoffsetX, mpfullscreenoffsetY, 274*mpscale, 144*mpscale)
	end

	-- background
	if gamestate ~= "gameAmulti_results" then
		love.graphics.draw(gamebackgroundmulti, 0, 0, 0, mpscale)
	else
		love.graphics.draw(multiresults, 0, 0, 0, mpscale)
	end

	-- countdown
	if gamestarted == false then
		if newtime - starttimer > 2 then
			love.graphics.draw(number1, 73*mpscale, 48*mpscale, 0, mpscale)
			love.graphics.draw(number1, 153*mpscale, 48*mpscale, 0, mpscale)
		elseif newtime - starttimer > 1 then
			love.graphics.draw(number2, 73*mpscale, 48*mpscale, 0, mpscale)
			love.graphics.draw(number2, 153*mpscale, 48*mpscale, 0, mpscale)
		elseif newtime - starttimer > 0 then
			love.graphics.draw(number3, 73*mpscale, 48*mpscale, 0, mpscale)
			love.graphics.draw(number3, 153*mpscale, 48*mpscale, 0, mpscale)
		end
	end

	-- pieces / cut animation
	if amulti_cuttingtimer == amulti_lineclearduration then
		-- normal: live bodies
		for i, v in pairs(tetribodiesp1) do
			love.graphics.setColor(255, 255, 255)
			if gamestate == "failingAmulti" or gamestate == "failedAmulti" then
				local tp = love.timer.getTime() - colorizetimer
				if v:getY() > 576 - 576*(tp/colorizeduration) then
					love.graphics.setColor(unpack(p1color))
				end
			end
			love.graphics.draw(tetriimagesp1[i],
				v:getX()*physicsmpscale, v:getY()*physicsmpscale, v:getAngle(),
				1, 1, piececenter[tetrikindp1[i]][1]*mpscale, piececenter[tetrikindp1[i]][2]*mpscale)
		end
		for i, v in pairs(tetribodiesp2) do
			love.graphics.setColor(255, 255, 255)
			if gamestate == "failingAmulti" or gamestate == "failedAmulti" then
				local tp = love.timer.getTime() - colorizetimer
				if v:getY() > 576 - 576*(tp/colorizeduration) then
					love.graphics.setColor(unpack(p2color))
				end
			end
			love.graphics.draw(tetriimagesp2[i],
				v:getX()*physicsmpscale, v:getY()*physicsmpscale, v:getAngle(),
				1, 1, piececenter[tetrikindp2[i]][1]*mpscale, piececenter[tetrikindp2[i]][2]*mpscale)
		end
	else
		-- cut animation: draw snapshot
		for _, snap in ipairs(amulti_cutsnapshot) do
			love.graphics.setColor(255, 255, 255)
			love.graphics.draw(snap.img,
				snap.x*physicsmpscale, snap.y*physicsmpscale, snap.angle,
				1, 1, piececenter[snap.kind][1]*mpscale, piececenter[snap.kind][2]*mpscale)
		end

		-- blinking cleared lines
		local section = math.ceil(amulti_cuttingtimer / (amulti_lineclearduration/amulti_lineclearblinks))
		if math.mod(section, 2) == 1 or amulti_cuttingtimer == 0 then
			local rr, rg, rb = unpack(getrainbowcolor(hue))
			local r = 145 + rr*64
			local g = 145 + rg*64
			local b = 145 + rb*64
			love.graphics.setColor(r, g, b)
			-- req #11: account for screen offset of each field
			-- P1 field left edge on screen = AMULTI_P1_LEFT * physicsmpscale
			local p1x = AMULTI_P1_LEFT * physicsmpscale
			local p1w = (AMULTI_P1_RIGHT - AMULTI_P1_LEFT) * physicsmpscale
			local p2x = AMULTI_P2_LEFT  * physicsmpscale
			local p2w = (AMULTI_P2_RIGHT - AMULTI_P2_LEFT) * physicsmpscale
			local lineH = 8 * mpscale   -- 32 world units * physicsmpscale = 8*mpscale
			for i = 1, 18 do
				if amulti_linesremovedp1[i] then
					love.graphics.rectangle("fill", p1x, (i-1)*lineH, p1w, lineH)
				end
				if amulti_linesremovedp2[i] then
					love.graphics.rectangle("fill", p2x, (i-1)*lineH, p2w, lineH)
				end
			end
		end
	end

	love.graphics.setColor(255, 255, 255)

	-- next pieces
	if p1fail == false and nextpiecep1 then
		love.graphics.draw(nextpieceimgmp[nextpiecep1], 24*mpscale, 120*mpscale, -nextpiecerot,
			1, 1, piececenterpreview[nextpiecep1][1]*mpscale, piececenterpreview[nextpiecep1][2]*mpscale)
	end
	if p2fail == false and nextpiecep2 then
		love.graphics.draw(nextpieceimgmp[nextpiecep2], 250*mpscale, 120*mpscale, nextpiecerot,
			1, 1, piececenterpreview[nextpiecep2][1]*mpscale, piececenterpreview[nextpiecep2][2]*mpscale)
	end

	-- fill gauges (req #12: per-player, settled only)
	local lineH = 8 * mpscale
	for i = 1, 18 do
		-- P1 gauge (left strip)
		local f1 = amulti_linereap1[i] / 1024 / amulti_linecleartreshold
		if f1 > 1 then f1 = 1 end
		local c1 = (f1 == 1) and 0 or (235 - f1*180)
		love.graphics.setColor(c1, c1, c1)
		love.graphics.rectangle("fill", 0, (i-1)*lineH, math.floor(6*mpscale*f1), lineH)

		-- P2 gauge (right strip, grows leftward from screen edge)
		local f2 = amulti_linereap2[i] / 1024 / amulti_linecleartreshold
		if f2 > 1 then f2 = 1 end
		local c2 = (f2 == 1) and 0 or (235 - f2*180)
		love.graphics.setColor(c2, c2, c2)
		local bw = math.floor(6*mpscale*f2)
		love.graphics.rectangle("fill", 274*mpscale - bw, (i-1)*lineH, bw, lineH)
	end
	love.graphics.setColor(255, 255, 255)

	-- scores P1
	local offsetX = 0
	local ss = tostring(scorescorep1)
	for i = 1, ss:len()-1 do offsetX = offsetX - 8*mpscale end
	love.graphics.print(scorescorep1, 36*mpscale + offsetX, 24*mpscale, 0, mpscale)
	offsetX = 0
	ss = tostring(linesscorep1)
	for i = 1, ss:len()-1 do offsetX = offsetX - 8*mpscale end
	love.graphics.print(linesscorep1, 28*mpscale + offsetX, 80*mpscale, 0, mpscale)

	-- scores P2
	offsetX = 0
	ss = tostring(scorescorep2)
	for i = 1, ss:len()-1 do offsetX = offsetX - 8*mpscale end
	love.graphics.print(scorescorep2, 262*mpscale + offsetX, 24*mpscale, 0, mpscale)
	offsetX = 0
	ss = tostring(linesscorep2)
	for i = 1, ss:len()-1 do offsetX = offsetX - 8*mpscale end
	love.graphics.print(linesscorep2, 254*mpscale + offsetX, 80*mpscale, 0, mpscale)

	-- results screen
	if gamestate == "gameAmulti_results" then
		if p1wins < 10 then love.graphics.print("0"..p1wins, 111*mpscale, 128*mpscale, 0, mpscale)
		else                love.graphics.print(p1wins,       111*mpscale, 128*mpscale, 0, mpscale) end
		if p2wins < 10 then love.graphics.print("0"..p2wins, 193*mpscale, 128*mpscale, 0, mpscale)
		else                love.graphics.print(p2wins,       193*mpscale, 128*mpscale, 0, mpscale) end

		if winner == 1 then
			if jumpframe == false then
				love.graphics.draw(marioidle, mariobody:getX()*physicsmpscale, mariobody:getY()*physicsmpscale, mariobody:getAngle(), mpscale, mpscale, 12, 13.5)
			else
				love.graphics.draw(mariojump, mariobody:getX()*physicsmpscale, mariobody:getY()*physicsmpscale, mariobody:getAngle(), mpscale, mpscale, 12, 13.5)
			end
			if cryframe == false then
				love.graphics.draw(luigicry1, 162*mpscale, 66*mpscale, 0, mpscale, mpscale)
			else
				love.graphics.draw(luigicry2, 162*mpscale, 66*mpscale, 0, mpscale, mpscale)
				love.graphics.print("mario", 93*mpscale,  20*mpscale, 0, mpscale)
				love.graphics.print("wins!", 141*mpscale, 20*mpscale, 0, mpscale)
				for i = 1, 5 do
					love.graphics.draw(congratsline, (86+(8*i-1))*mpscale,  28*mpscale, 0, mpscale, mpscale)
					love.graphics.draw(congratsline, (134+(8*i-1))*mpscale, 28*mpscale, 0, mpscale, mpscale)
				end
			end
		elseif winner == 2 then
			if jumpframe == false then
				love.graphics.draw(luigiidle, luigibody:getX()*physicsmpscale, luigibody:getY()*physicsmpscale, luigibody:getAngle(), mpscale, mpscale, 14, 15.5)
			else
				love.graphics.draw(luigijump, luigibody:getX()*physicsmpscale, luigibody:getY()*physicsmpscale, luigibody:getAngle(), mpscale, mpscale, 14, 15.5)
			end
			if cryframe == false then
				love.graphics.draw(mariocry1, 83*mpscale, 66*mpscale, 0, mpscale, mpscale)
			else
				love.graphics.draw(mariocry2, 83*mpscale, 66*mpscale, 0, mpscale, mpscale)
				love.graphics.print("luigi", 93*mpscale,  20*mpscale, 0, mpscale)
				love.graphics.print("wins!", 141*mpscale, 20*mpscale, 0, mpscale)
				for i = 1, 5 do
					love.graphics.draw(congratsline, (86+(8*i-1))*mpscale,  28*mpscale, 0, mpscale, mpscale)
					love.graphics.draw(congratsline, (134+(8*i-1))*mpscale, 28*mpscale, 0, mpscale, mpscale)
				end
			end
		else
			love.graphics.draw(marioidle, 84*mpscale, 69*mpscale, 0, mpscale, mpscale)
			love.graphics.draw(luigiidle, 162*mpscale, 65*mpscale, 0, mpscale, mpscale)
			if cryframe == false then
				love.graphics.print("draw", 160*mpscale, 40*mpscale, 0, mpscale)
				love.graphics.print("draw", 80*mpscale,  40*mpscale, 0, mpscale)
			end
		end
	end

	if fullscreen then
		love.graphics.translate(-mpfullscreenoffsetX, -mpfullscreenoffsetY)
		love.graphics.setScissor()
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- UPDATE
-- req #9: cutting timer freezes physics, controls, spawning, density
-- ─────────────────────────────────────────────────────────────────────────────
function gameAmulti_update(dt)
	newtime = love.timer.getTime()

	-- req #9: full freeze during cut animation
	if amulti_cuttingtimer < amulti_lineclearduration then
		amulti_cuttingtimer = amulti_cuttingtimer + dt
		if amulti_cuttingtimer >= amulti_lineclearduration then
			amulti_cuttingtimer = amulti_lineclearduration
			-- spawn deferred blocks after animation
			if amulti_newblockp1 then amulti_newblockp1 = false;  game_addTetriAmultip1() end
			if amulti_newblockp2 then amulti_newblockp2 = false;  game_addTetriAmultip2() end
		end
		return  -- freeze everything
	end

	nextpiecerot = nextpiecerot + nextpiecerotspeed*dt
	while nextpiecerot > math.pi*2 do nextpiecerot = nextpiecerot - math.pi*2 end

	world:update(dt)

	-- Process deferred endblocks (set by collision callback) here to avoid
	-- calling endblock from within the physics callback and to serialize handling
	-- process simultaneous pending endblocks atomically
	if pending_endblock_p1 and pending_endblock_p2 then
		pending_endblock_p1, pending_endblock_p2 = false, false
		if not amulti_forced_endblock and p1fail == false and p2fail == false then
			amulti_forced_endblock = true
			endblockAmultip_simultaneous()
			amulti_forced_endblock = false
		end
	else
		if pending_endblock_p1 then
			pending_endblock_p1 = false
			if not amulti_forced_endblock and p1fail == false then
				amulti_forced_endblock = true
				endblockAmultip1()
				amulti_forced_endblock = false
			end
		end
		if pending_endblock_p2 then
			pending_endblock_p2 = false
			if not amulti_forced_endblock and p2fail == false then
				amulti_forced_endblock = true
				endblockAmultip2()
				amulti_forced_endblock = false
			end
		end
	end

	if gamestarted == false then
		if newtime - starttimer > 3 then
			if musicno < 4 then love.audio.play(music[musicno]) end
			startgameAmulti()
			gamestarted = true
		elseif newtime - starttimer > 2 and beeped[3] == false then
			beeped[3] = true;  love.audio.stop(highscorebeep);  love.audio.play(highscorebeep)
		elseif newtime - starttimer > 1 and beeped[2] == false then
			beeped[2] = true;  love.audio.stop(highscorebeep);  love.audio.play(highscorebeep)
		elseif newtime - starttimer > 0 and beeped[1] == false then
			beeped[1] = true;  love.audio.stop(highscorebeep);  love.audio.play(highscorebeep)
		end

	elseif gamestate == "gameAmulti" then
		-- controls P1
		if p1fail == false and p1_control_enabled and active_is_controllable(1) then
			local active1 = tetribodiesp1[counterp1]
			if active1 then
				if love.keyboard.isDown("h") then
					if active1:getAngularVelocity() < 3 then active1:applyTorque(70) end
				end
				if love.keyboard.isDown("g") then
					if active1:getAngularVelocity() > -3 then active1:applyTorque(-70) end
				end
				if love.keyboard.isDown("a") then
					local x, y = active1:getWorldCenter()
					active1:applyForce(-70, 0, x, y)
				end
				if love.keyboard.isDown("d") then
					local x, y = active1:getWorldCenter()
					active1:applyForce(70, 0, x, y)
				end
				local x, y = active1:getLinearVelocity()
				if love.keyboard.isDown("s") then
					if y > difficulty_speed*5 then
						active1:setLinearVelocity(x, difficulty_speed*5)
					else
						local cx, cy = active1:getWorldCenter()
						active1:applyForce(0, 20, cx, cy)
					end
				else
					if y > difficulty_speed then active1:setLinearVelocity(x, y-2000*dt) end
				end
			end
		end
		-- controls P2
		if p2fail == false and p2_control_enabled and active_is_controllable(2) then
			local active2 = tetribodiesp2[counterp2]
			if active2 then
				if love.keyboard.isDown("kp2") then
					if active2:getAngularVelocity() < 3 then active2:applyTorque(70) end
				end
				if love.keyboard.isDown("kp1") then
					if active2:getAngularVelocity() > -3 then active2:applyTorque(-70) end
				end
				if love.keyboard.isDown("left") then
					local x, y = active2:getWorldCenter()
					active2:applyForce(-70, 0, x, y)
				end
				if love.keyboard.isDown("right") then
					local x, y = active2:getWorldCenter()
					active2:applyForce(70, 0, x, y)
				end
				local x, y = active2:getLinearVelocity()
				if love.keyboard.isDown("down") then
					if y > difficulty_speed*5 then
						active2:setLinearVelocity(x, difficulty_speed*5)
					else
						local cx, cy = active2:getWorldCenter()
						active2:applyForce(0, 20, cx, cy)
					end
				else
					if y > difficulty_speed then active2:setLinearVelocity(x, y-2000*dt) end
				end
			end
		end

		-- periodic density update (req #2: skip active pieces)
		amulti_densityupdatetimer = amulti_densityupdatetimer + dt
		if amulti_densityupdatetimer >= amulti_densityupdateinterval then
			while amulti_densityupdatetimer >= amulti_densityupdateinterval do
				amulti_checklinedensity(false, true, true)
				amulti_densityupdatetimer = amulti_densityupdatetimer - amulti_densityupdateinterval
			end
		end

	elseif gamestate == "failingAmulti" then
		local tp = love.timer.getTime() - colorizetimer
		if tp > colorizeduration then
			gamestate = "failedAmulti"
			wallshapesp1[2]:destroy();  wallshapesp2[2]:destroy()
			love.audio.stop(gameover2);  love.audio.play(gameover2)
		end

	elseif gamestate == "failedAmulti" then
		local ok = true
		for i, v in pairs(tetribodiesp1) do if v:getY() < 162*mpscale then ok = false end end
		for i, v in pairs(tetribodiesp2) do if v:getY() < 162*mpscale then ok = false end end
		if ok then
			gamestate = "gameAmulti_results"
			jumptimer = love.timer.getTime();  crytimer = love.timer.getTime()
			love.audio.play(musicresults)
			resultsfloorbody  = love.physics.newBody(world, 32, -64, 0, 0)
			resultsfloorshape = love.physics.newPolygonShape(resultsfloorbody, 196,448, 196,480, 836,480, 836,448)
			resultsfloorshape:setData("resultsfloor")
			if winner == 1 then
				mariobody  = love.physics.newBody(world, 388, 320, 0, 0)
				marioshape = love.physics.newRectangleShape(mariobody, 0, 0, 64, 108)
				marioshape:setMask(3);  marioshape:setData("mario")
				mariobody:setLinearDamping(0.5);  mariobody:setMassFromShapes()
				mariobody:setY(mariobody:getY()-1)
				local x, y = mariobody:getLinearVelocity();  mariobody:setLinearVelocity(x, -300)
			elseif winner == 2 then
				luigibody  = love.physics.newBody(world, 704, 320, 0, 0)
				luigishape = love.physics.newRectangleShape(luigibody, 0, 0, 64, 124)
				luigishape:setMask(2);  luigishape:setData("luigi")
				luigibody:setLinearDamping(0.5);  luigibody:setMassFromShapes()
				luigibody:setY(luigibody:getY()-1)
				local x, y = luigibody:getLinearVelocity();  luigibody:setLinearVelocity(x, -300)
			end
			jumpframe = true
		end

	elseif gamestate == "gameAmulti_results" then
		local jtp = love.timer.getTime() - jumptimer
		if jtp > 2 then
			jumptimer = love.timer.getTime();  jumpframe = true
			if winner == 1 then
				mariobody:setY(mariobody:getY()-1)
				local x, y = mariobody:getLinearVelocity();  mariobody:setLinearVelocity(x, -300)
			elseif winner == 2 then
				luigibody:setY(luigibody:getY()-1)
				local x, y = luigibody:getLinearVelocity();  luigibody:setLinearVelocity(x, -300)
			end
		end
		local ctp = love.timer.getTime() - crytimer
		if ctp > 0.4 then cryframe = not cryframe;  crytimer = love.timer.getTime() end
		if winner == 1 then
			if love.keyboard.isDown("a") then local x,y=mariobody:getWorldCenter(); mariobody:applyForce(-30,0,x,y-8) end
			if love.keyboard.isDown("d") then local x,y=mariobody:getWorldCenter(); mariobody:applyForce( 30,0,x,y-8) end
		elseif winner == 2 then
			if love.keyboard.isDown("left")  then local x,y=luigibody:getWorldCenter(); luigibody:applyForce(-30,0,x,y-8) end
			if love.keyboard.isDown("right") then local x,y=luigibody:getWorldCenter(); luigibody:applyForce( 30,0,x,y-8) end
		end
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- START / ADD PIECES
-- ─────────────────────────────────────────────────────────────────────────────
function startgameAmulti()
	if randomtable[1] == 2 then nextpiecep1 = 3
	elseif randomtable[1] == 3 then nextpiecep1 = 2
	elseif randomtable[1] == 5 then nextpiecep1 = 7
	elseif randomtable[1] == 7 then nextpiecep1 = 5
	else nextpiecep1 = randomtable[1] end
	nextpiecep2 = randomtable[1]
	game_addTetriAmultip1()
	game_addTetriAmultip2()
end

function game_addTetriAmultip1()
    -- Находим первый свободный индекс начиная с counterp1+1
    local newid = counterp1 + 1
    while tetribodiesp1[newid] ~= nil do
        newid = newid + 1
    end
    counterp1 = newid

    createtetriAmultip1(nextpiecep1, counterp1, 388, blockstartY)
    tetribodiesp1[counterp1]:setLinearVelocity(0, difficulty_speed)

	-- enable control for the newly spawned piece
	p1_control_enabled = true

    -- Убеждаемся, что randomtable достаточно велик
    while counterp1 > #randomtable do
        table.insert(randomtable, math.random(7))
    end
    local r = randomtable[counterp1]
    if r == 2 then nextpiecep1 = 3
    elseif r == 3 then nextpiecep1 = 2
    elseif r == 5 then nextpiecep1 = 7
    elseif r == 7 then nextpiecep1 = 5
    else nextpiecep1 = r end
end

function game_addTetriAmultip2()
    local newid = counterp2 + 1
    while tetribodiesp2[newid] ~= nil do
        newid = newid + 1
    end
    counterp2 = newid

    createtetriAmultip2(nextpiecep2, counterp2, 708, blockstartY)
    tetribodiesp2[counterp2]:setLinearVelocity(0, difficulty_speed)

	-- enable control for the newly spawned piece
	p2_control_enabled = true

    while counterp2 > #randomtable do
        table.insert(randomtable, math.random(7))
    end
    nextpiecep2 = randomtable[counterp2]
end

-- ─────────────────────────────────────────────────────────────────────────────
-- CREATE BODIES  (store imagedata for cutimage, use newImageData not newPaddedImage)
-- ─────────────────────────────────────────────────────────────────────────────
function createtetriAmultip1(i, uid, x, y)
	tetriimagedatap1[uid] = newImageData("graphics/pieces/"..i..".png", mpscale)
	tetriimagesp1[uid]    = padImagedata(tetriimagedatap1[uid])
	tetrikindp1[uid] = i
	tetrishapesp1[uid] = {}
	tetribodiesp1[uid] = love.physics.newBody(world, x, y, 0, blockrot)
	amulti_addPieceShapes(tetribodiesp1[uid], tetrishapesp1[uid], i)
	tetribodiesp1[uid]:setLinearDamping(0.5)
	tetribodiesp1[uid]:setMassFromShapes()
	tetribodiesp1[uid]:setBullet(true)
	for j, v in pairs(tetrishapesp1[uid]) do
		v:setData("p1-"..uid);  v:setMask(3)
	end
end

function createtetriAmultip2(i, uid, x, y)
	tetriimagedatap2[uid] = newImageData("graphics/pieces/"..i..".png", mpscale)
	tetriimagesp2[uid]    = padImagedata(tetriimagedatap2[uid])
	tetrikindp2[uid] = i
	tetrishapesp2[uid] = {}
	tetribodiesp2[uid] = love.physics.newBody(world, x, y, 0, blockrot)
	amulti_addPieceShapes(tetribodiesp2[uid], tetrishapesp2[uid], i)
	tetribodiesp2[uid]:setLinearDamping(0.5)
	tetribodiesp2[uid]:setMassFromShapes()
	tetribodiesp2[uid]:setBullet(true)
	for j, v in pairs(tetrishapesp2[uid]) do
		v:setData("p2-"..uid);  v:setMask(2)
	end
end

-- shared shape layout helper
function amulti_addPieceShapes(body, shapes, i)
	if i == 1 then
		shapes[1]=love.physics.newRectangleShape(body,-48,0,32,32)
		shapes[2]=love.physics.newRectangleShape(body,-16,0,32,32)
		shapes[3]=love.physics.newRectangleShape(body, 16,0,32,32)
		shapes[4]=love.physics.newRectangleShape(body, 48,0,32,32)
	elseif i == 2 then
		shapes[1]=love.physics.newRectangleShape(body,-32,-16,32,32)
		shapes[2]=love.physics.newRectangleShape(body,  0,-16,32,32)
		shapes[3]=love.physics.newRectangleShape(body, 32,-16,32,32)
		shapes[4]=love.physics.newRectangleShape(body, 32, 16,32,32)
	elseif i == 3 then
		shapes[1]=love.physics.newRectangleShape(body,-32,-16,32,32)
		shapes[2]=love.physics.newRectangleShape(body,  0,-16,32,32)
		shapes[3]=love.physics.newRectangleShape(body, 32,-16,32,32)
		shapes[4]=love.physics.newRectangleShape(body,-32, 16,32,32)
	elseif i == 4 then
		shapes[1]=love.physics.newRectangleShape(body,-16,-16,32,32)
		shapes[2]=love.physics.newRectangleShape(body,-16, 16,32,32)
		shapes[3]=love.physics.newRectangleShape(body, 16, 16,32,32)
		shapes[4]=love.physics.newRectangleShape(body, 16,-16,32,32)
	elseif i == 5 then
		shapes[1]=love.physics.newRectangleShape(body,-32, 16,32,32)
		shapes[2]=love.physics.newRectangleShape(body,  0,-16,32,32)
		shapes[3]=love.physics.newRectangleShape(body, 32,-16,32,32)
		shapes[4]=love.physics.newRectangleShape(body,  0, 16,32,32)
	elseif i == 6 then
		shapes[1]=love.physics.newRectangleShape(body,-32,-16,32,32)
		shapes[2]=love.physics.newRectangleShape(body,  0,-16,32,32)
		shapes[3]=love.physics.newRectangleShape(body, 32,-16,32,32)
		shapes[4]=love.physics.newRectangleShape(body,  0, 16,32,32)
	elseif i == 7 then
		shapes[1]=love.physics.newRectangleShape(body,  0, 16,32,32)
		shapes[2]=love.physics.newRectangleShape(body,  0,-16,32,32)
		shapes[3]=love.physics.newRectangleShape(body, 32, 16,32,32)
		shapes[4]=love.physics.newRectangleShape(body,-32,-16,32,32)
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- COLLISION CALLBACK  (own name, does not touch collideBmulti)
-- ─────────────────────────────────────────────────────────────────────────────
function collideAmulti(a, b)
	if (a == "p1-"..counterp1 and b ~= "p2-"..counterp2) or
	   (b == "p1-"..counterp1 and a ~= "p2-"..counterp2) then
		if not amulti_forced_endblock and p1fail == false and
		   a ~= "leftp1" and a ~= "rightp1" and
		   b ~= "leftp1" and b ~= "rightp1" then
			pending_endblock_p1 = true
		end
	elseif (a == "p2-"..counterp2 and b ~= "p1-"..counterp1) or
		   (b == "p2-"..counterp2 and a ~= "p1-"..counterp1) then
		if not amulti_forced_endblock and p2fail == false and
		   a ~= "leftp2" and a ~= "rightp2" and
		   b ~= "leftp2" and b ~= "rightp2" then
			pending_endblock_p2 = true
		end
	elseif gamestate == "gameAmulti_results" then
		if (a=="mario" and b=="resultsfloor") or (b=="mario" and a=="resultsfloor") then
			jumpframe = false
		elseif (a=="luigi" and b=="resultsfloor") or (b=="luigi" and a=="resultsfloor") then
			jumpframe = false
		end
		return
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- END-BLOCK  (req #1: invalid mode wall disable same as original gameBmulti)
-- ─────────────────────────────────────────────────────────────────────────────
function endblockAmultip1()
	-- req #1: in invalid mode, let settled pieces pass through center wall
	if gameno == 2 then
		if tetrishapesp1[counterp1] then
			for j, v in pairs(tetrishapesp1[counterp1]) do
				v:setMask(3, 2)
			end
		end
	end

	local active1 = tetribodiesp1[counterp1]
	if not active1 then return end
	if active1:getY() < losingY then
		p1fail = true
		if p2fail then endgameAmulti() end
	else
		love.audio.stop(blockfall);  love.audio.play(blockfall)
		-- req #2: include just-settled P1 (skip_p1=false), skip still-flying P2 (skip_p2=true)
		local removed = amulti_checklinedensity(true, false, true)
		if not removed then
			-- If a deferred spawn is already pending for P1, don't spawn immediately
			if not amulti_newblockp1 then
				game_addTetriAmultip1()
			end
		else
			amulti_newblockp1 = true
		end
	end
end

function endblockAmultip2()
	if gameno == 2 then
		if tetrishapesp2[counterp2] then
			for j, v in pairs(tetrishapesp2[counterp2]) do
				v:setMask(2, 3)
			end
		end
	end

	local active2 = tetribodiesp2[counterp2]
	if not active2 then return end
	if active2:getY() < losingY then
		p2fail = true
		if p1fail then endgameAmulti() end
	else
		love.audio.stop(blockfall);  love.audio.play(blockfall)
		-- req #2: skip still-flying P1 (skip_p1=true), include just-settled P2 (skip_p2=false)
		local removed = amulti_checklinedensity(true, true, false)
		if not removed then
			-- If a deferred spawn is already pending for P2, don't spawn immediately
			if not amulti_newblockp2 then
				game_addTetriAmultip2()
			end
		else
			amulti_newblockp2 = true
		end
	end
end

function endgameAmulti()
	colorizetimer = love.timer.getTime()
	gamestate = "failingAmulti"
	if musicno < 4 then love.audio.stop(music[musicno]) end
	love.audio.stop(gameover1);  love.audio.play(gameover1)
	if scorescorep1 > scorescorep2 then
		p1wins = p1wins + 1;  winner = 1
	elseif scorescorep1 < scorescorep2 then
		p2wins = p2wins + 1;  winner = 2
	else
		winner = 3
	end
	if p1wins > 99 then p1wins = math.mod(p1wins, 100) end
	if p2wins > 99 then p2wins = math.mod(p2wins, 100) end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- INTERSECTION HELPER  (wide X range covering both player fields)
-- replaces gameA's getintersectX which uses wrong bounds for this field
-- ─────────────────────────────────────────────────────────────────────────────
function amulti_getintersectX(shape, y)
	local xmin, xmax = 180, 920   -- safely outside both walls
	local lt = shape:testSegment(xmin, y, xmax, y)
	local rt = shape:testSegment(xmax, y, xmin, y)
	if lt ~= nil and rt ~= nil then
		local span = xmax - xmin
		return span*lt + xmin,  xmax - span*rt
	end
	return -1, -0.9
end

-- ─────────────────────────────────────────────────────────────────────────────
-- LINE DENSITY CHECK
-- active=false  → just update fill gauge (skip_p1/p2 both true)
-- active=true   → also trigger cut; skip_p1/skip_p2 control which active piece
--                 to exclude (the OTHER player's still-flying piece)
-- req #2: gauge only for settled pieces
-- req #4: gauge clips to each player's X range
-- req #6: check processes all pieces simultaneously
-- req #7: score awarded to player on whose side line is cleared
-- ─────────────────────────────────────────────────────────────────────────────
function amulti_checklinedensity(active, skip_active_p1, skip_active_p2)
	for i = 1, 18 do
		amulti_linereap1[i] = 0
		amulti_linereap2[i] = 0
	end

	-- Area estimation via horizontal sampling at 4 Y points per line.
	-- Each sample = width_at_y * 8 px² (4 samples × 8px = 32px band covered).
	local function sampleBody(tetribodies_tbl, tetrishapes_tbl, skip_idx)
		for bi, bv in pairs(tetribodies_tbl) do
			if bi ~= skip_idx then
				if tetrishapes_tbl[bi] then
					for si, sv in pairs(tetrishapes_tbl[bi]) do
					for line = 1, 18 do
						local y0 = (line-1)*32
						for sy = y0+4, y0+28, 8 do
							-- P1 side
							local lt1 = sv:testSegment(AMULTI_P1_LEFT, sy, AMULTI_P1_RIGHT, sy)
							local rt1 = sv:testSegment(AMULTI_P1_RIGHT, sy, AMULTI_P1_LEFT, sy)
							if lt1 ~= nil and rt1 ~= nil then
								local sp1 = AMULTI_P1_RIGHT - AMULTI_P1_LEFT
								local lx1 = sp1*lt1 + AMULTI_P1_LEFT
								local rx1 = AMULTI_P1_RIGHT - sp1*rt1
								if rx1 > lx1 then
									amulti_linereap1[line] = amulti_linereap1[line] + (rx1-lx1)*8
								end
							end
							-- P2 side
							local lt2 = sv:testSegment(AMULTI_P2_LEFT, sy, AMULTI_P2_RIGHT, sy)
							local rt2 = sv:testSegment(AMULTI_P2_RIGHT, sy, AMULTI_P2_LEFT, sy)
							if lt2 ~= nil and rt2 ~= nil then
								local sp2 = AMULTI_P2_RIGHT - AMULTI_P2_LEFT
								local lx2 = sp2*lt2 + AMULTI_P2_LEFT
								local rx2 = AMULTI_P2_RIGHT - sp2*rt2
								if rx2 > lx2 then
									amulti_linereap2[line] = amulti_linereap2[line] + (rx2-lx2)*8
									end
								end
							end
						end
					end
				end
			end
		end
	end

	local p1skip = skip_active_p1 and counterp1 or nil
	local p2skip = skip_active_p2 and counterp2 or nil
	sampleBody(tetribodiesp1, tetrishapesp1, p1skip)
	sampleBody(tetribodiesp2, tetrishapesp2, p2skip)

	if not active then return false end

	-- Determine cleared lines per side
	local removedlines  = false
	local nlp1, nlp2    = 0, 0
	amulti_linesremovedp1 = {}
	amulti_linesremovedp2 = {}
	for i = 1, 18 do
		if amulti_linereap1[i] > 1024 * amulti_linecleartreshold then
			amulti_linesremovedp1[i] = true;  nlp1 = nlp1+1;  removedlines = true
		end
		if amulti_linereap2[i] > 1024 * amulti_linecleartreshold then
			amulti_linesremovedp2[i] = true;  nlp2 = nlp2+1;  removedlines = true
		end
	end

	if not removedlines then return false end

	-- If any removed line intersects the currently-controlled piece, mark it as settled
	-- so it won't be controllable and will be processed by removeline as a settled piece.
	-- This prevents operating on an active piece and avoids nil-index and crash scenarios.
	local function active_overlaps_lines(bodies, shapes, active_idx, lines_tbl)
		if not active_idx then return false end
		local b = bodies[active_idx]
		if not b then return false end
		if not shapes[active_idx] then return false end
		-- Test if any shape center falls within a removed line's Y range
		for line = 1, 18 do
			if lines_tbl[line] then
				local upper = (line-1)*32
				local lower = line*32
				-- Test several points across the shape horizontally
				for sx = AMULTI_P1_LEFT, AMULTI_P2_RIGHT, 100 do
					for sy = upper+4, lower-4, 8 do
						for j, sh in pairs(shapes[active_idx]) do
							if sh:testPoint(sx, sy) then return true end
						end
					end
				end
			end
		end
		return false
	end

	-- Check active pieces for both players; if overlap detected, mark as settled
	-- and continue with removeline processing (do not return early).
	if active_overlaps_lines(tetribodiesp1, tetrishapesp1, counterp1, amulti_linesremovedp1) then
		if p1fail == false then
			amulti_mark_active_settled(1)
		end
	end
	if active_overlaps_lines(tetribodiesp2, tetrishapesp2, counterp2, amulti_linesremovedp2) then
		if p2fail == false then
			amulti_mark_active_settled(2)
		end
	end

	-- Sound
	local total = nlp1 + nlp2
	if total >= 4 then
		love.audio.stop(fourlineclear);  love.audio.play(fourlineclear)
	else
		love.audio.stop(lineclear);  love.audio.play(lineclear)
	end

	-- Scoring (req #7: to the side whose line is cleared)
	if nlp1 > 0 then
		local avg1 = 0
		for i = 1, 18 do if amulti_linesremovedp1[i] then avg1 = avg1 + amulti_linereap1[i] end end
		avg1 = avg1 / nlp1 / 10240
		local add1 = math.ceil((nlp1*3)^(avg1^10)*20 + nlp1^2*40)
		scorescorep1 = scorescorep1 + add1
		linesscorep1 = linesscorep1 + nlp1
	end
	if nlp2 > 0 then
		local avg2 = 0
		for i = 1, 18 do if amulti_linesremovedp2[i] then avg2 = avg2 + amulti_linereap2[i] end end
		avg2 = avg2 / nlp2 / 10240
		local add2 = math.ceil((nlp2*3)^(avg2^10)*20 + nlp2^2*40)
		scorescorep2 = scorescorep2 + add2
		linesscorep2 = linesscorep2 + nlp2
	end

	-- Snapshot BEFORE cuts (only on first trigger per animation cycle)
	if amulti_cuttingtimer >= amulti_lineclearduration then
		amulti_cutsnapshot = {}
		for i, v in pairs(tetribodiesp1) do
			if v.getX then
				table.insert(amulti_cutsnapshot, {
					x=v:getX(), y=v:getY(), angle=v:getAngle(),
					kind=tetrikindp1[i],
					img=padImagedata(tetriimagedatap1[i])
				})
			end
		end
		for i, v in pairs(tetribodiesp2) do
			if v.getX then
				table.insert(amulti_cutsnapshot, {
					x=v:getX(), y=v:getY(), angle=v:getAngle(),
					kind=tetrikindp2[i],
					img=padImagedata(tetriimagedatap2[i])
				})
			end
		end
		-- Draw pre-cut frame (same pattern as gameA)
		love.graphics.clear()
		gameAmulti_draw()
		love.graphics.present()
		amulti_cuttingtimer = 0
	end

	-- Perform cuts (deduplicated: cut each line at most once)
	-- req #6: removeline processes all pieces from both arrays
	local alreadycut = {}
	for i = 1, 18 do
		if (amulti_linesremovedp1[i] or amulti_linesremovedp2[i]) and not alreadycut[i] then
			alreadycut[i] = true
			amulti_removeline(i)
		end
	end

	-- If active pieces were marked settled and touched by removeline,
	-- set spawn flags so new pieces appear after animation
	if not tetribodiesp1[counterp1] or not tetrishapesp1[counterp1] then
		-- Active piece was fully destroyed or has no shapes
		amulti_newblockp1 = true
	else
		local has_p1_control = false
		for j, sh in pairs(tetrishapesp1[counterp1]) do
			local d = sh:getData()
			if type(d) == "string" and string.sub(d,1,3) == "p1-" then
				has_p1_control = true
				break
			end
		end
		if not has_p1_control then amulti_newblockp1 = true end
	end
	
	if not tetribodiesp2[counterp2] or not tetrishapesp2[counterp2] then
		-- Active piece was fully destroyed or has no shapes
		amulti_newblockp2 = true
	else
		local has_p2_control = false
		for j, sh in pairs(tetrishapesp2[counterp2]) do
			local d = sh:getData()
			if type(d) == "string" and string.sub(d,1,3) == "p2-" then
				has_p2_control = true
				break
			end
		end
		if not has_p2_control then amulti_newblockp2 = true end
	end

	return true
end

-- ─────────────────────────────────────────────────────────────────────────────
-- REMOVE LINE
-- Cuts horizontal band Y=[(lineno-1)*32, lineno*32] from all bodies in BOTH
-- player arrays (req #6).  New fragments go into the OWNER's array (req #8).
-- req #3: shared world — we process tetribodiesp1 and tetribodiesp2 together.
-- req #10: pieces straddling the border work because we test actual geometry.
-- FIX: uses sparse deletion (no table.remove) so counterp1/p2 stay valid.
-- ─────────────────────────────────────────────────────────────────────────────
function amulti_removeline(lineno)
	local upperline = (lineno-1)*32
	local lowerline =  lineno   *32

	-- Process one player's body array; req #8: new fragments go into same tables
	local function processArray(bodies, shapes, kinds, idata, imgs, settled_mask)
		-- Snapshot current indices (safe to modify bodies/shapes during loop)
		local indices = {}
		for i in pairs(bodies) do table.insert(indices, i) end
		table.sort(indices)

		for _, idx in ipairs(indices) do
			if bodies[idx] == nil then -- might have been cleared earlier (shouldn't happen, safety)
			else
				local refined = false
				local shapecopy = {}   -- temp refined shapes attached to bodies[idx]

				for j, w in pairs(shapes[idx]) do
					if w then
						local above, inside, below = false, false, false
						local coords = getPoints2table(w)
						for p = 1, #coords, 2 do
							local py = coords[p+1]
							if     py < upperline then above  = true
							elseif py <= lowerline then inside = true
							else                        below  = true end
						end

						if above and inside and not below then
							local s = amulti_refineshape(upperline, 1, idx, bodies[idx], j, shapes)
							if s then shapecopy[#shapecopy+1]=s end; refined=true
						elseif above and inside and below then
							local s1 = amulti_refineshape(upperline, 1, idx, bodies[idx], j, shapes)
							local s2 = amulti_refineshape(lowerline,-1, idx, bodies[idx], j, shapes)
							if s1 then shapecopy[#shapecopy+1]=s1 end
							if s2 then shapecopy[#shapecopy+1]=s2 end; refined=true
						elseif not above and inside and not below then
							refined=true  -- shape fully removed
						elseif not above and inside and below then
							local s = amulti_refineshape(lowerline,-1, idx, bodies[idx], j, shapes)
							if s then shapecopy[#shapecopy+1]=s end; refined=true
						elseif above and not inside and below then
							local s1 = amulti_refineshape(upperline, 1, idx, bodies[idx], j, shapes)
							local s2 = amulti_refineshape(lowerline,-1, idx, bodies[idx], j, shapes)
							if s1 then shapecopy[#shapecopy+1]=s1 end
							if s2 then shapecopy[#shapecopy+1]=s2 end; refined=true
						else
							-- shape unaffected; keep a local copy
							local ct = getPoints2table(shapes[idx][j])
							for v = 1, #ct, 2 do
								ct[v], ct[v+1] = bodies[idx]:getLocalPoint(ct[v], ct[v+1])
							end
							shapecopy[#shapecopy+1] = love.physics.newPolygonShape(bodies[idx], unpack(ct))
						end
					end
				end

				if refined then
					-- Destroy old shapes
					for a in pairs(shapes[idx]) do
						if shapes[idx][a] then shapes[idx][a]:destroy(); shapes[idx][a]=nil end
					end
					shapes[idx] = {}

					if #shapecopy == 0 then
						-- Body fully eaten by cut
						bodies[idx]:destroy()
						bodies[idx]=nil; shapes[idx]=nil; kinds[idx]=nil
						imgs[idx]=nil;   idata[idx]=nil
						-- If this was the active piece for P1, mark that new block must spawn
						if idx == counterp1 then amulti_newblockp1 = true end
						if idx == counterp2 then amulti_newblockp2 = true end
					else
						-- Pre-extract world coords BEFORE any body destruction
						local precalc = {}
						for b, sv in pairs(shapecopy) do
							precalc[b] = getPoints2table(sv)
						end

						-- Group disconnected shape clusters
						local grp  = {}
						local ngrp = 0
						for a in pairs(shapecopy) do
							grp[a] = 0
							local ca = precalc[a]
							for sc = 1, a-1 do
								local cp = precalc[sc]
								for ci = 1, #ca/2 do
									for pi = 1, #cp/2 do
										if math.abs(ca[ci*2-1]-cp[pi*2-1]) < 2 and
										   math.abs(ca[ci*2  ]-cp[pi*2  ]) < 2 then
											grp[a] = grp[sc]
										end
									end
								end
							end
							if grp[a] == 0 then ngrp=ngrp+1; grp[a]=ngrp end
						end

						-- Backup image
						local bkw = idata[idx]:getWidth()
						local bkh = idata[idx]:getHeight()
						local backup = love.image.newImageData(bkw, bkh)
						backup:paste(idata[idx], 0, 0, 0, 0, bkw, bkh)

						-- Save body state before destroying
						local ox   = bodies[idx]:getX()
						local oy   = bodies[idx]:getY()
						local oang = bodies[idx]:getAngle()
						local omass= bodies[idx]:getMass()
						local olvx, olvy = bodies[idx]:getLinearVelocity()
						local oangv      = bodies[idx]:getAngularVelocity()

						-- Find max existing id for new fragment IDs
						local maxid = 0
						for k in pairs(bodies) do if k > maxid then maxid=k end end

						for a = 1, ngrp do
							if a == 1 then
								-- Rebuild existing slot
								bodies[idx]:destroy()
								bodies[idx] = love.physics.newBody(world, ox, oy, omass, blockrot)
								bodies[idx]:setAngle(oang)
								shapes[idx] = {}
								for b in pairs(precalc) do
									if grp[b] == a then
										local ct = {}
										for k, pv in ipairs(precalc[b]) do ct[k]=pv end
										for v = 1, #ct, 2 do
											ct[v], ct[v+1] = bodies[idx]:getLocalPoint(ct[v], ct[v+1])
										end
										local ns = love.physics.newPolygonShape(bodies[idx], unpack(ct))
										ns:setData("s-"..idx)
										ns:setMask(unpack(settled_mask))
										shapes[idx][#shapes[idx]+1] = ns
									end
								end
								amulti_cutimage_mp(idx, bodies, shapes, idata, imgs)
								bodies[idx]:setMassFromShapes()
								local m = bodies[idx]:getMass()
								if m < minmass then
									for ii,vv in pairs(shapes[idx]) do vv:setDensity(minmass/m) end
									bodies[idx]:setMassFromShapes()
									for ii,vv in pairs(shapes[idx]) do vv:setDensity(1) end
								end
							else
								-- New fragment (req #8: goes into owner's array)
								maxid = maxid + 1
								local nid = maxid
								bodies[nid] = love.physics.newBody(world, ox, oy, omass, blockrot)
								bodies[nid]:setAngle(oang)
								shapes[nid] = {}
								for b in pairs(precalc) do
									if grp[b] == a then
										local ct = {}
										for k, pv in ipairs(precalc[b]) do ct[k]=pv end
										for v = 1, #ct, 2 do
											ct[v], ct[v+1] = bodies[nid]:getLocalPoint(ct[v], ct[v+1])
										end
										local ns = love.physics.newPolygonShape(bodies[nid], unpack(ct))
										ns:setData("s-"..nid)
										ns:setMask(unpack(settled_mask))
										shapes[nid][#shapes[nid]+1] = ns
									end
								end
								bodies[nid]:setLinearVelocity(olvx, olvy)
								bodies[nid]:setLinearDamping(0.5)
								bodies[nid]:setBullet(true)
								bodies[nid]:setAngularVelocity(oangv)
								idata[nid] = love.image.newImageData(bkw, bkh)
								idata[nid]:paste(backup, 0, 0, 0, 0, bkw, bkh)
								imgs[nid]  = padImagedata(idata[nid])
								kinds[nid] = kinds[idx]
								amulti_cutimage_mp(nid, bodies, shapes, idata, imgs)
								bodies[nid]:setMassFromShapes()
								local m = bodies[nid]:getMass()
								if m < minmass then
									for ii,vv in pairs(shapes[nid]) do vv:setDensity(minmass/m) end
									bodies[nid]:setMassFromShapes()
									for ii,vv in pairs(shapes[nid]) do vv:setDensity(1) end
								end
							end
						end
					end
				end

				-- Cleanup temp shapes (may already be destroyed with body; that's OK)
				for a in pairs(shapecopy) do
					if shapecopy[a] then
						shapecopy[a]:destroy(); shapecopy[a]=nil
					end
				end
			end -- bodies[idx] ~= nil
		end -- for indices
	end -- processArray

	-- Settled mask: normal=only own center wall masked; invalid=both walls masked
	local p1mask = (gameno == 2) and {3, 2} or {3}
	local p2mask = (gameno == 2) and {2, 3} or {2}

	-- req #6: process all pieces from both arrays
	processArray(tetribodiesp1, tetrishapesp1, tetrikindp1, tetriimagedatap1, tetriimagesp1, p1mask)
	processArray(tetribodiesp2, tetrishapesp2, tetrikindp2, tetriimagedatap2, tetriimagesp2, p2mask)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- REFINE SHAPE  (like gameA's refineshape but uses amulti_getintersectX)
-- ─────────────────────────────────────────────────────────────────────────────
function amulti_refineshape(line, mult, bodyid, body, shapeid, shapes_tbl)
	if not shapes_tbl[bodyid] or not shapes_tbl[bodyid][shapeid] then return nil end
	local leftx, rightx = amulti_getintersectX(shapes_tbl[bodyid][shapeid], line)
	if leftx ~= -1 then
		local coords = getPoints2table(shapes_tbl[bodyid][shapeid])
		local lastcutoff
		local i = 2
		while i <= #coords do
			if coords[i]*mult > line*mult then
				table.remove(coords, i);  table.remove(coords, i-1)
				lastcutoff = i;  i = 0
			end
			i = i + 2
		end
		if lastcutoff then
			if mult == 1 then
				if not samepos(coords, line, leftx)  then table.insert(coords, lastcutoff-1, leftx);  table.insert(coords, lastcutoff, line) end
				if not samepos(coords, line, rightx) then table.insert(coords, lastcutoff-1, rightx); table.insert(coords, lastcutoff, line) end
			else
				if not samepos(coords, line, rightx) then table.insert(coords, lastcutoff-1, rightx); table.insert(coords, lastcutoff, line) end
				if not samepos(coords, line, leftx)  then table.insert(coords, lastcutoff-1, leftx);  table.insert(coords, lastcutoff, line) end
			end
		end
		if #coords/2 >= 3 and #coords/2 <= 8 then
			if largeenough(coords) then
				local nc = {}
				for i = 1, #coords, 2 do
					nc[i], nc[i+1] = body:getLocalPoint(coords[i], coords[i+1])
				end
				return love.physics.newPolygonShape(body, unpack(nc))
			end
		end
	else
		local coords = getPoints2table(shapes_tbl[bodyid][shapeid])
		local nc = {}
		for i = 1, #coords, 2 do nc[i], nc[i+1] = body:getLocalPoint(coords[i], coords[i+1]) end
		return love.physics.newPolygonShape(body, unpack(nc))
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- CUT IMAGE  (like gameA's cutimage; uses mpscale instead of scale)
-- ─────────────────────────────────────────────────────────────────────────────
function amulti_cutimage_mp(bodyid, bodies, shapes, idata, imgs)
	local w = idata[bodyid]:getWidth()
	local h = idata[bodyid]:getHeight()
	for py = 0, h-1 do
		for px = 0, w-1 do
			local wx, wy = bodies[bodyid]:getWorldPoint(
				(px - w/2 + 0.5) * (4/mpscale),
				(py - h/2 + 0.5) * (4/mpscale))
			local del = true
			for i, v in pairs(shapes[bodyid]) do
				if v:testPoint(wx, wy) then del=false; break end
			end
			if del then idata[bodyid]:setPixel(px, py, 255, 255, 255, 0) end
		end
	end
	imgs[bodyid] = padImagedata(idata[bodyid])
end

-- Mark the active piece as settled (convert its shapes to 's-<id>' and set settled mask)
function amulti_mark_active_settled(player)
	if player == 1 then
		local idx = counterp1
		if not idx or not tetribodiesp1[idx] or not tetrishapesp1[idx] then return end
		-- Check if already marked settled
		local already_settled = true
		for j, sh in pairs(tetrishapesp1[idx]) do
			local d = sh:getData()
			if type(d) == "string" and string.sub(d,1,3) == "p1-" then
				already_settled = false
				break
			end
		end
		if already_settled then return end
		-- Mark as settled
		local settled_mask = (gameno == 2) and {3,2} or {3}
		for j, sh in pairs(tetrishapesp1[idx]) do
			sh:setData("s-"..idx)
			sh:setMask(unpack(settled_mask))
		end
	elseif player == 2 then
		local idx = counterp2
		if not idx or not tetribodiesp2[idx] or not tetrishapesp2[idx] then return end
		-- Check if already marked settled
		local already_settled = true
		for j, sh in pairs(tetrishapesp2[idx]) do
			local d = sh:getData()
			if type(d) == "string" and string.sub(d,1,3) == "p2-" then
				already_settled = false
				break
			end
		end
		if already_settled then return end
		-- Mark as settled
		local settled_mask = (gameno == 2) and {2,3} or {2}
		for j, sh in pairs(tetrishapesp2[idx]) do
			sh:setData("s-"..idx)
			sh:setMask(unpack(settled_mask))
		end
	end
end

function active_is_controllable(player)
	if player == 1 then
		local idx = counterp1
		if not idx then return false end
		if not tetribodiesp1[idx] or not tetrishapesp1[idx] then return false end
		for j, sh in pairs(tetrishapesp1[idx]) do
			local d = sh:getData()
			if type(d) == "string" and string.sub(d,1,3) == "p1-" then return true end
		end
		return false
	elseif player == 2 then
		local idx = counterp2
		if not idx then return false end
		if not tetribodiesp2[idx] or not tetrishapesp2[idx] then return false end
		for j, sh in pairs(tetrishapesp2[idx]) do
			local d = sh:getData()
			if type(d) == "string" and string.sub(d,1,3) == "p2-" then return true end
		end
		return false
	end
	return false
end

-- Handle both players ending block in the same frame
function endblockAmultip_simultaneous()
	-- apply invalid-mode mask adjustments
	if gameno == 2 then
		if tetrishapesp1[counterp1] then
			for j, v in pairs(tetrishapesp1[counterp1]) do v:setMask(3,2) end
		end
		if tetrishapesp2[counterp2] then
			for j, v in pairs(tetrishapesp2[counterp2]) do v:setMask(2,3) end
		end
	end

	-- check losing conditions
	local a1 = tetribodiesp1[counterp1]
	local a2 = tetribodiesp2[counterp2]
	if a1 and a1:getY() < losingY then
		p1fail = true
	end
	if a2 and a2:getY() < losingY then
		p2fail = true
	end
	if p1fail and p2fail then endgameAmulti(); return end

	love.audio.stop(blockfall); love.audio.play(blockfall)

	-- include both active pieces in density check
	local removed = amulti_checklinedensity(true, false, false)

	if not removed then
		if not p1fail then
			if not amulti_newblockp1 then game_addTetriAmultip1() end
		end
		if not p2fail then
			if not amulti_newblockp2 then game_addTetriAmultip2() end
		end
	else
		if not p1fail then amulti_newblockp1 = true end
		if not p2fail then amulti_newblockp2 = true end
	end
end