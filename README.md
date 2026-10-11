# rsg-overlay

[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-support-FFDD00?style=for-the-badge&logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/rexshack)

Player-placed **images, GIFs and videos in the world** for RedM servers running the **RSG Framework**.

Players paste a media link, aim at a wall or the ground, fine-tune the placement with live feedback, and the overlay appears in true 3D perspective for everyone nearby. Overlays are saved to the database and survive restarts.

---

## Features

- **Images, GIFs, videos and YouTube.** Supports png / jpg / gif / webp, direct mp4 / webm links and YouTube videos (including shorts and youtu.be links). The media type is detected automatically or can be chosen manually.
- **True perspective rendering.** Overlays are drawn as flat planes in the world and projected onto the screen every frame, so they look correct from any angle.
- **Two-stage placement with live feedback**
  - **Aim:** the overlay follows your camera and snaps flat to walls or stands upright on the ground. A controls bar shows key hints and a live range meter (green / amber / red).
  - **Adjust:** a panel with a cursor where you can nudge position (left/right, up/down, push in/pull out), rotate, resize (with aspect-ratio lock) and change opacity and volume. Every change is shown on the overlay instantly.
- **Spatial audio for videos.** Volume fades with distance and stops completely out of range.
- **Performance friendly.** Only overlays within the render distance are created. Media is unloaded when you walk away, overlays behind walls are hidden (line-of-sight check), and the view is hidden in the pause menu.
- **Persistent.** Overlays are stored in MySQL with optional auto-expiry.
- **Ownership and moderation.** Players can remove their own overlays and admins can remove any. Placements and removals are logged through `rsg-log`.
- **Server-side validation.** Links must be https and from approved hosts. Size, opacity, volume, placement distance, per-player limits and cooldown are all enforced by the server.
- **Optional economy hooks.** You can require an item and/or charge cash per placement.
- **RDR2-style UI.** A dark leather-and-silver NUI matching the other RSG scripts.

---

## Requirements

| Resource | Notes |
|---|---|
| [rsg-core](https://github.com/Rexshack-RedM/rsg-core) | Framework |
| [ox_lib](https://github.com/overextended/ox_lib) | Callbacks, notifications, locales |
| [oxmysql](https://github.com/overextended/oxmysql) | Database |
| rsg-inventory | Only if `Config.RequiredItem` is used |

---

## Installation

1. Drop the `rsg-overlay` folder into your resources (for example `resources/[rsg]/rsg-overlay`).
2. **Database:** the table is created automatically on first start. If you prefer to create it manually, run `install.sql`.
3. Add to your `server.cfg` **after** the dependencies:
   ```cfg
   ensure ox_lib
   ensure oxmysql
   ensure rsg-core
   ensure rsg-overlay
   ```
4. *(Optional)* If you use `Config.RequiredItem`, add the item to `rsg-core/shared/items.lua`, for example:
   ```lua
   poster = { name = 'poster', label = 'Blank Poster', weight = 50, type = 'item', image = 'poster.png', unique = false, useable = false, shouldClose = true, description = 'Used to put up a poster' },
   ```
5. *(Optional)* Add a `overlay` channel to your `rsg-log` webhooks to receive placement and removal logs.
6. Restart the server.

---

## Usage

### Opening the manager
Type **`/overlay`** (configurable) to open the manager.

1. Paste a media link into **Media link**. The *Detected* box shows what type it will be, or *invalid link*.
2. Pick a size, opacity and (for videos) volume. **Fit to media** sets the height from the image or video's real shape.
3. Click **Place in world**.

The bottom half of the manager lists overlays near you and every overlay you own, with distance and owner. Use **Remove** to delete your own (admins can remove any).

### Stage 1: Aim

| Key | Action |
|---|---|
| **Left mouse / Enter** | Lock position and open the adjust panel |
| **Scroll** | Rotate |
| **Shift + Scroll** | Raise / lower |
| **Right mouse / Backspace** | Cancel |

Aim at a wall to stick the overlay flat to it, or at the ground to stand it upright facing you. The range meter turns red when it's too far from you.

### Stage 2: Adjust

| Control | Action |
|---|---|
| Arrow pad / **W A S D** / arrow keys | Move up, left, down, right (relative to the overlay's facing) |
| **Push in / Pull out** / **F / R** | Move towards / away from the wall |
| Step buttons (1cm, 5cm, 25cm, 1m) | Nudge step size. Hold a button to repeat |
| **Shift** + key | Fine movement (step ÷ 5) and 1° rotation |
| Rotation slider / **Q / E** | Rotate |
| Width / Height sliders | Resize. **Lock ratio** keeps the aspect ratio |
| Opacity / Volume sliders | Appearance and sound |
| **Hold right mouse** | Free look: move the camera, release to get the cursor back |
| **Reset** | Return to the position you locked |
| **↺** | Go back to aiming (keeps size and appearance) |
| **Place overlay** / **Enter** | Confirm (disabled while out of range) |
| **✕** / **Esc** | Cancel |

---

## Configuration

All settings live in `shared/config.lua`.

### Access

| Option | Default | Description |
|---|---|---|
| `Config.Command` | `'overlay'` | Command that opens the manager |
| `Config.CommandPerm` | `'user'` | RSG permission needed to use the command (`'user'` = everyone) |
| `Config.AdminPerm` | `'admin'` | Permission that can remove any overlay and ignores the limit |
| `Config.AllowedJobs` | `{}` | Restrict placing to jobs, e.g. `{ 'newspaper', 'saloon' }`. Empty = everyone |
| `Config.MaxPerPlayer` | `5` | Max overlays a character can own |
| `Config.RequiredItem` | `nil` | Item consumed per placement, e.g. `'poster'` |
| `Config.PlaceCost` | `0` | Cash charged per placement |
| `Config.ExpireHours` | `72` | Auto-remove after X hours (`0` = never) |
| `Config.Cooldown` | `10` | Seconds between placements per player |

### Media

| Option | Default | Description |
|---|---|---|
| `Config.AllowedDomains` | imgur, discord, ibb, gyazo, catbox, youtube, giphy, tenor | Hosts accepted (subdomains included). Empty table = any https host |
| `Config.AllowVideo` | `true` | Allow mp4 / webm links |
| `Config.AllowYoutube` | `true` | Allow YouTube links |
| `Config.MaxUrlLength` | `500` | Maximum link length |

### Size and placement (metres)

| Option | Default | Description |
|---|---|---|
| `Config.MinSize` / `Config.MaxSize` | `0.25` / `8.0` | Width and height limits |
| `Config.DefaultWidth` / `Config.DefaultHeight` | `1.5` / `1.0` | Defaults in the manager |
| `Config.MaxPlaceDistance` | `10.0` | How far from the player an overlay may be placed |
| `Config.RotateStep` | `5.0` | Degrees per scroll tick while aiming |
| `Config.HeightStep` | `0.05` | Metres per Shift+scroll tick while aiming |

### Rendering

| Option | Default | Description |
|---|---|---|
| `Config.RenderDistance` | `40.0` | Overlays further away are not drawn |
| `Config.VisibilityInterval` | `300` | ms between distance and line-of-sight checks |
| `Config.OcclusionCheck` | `true` | Hide overlays behind walls |
| `Config.DoubleSided` | `false` | Draw overlays when viewed from behind |
| `Config.AudioDistance` | `15.0` | Distance at which video sound reaches 0 |
| `Config.MaxVolume` | `0.6` | Master volume cap (0.0 – 1.0) |

### Locales
Text is in `locales/en.json` (ox_lib locale format). Copy it to e.g. `locales/fr.json` and set `setr ox:locale fr` in your `server.cfg`.

---

## Exports (server)

```lua
-- all loaded overlays, keyed by id
local overlays = exports['rsg-overlay']:GetOverlays()

-- remove an overlay by id (deletes from DB and all clients)
exports['rsg-overlay']:RemoveOverlay(id)
```

---

## Database

Table `rsg_overlays`:

| Column | Description |
|---|---|
| `id` | Overlay id |
| `citizenid`, `owner_name` | Owner |
| `url`, `media_type` | Link and `image` / `video` / `youtube` |
| `x`, `y`, `z`, `heading` | World position (centre) and facing |
| `width`, `height` | Size in metres |
| `opacity`, `volume` | Appearance |
| `created_at` | Used for expiry |

---

## Notes and limitations

- Overlays are drawn by the NUI layer, so **players, horses and props walking in front of them do not cover them**. Walls and terrain do hide them, via the line-of-sight check.
- **YouTube** can refuse to play inside the game's built-in browser for some videos. Direct **mp4 / webm** links are the most reliable choice for video.
- Overlays are vertical planes (rotation around the vertical axis only). Flat-on-the-floor or ceiling posters are not supported.
- Keep `Config.AllowedDomains` restricted on public servers to stop players from loading unwanted content.

---

## Support

If you enjoy this script and want to support development, you can buy me a coffee:

☕ **[buymeacoffee.com/rexshack](https://buymeacoffee.com/rexshack)**

---

## Credits

Built for the RSG Framework.
