local RSGCore = exports['rsg-core']:GetCoreObject()
lib.locale()

local Overlays   = {}     -- [id] = data
local nearCount  = 0
local placing    = false
local menuOpen   = false

-- RedM control hashes
local KEY_ATTACK   = 0x07CE1E61 -- LMB
local KEY_AIM      = 0xF84FA74F -- RMB
local KEY_ENTER    = 0xC7B5340A
local KEY_BACK     = 0x156F7119
local KEY_SCROLLUP = 0xCC1075A7
local KEY_SCROLLDN = 0xFD0F0C2C
local KEY_SPRINT   = 0x8FFC75D6

local function nui(action, data) SendNUIMessage({ action = action, data = data }) end

---------------------------------
-- sync
---------------------------------
RegisterNetEvent('rsg-overlay:client:sync', function(list)
    Overlays = {}
    for _, o in ipairs(list) do Overlays[o.id] = o end
    nui('setOverlays', list)
end)

RegisterNetEvent('rsg-overlay:client:add', function(o)
    Overlays[o.id] = o
    nui('addOverlay', o)
end)

RegisterNetEvent('rsg-overlay:client:remove', function(id)
    Overlays[id] = nil
    nui('removeOverlay', id)
end)

RegisterNetEvent('RSGCore:Client:OnPlayerLoaded', function()
    TriggerServerEvent('rsg-overlay:server:requestSync')
end)

RegisterNUICallback('ready', function(_, cb)
    nui('config', {
        doubleSided = Config.DoubleSided, audioDistance = Config.AudioDistance, maxVolume = Config.MaxVolume,
        minSize = Config.MinSize, maxSize = Config.MaxSize,
        defW = Config.DefaultWidth, defH = Config.DefaultHeight,
        allowVideo = Config.AllowVideo, allowYoutube = Config.AllowYoutube,
    })
    if LocalPlayer.state.isLoggedIn then TriggerServerEvent('rsg-overlay:server:requestSync') end
    cb('ok')
end)

---------------------------------
-- visibility (distance, facing, line of sight)
---------------------------------
local function lineOfSight(from, o)
    local h = math.rad(o.heading)
    local tx, ty, tz = o.x - math.sin(h) * 0.15, o.y + math.cos(h) * 0.15, o.z
    local ray = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, tx, ty, tz, 1, PlayerPedId(), 7)
    local _, hit = GetShapeTestResult(ray)
    return hit ~= 1
end

CreateThread(function()
    while true do
        local vis = {}
        if next(Overlays) then
            local cam = GetFinalRenderedCamCoord()
            for id, o in pairs(Overlays) do
                local d = #(cam - vector3(o.x, o.y, o.z))
                if d <= Config.RenderDistance then
                    if not Config.OcclusionCheck or lineOfSight(cam, o) then
                        vis[#vis + 1] = { id = id, dist = d }
                    end
                end
            end
        end
        if #vis > 0 or nearCount > 0 then nui('visible', vis) end
        nearCount = #vis
        Wait(Config.VisibilityInterval)
    end
end)

-- per frame camera feed; the NUI does the perspective projection itself
CreateThread(function()
    local wasHidden = false
    while true do
        if nearCount > 0 or placing then
            local hidden = IsPauseMenuActive() or IsScreenFadedOut()
            if hidden then
                if not wasHidden then nui('cam', { hidden = true }) end
            else
                local c = GetFinalRenderedCamCoord()
                local r = GetFinalRenderedCamRot(2)
                nui('cam', { x = c.x, y = c.y, z = c.z, rx = r.x, rz = r.z, fov = GetFinalRenderedCamFov() })
            end
            wasHidden = hidden
            Wait(0)
        else
            Wait(250)
        end
    end
end)

---------------------------------
-- placement
--  stage 1 'aim'    : overlay follows the camera, HUD bar shows keys + live range
--  stage 2 'adjust' : NUI panel with cursor, fine tune position / rotation / size live
---------------------------------
local placeForm = nil
local lookMode  = false

local function camRaycast(dist)
    local c = GetGameplayCamCoord()
    local rot = GetGameplayCamRot(2)
    local p, yaw = math.rad(rot.x), math.rad(rot.z)
    local dir = vector3(-math.sin(yaw) * math.cos(p), math.cos(yaw) * math.cos(p), math.sin(p))
    local dest = c + dir * dist
    local ray = StartExpensiveSynchronousShapeTestLosProbe(c.x, c.y, c.z, dest.x, dest.y, dest.z, 1 | 16, PlayerPedId(), 7)
    local _, hit, endC, normal = GetShapeTestResult(ray)
    if hit == 1 then return endC, normal end
    return dest, nil
end

local function distFromPlayer(x, y, z)
    return #(GetEntityCoords(PlayerPedId()) - vector3(x, y, z))
end

local function finishPlacement(state)
    placing = false
    lookMode = false
    SetNuiFocus(false, false)
    nui('preview', false)
    nui('placeHud', false)
    nui('adjustClose')
    if not state then
        return lib.notify({ title = 'Overlay', description = locale('cancelled'), type = 'inform' })
    end
    CreateThread(function()
        local ok, msg = lib.callback.await('rsg-overlay:server:create', false, state)
        if msg then lib.notify({ title = 'Overlay', description = msg, type = ok and 'success' or 'error' }) end
    end)
end

local function startAdjust(state)
    placing = 'adjust'
    nui('placeHud', false)
    SetNuiFocus(true, true)
    nui('adjustOpen', {
        state = state, maxDist = Config.MaxPlaceDistance,
        minSize = Config.MinSize, maxSize = Config.MaxSize,
    })
    -- keeps right mouse "free look" working while the panel is open
    CreateThread(function()
        while placing == 'adjust' do
            if lookMode then
                DisableControlAction(0, KEY_ATTACK, true)
                if not IsControlPressed(0, KEY_AIM) and not IsDisabledControlPressed(0, KEY_AIM) then
                    lookMode = false
                    SetNuiFocus(true, true)
                    nui('lookMode', false)
                end
            end
            Wait(0)
        end
    end)
end

local function startAim(form, rotOffset, zOffset)
    if placing then return end
    placing = 'aim'
    placeForm = form
    rotOffset, zOffset = rotOffset or 0.0, zOffset or 0.0

    CreateThread(function()
        while placing == 'aim' do
            DisableControlAction(0, KEY_ATTACK, true)
            DisableControlAction(0, KEY_AIM, true)
            DisableControlAction(0, KEY_SCROLLUP, true)
            DisableControlAction(0, KEY_SCROLLDN, true)

            local hitPos, normal = camRaycast(Config.MaxPlaceDistance + 5.0)
            local heading, surface
            if normal and math.abs(normal.z) < 0.7 then
                heading = GetHeadingFromVector_2d(normal.x, normal.y)
                hitPos = hitPos + vector3(normal.x, normal.y, 0.0) * 0.03
                surface = 'wall'
            else
                heading = GetGameplayCamRot(2).z + 180.0
                hitPos = hitPos + vector3(0.0, 0.0, form.height / 2)
                surface = normal and 'ground' or 'air'
            end
            heading = (heading + rotOffset) % 360.0
            local pos = hitPos + vector3(0.0, 0.0, zOffset)
            local dist = distFromPlayer(pos.x, pos.y, pos.z)
            local valid = dist <= Config.MaxPlaceDistance

            local shift = IsControlPressed(0, KEY_SPRINT)
            if IsDisabledControlJustPressed(0, KEY_SCROLLUP) then
                if shift then zOffset = zOffset + Config.HeightStep else rotOffset = rotOffset + Config.RotateStep end
            elseif IsDisabledControlJustPressed(0, KEY_SCROLLDN) then
                if shift then zOffset = zOffset - Config.HeightStep else rotOffset = rotOffset - Config.RotateStep end
            end

            local state = {
                url = form.url, mediaType = form.mediaType, volume = form.volume,
                x = pos.x, y = pos.y, z = pos.z, heading = heading,
                width = form.width, height = form.height, opacity = form.opacity,
            }
            nui('preview', { url = state.url, type = state.mediaType, x = pos.x, y = pos.y, z = pos.z, heading = heading,
                width = state.width, height = state.height, opacity = state.opacity, invalid = not valid })
            nui('placeHud', { dist = dist, maxDist = Config.MaxPlaceDistance, heading = heading,
                rot = rotOffset, zOff = zOffset, surface = surface, valid = valid })

            if IsDisabledControlJustPressed(0, KEY_ATTACK) or IsControlJustPressed(0, KEY_ENTER) then
                if valid then
                    state._rot, state._z = rotOffset, zOffset
                    startAdjust(state)
                else
                    lib.notify({ title = 'Overlay', description = locale('too_far'), type = 'error' })
                end
            elseif IsDisabledControlJustPressed(0, KEY_AIM) or IsControlJustPressed(0, KEY_BACK) then
                finishPlacement(nil)
            end
            Wait(0)
        end
    end)
end

-- live feedback from the adjust panel: validate range for every change
RegisterNUICallback('adjustUpdate', function(s, cb)
    if placing ~= 'adjust' or type(s) ~= 'table' then return cb({}) end
    local d = distFromPlayer(tonumber(s.x) or 0, tonumber(s.y) or 0, tonumber(s.z) or 0)
    cb({ dist = d, valid = d <= Config.MaxPlaceDistance })
end)

RegisterNUICallback('adjustConfirm', function(s, cb)
    cb('ok')
    if placing ~= 'adjust' or type(s) ~= 'table' then return end
    if distFromPlayer(tonumber(s.x) or 0, tonumber(s.y) or 0, tonumber(s.z) or 0) > Config.MaxPlaceDistance then
        return lib.notify({ title = 'Overlay', description = locale('too_far'), type = 'error' })
    end
    finishPlacement(s)
end)

RegisterNUICallback('adjustCancel', function(_, cb) cb('ok') if placing then finishPlacement(nil) end end)

RegisterNUICallback('adjustReaim', function(s, cb)
    cb('ok')
    if placing ~= 'adjust' then return end
    SetNuiFocus(false, false)
    nui('adjustClose')
    placing = false
    startAim({
        url = placeForm.url, mediaType = placeForm.mediaType, volume = tonumber(s.volume) or placeForm.volume,
        width = tonumber(s.width) or placeForm.width, height = tonumber(s.height) or placeForm.height,
        opacity = tonumber(s.opacity) or placeForm.opacity,
    })
end)

-- hold right mouse on the panel to look around, release to get the cursor back
RegisterNUICallback('lookStart', function(_, cb)
    cb('ok')
    if placing ~= 'adjust' then return end
    lookMode = true
    SetNuiFocus(false, false)
    nui('lookMode', true)
end)

---------------------------------
-- menu
---------------------------------
local function closeMenu()
    menuOpen = false
    SetNuiFocus(false, false)
    nui('closeMenu')
end

RegisterNetEvent('rsg-overlay:client:openMenu', function()
    if placing or menuOpen then return end
    local data = lib.callback.await('rsg-overlay:server:getMenuData', false)
    menuOpen = true
    SetNuiFocus(true, true)
    nui('openMenu', data)
end)

RegisterNUICallback('close', function(_, cb) closeMenu() cb('ok') end)

RegisterNUICallback('place', function(form, cb)
    cb('ok')
    closeMenu()
    if type(form) ~= 'table' or type(form.url) ~= 'string' then return end
    startAim({
        url = form.url, mediaType = form.mediaType,
        width = tonumber(form.width) or Config.DefaultWidth, height = tonumber(form.height) or Config.DefaultHeight,
        opacity = tonumber(form.opacity) or 1.0, volume = tonumber(form.volume) or 0.5,
    })
end)

RegisterNUICallback('delete', function(data, cb)
    local ok, msg = lib.callback.await('rsg-overlay:server:delete', false, data.id)
    if msg then lib.notify({ title = 'Overlay', description = msg, type = ok and 'success' or 'error' }) end
    cb({ ok = ok, menu = lib.callback.await('rsg-overlay:server:getMenuData', false) })
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if menuOpen then SetNuiFocus(false, false) end
    if placing then SetNuiFocus(false, false) end
end)
