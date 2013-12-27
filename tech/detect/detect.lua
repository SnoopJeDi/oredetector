-- TODO
-- future-loading? (use coroutine.yield() and coroutine.resume())
-- glob detection/weighting (more ore = faster)
---- hints_ suggested doing a full scan, splining over the results, and finding maxima (analytical?!)
-- sparse scanning (interlace + use collision data)
-- particle FX?

local dmin = 10/45
local searchpattern = {}
local candidates = {}
local results = {}
local startTime = {}
local lastScan = os.clock()
local nextOreSound = nil
local soundDelay = 0.2
local scoringPower = 0.7 
local scanning = false
local cache = {}
local cachettl = 30
local flushtime = 0
local neighbor3x3 = { {1,0}, {1,1}, {0,1}, {-1,1}, {-1,0}, {-1,-1}, {0,-1}, {1,-1} }
local pingTargets = { ["coal"]=true, ["silver"]=true, ["dirt"]=false, ["cobblestone"]=false }
local scanorigin = {}
local maxSoundDelay = 2
local minScanDelay = 0.1
local scanDelay = 0
local minScore = 3
local soundstr = "/sfx/beep.ogg"
local farDist = 30
local mediumDist = 15

-- set this flag to true to test mats, not mods (debugging)
local debugTestMat = false

function init()
  world.logInfo("Initialized detect.lua")
  data.detectRange = 45
  --data.detectRange = 20
  data.delayScan = false
  data.origPos = tech.position()
  generateSearchPattern()
 
  a = { 1,2,3 }
  b = { 2,2,1 }
  --int_ab should be ==  { [2]=2 }
  int_ab = intersectTables(a,b)
  world.logInfo("Intersecting tables a,b, result is %s",int_ab)
end

function intersectTables(a,b)
    local c = {}
    for k,v in pairs(a) do
	-- if b[k] doesn't exist, c[k] is nil!
	    if b[k] == v then
    	    c[k] = v
	    end
    end
    return c
end

function scan()
    local origpos = tech.position()
    scanorigin = origpos
    local maxscore = { {}, 0 } 
    results = {}
    flushtime = os.clock() + cachettl
    -- if this ends up being future-loaded, run with coroutine.create(scan)
    if nextOreSound then return nil end
    for i,ring in pairs(searchpattern) do
        --table.insert(results,scanRing(ring,origpos))
        scanRing(ring,origpos)
    end

    local num = 0
    local scoring = {}
    for px,t in pairs(results) do
        for py,mod in pairs (t) do 
            num = num + 1
            if not scoring[px] then scoring[px]={} end
            dist = math.sqrt(math.pow(px-origpos[1],2)+math.pow(py-origpos[2],2))
            if dist < 1 then dist = 1 end
            scoring[px][py] = scoreTile({px,py},mod,dist)
            world.logInfo("Now scoring %s, dist is %d, score is %d",{px,py},dist,scoring[px][py])
            if scoring[px][py] > maxscore[2] then maxscore = { {px,py}, scoring[px][py] } end
        end
    end
    --world.logInfo("Max score is %s",maxscore)
    if not maxscore[1][1] then 
        scanDelay = 1.0 -- switch to 'passive' scan
        return nil 
    end
    scanDelay = 0.0 -- switch to 'active' scan
    dist = math.sqrt(math.pow(maxscore[1][1]-origpos[1],2)+math.pow(maxscore[1][2]-origpos[2],2))
    if dist >= farDist then
        soundstr = "/sfx/oredetector/coal/far.wav"
    elseif dist < farDist and dist >= mediumDist then
        soundstr = "/sfx/oredetector/coal/medium.wav"
    elseif dist < mediumDist then
        soundstr = "/sfx/oredetector/coal/close.wav"
    end 
    nextOreSound = os.clock() + math.min(soundDelay * 1/maxscore[2],maxSoundDelay)
    world.spawnProjectile("oreflash2",maxscore[1],tech.parentEntityId(),{0,0},false)
end

function scoreTile(pos,target,dist)
    local score = 1
    for i=1,8 do
        local neighbor = {round(pos[1]+neighbor3x3[i][1]),round(pos[2]+neighbor3x3[i][2])}
        if results[neighbor[1]] and results[neighbor[1]][neighbor[2]] then 
            --world.logInfo("Incrementing score...")
            score=score+1 
        end
    end 
    if score < minScore then return 0 end
    return score/math.pow(dist+1,scoringPower)
end

function scanRing(ring,origpos)
	local res = {}
	for j,pos in pairs(ring) do
		local dist = pos[1]*pos[1]+pos[2]*pos[2]
		local scanpos = {round(origpos[1]+pos[1]),round(origpos[2]+pos[2])}
		local usecache = (dist > 25)
		res[scanpos] = scanTile(scanpos,dist,usecache)
    end
	return res
end

function scanTile(scanpos,dist,usecache)
	local res = nil 
	local ctile = nil

	-- this will initialize the child table as necessary
	if not cache[scanpos[1]] then cache[scanpos[1]] = {} end
	xcache = cache[scanpos[1]]
	ctile = xcache[scanpos[2]]
	
	if ctile and usecache then
		--world.logInfo("Using cached result...")
		res = ctile[1]
	else
		res = world.mod(scanpos,"foreground") or "empty"
        if debugTestMat then res = world.material(scanpos,"foreground") or "empty" end 
		cache[scanpos[1]][scanpos[2]] = { res, flushtime }
    end
	if pingTargets[res] then 
        if not results[scanpos[1]] then results[scanpos[1]] = {} end
        results[scanpos[1]][scanpos[2]] = res 
        --world.logInfo("%s",results)
    end
	return res
end

function generateSearchPattern()
    searchpattern = { 
        { {1,0}, {0,1}, {-1,0}, {0,-1} } 
    }
    for i=2,data.detectRange do
        table.insert(searchpattern,createOctagon(i))
    end
    --world.logInfo("Full searchpattern is %s",searchpattern)
    for k,v in pairs(searchpattern[1]) do
        --world.logInfo("Key %s has val %s",k,v)
    end
end

function round(num)
-- to nearest integer
    return math.floor(num + 0.5)
end

function createOctagon(i)
-- do stuff.  see the xcf file
    local perimeter = 4*math.ceil(i/2) + (3-i%2)*4*math.floor(i/2)
    local ret = {}
    --world.logInfo("'Perimeter' of octagon %d is %d",i,perimeter)  
    
    for j=0,perimeter-1 do
    table.insert(ret,
        {
            round(i*math.cos(j*2*math.pi/perimeter)),
            round(i*math.sin(j*2*math.pi/perimeter))
        })
    end
    return ret
end

function input(args)
  if args.moves["special"] == 1 then
    world.logInfo("returning 'detect' in detect.lua:input()")
    return "detect"
  end
  if args.moves["special"] == 2 then
    --world.logInfo("Flushing cache")
    --cache = {}
    --return "mousepos"
    nearpow = nearpow - 0.1
    world.logInfo("nearpow is %d",nearpow)
  end
  if args.moves["special"] == 3 then
    nearpow = nearpow + 0.1
    world.logInfo("nearpow is %d",nearpow)
    return "mousepos"
  end
  
  return nil
end

function update(args)
  if args.actions["mousepos"] then
    local mpos = args.aimPosition 
    world.spawnProjectile("oreflash2", mpos, tech.parentEntityId(), {0,0}, false)
    world.logInfo("Mouse position is (%d,%d)",mpos[1],mpos[2])
  end
  
  if nextOreSound and os.clock() > nextOreSound then
    --world.logInfo("Playing that sound...")
    nextOreSound = nil
    tech.playImmediateSound(soundstr)
  end
  
  if (os.clock()-lastScan) > (minScanDelay + scanDelay) and scanning then
    lastScan=os.clock()
    scan()
  end
  
  if args.actions["detect"] then
    scanning = not scanning
    nextOreSound = nil
    world.logInfo("detect passed as an arg in detect.lua:update(), setting scanning to %s",scanning)
    return nil
  end
end


function getCandidates()
    local c = {}
    local collisions = {}
    local origpos = tech.position()
    local n = 0
    local scanstartTime = os.clock()
    
    for i=-data.detectRange,data.detectRange do
        collisions = world.collisionBlocksAlongLine({origpos[1]+i,origpos[2]+data.detectRange},{origpos[1]+i,origpos[2]-data.detectRange})
        --[[for k,v in pairs(collisions) do
            c[v] = 1
            n = n + 1
            --world.logInfo("In detect.lua:getCandidates() Logging key %s val %s",k,v)
        end ]]--
    end
    world.logInfo("Found %d collisions in detect.lua:getCandidates(), total scan took %d ms",n,(os.clock()-scanstartTime)*1000)
    c = collisions
    return c
end
