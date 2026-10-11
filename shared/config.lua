Config = {}

---------------------------------
-- access
---------------------------------
Config.Command          = 'overlay'   -- opens the overlay manager
Config.CommandPerm      = 'user'      -- rsg permission needed for the command ('user' = everyone)
Config.AdminPerm        = 'admin'     -- can delete any overlay
Config.AllowedJobs      = {}          -- e.g. { 'newspaper', 'saloon' } ; empty = everyone
Config.MaxPerPlayer     = 5           -- overlays a single character can own (admins unlimited)
Config.RequiredItem     = nil         -- e.g. 'poster' : item consumed on placement (nil = none)
Config.PlaceCost        = 0           -- cash cost per placement (0 = free)
Config.ExpireHours      = 72          -- auto remove after X hours (0 = never)
Config.Cooldown         = 10          -- seconds between placements per player

---------------------------------
-- media
---------------------------------
-- only https links from these hosts are accepted (subdomains included). Empty table = any https host.
Config.AllowedDomains = {
    'imgur.com', 'discordapp.com', 'discordapp.net', 'ibb.co', 'gyazo.com',
    'catbox.moe', 'youtube.com', 'youtu.be', 'giphy.com', 'tenor.com',
}
Config.AllowVideo       = true        -- mp4 / webm links
Config.AllowYoutube     = true
Config.MaxUrlLength     = 500

---------------------------------
-- size / placement (metres)
---------------------------------
Config.MinSize          = 0.25
Config.MaxSize          = 8.0
Config.DefaultWidth     = 1.5
Config.DefaultHeight    = 1.0
Config.MaxPlaceDistance = 10.0        -- how far from the player an overlay can be placed
Config.RotateStep       = 5.0         -- degrees per scroll tick
Config.HeightStep       = 0.05        -- metres per shift+scroll tick

---------------------------------
-- rendering
---------------------------------
Config.RenderDistance     = 40.0      -- overlays further than this are not drawn
Config.VisibilityInterval = 300       -- ms between distance / line of sight checks
Config.OcclusionCheck     = true      -- hide overlays behind walls
Config.DoubleSided        = false     -- draw when viewed from behind
Config.AudioDistance      = 15.0      -- video sound fades to 0 at this distance
Config.MaxVolume          = 0.6       -- 0.0 - 1.0
