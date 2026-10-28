# reaper-web-faders

A touch-friendly mixer for REAPER's built-in web remote. It runs in any browser on your network (phone, tablet, laptop).

- **Transport:** record start/stop (plus play/pause and stop), with a large clock showing the current position, the transport state and bars/beats.
- **Channel strips:** fader with a dBFS meter (scale lines and numbers, peak hold), pan, mute, solo, record arm and input monitoring. Faders line up across all strips.
- **Graphical EQ (ReaEQ):** a mini curve sits on each strip. Tap it to open a popup with draggable band points, band type and on/off, and knobs for frequency, gain, bandwidth, output gain and wet. The curve is computed at the project's actual sample rate.
- **Graphical compressor (ReaComp):** a mini transfer curve with a threshold knob sits on each strip. The popup has a square transfer graph with draggable threshold and ratio handles, a live gain-reduction meter, and a scrolling gain-reduction history behind the curve. Knobs cover threshold, ratio, knee, attack, release, pre-comp, wet, dry and RMS size, with auto make-up and auto release buttons.
- **Other plug-ins:** listed by name with an on/off toggle. Tapping one opens a slider list of its parameters.
- **Sends and receives:** collapsible sections, two rows per item, showing the destination or source and the channel routing (e.g. `ch 1-2 → 3-4`), with level and mute controls.
- **Hide/unhide tracks** in REAPER's track view and mixer.
- **View banks 1/2/3:** each bank stores which items every strip shows (EQ, compressor, EQ on its own row, other FX, pan, arm, monitoring, sends, receives, meter scale, the strip itself) and the strip width. Banks are saved inside REAPER, so they survive page reloads and REAPER restarts and are shared by all devices. Each device remembers which bank it last used.

## Install

Download the zip for your system from the [latest release](https://github.com/Pekyyyyy/reaper-web-faders/releases/latest) and unzip it.

- **macOS:** right-click `install.command` → **Open** (the first time, macOS asks you to confirm because the file was downloaded).
- **Windows:** double-click `install.bat`.

The installer puts everything into your REAPER resource folder. That needs no admin rights, and REAPER updates don't overwrite it. It also adds the FX bridge to `Scripts/__startup.lua` and starts the bridge right away if REAPER is running. Running it again updates an existing install. For a portable REAPER, pass its folder: `./install.command /path/to/REAPER` or `install.bat -ResourcePath D:\REAPER`.

Then, if you haven't already, set up the web interface in REAPER: **Preferences → Control/OSC/Web → Add → Web browser interface**. Pick a port (e.g. 8889) and choose `faders.html` as the default interface. Open `http://<your-computer-ip>:<port>/` on your phone or tablet.

## Manual install

### Files

| File | Goes to |
| --- | --- |
| `faders.html` | `<REAPER resource path>/reaper_www_root/faders.html`. REAPER serves pages from here first and falls back to its built-in web root for `main.js`. |
| `reaper-scripts/web_fx_bridge.lua` | `<REAPER resource path>/Scripts/WebRemote/web_fx_bridge.lua` |

The resource path is shown in REAPER under **Options → Show REAPER resource path**. Usually it's `~/Library/Application Support/REAPER` on macOS and `%APPDATA%\REAPER` on Windows.

### Setup

1. Copy the files as shown above.
2. In REAPER, open **Preferences → Control/OSC/Web**, then **Add → Web browser interface**. Pick a port (e.g. 8889) and set the default interface to `faders.html`.
3. Start the FX bridge. REAPER's web API can't read or change plug-in settings, so this small ReaScript publishes FX state, ReaEQ band types, compressor gain reduction, send channel routing and the sample rate through ExtState, and applies changes coming from the page. Run it from **Actions → Load ReaScript**. To start it automatically, add this line to `<REAPER resource path>/Scripts/__startup.lua`:

   ```lua
   dofile(reaper.GetResourcePath() .. "/Scripts/WebRemote/web_fx_bridge.lua")
   ```

4. Open `http://<your-computer-ip>:<port>/` in a browser. A green **FX bridge** dot means the script is running.

Without the bridge, faders, pan, buttons, sends/receives, transport and track hiding still work. EQ/compressor graphics and plug-in controls need it.

## Notes

- If a newer copy of the bridge is started, any older copy still running stops by itself.
- The EQ curve is drawn with standard biquad formulas at the project's sample rate. It closely matches ReaEQ, but shelf shapes may differ slightly.
- Strip settings are matched to tracks by name.
