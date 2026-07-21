# Changelog

## 3.1.0

### Fixed

- Verify the exact URI sequence VLC installed, not only item counts and URI multiplicities.
- Roll back to the previous playlist if enqueueing or ordered read-back verification fails; failed attempts no longer increment the successful-shuffle counter.
- Count only active playback time so paused wall time cannot create false completions or skips.
- Recover a damaged primary history database from `.bak`, preserve the unreadable file for inspection, and leave both primary and backup copies valid.
- Do not consume a cooldown-tail slot when the current URI is absent from the eligible source.
- Disable VLC loop mode as well as random and repeat-one while the extension owns playback.
- Detect `skins2`, other non-Qt interfaces, and Qt minimal view in the Windows installer—the principal cause of a missing extension View menu despite a correct install.
- Remove a sandbox-incompatible `rawget` call that caused VLC's real extension scanner to hide an otherwise valid script.
- Provide VLC 3's implicit `meta_changed()` input-listener callback so active playback does not flood the debug log with missing-function warnings.
- Prefix the actual VLC View-menu label with `History Shuffle` (VLC displays `shortdesc`, not the descriptor title, in that menu).

### Added

- Continuous decks: completing the last item automatically builds a new complete history-aware deck instead of replaying VLC's old order.
- A panel/menu toggle for continuous decks, enabled by default.
- Transactional shuffle receipts with attempt count, exact verification state, and the last failure reason.
- Installer interface diagnostics, conflicting-copy detection, automatic Qt configuration, and a recoverable `vlcrc` backup.
- Tests for exact order, rollback, backup recovery, pause-aware timing, and cooldown edge cases.

## 3.0.0

### Fixed

- Replaced the VLC 3-incompatible `vlc.json` dependency with VLC's bundled `dkjson`, while retaining a VLC 4 JSON fallback.
- Stopped clearing the current playlist just to import the media library.
- Replaced repeated weighted selection with a complete no-repeat deck and a recent-item cooldown tail.
- Added a read-back verification step so the UI reports whether VLC received the generated deck.
- Replaced the unreachable negative-score blacklist with explicit blacklist state.
- Corrected playback tracking so the previous session is finalized when the input URI changes.
- Added Windows-safe `.tmp`/`.bak` persistence and migration from `better_playlist_data.json`.
- Removed duplicate blacklist/view function definitions.

### Added

- Always-visible ACTIVE control panel, activation/deactivation OSD messages, and an auditable last-shuffle receipt.
- Current-playlist and explicit media-library shuffle actions.
- Per-user Windows installer with SHA-256 installation verification and a read-only `-Check` mode.
- Backed-up `-RepairDiscovery` rebuild for Windows VLC installations with a stale plugin cache.
- Lua unit and mocked VLC activation tests.
- Project banner and rewritten installation, usage, troubleshooting, privacy, and development documentation.
