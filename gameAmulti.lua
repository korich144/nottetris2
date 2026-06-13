-- gameAmulti.lua
-- Multiplayer A-type with line cutting (nettris-style) and fill gauges per player.
--
-- Physics coordinate notes (all in world space):
--   wallbodiesp1/p2 are anchored at (32, -64).
--   P1 play field:  worldX  228 .. 548,  worldY  -64 .. 576
--   P2 play field:  worldX  548 .. 868,  worldY  -64 .. 576
--   18 cut lines at worldY = k*32  (k=1..18), same as gameA.
--   Mid-wall (border P1/P2): worldX = 548
--
-- Display units = worldUnits * physicsmpscale  (physicsmpscale = mpscale/4)
--   Screen offset due to UI borders:
--     P1 field left edge on screen  = (228-32)*physicsmpscale = 196*physicsmpscale
--       but because the body origin is 32,-64 the shapes' local x=196 -> world x = 228
--       display x = 228 * physicsmpscale ... wait, physicsmpscale already converts physics -> screen.
--     Actually: display_x = worldX * physicsmpscale, display_y = worldY * physicsmpscale
--   P1 field on screen: x from 228*physicsmpscale to 548*physicsmpscale
--   P2 field on screen: x from 548*physicsmpscale to 868*physicsmpscale
--   The background image is 274 px wide at mpscale, physics world spans 0..960 local => 32..868+32 world
--   Screen display: world_x * physicsmpscale = world_x * mpscale/4
--   At mpscale=4: field left (world 196+32=228) => 228/4*4=228 px... 
--     Actually the drawable coordinate IS world*physicsmpscale, so:
--     P1 left wall inner: world 228 => screen 228*(mpscale/4)
--     For mpscale=4: 228*1=228, background is 274*4=1096 wide... that can't be right.
--   Re-examining: physicsmpscale = mpscale/4. Bodies drawn at v:getX()*physicsmpscale.
--   World coordinates are in physics units (Box2D). meter=30.
--   Wall coords are in the hundreds, meaning the physics world is NOT scaled per meter here;
--   the game just uses raw pixel-like coords in Box2D.
--   So world X=228, physicsmpscale=mpscale/4 => screen x = 228*(mpscale/4).
--   Background is 274*mpscale wide. P1 field inner left = 228*(mpscale/4) = 57*mpscale.
--   P2 field inner right = 868*(mpscale/4) = 217*mpscale. That fits 274*mpscale.
--   P1 field: screen x 57*mpscale .. 137*mpscale  (width 80*mpscale = 320/4 ... 10 cols * 32/4)
--   P2 field: screen x 137*mpscale .. 217*mpscale
--   Mid-border: 548*(mpscale/4) = 137*mpscale
--
-- Fill gauge:
--   P1 gauge drawn left of P1 field (like gameA: x=0..6*scale)
--     Here at x = (228-8)*(mpscale/4) = 55*mpscale .. (55+6)*mpscale  => ~55..61*mpscale
--     But UI area is 0..57*mpscale, so use x from 0, width 6*mpscale per row (like gameA scaled).
--     gameA: rectangle("fill", 0, (i-1)*8*scale, 6*scale*fullness, 8*scale)
--     Here we want it against the left wall of each player's field.
--     P1: against left side of screen (like gameA), x from (57-6)*mpscale ... but let's just use
--         x from 0 (screen left), offset so it lines up nicely within the UI strip.
--         Looking at gameA: gauge is at x=0, field starts at 14*scale. UI strip = 14*scale wide.
--         In gameAmulti: P1 field left edge = 57*mpscale. UI strip left = 0.
--         We place P1 gauge at x= (57-6)*mpscale = 51*mpscale, or simply at x=0 (far left).
--         Use: x=0, like gameA.
--     P2: mirror on right side. Field right edge = 217*mpscale. Screen right = 274*mpscale.
--         Place gauge at x = (274-6)*mpscale from right: x = 268*mpscale, width 6*mpscale right-to-left.
--         Draw: x = 268*mpscale, width = 6*fullness*mpscale  BUT drawn from right edge leftward.
--         Simplest: x = (274-6*fullness)*mpscale ... no, draw rectangle from fixed right anchor:
--           love.graphics.rectangle("fill", 268*mpscale, (i-1)*8*mpscale, 6*mpscale*fullness, 8*mpscale)

-- IMPORTANT SCALING NOTE for line positions on screen:
--   gameA draws blinky lines at: love.graphics.rectangle("fill", 14*scale, (i-1)*8*scale, 82*scale, 8*scale)
--   The field left edge on screen in gameA = 14*scale (from background image layout).
--   In gameAmulti:
--     P1 field left edge = 57*mpscale, width = 80*mpscale
--     P2 field left edge = 137*mpscale, width = 80*mpscale

function gameAmulti_load()
	if musicno < 4 then
		love.audio.stop(music[musicno])
	end
	
	gamestate = "gameAmulti"
	gamestarted = false
	
	beeped = {false, false, false}
	
	--figure out the multiplayer scale
	mpscale = scale
	while 274*mpscale > desktopwidth do
		mpscale = mpscale - 1
	end
	physicsmpscale = mpscale/4
	
	mpfullscreenoffsetX = (desktopwidth-274*mpscale)/2
	mpfullscreenoffsetY = (desktopheight-144*mpscale)/2
	
	if not fullscreen then
		love.graphics.setMode( 274*mpscale, 144*mpscale, fullscreen, vsync, 16 )
	end
	
	--nextpieces
	nextpieceimgmp = {}
	for i = 1, 7 do
		nextpieceimgmp[i] = newPaddedImage( "graphics/pieces/"..i..".png", mpscale )
	end
	
	difficulty_speed = 100

	p1fail = false
	p2fail = false
	
	p1color = {255, 50, 50}
	p2color = {50, 255, 50}
	
	scorescorep1 = 0
	linesscorep1 = 0
	
	scorescorep2 = 0
	linesscorep2 = 0
	
	counterp1 = 0 --first piece is 1
	counterp2 = 0 --first piece is 1
	
	tetrikindp1 = {}
	tetriimagedatap1 = {}
	tetriimagesp1 = {}
	
	tetrikindp2 = {}
	tetriimagedatap2 = {}
	tetriimagesp2 = {}
	
	randomtable = {}
	nextpiecep1 = nil
	nextpiecep2 = nil
	
	nextpiecerot = 0
	
	-- Cutting state (new for gameAmulti)
	amulti_cuttingtimer = amulti_lineclearduration  -- when == duration: no cut in progress
	amulti_linesremoved = {}
	amulti_linessidep1 = {}  -- which player's side each removed line belongs to
	amulti_linessidep2 = {}
	amulti_linesremovedp1 = {} -- booleans indexed 1-18
	amulti_linesremovedp2 = {}
	
	-- Snapshot of bodies/positions for cut animation
	amulti_tetricutpos    = {}
	amulti_tetricutang    = {}
	amulti_tetricutkind   = {}
	amulti_tetricutimg_p1 = {}
	amulti_tetricutimg_p2 = {}
	
	-- Per-player line density (fill gauge)
	amulti_linereap1 = {}
	amulti_linereap2 = {}
	for i = 1, 18 do
		amulti_linereap1[i] = 0
		amulti_linereap2[i] = 0
	end
	
	amulti_densityupdatetimer = 0
	
	amulti_newblockp1 = false
	amulti_newblockp2 = false
	
	--PHYSICS--
	meter = 30
	world = love.physics.newWorld(0, -720, 960, 1050, 0, 500, true )
	
	wallshapesp1 = {}
	tetrishapesp1 = {}
	tetribodiesp1 = {}
	
	wallshapesp2 = {}
	tetrishapesp2 = {}
	tetribodiesp2 = {}
	
	--WALLS P1--
	wallbodiesp1 = love.physics.newBody(world, 32, -64, 0, 0)
	
	wallshapesp1[0] = love.physics.newPolygonShape( wallbodiesp1,164, 0, 164,672, 196,672, 196, 0)
	wallshapesp1[0]:setData("leftp1")
	wallshapesp1[0]:setFriction(0.0001)
	
	wallshapesp1[1] = love.physics.newPolygonShape( wallbodiesp1,516,0, 516,672, 548,672, 548,0)
	wallshapesp1[1]:setData("rightp1")
	wallshapesp1[1]:setCategory( 2 )
	wallshapesp1[1]:setFriction(0.0001)
	
	wallshapesp1[2] = love.physics.newPolygonShape( wallbodiesp1,196,640, 196,672, 516,672, 516,640)
	wallshapesp1[2]:setData("groundp1")
	
	--WALLS P2--
	wallbodiesp2 = love.physics.newBody(world, 32, -64, 0, 0)
	
	wallshapesp2[0] = love.physics.newPolygonShape( wallbodiesp2,484, 0, 484,672, 516,672, 516, 0)
	wallshapesp2[0]:setData("leftp2")
	wallshapesp2[0]:setCategory( 3 )
	wallshapesp2[0]:setFriction(0.0001)
	
	wallshapesp2[1] = love.physics.newPolygonShape( wallbodiesp2,836,0, 836,672, 868,672, 868,0)
	wallshapesp2[1]:setData("rightp2")
	wallshapesp2[1]:setFriction(0.0001)
	
	wallshapesp2[2] = love.physics.newPolygonShape( wallbodiesp2,516,640, 516,672, 836,672, 836,640)
	wallshapesp2[2]:setData("groundp2")
	-----------
	world:setCallbacks(collideBmulti)
	-----------
	
	randomtable[1] = math.random(7)
	starttimer = love.timer.getTime()
end

-- ──────────────────────────────────────────────────────────────────────────────
-- Constants (mirrors of gameA globals, prefixed to avoid collision)
-- ──────────────────────────────────────────────────────────────────────────────
amulti_lineclearduration  = 1.2   -- seconds (same as lineclearduration)
amulti_lineclearblinks    = 7     -- same as lineclearblinks
amulti_linecleartreshold  = 8.1   -- same as linecleartreshold (in blocks)
amulti_densityupdateinterval = 1/30

-- World X bounds for each player's field (local shape coords + body offset 32)
-- Local coords in shapes: P1 left inner=196, right inner=516; P2 left inner=484, right inner=836
-- World = local + bodyOffset(32,−64) for X: P1=(228,548), P2=(516,868)
-- The mid-wall is shared; we use 548 as the divider (inner edge of P1's right wall)
AMULTI_P1_LEFT  = 228
AMULTI_P1_RIGHT = 548
AMULTI_P2_LEFT  = 548
AMULTI_P2_RIGHT = 868

-- ──────────────────────────────────────────────────────────────────────────────
-- DRAW
-- ──────────────────────────────────────────────────────────────────────────────
function gameAmulti_draw()
	if fullscreen then
		love.graphics.translate(mpfullscreenoffsetX, mpfullscreenoffsetY)
		love.graphics.setScissor(mpfullscreenoffsetX, mpfullscreenoffsetY, 274*mpscale, 144*mpscale)
	end

	--background--
	if gamestate ~= "gameAmulti_results" then
		love.graphics.draw(gamebackgroundmulti, 0, 0, 0, mpscale)
	else
		love.graphics.draw(multiresults, 0, 0, 0, mpscale)
	end
	
	---------------
	-- Countdown
	if gamestarted == false then
		if newtime - starttimer > 2 then
			love.graphics.draw( number1, 73*mpscale, 48*mpscale, 0, mpscale)
			love.graphics.draw( number1, 153*mpscale, 48*mpscale, 0, mpscale)
		elseif newtime - starttimer > 1 then
			love.graphics.draw( number2, 73*mpscale, 48*mpscale, 0, mpscale)
			love.graphics.draw( number2, 153*mpscale, 48*mpscale, 0, mpscale)
		elseif newtime - starttimer > 0 then
			love.graphics.draw( number3, 73*mpscale, 48*mpscale, 0, mpscale)
			love.graphics.draw( number3, 153*mpscale, 48*mpscale, 0, mpscale)
		end
	end

	-- ── Draw pieces ──────────────────────────────────────────────────────────
	if amulti_cuttingtimer == amulti_lineclearduration then
		-- Normal: draw actual bodies
		for i,v in pairs(tetribodiesp1) do
			love.graphics.setColor(255, 255, 255)
			if gamestate == "failingAmulti" or gamestate == "failedAmulti" then
				local timepassed = love.timer.getTime() - colorizetimer
				if v:getY() > 576 - (576*(timepassed/colorizeduration)) then
					love.graphics.setColor(unpack(p1color))
				end
			end
			love.graphics.draw( tetriimagesp1[i], v:getX()*physicsmpscale, v:getY()*physicsmpscale, v:getAngle(), 1, 1, piececenter[tetrikindp1[i]][1]*mpscale, piececenter[tetrikindp1[i]][2]*mpscale)
		end
		
		for i,v in pairs(tetribodiesp2) do
			love.graphics.setColor(255, 255, 255)
			if gamestate == "failingAmulti" or gamestate == "failedAmulti" then
				local timepassed = love.timer.getTime() - colorizetimer
				if v:getY() > 576 - (576*(timepassed/colorizeduration)) then
					love.graphics.setColor(unpack(p2color))
				end
			end
			love.graphics.draw( tetriimagesp2[i], v:getX()*physicsmpscale, v:getY()*physicsmpscale, v:getAngle(), 1, 1, piececenter[tetrikindp2[i]][1]*mpscale, piececenter[tetrikindp2[i]][2]*mpscale)
		end
	else
		-- Cut animation: draw snapshot
		for i = 1, #amulti_tetricutpos/2 do
			love.graphics.setColor(255, 255, 255)
			local px = amulti_tetricutpos[i*2-1]
			local py = amulti_tetricutpos[i*2]
			-- We stored index and owner; img stored per-player separately
			if amulti_tetricutimg_p1[i] then
				love.graphics.draw( amulti_tetricutimg_p1[i], px*physicsmpscale, py*physicsmpscale, amulti_tetricutang[i], 1, 1, piececenter[amulti_tetricutkind[i]][1]*mpscale, piececenter[amulti_tetricutkind[i]][2]*mpscale)
			elseif amulti_tetricutimg_p2[i] then
				love.graphics.draw( amulti_tetricutimg_p2[i], px*physicsmpscale, py*physicsmpscale, amulti_tetricutang[i], 1, 1, piececenter[amulti_tetricutkind[i]][1]*mpscale, piececenter[amulti_tetricutkind[i]][2]*mpscale)
			end
		end
		
		-- Blinky lines
		local section = math.ceil(amulti_cuttingtimer/(amulti_lineclearduration/amulti_lineclearblinks))
		if math.mod(section, 2) == 1 or amulti_cuttingtimer == 0 then
			local rr, rg, rb = unpack(getrainbowcolor(hue))
			local r = 145 + rr*64
			local g = 145 + rg*64
			local b = 145 + rb*64
			
			-- P1 field on screen: left edge = AMULTI_P1_LEFT * physicsmpscale
			-- P2 field on screen: left edge = AMULTI_P2_LEFT * physicsmpscale
			local p1screenX = AMULTI_P1_LEFT * physicsmpscale
			local p1width   = (AMULTI_P1_RIGHT - AMULTI_P1_LEFT) * physicsmpscale
			local p2screenX = AMULTI_P2_LEFT * physicsmpscale
			local p2width   = (AMULTI_P2_RIGHT - AMULTI_P2_LEFT) * physicsmpscale
			-- line height in screen coords: 32 * physicsmpscale = 32*(mpscale/4) = 8*mpscale
			local lineH = 8*mpscale
			
			love.graphics.setColor(r, g, b)
			for i = 1, 18 do
				if amulti_linesremovedp1[i] then
					love.graphics.rectangle("fill", p1screenX, (i-1)*lineH, p1width, lineH)
				end
				if amulti_linesremovedp2[i] then
					love.graphics.rectangle("fill", p2screenX, (i-1)*lineH, p2width, lineH)
				end
			end
		end
	end
	
	love.graphics.setColor(255, 255, 255)

	-- ── Next pieces ───────────────────────────────────────────────────────────
	if p1fail == false and nextpiecep1 then
		love.graphics.draw(nextpieceimgmp[nextpiecep1], 24*mpscale, 120*mpscale, -nextpiecerot, 1, 1, piececenterpreview[nextpiecep1][1]*mpscale, piececenterpreview[nextpiecep1][2]*mpscale)
	end
	if p2fail == false and nextpiecep2 then
		love.graphics.draw(nextpieceimgmp[nextpiecep2], 250*mpscale, 120*mpscale, nextpiecerot, 1, 1, piececenterpreview[nextpiecep2][1]*mpscale, piececenterpreview[nextpiecep2][2]*mpscale)
	end

	-- ── Fill gauges ───────────────────────────────────────────────────────────
	-- P1 gauge: left strip of screen (like gameA at x=0)
	-- P2 gauge: right strip of screen, drawn rightward from right edge
	local lineH = 8*mpscale
	for i = 1, 18 do
		-- P1
		local fullness1 = amulti_linereap1[i] / 1024 / amulti_linecleartreshold
		if fullness1 > 1 then fullness1 = 1 end
		local color1
		if fullness1 == 1 then color1 = 0
		else color1 = 235 - (fullness1/1)*180 end
		love.graphics.setColor(color1, color1, color1)
		love.graphics.rectangle("fill", 0, (i-1)*lineH, math.floor(6*mpscale*fullness1), lineH)
		
		-- P2 (mirrored on right, grows from right edge leftward)
		local fullness2 = amulti_linereap2[i] / 1024 / amulti_linecleartreshold
		if fullness2 > 1 then fullness2 = 1 end
		local color2
		if fullness2 == 1 then color2 = 0
		else color2 = 235 - (fullness2/1)*180 end
		love.graphics.setColor(color2, color2, color2)
		local barW = math.floor(6*mpscale*fullness2)
		love.graphics.rectangle("fill", 274*mpscale - barW, (i-1)*lineH, barW, lineH)
	end
	
	love.graphics.setColor(255, 255, 255)

	-- ── Scores P1 ─────────────────────────────────────────────────────────────
	local offsetX = 0
	local scorestring = tostring(scorescorep1)
	for i = 1, scorestring:len() - 1 do
		offsetX = offsetX - 8*mpscale
	end
	love.graphics.print( scorescorep1, 36*mpscale + offsetX, 24*mpscale, 0, mpscale)
	
	offsetX = 0
	scorestring = tostring(linesscorep1)
	for i = 1, scorestring:len() - 1 do
		offsetX = offsetX - 8*mpscale
	end
	love.graphics.print( linesscorep1, 28*mpscale + offsetX, 80*mpscale, 0, mpscale)

	-- ── Scores P2 ─────────────────────────────────────────────────────────────
	offsetX = 0
	scorestring = tostring(scorescorep2)
	for i = 1, scorestring:len() - 1 do
		offsetX = offsetX - 8*mpscale
	end
	love.graphics.print( scorescorep2, 262*mpscale + offsetX, 24*mpscale, 0, mpscale)
	
	offsetX = 0
	scorestring = tostring(linesscorep2)
	for i = 1, scorestring:len() - 1 do
		offsetX = offsetX - 8*mpscale
	end
	love.graphics.print( linesscorep2, 254*mpscale + offsetX, 80*mpscale, 0, mpscale)

	-- ── Results screen ────────────────────────────────────────────────────────
	if gamestate == "gameAmulti_results" then
		if p1wins < 10 then
			love.graphics.print( "0"..p1wins, 111*mpscale, 128*mpscale, 0, mpscale)
		else
			love.graphics.print( p1wins, 111*mpscale, 128*mpscale, 0, mpscale)
		end
		if p2wins < 10 then
			love.graphics.print( "0"..p2wins, 193*mpscale, 128*mpscale, 0, mpscale)
		else
			love.graphics.print( p2wins, 193*mpscale, 128*mpscale, 0, mpscale)
		end
		
		if winner == 1 then
			if jumpframe == false then
				love.graphics.draw( marioidle, mariobody:getX()*physicsmpscale, mariobody:getY()*physicsmpscale, mariobody:getAngle(), mpscale, mpscale, 12, 13.5)
			else
				love.graphics.draw( mariojump, mariobody:getX()*physicsmpscale, mariobody:getY()*physicsmpscale, mariobody:getAngle(), mpscale, mpscale, 12, 13.5)
			end
			if cryframe == false then
				love.graphics.draw( luigicry1, 162*mpscale, 66*mpscale,  0, mpscale, mpscale)
			else
				love.graphics.draw( luigicry2, 162*mpscale, 66*mpscale,  0, mpscale, mpscale)
				love.graphics.print( "mario", 93*mpscale, 20*mpscale, 0, mpscale)
				love.graphics.print( "wins!", 141*mpscale, 20*mpscale, 0, mpscale)
				for i = 1, 5 do
					love.graphics.draw( congratsline, (86+(8*i-1))*mpscale, 28*mpscale, 0, mpscale, mpscale)
					love.graphics.draw( congratsline, (134+(8*i-1))*mpscale, 28*mpscale, 0, mpscale, mpscale)
				end
			end
		elseif winner == 2 then
			if jumpframe == false then
				love.graphics.draw( luigiidle, luigibody:getX()*physicsmpscale, luigibody:getY()*physicsmpscale, luigibody:getAngle(), mpscale, mpscale, 14, 15.5)
			else
				love.graphics.draw( luigijump, luigibody:getX()*physicsmpscale, luigibody:getY()*physicsmpscale, luigibody:getAngle(), mpscale, mpscale, 14, 15.5)
			end
			if cryframe == false then
				love.graphics.draw( mariocry1, 83*mpscale, 66*mpscale, 0, mpscale, mpscale)
			else
				love.graphics.draw( mariocry2, 83*mpscale, 66*mpscale, 0, mpscale, mpscale)
				love.graphics.print( "luigi", 93*mpscale, 20*mpscale, 0, mpscale)
				love.graphics.print( "wins!", 141*mpscale, 20*mpscale, 0, mpscale)
				for i = 1, 5 do
					love.graphics.draw( congratsline, (86+(8*i-1))*mpscale, 28*mpscale, 0, mpscale, mpscale)
					love.graphics.draw( congratsline, (134+(8*i-1))*mpscale, 28*mpscale, 0, mpscale, mpscale)
				end
			end
		else
			love.graphics.draw( marioidle, 84*mpscale, 69*mpscale, 0, mpscale, mpscale)
			if cryframe == false then
				love.graphics.print( "draw", 160*mpscale, 40*mpscale, 0, mpscale)
			end
			love.graphics.draw( luigiidle, 162*mpscale, 65*mpscale,  0, mpscale, mpscale)
			if cryframe == false then
				love.graphics.print( "draw", 80*mpscale, 40*mpscale, 0, mpscale)
			end
		end
	end
	
	if fullscreen then
		love.graphics.translate(-mpfullscreenoffsetX, -mpfullscreenoffsetY)
		love.graphics.setScissor()
	end
end

-- ──────────────────────────────────────────────────────────────────────────────
-- UPDATE
-- ──────────────────────────────────────────────────────────────────────────────
function gameAmulti_update(dt)
	newtime = love.timer.getTime()

	-- ── Cutting timer (freezes everything) ───────────────────────────────────
	if amulti_cuttingtimer < amulti_lineclearduration then
		amulti_cuttingtimer = amulti_cuttingtimer + dt
		if amulti_cuttingtimer >= amulti_lineclearduration then
			amulti_cuttingtimer = amulti_lineclearduration
			-- Spawn pending blocks
			if amulti_newblockp1 then
				amulti_newblockp1 = false
				game_addTetriAmultip1()
			end
			if amulti_newblockp2 then
				amulti_newblockp2 = false
				game_addTetriAmultip2()
			end
		end
		-- While cutting: do NOT run physics, controls, spawn, density checks
		return
	end

	-- ── Next-piece rotation ───────────────────────────────────────────────────
	nextpiecerot = nextpiecerot + nextpiecerotspeed*dt
	while nextpiecerot > math.pi*2 do
		nextpiecerot = nextpiecerot - math.pi*2
	end

	-- ── Physics ───────────────────────────────────────────────────────────────
	world:update(dt)

	-- ── Countdown / game start ────────────────────────────────────────────────
	if gamestarted == false then
		if newtime - starttimer > 3 then
			if musicno < 4 then
				love.audio.play(music[musicno])
			end
			startgame()
			gamestarted = true
		elseif newtime - starttimer > 2 and beeped[3] == false then
			beeped[3] = true
			love.audio.stop(highscorebeep)
			love.audio.play(highscorebeep)
		elseif newtime - starttimer > 1 and beeped[2] == false then
			beeped[2] = true
			love.audio.stop(highscorebeep)
			love.audio.play(highscorebeep)
		elseif newtime - starttimer > 0 and beeped[1] == false then
			beeped[1] = true
			love.audio.stop(highscorebeep)
			love.audio.play(highscorebeep)
		end

	elseif gamestate == "gameAmulti" then
		-- ── Controls P1 ──────────────────────────────────────────────────────
		if p1fail == false then
			if love.keyboard.isDown( "h" ) then
				if tetribodiesp1[counterp1]:getAngularVelocity() < 3 then
					tetribodiesp1[counterp1]:applyTorque( 70 )
				end
			end
			if love.keyboard.isDown( "g" ) then
				if tetribodiesp1[counterp1]:getAngularVelocity() > -3 then
					tetribodiesp1[counterp1]:applyTorque( -70 )
				end
			end
			if love.keyboard.isDown( "a" ) then
				local x, y = tetribodiesp1[counterp1]:getWorldCenter()
				tetribodiesp1[counterp1]:applyForce( -70, 0, x, y )
			end
			if love.keyboard.isDown( "d" ) then
				local x, y = tetribodiesp1[counterp1]:getWorldCenter()
				tetribodiesp1[counterp1]:applyForce( 70, 0, x, y )
			end
			local x, y = tetribodiesp1[counterp1]:getLinearVelocity()
			if love.keyboard.isDown( "s" ) then
				if y > difficulty_speed*5 then
					tetribodiesp1[counterp1]:setLinearVelocity(x, difficulty_speed*5)
				else
					local cx, cy = tetribodiesp1[counterp1]:getWorldCenter()
					tetribodiesp1[counterp1]:applyForce( 0, 20, cx, cy )
				end
			else
				if y > difficulty_speed then
					tetribodiesp1[counterp1]:setLinearVelocity(x, y-2000*dt)
				end
			end
		end
		-- ── Controls P2 ──────────────────────────────────────────────────────
		if p2fail == false then
			if love.keyboard.isDown( "kp2" ) then
				if tetribodiesp2[counterp2]:getAngularVelocity() < 3 then
					tetribodiesp2[counterp2]:applyTorque( 70 )
				end
			end
			if love.keyboard.isDown( "kp1" ) then
				if tetribodiesp2[counterp2]:getAngularVelocity() > -3 then
					tetribodiesp2[counterp2]:applyTorque( -70 )
				end
			end
			if love.keyboard.isDown( "left" ) then
				local x, y = tetribodiesp2[counterp2]:getWorldCenter()
				tetribodiesp2[counterp2]:applyForce( -70, 0, x, y )
			end
			if love.keyboard.isDown( "right" ) then
				local x, y = tetribodiesp2[counterp2]:getWorldCenter()
				tetribodiesp2[counterp2]:applyForce( 70, 0, x, y )
			end
			local x, y = tetribodiesp2[counterp2]:getLinearVelocity()
			if love.keyboard.isDown( "down" ) then
				if y > difficulty_speed*5 then
					tetribodiesp2[counterp2]:setLinearVelocity(x, difficulty_speed*5)
				else
					local cx, cy = tetribodiesp2[counterp2]:getWorldCenter()
					tetribodiesp2[counterp2]:applyForce( 0, 20, cx, cy )
				end
			else
				if y > difficulty_speed then
					tetribodiesp2[counterp2]:setLinearVelocity(x, y-2000*dt)
				end
			end
		end
		
		-- ── Density update ────────────────────────────────────────────────────
		amulti_densityupdatetimer = amulti_densityupdatetimer + dt
		if amulti_densityupdatetimer >= amulti_densityupdateinterval then
			while amulti_densityupdatetimer >= amulti_densityupdateinterval do
				amulti_checklinedensity(false)
				amulti_densityupdatetimer = amulti_densityupdatetimer - amulti_densityupdateinterval
			end
		end

	elseif gamestate == "failingAmulti" then
		local timepassed = love.timer.getTime() - colorizetimer
		if timepassed > colorizeduration then
			gamestate = "failedAmulti"
			wallshapesp1[2]:destroy()
			wallshapesp2[2]:destroy()
			love.audio.stop(gameover2)
			love.audio.play(gameover2)
		end
	elseif gamestate == "failedAmulti" then
		local clearcheck = true
		for i,v in pairs(tetribodiesp1) do
			if v:getY() < 162*mpscale then clearcheck = false end
		end
		for i,v in pairs(tetribodiesp2) do
			if v:getY() < 162*mpscale then clearcheck = false end
		end
		
		if clearcheck then
			gamestate = "gameAmulti_results"
			jumptimer = love.timer.getTime()
			crytimer = love.timer.getTime()
			love.audio.play(musicresults)
			
			resultsfloorbody = love.physics.newBody(world, 32, -64, 0, 0)
			resultsfloorshape = love.physics.newPolygonShape( resultsfloorbody,196,448, 196,480, 836,480, 836,448)
			resultsfloorshape:setData("resultsfloor")
			
			if winner == 1 then
				mariobody = love.physics.newBody(world, 388, 320, 0, 0)
				marioshape = love.physics.newRectangleShape( mariobody, 0, 0, 64, 108)
				marioshape:setMask(3)
				marioshape:setData("mario")
				mariobody:setLinearDamping(0.5)
				mariobody:setMassFromShapes()
				mariobody:setY(mariobody:getY()-1)
				local x, y = mariobody:getLinearVelocity()
				mariobody:setLinearVelocity(x, -300)
			elseif winner == 2 then
				luigibody = love.physics.newBody(world, 704, 320, 0, 0)
				luigishape = love.physics.newRectangleShape( luigibody, 0, 0, 64, 124)
				luigishape:setMask(2)
				luigishape:setData("luigi")
				luigibody:setLinearDamping(0.5)
				luigibody:setMassFromShapes()
				luigibody:setY(luigibody:getY()-1)
				local x, y = luigibody:getLinearVelocity()
				luigibody:setLinearVelocity(x, -300)
			end
			jumpframe = true
		end
	elseif gamestate == "gameAmulti_results" then
		local jumptimepassed = love.timer.getTime() - jumptimer
		if jumptimepassed > 2 then
			jumptimer = love.timer.getTime()
			jumpframe = true
			if winner == 1 then
				mariobody:setY(mariobody:getY()-1)
				local x, y = mariobody:getLinearVelocity()
				mariobody:setLinearVelocity(x, -300)
			elseif winner == 2 then
				luigibody:setY(luigibody:getY()-1)
				local x, y = luigibody:getLinearVelocity()
				luigibody:setLinearVelocity(x, -300)
			end
		end
		local crytimepassed = love.timer.getTime() - crytimer
		if crytimepassed > 0.4 then
			cryframe = not cryframe
			crytimer = love.timer.getTime()
		end
		if winner == 1 then
			if love.keyboard.isDown("a") then
				local x, y = mariobody:getWorldCenter()
				mariobody:applyForce( -30, 0, x, y-8 )
			end
			if love.keyboard.isDown("d") then
				local x, y = mariobody:getWorldCenter()
				mariobody:applyForce( 30, 0, x, y-8 )
			end
		elseif winner == 2 then
			if love.keyboard.isDown("left") then
				local x, y = luigibody:getWorldCenter()
				luigibody:applyForce( -30, 0, x, y-8 )
			end
			if love.keyboard.isDown("right") then
				local x, y = luigibody:getWorldCenter()
				luigibody:applyForce( 30, 0, x, y-8 )
			end
		end
	end
end

-- ──────────────────────────────────────────────────────────────────────────────
-- GAME START / ADD PIECES
-- ──────────────────────────────────────────────────────────────────────────────
function startgame()
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
	counterp1 = counterp1 + 1
	local randomblockp1 = nextpiecep1
	createtetriAmultip1(randomblockp1, counterp1, 388, blockstartY)
	tetribodiesp1[counterp1]:setLinearVelocity(0, difficulty_speed)
	
	if counterp1 > #randomtable then
		table.insert(randomtable, math.random(7))
	end
	if randomtable[counterp1] == 2 then nextpiecep1 = 3
	elseif randomtable[counterp1] == 3 then nextpiecep1 = 2
	elseif randomtable[counterp1] == 5 then nextpiecep1 = 7
	elseif randomtable[counterp1] == 7 then nextpiecep1 = 5
	else nextpiecep1 = randomtable[counterp1] end
end

function game_addTetriAmultip2()
	counterp2 = counterp2 + 1
	local randomblockp2 = nextpiecep2
	createtetriAmultip2(randomblockp2, counterp2, 708, blockstartY)
	tetribodiesp2[counterp2]:setLinearVelocity(0, difficulty_speed)
	
	if counterp2 > #randomtable then
		table.insert(randomtable, math.random(7))
	end
	nextpiecep2 = randomtable[counterp2]
end

-- ──────────────────────────────────────────────────────────────────────────────
-- CREATE TETRI BODIES
-- ──────────────────────────────────────────────────────────────────────────────
function createtetriAmultip1(i, uniqueid, x, y)
	tetriimagedatap1[uniqueid] = newImageData( "graphics/pieces/"..i..".png", mpscale)
	tetriimagesp1[uniqueid]    = padImagedata( tetriimagedatap1[uniqueid] )
	tetrikindp1[uniqueid] = i
	tetrishapesp1[uniqueid] = {}
	if i == 1 then
		tetribodiesp1[uniqueid] = love.physics.newBody(world, x, y, 0, blockrot)
		tetrishapesp1[uniqueid][1] = love.physics.newRectangleShape( tetribodiesp1[uniqueid], -48,0, 32, 32)
		tetrishapesp1[uniqueid][2] = love.physics.newRectangleShape( tetribodiesp1[uniqueid], -16,0, 32, 32)
		tetrishapesp1[uniqueid][3] = love.physics.newRectangleShape( tetribodiesp1[uniqueid], 16,0, 32, 32)
		tetrishapesp1[uniqueid][4] = love.physics.newRectangleShape( tetribodiesp1[uniqueid], 48,0, 32, 32)
	elseif i == 2 then
		tetribodiesp1[uniqueid] = love.physics.newBody(world, x, y, 0, blockrot)
		tetrishapesp1[uniqueid][1] = love.physics.newRectangleShape( tetribodiesp1[uniqueid], -32,-16, 32, 32)
		tetrishapesp1[uniqueid][2] = love.physics.newRectangleShape( tetribodiesp1[uniqueid], 0,-16, 32, 32)
		tetrishapesp1[uniqueid][3] = love.physics.newRectangleShape( tetribodiesp1[uniqueid], 32,-16, 32, 32)
		tetrishapesp1[uniqueid][4] = love.physics.newRectangleShape( tetribodiesp1[uniqueid], 32,16, 32, 32)
	elseif i == 3 then
		tetribodiesp1[uniqueid] = love.physics.newBody(world, x, y, 0, blockrot)
		tetrishapesp1[uniqueid][1] = love.physics.newRectangleShape( tetribodiesp1[uniqueid], -32,-16, 32, 32)
		tetrishapesp1[uniqueid][2] = love.physics.newRectangleShape( tetribodiesp1[uniqueid], 0,-16, 32, 32)
		tetrishapesp1[uniqueid][3] = love.physics.newRectangleShape( tetribodiesp1[uniqueid], 32,-16, 32, 32)
		tetrishapesp1[uniqueid][4] = love.physics.newRectangleShape( tetribodiesp1[uniqueid], -32,16, 32, 32)
	elseif i == 4 then
		tetribodiesp1[uniqueid] = love.physics.newBody(world, x, y, 0, blockrot)
		tetrishapesp1[uniqueid][1] = love.physics.newRectangleShape( tetribodiesp1[uniqueid], -16,-16, 32, 32)
		tetrishapesp1[uniqueid][2] = love.physics.newRectangleShape( tetribodiesp1[uniqueid], -16,16, 32, 32)
		tetrishapesp1[uniqueid][3] = love.physics.newRectangleShape( tetribodiesp1[uniqueid], 16,16, 32, 32)
		tetrishapesp1[uniqueid][4] = love.physics.newRectangleShape( tetribodiesp1[uniqueid], 16,-16, 32, 32)
	elseif i == 5 then
		tetribodiesp1[uniqueid] = love.physics.newBody(world, x, y, 0, blockrot)
		tetrishapesp1[uniqueid][1] = love.physics.newRectangleShape( tetribodiesp1[uniqueid], -32,16, 32, 32)
		tetrishapesp1[uniqueid][2] = love.physics.newRectangleShape( tetribodiesp1[uniqueid], 0,-16, 32, 32)
		tetrishapesp1[uniqueid][3] = love.physics.newRectangleShape( tetribodiesp1[uniqueid], 32,-16, 32, 32)
		tetrishapesp1[uniqueid][4] = love.physics.newRectangleShape( tetribodiesp1[uniqueid], 0,16, 32, 32)
	elseif i == 6 then
		tetribodiesp1[uniqueid] = love.physics.newBody(world, x, y, 0, blockrot)
		tetrishapesp1[uniqueid][1] = love.physics.newRectangleShape( tetribodiesp1[uniqueid], -32,-16, 32, 32)
		tetrishapesp1[uniqueid][2] = love.physics.newRectangleShape( tetribodiesp1[uniqueid], 0,-16, 32, 32)
		tetrishapesp1[uniqueid][3] = love.physics.newRectangleShape( tetribodiesp1[uniqueid], 32,-16, 32, 32)
		tetrishapesp1[uniqueid][4] = love.physics.newRectangleShape( tetribodiesp1[uniqueid], 0,16, 32, 32)
	elseif i == 7 then
		tetribodiesp1[uniqueid] = love.physics.newBody(world, x, y, 0, blockrot)
		tetrishapesp1[uniqueid][1] = love.physics.newRectangleShape( tetribodiesp1[uniqueid], 0,16, 32, 32)
		tetrishapesp1[uniqueid][2] = love.physics.newRectangleShape( tetribodiesp1[uniqueid], 0,-16, 32, 32)
		tetrishapesp1[uniqueid][3] = love.physics.newRectangleShape( tetribodiesp1[uniqueid], 32,16, 32, 32)
		tetrishapesp1[uniqueid][4] = love.physics.newRectangleShape( tetribodiesp1[uniqueid], -32,-16, 32, 32)
	end
	tetribodiesp1[uniqueid]:setLinearDamping(0.5)
	tetribodiesp1[uniqueid]:setMassFromShapes()
	tetribodiesp1[uniqueid]:setBullet(true)
	for j, v in pairs(tetrishapesp1[uniqueid]) do
		v:setData("p1-"..uniqueid)
		v:setMask(3)
	end
end

function createtetriAmultip2(i, uniqueid, x, y)
	tetriimagedatap2[uniqueid] = newImageData( "graphics/pieces/"..i..".png", mpscale)
	tetriimagesp2[uniqueid]    = padImagedata( tetriimagedatap2[uniqueid] )
	tetrikindp2[uniqueid] = i
	tetrishapesp2[uniqueid] = {}
	if i == 1 then
		tetribodiesp2[uniqueid] = love.physics.newBody(world, x, y, 0, blockrot)
		tetrishapesp2[uniqueid][1] = love.physics.newRectangleShape( tetribodiesp2[uniqueid], -48,0, 32, 32)
		tetrishapesp2[uniqueid][2] = love.physics.newRectangleShape( tetribodiesp2[uniqueid], -16,0, 32, 32)
		tetrishapesp2[uniqueid][3] = love.physics.newRectangleShape( tetribodiesp2[uniqueid], 16,0, 32, 32)
		tetrishapesp2[uniqueid][4] = love.physics.newRectangleShape( tetribodiesp2[uniqueid], 48,0, 32, 32)
	elseif i == 2 then
		tetribodiesp2[uniqueid] = love.physics.newBody(world, x, y, 0, blockrot)
		tetrishapesp2[uniqueid][1] = love.physics.newRectangleShape( tetribodiesp2[uniqueid], -32,-16, 32, 32)
		tetrishapesp2[uniqueid][2] = love.physics.newRectangleShape( tetribodiesp2[uniqueid], 0,-16, 32, 32)
		tetrishapesp2[uniqueid][3] = love.physics.newRectangleShape( tetribodiesp2[uniqueid], 32,-16, 32, 32)
		tetrishapesp2[uniqueid][4] = love.physics.newRectangleShape( tetribodiesp2[uniqueid], 32,16, 32, 32)
	elseif i == 3 then
		tetribodiesp2[uniqueid] = love.physics.newBody(world, x, y, 0, blockrot)
		tetrishapesp2[uniqueid][1] = love.physics.newRectangleShape( tetribodiesp2[uniqueid], -32,-16, 32, 32)
		tetrishapesp2[uniqueid][2] = love.physics.newRectangleShape( tetribodiesp2[uniqueid], 0,-16, 32, 32)
		tetrishapesp2[uniqueid][3] = love.physics.newRectangleShape( tetribodiesp2[uniqueid], 32,-16, 32, 32)
		tetrishapesp2[uniqueid][4] = love.physics.newRectangleShape( tetribodiesp2[uniqueid], -32,16, 32, 32)
	elseif i == 4 then
		tetribodiesp2[uniqueid] = love.physics.newBody(world, x, y, 0, blockrot)
		tetrishapesp2[uniqueid][1] = love.physics.newRectangleShape( tetribodiesp2[uniqueid], -16,-16, 32, 32)
		tetrishapesp2[uniqueid][2] = love.physics.newRectangleShape( tetribodiesp2[uniqueid], -16,16, 32, 32)
		tetrishapesp2[uniqueid][3] = love.physics.newRectangleShape( tetribodiesp2[uniqueid], 16,16, 32, 32)
		tetrishapesp2[uniqueid][4] = love.physics.newRectangleShape( tetribodiesp2[uniqueid], 16,-16, 32, 32)
	elseif i == 5 then
		tetribodiesp2[uniqueid] = love.physics.newBody(world, x, y, 0, blockrot)
		tetrishapesp2[uniqueid][1] = love.physics.newRectangleShape( tetribodiesp2[uniqueid], -32,16, 32, 32)
		tetrishapesp2[uniqueid][2] = love.physics.newRectangleShape( tetribodiesp2[uniqueid], 0,-16, 32, 32)
		tetrishapesp2[uniqueid][3] = love.physics.newRectangleShape( tetribodiesp2[uniqueid], 32,-16, 32, 32)
		tetrishapesp2[uniqueid][4] = love.physics.newRectangleShape( tetribodiesp2[uniqueid], 0,16, 32, 32)
	elseif i == 6 then
		tetribodiesp2[uniqueid] = love.physics.newBody(world, x, y, 0, blockrot)
		tetrishapesp2[uniqueid][1] = love.physics.newRectangleShape( tetribodiesp2[uniqueid], -32,-16, 32, 32)
		tetrishapesp2[uniqueid][2] = love.physics.newRectangleShape( tetribodiesp2[uniqueid], 0,-16, 32, 32)
		tetrishapesp2[uniqueid][3] = love.physics.newRectangleShape( tetribodiesp2[uniqueid], 32,-16, 32, 32)
		tetrishapesp2[uniqueid][4] = love.physics.newRectangleShape( tetribodiesp2[uniqueid], 0,16, 32, 32)
	elseif i == 7 then
		tetribodiesp2[uniqueid] = love.physics.newBody(world, x, y, 0, blockrot)
		tetrishapesp2[uniqueid][1] = love.physics.newRectangleShape( tetribodiesp2[uniqueid], 0,16, 32, 32)
		tetrishapesp2[uniqueid][2] = love.physics.newRectangleShape( tetribodiesp2[uniqueid], 0,-16, 32, 32)
		tetrishapesp2[uniqueid][3] = love.physics.newRectangleShape( tetribodiesp2[uniqueid], 32,16, 32, 32)
		tetrishapesp2[uniqueid][4] = love.physics.newRectangleShape( tetribodiesp2[uniqueid], -32,-16, 32, 32)
	end
	tetribodiesp2[uniqueid]:setLinearDamping(0.5)
	tetribodiesp2[uniqueid]:setMassFromShapes()
	tetribodiesp2[uniqueid]:setBullet(true)
	for j, v in pairs(tetrishapesp2[uniqueid]) do
		v:setData("p2-"..uniqueid)
		v:setMask(2)
	end
end

-- ──────────────────────────────────────────────────────────────────────────────
-- COLLISION CALLBACK
-- ──────────────────────────────────────────────────────────────────────────────
function collideBmulti(a, b)
	if (a == "p1-"..counterp1 and b ~= "p2-"..counterp2) or (b == "p1-"..counterp1 and a ~= "p2-"..counterp2) then
		if p1fail == false and a ~= "leftp1" and a ~= "rightp1" and b ~= "leftp1" and b ~= "rightp1" then
			endblockAmultip1()
		end
	elseif (a == "p2-"..counterp2 and b ~= "p1-"..counterp1) or (b == "p2-"..counterp2 and a ~= "p1-"..counterp1) then
		if p2fail == false and a ~= "leftp2" and a ~= "rightp2" and b ~= "leftp2" and b ~= "rightp2" then
			endblockAmultip2()
		end
	elseif gamestate == "gameAmulti_results" then
		if (a == "mario" and b == "resultsfloor") or (b == "mario" and a == "resultsfloor") then
			jumpframe = false
		elseif (a == "luigi" and b == "resultsfloor") or (b == "luigi" and a == "resultsfloor") then
			jumpframe = false
		end
	end
end

function endblockAmultip1()
	if tetribodiesp1[counterp1]:getY() < losingY then
		p1fail = true
		if p2fail == true then endgameAmulti() end
	else
		love.audio.stop(blockfall)
		love.audio.play(blockfall)
		
		-- Move current P1 piece to "settled" state and check lines
		-- Re-tag shapes so they don't trigger collision again as active piece
		local newid = amulti_highestbodyp1() + 1
		-- Reassign to a new slot beyond counterp1 so collision won't retrigger
		-- Actually we keep the same body; just run line check then spawn next.
		local removed = amulti_checklinedensity(true)
		if not removed then
			-- No cut animation; spawn immediately
			game_addTetriAmultip1()
		else
			-- Spawn deferred until animation ends
			amulti_newblockp1 = true
		end
	end
end

function endblockAmultip2()
	if tetribodiesp2[counterp2]:getY() < losingY then
		p2fail = true
		if p1fail == true then endgameAmulti() end
	else
		love.audio.stop(blockfall)
		love.audio.play(blockfall)
		
		local removed = amulti_checklinedensity(true)
		if not removed then
			game_addTetriAmultip2()
		else
			amulti_newblockp2 = true
		end
	end
end

function endgameAmulti()
	colorizetimer = love.timer.getTime()
	gamestate = "failingAmulti"
	if musicno < 4 then
		love.audio.stop(music[musicno])
	end
	love.audio.stop(gameover1)
	love.audio.play(gameover1)
	
	if scorescorep1 > scorescorep2 then
		p1wins = p1wins + 1
		winner = 1
	elseif scorescorep1 < scorescorep2 then
		p2wins = p2wins + 1
		winner = 2
	else
		winner = 3
	end
	if p1wins > 99 then p1wins = math.mod(p1wins, 100) end
	if p2wins > 99 then p2wins = math.mod(p2wins, 100) end
end

-- ──────────────────────────────────────────────────────────────────────────────
-- LINE DENSITY & CUTTING (adapted from gameA's checklinedensity / removeline)
-- ──────────────────────────────────────────────────────────────────────────────

-- Returns highest index in tetribodiesp1 (analogous to gameA's highestbody)
function amulti_highestbodyp1()
	local i = 1
	while tetribodiesp1[i] ~= nil do i = i + 1 end
	return i - 1
end

function amulti_highestbodyp2()
	local i = 1
	while tetribodiesp2[i] ~= nil do i = i + 1 end
	return i - 1
end

-- getintersectX reused from gameA (no name collision — it's a global there).
-- checklinedensity: per-player, checking only the portion of the shared world
-- that belongs to each player (X range).
-- active=true: perform cuts and scoring; active=false: just update fill gauge.
-- Returns true if any lines were removed (cut animation triggered).
function amulti_checklinedensity(active)
	-- Reset area accumulators
	for i = 1, 18 do
		amulti_linereap1[i] = 0
		amulti_linereap2[i] = 0
	end
	
	-- We iterate all bodies from BOTH players (shared world, requirement #3 & #4).
	-- For each shape we calculate area contribution, but only count the portion
	-- that falls within the owning player's X range.
	-- Requirement #4: "check only the player's portion of the shared field."
	-- Requirement #6: density check processes all players' pieces simultaneously.
	
	-- Build a unified list: {shapes=, bodies=, owner_xmin, owner_xmax}
	-- For line area we clip the X range used in getintersectX to player bounds.
	-- Since getintersectX casts a horizontal ray, we provide clipped segment ends.
	
	-- Helper: compute line areas clipping to [xmin, xmax]
	local function accumulateAreas(tetribodies_tbl, tetrishapes_tbl, linearea_tbl, xmin, xmax)
		for bi, bv in pairs(tetribodies_tbl) do
			for si, sv in pairs(tetrishapes_tbl[bi]) do
				local coords = getPoints2table(sv)
				
				local firstline = 19
				local lastline  = 0
				for pt = 2, #coords, 2 do
					local lineIdx = math.ceil(round(coords[pt]) / 32)
					if lineIdx < firstline then firstline = lineIdx end
					if lineIdx > lastline  then lastline  = lineIdx end
				end
				
				for line = firstline, lastline do
					if line >= 1 and line <= 18 then
						-- Use clipped X segment for the intersection test
						local function getintersectX_clipped(shape, y, x_lo, x_hi)
							local lefttime  = shape:testSegment(x_lo, y, x_hi, y)
							local righttime = shape:testSegment(x_hi, y, x_lo, y)
							if lefttime ~= nil and righttime ~= nil then
								local span = x_hi - x_lo
								local lx = span * lefttime  + x_lo
								local rx = x_hi - span * righttime
								return lx, rx
							else
								return -1, -0.9
							end
						end
						
						local coords2 = getPoints2table(sv)
						
						if line > firstline then
							local offset = 0
							local lx, rx
							repeat
								lx, rx = getintersectX_clipped(sv, (line-1)*32+offset, xmin, xmax)
								offset = offset + 1
							until lx ~= -1 or offset >= 32
							
							local coi = 2
							local lastcutoff = nil
							while coi <= #coords2 do
								if coords2[coi] <= (line-1)*32 then
									table.remove(coords2, coi)
									table.remove(coords2, coi-1)
									lastcutoff = coi
									coi = 0
								end
								coi = coi + 2
							end
							if lastcutoff and lx ~= -1 then
								table.insert(coords2, lastcutoff-1, rx)
								table.insert(coords2, lastcutoff,   (line-1)*32)
								table.insert(coords2, lastcutoff-1, lx)
								table.insert(coords2, lastcutoff,   (line-1)*32)
							end
						end
						
						if line < lastline then
							local offset = 0
							local lx, rx
							repeat
								local function gi2(shape, y, xl, xr)
									local lt = shape:testSegment(xl, y, xr, y)
									local rt = shape:testSegment(xr, y, xl, y)
									if lt ~= nil and rt ~= nil then
										return xl + (xr-xl)*lt, xr - (xr-xl)*rt
									else return -1, -0.9 end
								end
								lx, rx = gi2(sv, line*32-offset, xmin, xmax)
								offset = offset + 1
							until lx ~= -1 or offset >= 32
							
							local coi = 2
							local lastcutoff = nil
							while coi <= #coords2 do
								if coords2[coi] >= line*32 then
									table.remove(coords2, coi)
									table.remove(coords2, coi-1)
									lastcutoff = coi
									coi = 0
								end
								coi = coi + 2
							end
							if lastcutoff and lx ~= -1 then
								table.insert(coords2, lastcutoff-1, lx)
								table.insert(coords2, lastcutoff,   line*32)
								table.insert(coords2, lastcutoff-1, rx)
								table.insert(coords2, lastcutoff,   line*32)
							end
						end
						
						linearea_tbl[line] = linearea_tbl[line] + polygonarea(coords2)
					end
				end
			end
		end
	end
	
	-- For density: count ALL bodies (both players) but clipped to each side.
	-- This satisfies req #4 (check the player's portion of the field).
	-- We merge both body tables for the check.
	local function accumulateBothSides(lineareap1, lineareap2)
		local function doBody(tetribodies_tbl, tetrishapes_tbl)
			for bi, bv in pairs(tetribodies_tbl) do
				for si, sv in pairs(tetrishapes_tbl[bi]) do
					local coords_base = getPoints2table(sv)
					
					local firstline = 19
					local lastline  = 0
					for pt = 2, #coords_base, 2 do
						local lineIdx = math.ceil(round(coords_base[pt]) / 32)
						if lineIdx < firstline then firstline = lineIdx end
						if lineIdx > lastline  then lastline  = lineIdx end
					end
					
					for line = firstline, lastline do
						if line >= 1 and line <= 18 then
							local function processForSide(linearea_tbl, xmin, xmax)
								local coords = getPoints2table(sv)
								
								if line > firstline then
									local offset = 0
									local lx, rx = -1, -0.9
									repeat
										local lt = sv:testSegment(xmin, (line-1)*32+offset, xmax, (line-1)*32+offset)
										local rt = sv:testSegment(xmax, (line-1)*32+offset, xmin, (line-1)*32+offset)
										if lt ~= nil and rt ~= nil then
											lx = xmin + (xmax-xmin)*lt
											rx = xmax - (xmax-xmin)*rt
										end
										offset = offset + 1
									until lx ~= -1 or offset >= 32
									
									local coi = 2; local lastcutoff = nil
									while coi <= #coords do
										if coords[coi] <= (line-1)*32 then
											table.remove(coords, coi); table.remove(coords, coi-1)
											lastcutoff = coi; coi = 0
										end
										coi = coi + 2
									end
									if lastcutoff and lx ~= -1 then
										table.insert(coords, lastcutoff-1, rx); table.insert(coords, lastcutoff, (line-1)*32)
										table.insert(coords, lastcutoff-1, lx); table.insert(coords, lastcutoff, (line-1)*32)
									end
								end
								
								if line < lastline then
									local offset = 0
									local lx, rx = -1, -0.9
									repeat
										local lt = sv:testSegment(xmin, line*32-offset, xmax, line*32-offset)
										local rt = sv:testSegment(xmax, line*32-offset, xmin, line*32-offset)
										if lt ~= nil and rt ~= nil then
											lx = xmin + (xmax-xmin)*lt
											rx = xmax - (xmax-xmin)*rt
										end
										offset = offset + 1
									until lx ~= -1 or offset >= 32
									
									local coi = 2; local lastcutoff = nil
									while coi <= #coords do
										if coords[coi] >= line*32 then
											table.remove(coords, coi); table.remove(coords, coi-1)
											lastcutoff = coi; coi = 0
										end
										coi = coi + 2
									end
									if lastcutoff and lx ~= -1 then
										table.insert(coords, lastcutoff-1, lx); table.insert(coords, lastcutoff, line*32)
										table.insert(coords, lastcutoff-1, rx); table.insert(coords, lastcutoff, line*32)
									end
								end
								
								linearea_tbl[line] = linearea_tbl[line] + polygonarea(coords)
							end
							
							-- Determine which side(s) this shape overlaps
							local bx = bv:getX()
							-- A body near the border can contribute to both sides
							processForSide(lineareap1, AMULTI_P1_LEFT, AMULTI_P1_RIGHT)
							processForSide(lineareap2, AMULTI_P2_LEFT, AMULTI_P2_RIGHT)
						end
					end
				end
			end
		end
		doBody(tetribodiesp1, tetrishapesp1)
		doBody(tetribodiesp2, tetrishapesp2)
	end
	
	accumulateBothSides(amulti_linereap1, amulti_linereap2)
	
	if not active then return false end
	
	-- Check which lines are over threshold on each side
	local removedlines = false
	local numberoflinesp1 = 0
	local numberoflinesp2 = 0
	amulti_linesremovedp1 = {}
	amulti_linesremovedp2 = {}
	
	for i = 1, 18 do
		if amulti_linereap1[i] > 1024 * amulti_linecleartreshold then
			amulti_linesremovedp1[i] = true
			numberoflinesp1 = numberoflinesp1 + 1
			removedlines = true
		end
		if amulti_linereap2[i] > 1024 * amulti_linecleartreshold then
			amulti_linesremovedp2[i] = true
			numberoflinesp2 = numberoflinesp2 + 1
			removedlines = true
		end
	end
	
	if removedlines then
		-- Sound
		local totallines = numberoflinesp1 + numberoflinesp2
		if totallines >= 4 then
			love.audio.stop(fourlineclear)
			love.audio.play(fourlineclear)
		else
			love.audio.stop(lineclear)
			love.audio.play(lineclear)
		end
		
		-- Scoring: award to player on whose side the line was cleared (req #7)
		if numberoflinesp1 > 0 then
			local avgarea1 = 0
			for i = 1, 18 do
				if amulti_linesremovedp1[i] then avgarea1 = avgarea1 + amulti_linereap1[i] end
			end
			avgarea1 = avgarea1 / numberoflinesp1 / 10240
			local scoreadd1 = math.ceil((numberoflinesp1*3)^(avgarea1^10)*20 + numberoflinesp1^2*40)
			scorescorep1 = scorescorep1 + scoreadd1
			linesscorep1 = linesscorep1 + numberoflinesp1
		end
		
		if numberoflinesp2 > 0 then
			local avgarea2 = 0
			for i = 1, 18 do
				if amulti_linesremovedp2[i] then avgarea2 = avgarea2 + amulti_linereap2[i] end
			end
			avgarea2 = avgarea2 / numberoflinesp2 / 10240
			local scoreadd2 = math.ceil((numberoflinesp2*3)^(avgarea2^10)*20 + numberoflinesp2^2*40)
			scorescorep2 = scorescorep2 + scoreadd2
			linesscorep2 = linesscorep2 + numberoflinesp2
		end
		
		-- Snapshot bodies for animation
		amulti_tetricutpos    = {}
		amulti_tetricutang    = {}
		amulti_tetricutkind   = {}
		amulti_tetricutimg_p1 = {}
		amulti_tetricutimg_p2 = {}
		
		for i, v in pairs(tetribodiesp1) do
			table.insert(amulti_tetricutpos, tetribodiesp1[i]:getX())
			table.insert(amulti_tetricutpos, tetribodiesp1[i]:getY())
			table.insert(amulti_tetricutang, tetribodiesp1[i]:getAngle())
			table.insert(amulti_tetricutkind, tetrikindp1[i])
			local idx = #amulti_tetricutang
			amulti_tetricutimg_p1[idx] = padImagedata(tetriimagedatap1[i])
		end
		for i, v in pairs(tetribodiesp2) do
			table.insert(amulti_tetricutpos, tetribodiesp2[i]:getX())
			table.insert(amulti_tetricutpos, tetribodiesp2[i]:getY())
			table.insert(amulti_tetricutang, tetribodiesp2[i]:getAngle())
			table.insert(amulti_tetricutkind, tetrikindp2[i])
			local idx = #amulti_tetricutang
			amulti_tetricutimg_p2[idx] = padImagedata(tetriimagedatap2[i])
		end
		
		-- Draw once before removing (like gameA)
		love.graphics.clear()
		gameAmulti_draw()
		love.graphics.present()
		
		-- Perform cuts on P1 lines (on all bodies in both player tables, req #6 & #8)
		for i = 1, 18 do
			if amulti_linesremovedp1[i] then
				amulti_removeline(i, AMULTI_P1_LEFT, AMULTI_P1_RIGHT)
			end
		end
		for i = 1, 18 do
			if amulti_linesremovedp2[i] then
				amulti_removeline(i, AMULTI_P2_LEFT, AMULTI_P2_RIGHT)
			end
		end
		
		-- Start animation timer
		amulti_cuttingtimer = 0
	end
	
	return removedlines
end

-- ──────────────────────────────────────────────────────────────────────────────
-- amulti_removeline: cuts one line from all bodies in both player arrays.
-- xmin/xmax define the horizontal extent of the line to cut.
-- Requirement #8: pieces split off go into the OWNER's array.
-- Requirement #10: a body in "invalid" mode may straddle the border; we still
--   cut it correctly because we use the actual world geometry.
-- ──────────────────────────────────────────────────────────────────────────────
function amulti_removeline(lineno, xmin, xmax)
	local upperline = (lineno - 1) * 32
	local lowerline = lineno * 32
	
	-- Process bodies from BOTH player arrays (req #6: all pieces processed).
	-- We need to know the owner to place split-off fragments (req #8).
	-- Build a list of {tetribodies, tetrishapes, tetrikind, tetriimagedata,
	--                   tetriimages, owner} entries.
	local function processArray(tetribodies_tbl, tetrishapes_tbl, tetrikind_tbl,
	                            tetriimagedata_tbl, tetriimages_tbl)
		-- Like gameA's removeline but adapted:
		--   - uses xmin/xmax clipped intersection instead of full-width 55..385
		--   - new bodies from splits are placed back in the same (owner's) tables
		
		local ioffset = 0
		local numberofbodies = 0
		-- find count
		local k = 1
		while tetribodies_tbl[k] ~= nil do k = k + 1 end
		numberofbodies = k - 1
		
		-- Dummy slot 1 trick from gameA: we skip body index 1 (the active piece).
		-- In multiplayer the "active" piece is counterp1/counterp2; we still want
		-- to cut all settled bodies. The active piece IS already settled when we
		-- reach here (endblock was called). So we process everything from 1.
		-- (In gameA, bodies[1] was temporarily set to "dummy" to skip the newly
		--  landed piece, but here we want to cut it too since it just landed.)
		
		for i = 1, numberofbodies do
			local idx = i - ioffset
			if idx < 1 or idx > numberofbodies - ioffset then break end
			
			local v = tetribodies_tbl[idx]
			if v == nil then break end
			
			local refined = false
			local tetrishapescopy_local = {}
			
			local coordinateproperties = {}
			coordinateproperties[idx] = {}
			
			for j, w in pairs(tetrishapes_tbl[idx]) do
				local above  = false
				local inside = false
				local below  = false
				coordinateproperties[idx][j] = {}
				local coords = getPoints2table(w)
				
				for y = 1, #coords, 2 do
					if coords[y+1] < upperline then
						coordinateproperties[idx][j][math.ceil(y/2)] = 1; above = true
					elseif coords[y+1] >= upperline and coords[y+1] <= lowerline then
						coordinateproperties[idx][j][math.ceil(y/2)] = 2; inside = true
					elseif coords[y+1] > lowerline then
						coordinateproperties[idx][j][math.ceil(y/2)] = 3; below = true
					end
				end
				
				if above and inside and not below then
					local s = amulti_refineshape(upperline, 1, idx, v, j, w, tetrishapes_tbl)
					if s then tetrishapescopy_local[#tetrishapescopy_local+1] = s end
					refined = true
				elseif above and inside and below then
					local s1 = amulti_refineshape(upperline, 1, idx, v, j, w, tetrishapes_tbl)
					local s2 = amulti_refineshape(lowerline,-1, idx, v, j, w, tetrishapes_tbl)
					if s1 then tetrishapescopy_local[#tetrishapescopy_local+1] = s1 end
					if s2 then tetrishapescopy_local[#tetrishapescopy_local+1] = s2 end
					refined = true
				elseif not above and inside and not below then
					refined = true -- shape removed entirely
				elseif not above and inside and below then
					local s = amulti_refineshape(lowerline,-1, idx, v, j, w, tetrishapes_tbl)
					if s then tetrishapescopy_local[#tetrishapescopy_local+1] = s end
					refined = true
				elseif above and not inside and below then
					local s1 = amulti_refineshape(upperline, 1, idx, v, j, w, tetrishapes_tbl)
					local s2 = amulti_refineshape(lowerline,-1, idx, v, j, w, tetrishapes_tbl)
					if s1 then tetrishapescopy_local[#tetrishapescopy_local+1] = s1 end
					if s2 then tetrishapescopy_local[#tetrishapescopy_local+1] = s2 end
					refined = true
				else
					local cotable = getPoints2table(tetrishapes_tbl[idx][j])
					for var = 1, #cotable, 2 do
						cotable[var], cotable[var+1] = tetribodies_tbl[idx]:getLocalPoint(cotable[var], cotable[var+1])
					end
					tetrishapescopy_local[#tetrishapescopy_local+1] = love.physics.newPolygonShape(tetribodies_tbl[idx], unpack(cotable))
				end
			end -- for shapes
			
			if refined then
				-- Destroy old shapes
				for a, b in pairs(tetrishapes_tbl[idx]) do
					if tetrishapes_tbl[idx][a] then
						tetrishapes_tbl[idx][a]:destroy()
						tetrishapes_tbl[idx][a] = nil
					end
				end
				tetrishapes_tbl[idx] = {}
				
				if #tetrishapescopy_local == 0 then
					-- Body emptied
					if tetribodies_tbl[idx] then
						tetribodies_tbl[idx]:destroy()
						table.remove(tetribodies_tbl, idx)
						table.remove(tetrishapes_tbl, idx)
						table.remove(tetrikind_tbl, idx)
						table.remove(tetriimages_tbl, idx)
						table.remove(tetriimagedata_tbl, idx)
						numberofbodies = numberofbodies - 1
						ioffset = ioffset + 1
					end
				else
					-- Group disconnected shapes
					local shapegroups = {}
					local numberofgroups = 0
					for a, b in pairs(tetrishapescopy_local) do
						shapegroups[a] = 0
						local currentcoords = getPoints2table(b)
						for shapecounter = 1, a - 1 do
							local prevcoords = getPoints2table(tetrishapescopy_local[shapecounter])
							for cc = 1, #currentcoords/2 do
								for pc = 1, #prevcoords/2 do
									if math.abs(currentcoords[cc*2-1] - prevcoords[pc*2-1]) < 2 and
									   math.abs(currentcoords[cc*2]   - prevcoords[pc*2]  ) < 2 then
										shapegroups[a] = shapegroups[shapecounter]
									end
								end
							end
						end
						if shapegroups[a] == 0 then
							numberofgroups = numberofgroups + 1
							shapegroups[a] = numberofgroups
						end
					end
					
					-- Save imagedata backup
					local backupimagedata = love.image.newImageData(tetriimagedata_tbl[idx]:getWidth(), tetriimagedata_tbl[idx]:getHeight())
					backupimagedata:paste(tetriimagedata_tbl[idx], 0, 0, 0, 0, tetriimagedata_tbl[idx]:getWidth(), tetriimagedata_tbl[idx]:getHeight())
					
					for a = 1, numberofgroups do
						if a == 1 then
							local rotation = tetribodies_tbl[idx]:getAngle()
							local ox = tetribodies_tbl[idx]:getX()
							local oy = tetribodies_tbl[idx]:getY()
							local omass = tetribodies_tbl[idx]:getMass()
							tetribodies_tbl[idx]:destroy()
							tetribodies_tbl[idx] = love.physics.newBody(world, ox, oy, omass, blockrot)
							tetribodies_tbl[idx]:setAngle(rotation)
							tetrishapes_tbl[idx] = {}
							for b, c in pairs(tetrishapescopy_local) do
								if shapegroups[b] == a then
									local cotable = getPoints2table(tetrishapescopy_local[b])
									for var = 1, #cotable, 2 do
										cotable[var], cotable[var+1] = tetribodies_tbl[idx]:getLocalPoint(cotable[var], cotable[var+1])
									end
									tetrishapes_tbl[idx][#tetrishapes_tbl[idx]+1] = love.physics.newPolygonShape(tetribodies_tbl[idx], unpack(cotable))
									tetrishapes_tbl[idx][#tetrishapes_tbl[idx]]:setData("settled-"..idx)
								end
							end
							
							amulti_cutimage_mp(idx, numberofgroups, tetribodies_tbl, tetrishapes_tbl, tetriimagedata_tbl, tetriimages_tbl)
							tetribodies_tbl[idx]:setMassFromShapes()
							local mass = tetribodies_tbl[idx]:getMass()
							if mass < minmass then
								for ii, vv in pairs(tetrishapes_tbl[idx]) do vv:setDensity(minmass/mass) end
								tetribodies_tbl[idx]:setMassFromShapes()
								for ii, vv in pairs(tetrishapes_tbl[idx]) do vv:setDensity(1) end
							end
						else
							-- New fragment: req #8 => placed in same owner's array
							local newid = 1
							while tetribodies_tbl[newid] ~= nil do newid = newid + 1 end
							
							local lvx, lvy = tetribodies_tbl[idx]:getLinearVelocity()
							local angv     = tetribodies_tbl[idx]:getAngularVelocity()
							local ox = tetribodies_tbl[idx]:getX()
							local oy = tetribodies_tbl[idx]:getY()
							local omass = tetribodies_tbl[idx]:getMass()
							tetribodies_tbl[newid] = love.physics.newBody(world, ox, oy, omass, blockrot)
							tetribodies_tbl[newid]:setAngle(tetribodies_tbl[idx]:getAngle())
							tetrishapes_tbl[newid] = {}
							
							for b, c in pairs(tetrishapescopy_local) do
								if shapegroups[b] == a then
									local cotable = getPoints2table(tetrishapescopy_local[b])
									for var = 1, #cotable, 2 do
										cotable[var], cotable[var+1] = tetribodies_tbl[idx]:getLocalPoint(cotable[var], cotable[var+1])
									end
									tetrishapes_tbl[newid][#tetrishapes_tbl[newid]+1] = love.physics.newPolygonShape(tetribodies_tbl[newid], unpack(cotable))
									tetrishapes_tbl[newid][#tetrishapes_tbl[newid]]:setData("settled-"..newid)
								end
							end
							
							tetribodies_tbl[newid]:setLinearVelocity(lvx, lvy)
							tetribodies_tbl[newid]:setLinearDamping(0.5)
							tetribodies_tbl[newid]:setBullet(true)
							tetribodies_tbl[newid]:setAngularVelocity(angv)
							
							tetriimagedata_tbl[newid] = love.image.newImageData(backupimagedata:getWidth(), backupimagedata:getHeight())
							tetriimagedata_tbl[newid]:paste(backupimagedata, 0, 0, 0, 0, backupimagedata:getWidth(), backupimagedata:getHeight())
							tetriimages_tbl[newid]    = padImagedata(tetriimagedata_tbl[newid])
							tetrikind_tbl[newid]      = tetrikind_tbl[idx]
							
							amulti_cutimage_mp(newid, numberofgroups, tetribodies_tbl, tetrishapes_tbl, tetriimagedata_tbl, tetriimages_tbl)
							tetribodies_tbl[newid]:setMassFromShapes()
							local mass = tetribodies_tbl[newid]:getMass()
							if mass < minmass then
								for ii, vv in pairs(tetrishapes_tbl[newid]) do vv:setDensity(minmass/mass) end
								tetribodies_tbl[newid]:setMassFromShapes()
								for ii, vv in pairs(tetrishapes_tbl[newid]) do vv:setDensity(1) end
							end
						end
					end
				end
			end -- if refined
			
			-- Cleanup temp shapes
			for a, b in pairs(tetrishapescopy_local) do
				if tetrishapescopy_local[a] then
					tetrishapescopy_local[a]:destroy()
					tetrishapescopy_local[a] = nil
				end
			end
		end -- for bodies
	end -- processArray
	
	-- Process BOTH arrays (req #6)
	processArray(tetribodiesp1, tetrishapesp1, tetrikindp1, tetriimagedatap1, tetriimagesp1)
	processArray(tetribodiesp2, tetrishapesp2, tetrikindp2, tetriimagedatap2, tetriimagesp2)
end

-- ──────────────────────────────────────────────────────────────────────────────
-- amulti_refineshape: same as gameA's refineshape but uses per-player tetrishapes
-- ──────────────────────────────────────────────────────────────────────────────
function amulti_refineshape(line, mult, bodyid, body, shapeid, shape, tetrishapes_tbl)
	local leftx, rightx = getintersectX(tetrishapes_tbl[bodyid][shapeid], line)
	if leftx ~= -1 then
		local coords = getPoints2table(tetrishapes_tbl[bodyid][shapeid])
		
		local lastcutoff
		local i = 2
		while i <= #coords do
			if coords[i]*mult > line*mult then
				table.remove(coords, i)
				table.remove(coords, i-1)
				lastcutoff = i
				i = 0
			end
			i = i + 2
		end
		
		if lastcutoff then
			if mult == 1 then
				if samepos(coords, line, leftx) == false then
					table.insert(coords, lastcutoff-1, leftx)
					table.insert(coords, lastcutoff, line)
				end
				if samepos(coords, line, rightx) == false then
					table.insert(coords, lastcutoff-1, rightx)
					table.insert(coords, lastcutoff, line)
				end
			else
				if samepos(coords, line, rightx) == false then
					table.insert(coords, lastcutoff-1, rightx)
					table.insert(coords, lastcutoff, line)
				end
				if samepos(coords, line, leftx) == false then
					table.insert(coords, lastcutoff-1, leftx)
					table.insert(coords, lastcutoff, line)
				end
			end
		end
		
		if #coords/2 >= 3 and #coords/2 <= 8 then
			if largeenough(coords) then
				local newcoords = {}
				for i = 1, #coords, 2 do
					newcoords[i], newcoords[i+1] = body:getLocalPoint(coords[i], coords[i+1])
				end
				return love.physics.newPolygonShape(body, unpack(newcoords))
			end
		end
	else
		local coords = getPoints2table(tetrishapes_tbl[bodyid][shapeid])
		local newcoords = {}
		for i = 1, #coords, 2 do
			newcoords[i], newcoords[i+1] = body:getLocalPoint(coords[i], coords[i+1])
		end
		return love.physics.newPolygonShape(body, unpack(newcoords))
	end
end

-- ──────────────────────────────────────────────────────────────────────────────
-- amulti_cutimage_mp: like gameA's cutimage but operates on per-player tables.
-- Scale factor: mpscale instead of scale. Physics -> pixel: (4/mpscale).
-- ──────────────────────────────────────────────────────────────────────────────
function amulti_cutimage_mp(bodyid, numberofgroups, tetribodies_tbl, tetrishapes_tbl, tetriimagedata_tbl, tetriimages_tbl)
	local width  = tetriimagedata_tbl[bodyid]:getWidth()
	local height = tetriimagedata_tbl[bodyid]:getHeight()
	
	for y = 0, height-1 do
		for x = 0, width-1 do
			local wx, wy = tetribodies_tbl[bodyid]:getWorldPoint(
				(x - width/2  + 0.5) * (4/mpscale),
				(y - height/2 + 0.5) * (4/mpscale)
			)
			local deletepixel = true
			for i, v in pairs(tetrishapes_tbl[bodyid]) do
				if v:testPoint(wx, wy) then
					deletepixel = false
					break
				end
			end
			if deletepixel then
				tetriimagedata_tbl[bodyid]:setPixel(x, y, 255, 255, 255, 0)
			end
		end
	end
	
	tetriimages_tbl[bodyid] = padImagedata(tetriimagedata_tbl[bodyid])
end