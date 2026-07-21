<p align="center">
  <img src="assets/history-shuffle-banner.png" alt="History Shuffle banner" width="100%">
</p>

<h1 align="center">History Shuffle for VLC</h1>

<p align="center">
  A complete, history-aware shuffle deck for VLC — with visible status and exact queue-order verification.
</p>

<p align="center">
  <img alt="VLC 3.x" src="https://img.shields.io/badge/VLC-3.x-ff8800?logo=vlcmediaplayer&logoColor=white">
  <img alt="Lua 5.1" src="https://img.shields.io/badge/Lua-5.1-2c2d72?logo=lua&logoColor=white">
  <img alt="Windows 10 and 11 installer" src="https://img.shields.io/badge/Windows-10%20%7C%2011-0078d4?logo=windows&logoColor=white">
  <img alt="No-repeat deck" src="https://img.shields.io/badge/deck-no%20repeats-20a36a">
</p>

VLC's random mode can feel as if it keeps returning to the same small group of media. History Shuffle takes a different approach: it physically rebuilds the playlist as one complete deck, pushes recently started items toward the end, and verifies that VLC received the generated URI sequence in the exact same order.

## At a glance

| Question | Where to verify it |
| --- | --- |
| Is it installed? | Run `powershell -ExecutionPolicy Bypass -File .\install.ps1 -Check`. |
| Did VLC discover it? | `install.ps1 -Check` verifies that the desktop Qt interface can expose it; after a full VLC restart, `View > History Shuffle` exists. |
| Is it on? | The control panel title and first line say **ACTIVE**; activation also shows an on-screen message. |
| Did it actually shuffle? | The control panel records the time, item count, first item, and either **VERIFIED** or **NOT VERIFIED**. |
| Is history being saved? | The panel displays the exact JSON path; on Windows it is `%APPDATA%\vlc\history_shuffle_data.json`. |

## What makes this shuffle different

- **One complete deck:** every eligible playlist entry occurs exactly once per shuffle. Duplicates already present in the source playlist remain duplicates; the extension does not invent new ones.
- **Continuous fresh decks:** when the final item completes, the extension builds another complete deck instead of handing playback back to VLC's repeating random mode. This is on by default and can be toggled in the panel.
- **Recent-item cooldown:** roughly the most recent 25% of a playlist is moved to the deck's tail. Recent items remain playable, but they do not dominate the beginning of the next shuffle.
- **Ratings without a “favorite loop”:** a 0–10 rating applies only a small ordering bias. It cannot remove the rest of the playlist from the deck.
- **Real blacklist state:** blacklisting is an explicit boolean, not an unreachable negative-score threshold.
- **Transactional playlist verification:** after enqueueing, the extension reads VLC's playlist back and compares every URI in order. If anything differs, the failed attempt is not counted and the previous playlist is restored.
- **Competing modes disabled:** VLC's built-in random, repeat-one, and loop modes are turned off while History Shuffle owns the deck.
- **Pause-aware history:** only active playback time counts toward completion and skip decisions; leaving a video paused does not make it look watched.
- **Durable history:** VLC 3 uses its bundled `dkjson` module; writes rotate through `.tmp` and `.bak` files, and a readable backup is recovered automatically if the primary JSON is damaged.

## Install on Windows 10 or 11

Download or clone the repository, open PowerShell in its directory, and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

The installer:

1. creates `%APPDATA%\vlc\lua\extensions` if needed;
2. copies the plugin with its real `.lua` extension;
3. compares SHA-256 hashes of the source and installed copies;
4. detects interface settings that hide every Lua extension (`skins2`, another non-Qt interface, or Qt minimal view), backs up `vlcrc`, and selects the standard Qt interface;
5. reports the detected VLC path/version, interface compatibility, conflicting copies, cache timestamp, and whether VLC is still running.

The interface backup is `%APPDATA%\vlc\vlcrc.history-shuffle-interface-backup`. Advanced users who intentionally do not want Qt can pass `-KeepInterface`, but VLC will not provide the `View > History Shuffle` entry in that configuration.

Fully exit every VLC window, start VLC again, and choose:

```text
View > History Shuffle
```

### Manual installation

Copy [VLC - MediaPlayer History Shuffle.lua](VLC%20-%20MediaPlayer%20History%20Shuffle.lua) to:

```text
%APPDATA%\vlc\lua\extensions\VLC - MediaPlayer History Shuffle.lua
```

Create the folders if they do not exist. In File Explorer, enable **View > Show > File name extensions** and confirm the file does not end in `.lua.txt`.

Desktop Lua extensions are exposed by VLC's Qt interface. If VLC is configured to start with a custom `skins2` interface, switch back to Qt before looking for the View entry, or use the Windows installer to do this safely with a backup.

### Linux and macOS

Copy the Lua file into the desktop VLC extension directory, then fully restart VLC:

| Platform | Per-user extension directory |
| --- | --- |
| Linux | `~/.local/share/vlc/lua/extensions/` |
| Linux (Snap) | `~/snap/vlc/current/.local/share/vlc/lua/extensions/` |
| macOS | `~/Library/Application Support/org.videolan.vlc/lua/extensions/` |

The PowerShell installer is Windows-only. The Lua extension itself uses VLC/Lua path APIs and keeps VLC 3/4 playback access behind compatibility helpers.

## Use it

1. Add media to VLC's current playlist.
2. Open `View > History Shuffle`.
3. Keep the ACTIVE panel open or use **Hide panel (still ACTIVE)**; the extension stays active until you turn it off or close VLC. Closing the panel with its native **X** is treated as an explicit OFF action.
4. Read the shuffle receipt. A successful run looks like:

```text
ACTIVE - shuffle #4 built a 327-item deck (50 cooled, 3 blacklisted); verified in VLC.
```

The panel provides:

- **Shuffle current playlist** — rebuilds only the playlist already open in VLC.
- **Load media library + shuffle** — explicitly uses VLC's media-library list. It is never silently substituted for a non-empty current playlist.
- **Toggle continuous decks** — controls whether completing the final item automatically builds and starts a new full deck.
- **Rate current** — saves a weak 0–10 preference.
- **Toggle blacklist** — includes/excludes the current URI on the next shuffle.
- **Recent history** — shows the 25 most recently started items with start, completion, and skip counts.
- **Export / Import** — backs up or merges portable JSON history.
- **Turn History Shuffle OFF** — deactivates the extension and displays an OFF message.

VLC extensions do not auto-activate across application restarts, so `View > History Shuffle` must be chosen once in each VLC session.

## If it is missing from the View menu

Run the deterministic check first:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Check
```

The check deliberately fails if `vlcrc` selects `skins2`, another non-Qt interface, or Qt minimal view, because those modes do not expose the desktop extension list. Fully exit VLC and run the normal installer once to back up the configuration and select Qt.

If it says `installed correctly` but the menu entry is still absent:

1. Open Task Manager and make sure no `vlc.exe` process remains, then restart VLC.
2. Confirm the installed filename ends in `.lua`, not `.lua.txt`.
3. Confirm you are using desktop VLC. Mobile VLC builds do not load desktop Lua extensions.
4. In VLC, open `Tools > Messages`, set verbosity to `2 (debug)`, restart VLC, and search messages for `History Shuffle`, `lua/extensions`, or `stale plugins cache`.
5. If the log contains stale-plugin-cache errors, fully exit VLC and run the deterministic cache repair:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\install.ps1 -RepairDiscovery
   ```

   This runs VLC's own `vlc-cache-gen.exe` against its plugins directory after backing up `plugins.dat` to `%APPDATA%\vlc\plugins.dat.history-shuffle-backup`. If Windows denies the write, open PowerShell as Administrator and repeat only this repair command.
6. Re-run the installer. It writes to the current Windows user's roaming profile, which avoids admin-only `Program Files` installs.

The plugin descriptor intentionally uses the documented `menu`, `input-listener`, and `playing-listener` capabilities and contains no activation-time dependency on VLC 4-only `vlc.media.library()` or on the unavailable VLC 3 `vlc.json` API. See VideoLAN's [VLC Lua reference](https://github.com/videolan/vlc/blob/3.0.x/share/lua/README.txt).

## Data and privacy

All history stays local. No playlist URI, rating, or playback event is sent over the network.

```text
Windows: %APPDATA%\vlc\history_shuffle_data.json
Backup:  %APPDATA%\vlc\history_shuffle_data.json.bak
Legacy:  %APPDATA%\vlc\better_playlist_data.json  (read once and migrated when present)
```

The database records normalized counts, the recent URI ring, explicit blacklist state, ratings, and the last shuffle receipt. Exported JSON is user-selected and is not created automatically.

## Algorithm

```text
current playlist
      |
      +--> remove explicitly blacklisted entries
      |
      +--> split into fresh pool + recent cooldown pool
      |
      +--> lightly rating-biased shuffle inside each pool
      |
      +--> fresh pool followed by cooldown pool
      |
      +--> enqueue once, read VLC playlist back, verify the exact sequence
      |
      +--> on mismatch: restore the previous playlist and report failure
      |
      +--> at completed deck end: build the next fresh deck
```

This is deliberately a deck rather than repeated weighted sampling. The important invariant is simple: if 500 eligible entries go in, 500 entries come out before playback begins.

## Development and tests

The test suite runs the Lua source through a Lua VM and covers exact deck order, duplicate preservation, blacklist handling, cooldown behavior, pause-aware timing, backup recovery, legacy-data migration, mocked VLC 3 activation, mode disabling, failed-enqueue rollback, and playback start. `tests/vlc_native_check.lua` is a smoke-test interface used to compile the extension and resolve `dkjson` inside VLC's own Lua 5.1 engine.

```powershell
npm install
npm test
```

Expected result:

```text
History Shuffle tests passed
```

## Compatibility notes

- Primary target: desktop VLC 3.x on Windows 10/11.
- VLC's standard Qt interface is required for the View-menu entry; `skins2` and other interfaces do not host VLC's desktop Lua-extension menu.
- The playlist and player wrappers are prepared for VLC 4 APIs where VLC exposes compatible extension hooks.
- Rebuilding a deck stops the current input, replaces the queue, and starts the first item.
- Streams with transient/authenticated URLs may not survive any extension that reconstructs a playlist from their URIs.
- The optional Windows discovery repair regenerates VLC's global plugin index with VLC's own cache generator. The installer keeps the previous `plugins.dat` in the current user's VLC directory for recovery.

## Contributing

Bug reports are most useful when they include the VLC version, operating system, the `install.ps1 -Check` output on Windows, and the relevant lines from `Tools > Messages` at debug verbosity.

See [CHANGELOG.md](CHANGELOG.md) for the v3 rewrite and v3.1 reliability pass. This project is an independent VLC extension and is not affiliated with or endorsed by VideoLAN.
