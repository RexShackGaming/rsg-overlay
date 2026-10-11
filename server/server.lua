local RSGCore = exports['rsg-core']:GetCoreObject()
lib.locale()

local Overlays = {}   -- [id] = row
local Cooldowns = {}  -- [src] = os.time()

---------------------------------
-- helpers
---------------------------------
local function notify(src, msg, typ)
    TriggerClientEvent('ox_lib:notify', src, { title = 'Overlay', description = msg, type = typ or 'inform' })
end

local function clamp(v, mn, mx)
    v = tonumber(v)
    if not v or v ~= v then return mn end
    return math.max(mn, math.min(mx, v))
end

local function toClient(o)
    return {
        id = o.id, url = o.url, type = o.media_type, ytId = o.ytId,
        x = o.x, y = o.y, z = o.z, heading = o.heading,
        width = o.width, height = o.height, opacity = o.opacity, volume = o.volume,
    }
end

local function youtubeId(url)
    return url:match('youtu%.be/([%w_%-]+)')
        or url:match('[?&]v=([%w_%-]+)')
        or url:match('/embed/([%w_%-]+)')
        or url:match('/shorts/([%w_%-]+)')
end

local function hostAllowed(host)
    if #Config.AllowedDomains == 0 then return true end
    host = host:lower()
    for _, d in ipairs(Config.AllowedDomains) do
        if host == d or host:sub(-(#d + 1)) == ('.' .. d) then return true end
    end
    return false
end

-- returns mediaType, ytId or nil on failure
local function classify(url, wanted)
    if type(url) ~= 'string' or #url > Config.MaxUrlLength or url:find('[%s"\'<>\\]') then return nil end
    local host = url:match('^https://([^/:?#]+)')
    if not host or not hostAllowed(host) then return nil end

    local yt = youtubeId(url)
    if yt and (host:find('youtube%.com$') or host:find('youtu%.be$')) then
        if not Config.AllowYoutube or #yt ~= 11 then return nil end
        return 'youtube', yt
    end

    local ext = (url:match('^[^?#]+%.(%w+)[?#]?') or ''):lower()
    if wanted == 'video' or ext == 'mp4' or ext == 'webm' or ext == 'ogv' then
        if not Config.AllowVideo then return nil end
        return 'video'
    end
    return 'image'
end

local function countOwned(cid)
    local n = 0
    for _, o in pairs(Overlays) do if o.citizenid == cid then n = n + 1 end end
    return n
end

local function jobAllowed(Player)
    if #Config.AllowedJobs == 0 then return true end
    for _, j in ipairs(Config.AllowedJobs) do
        if Player.PlayerData.job.name == j then return true end
    end
    return false
end

local function isAdmin(src)
    return RSGCore.Functions.HasPermission(src, Config.AdminPerm)
end

---------------------------------
-- load / expiry
---------------------------------
local function loadAll()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `rsg_overlays` (
        `id` INT NOT NULL AUTO_INCREMENT, `citizenid` VARCHAR(50) NOT NULL,
        `owner_name` VARCHAR(100) NOT NULL DEFAULT '', `url` VARCHAR(512) NOT NULL,
        `media_type` VARCHAR(16) NOT NULL DEFAULT 'image',
        `x` FLOAT NOT NULL, `y` FLOAT NOT NULL, `z` FLOAT NOT NULL,
        `heading` FLOAT NOT NULL DEFAULT 0, `width` FLOAT NOT NULL DEFAULT 1.5,
        `height` FLOAT NOT NULL DEFAULT 1.0, `opacity` FLOAT NOT NULL DEFAULT 1.0,
        `volume` FLOAT NOT NULL DEFAULT 0.5,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`), KEY `citizenid` (`citizenid`))]])

    if Config.ExpireHours > 0 then
        MySQL.query.await('DELETE FROM rsg_overlays WHERE created_at < (NOW() - INTERVAL ? HOUR)', { Config.ExpireHours })
    end

    Overlays = {}
    local rows = MySQL.query.await('SELECT *, UNIX_TIMESTAMP(created_at) AS ts FROM rsg_overlays') or {}
    for _, r in ipairs(rows) do
        if r.media_type == 'youtube' then r.ytId = youtubeId(r.url) end
        Overlays[r.id] = r
    end
    TriggerClientEvent('rsg-overlay:client:sync', -1, (function()
        local list = {}
        for _, o in pairs(Overlays) do list[#list + 1] = toClient(o) end
        return list
    end)())
    print(('[rsg-overlay] loaded %d overlays'):format(#rows))
end

local function removeOverlay(id)
    if not Overlays[id] then return end
    Overlays[id] = nil
    MySQL.query('DELETE FROM rsg_overlays WHERE id = ?', { id })
    TriggerClientEvent('rsg-overlay:client:remove', -1, id)
end

CreateThread(function()
    loadAll()
    if Config.ExpireHours <= 0 then return end
    while true do
        Wait(10 * 60 * 1000)
        local cutoff = os.time() - Config.ExpireHours * 3600
        for id, o in pairs(Overlays) do
            if o.ts and o.ts < cutoff then removeOverlay(id) end
        end
    end
end)

---------------------------------
-- sync
---------------------------------
RegisterNetEvent('rsg-overlay:server:requestSync', function()
    local list = {}
    for _, o in pairs(Overlays) do list[#list + 1] = toClient(o) end
    TriggerClientEvent('rsg-overlay:client:sync', source, list)
end)

---------------------------------
-- command
---------------------------------
RSGCore.Commands.Add(Config.Command, locale('cmd_help'), {}, false, function(source)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player then return end
    if not jobAllowed(Player) and not isAdmin(source) then
        return notify(source, locale('no_job'), 'error')
    end
    TriggerClientEvent('rsg-overlay:client:openMenu', source)
end, Config.CommandPerm)

---------------------------------
-- callbacks
---------------------------------
lib.callback.register('rsg-overlay:server:getMenuData', function(source)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player then return {} end
    local cid = Player.PlayerData.citizenid
    local admin = isAdmin(source)
    local pos = GetEntityCoords(GetPlayerPed(source))
    local list = {}
    for _, o in pairs(Overlays) do
        local d = #(pos - vector3(o.x, o.y, o.z))
        local mine = o.citizenid == cid
        if mine or d <= 50.0 then
            list[#list + 1] = {
                id = o.id, type = o.media_type, url = o.url, owner = o.owner_name,
                dist = math.floor(d * 10) / 10, mine = mine, canDelete = mine or admin,
            }
        end
    end
    table.sort(list, function(a, b) return a.dist < b.dist end)
    return {
        list = list, admin = admin, owned = countOwned(cid),
        max = Config.MaxPerPlayer, cost = Config.PlaceCost, item = Config.RequiredItem,
    }
end)

lib.callback.register('rsg-overlay:server:create', function(source, data)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player or type(data) ~= 'table' then return false end
    local cid = Player.PlayerData.citizenid
    local admin = isAdmin(src)

    if not jobAllowed(Player) and not admin then return false, locale('no_job') end
    if Cooldowns[src] and os.time() - Cooldowns[src] < Config.Cooldown then return false, locale('cooldown') end
    if not admin and countOwned(cid) >= Config.MaxPerPlayer then return false, locale('limit') end

    local mediaType, ytId = classify(data.url, data.mediaType)
    if not mediaType then return false, locale('bad_url') end

    local x, y, z = tonumber(data.x), tonumber(data.y), tonumber(data.z)
    if not x or not y or not z then return false end
    local pos = GetEntityCoords(GetPlayerPed(src))
    if #(pos - vector3(x, y, z)) > Config.MaxPlaceDistance + 3.0 then return false, locale('too_far') end

    if Config.RequiredItem and not exports['rsg-inventory']:HasItem(src, Config.RequiredItem, 1) then
        return false, locale('no_item')
    end
    if Config.PlaceCost > 0 and not Player.Functions.RemoveMoney('cash', Config.PlaceCost, 'overlay-placed') then
        return false, locale('no_money')
    end
    if Config.RequiredItem then
        exports['rsg-inventory']:RemoveItem(src, Config.RequiredItem, 1, nil, 'overlay-placed')
    end

    local row = {
        citizenid = cid,
        owner_name = ('%s %s'):format(Player.PlayerData.charinfo.firstname, Player.PlayerData.charinfo.lastname),
        url = data.url, media_type = mediaType, ytId = ytId,
        x = x, y = y, z = z,
        heading = (tonumber(data.heading) or 0.0) % 360.0,
        width = clamp(data.width, Config.MinSize, Config.MaxSize),
        height = clamp(data.height, Config.MinSize, Config.MaxSize),
        opacity = clamp(data.opacity, 0.1, 1.0),
        volume = clamp(data.volume, 0.0, 1.0),
        ts = os.time(),
    }
    row.id = MySQL.insert.await([[INSERT INTO rsg_overlays
        (citizenid, owner_name, url, media_type, x, y, z, heading, width, height, opacity, volume)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]], {
        row.citizenid, row.owner_name, row.url, row.media_type, row.x, row.y, row.z,
        row.heading, row.width, row.height, row.opacity, row.volume,
    })
    if not row.id then return false end

    Overlays[row.id] = row
    Cooldowns[src] = os.time()
    TriggerClientEvent('rsg-overlay:client:add', -1, toClient(row))
    TriggerEvent('rsg-log:server:CreateLog', 'overlay', 'Overlay Placed', 'green',
        ('%s (%s) placed overlay #%d: %s'):format(GetPlayerName(src), cid, row.id, row.url))
    return true, locale('placed')
end)

lib.callback.register('rsg-overlay:server:delete', function(source, id)
    local Player = RSGCore.Functions.GetPlayer(source)
    id = tonumber(id)
    if not Player or not id then return false end
    local o = Overlays[id]
    if not o then return false, locale('not_found') end
    if o.citizenid ~= Player.PlayerData.citizenid and not isAdmin(source) then
        return false, locale('not_owner')
    end
    removeOverlay(id)
    TriggerEvent('rsg-log:server:CreateLog', 'overlay', 'Overlay Removed', 'red',
        ('%s removed overlay #%d (%s)'):format(GetPlayerName(source), id, o.url))
    return true, locale('removed')
end)

AddEventHandler('playerDropped', function() Cooldowns[source] = nil end)

-- exports for other resources
exports('GetOverlays', function() return Overlays end)
exports('RemoveOverlay', removeOverlay)
