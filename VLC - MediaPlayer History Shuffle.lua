-- History Shuffle for VLC
-- A history-aware, no-repeat shuffle deck for VLC 3.x and VLC 4.x.

local HistoryShuffle = {
    VERSION = "3.1.1",
    PREFIX = "[History Shuffle] ",
    SCHEMA_VERSION = 3,
    state = {
        schema_version = 3,
        tracks = {},
        recent = {},
        shuffle_count = 0
    },
    data_file = nil,
    legacy_data_file = nil,
    dialog = nil,
    status_label = nil,
    queue_label = nil,
    history_label = nil,
    data_label = nil,
    session = nil,
    active = false,
    is_shuffling = false,
    last_source = "playlist",
    last_status = "Starting...",
    json = nil,
    config = {
        recent_fraction = 0.25,
        recent_limit = 200,
        max_cooldown_items = 50,
        completed_threshold = 0.90,
        minimum_skip_seconds = 8,
        preference_bias = 0.08,
        continuous_default = true
    }
}

local util = {}

local function log_info(message)
    if vlc and vlc.msg then
        vlc.msg.info(HistoryShuffle.PREFIX .. tostring(message))
    end
end

local function log_warn(message)
    if vlc and vlc.msg then
        vlc.msg.warn(HistoryShuffle.PREFIX .. tostring(message))
    end
end

local function log_error(message)
    if vlc and vlc.msg then
        vlc.msg.err(HistoryShuffle.PREFIX .. tostring(message))
    end
end

local function safe_call(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, value = pcall(fn, ...)
    if ok then
        return value
    end
    return nil
end

function util.clamp(value, minimum, maximum)
    return math.max(minimum, math.min(value, maximum))
end

function util.copy_array(source)
    local result = {}
    for i, value in ipairs(source or {}) do
        result[i] = value
    end
    return result
end

function util.fisher_yates(items, random_unit)
    local shuffled = util.copy_array(items)
    for i = #shuffled, 2, -1 do
        local j = math.floor(random_unit() * i) + 1
        if j > i then
            j = i
        end
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end
    return shuffled
end

local function track_rating(track)
    if track and type(track.user_rating) == "number" then
        return util.clamp(track.user_rating, 0, 10)
    end
    return 5
end

function util.preference_shuffle(items, tracks, random_unit)
    local decorated = {}
    for index, item in ipairs(items) do
        local track = tracks[item.path] or {}
        local rating_offset = (track_rating(track) - 5) / 5
        decorated[index] = {
            item = item,
            key = random_unit() + rating_offset * HistoryShuffle.config.preference_bias
        }
    end
    table.sort(decorated, function(a, b)
        if a.key == b.key then
            return tostring(a.item.path) < tostring(b.item.path)
        end
        return a.key > b.key
    end)
    local result = {}
    for i, value in ipairs(decorated) do
        result[i] = value.item
    end
    return result
end

function util.same_entry_multiset(left, right)
    if #left ~= #right then
        return false
    end
    local counts = {}
    for _, entry in ipairs(left) do
        counts[entry.path] = (counts[entry.path] or 0) + 1
    end
    for _, entry in ipairs(right) do
        local count = counts[entry.path]
        if not count or count == 0 then
            return false
        end
        counts[entry.path] = count - 1
    end
    for _, count in pairs(counts) do
        if count ~= 0 then
            return false
        end
    end
    return true
end

function util.same_entry_sequence(left, right)
    if #left ~= #right then
        return false
    end
    for i = 1, #left do
        if left[i].path ~= right[i].path then
            return false
        end
    end
    return true
end

-- Build one complete deck. Every eligible playlist entry occurs exactly once.
-- Recently started items are moved into a cooldown tail, not removed forever.
function util.build_shuffle_deck(entries, tracks, recent, random_unit, current_uri)
    local eligible = {}
    local eligible_uri = {}
    local blacklisted = 0
    for _, entry in ipairs(entries or {}) do
        local track = tracks[entry.path]
        if track and track.blacklisted == true then
            blacklisted = blacklisted + 1
        else
            eligible[#eligible + 1] = entry
            eligible_uri[entry.path] = true
        end
    end

    if #eligible <= 1 then
        return eligible, {
            eligible = #eligible,
            blacklisted = blacklisted,
            cooled = 0
        }
    end

    local cooldown_target = math.floor(#eligible * HistoryShuffle.config.recent_fraction + 0.5)
    cooldown_target = math.max(1, math.min(cooldown_target, HistoryShuffle.config.max_cooldown_items, #eligible - 1))

    local cooldown_set = {}
    local cooled_unique = 0
    if current_uri and current_uri ~= "" and eligible_uri[current_uri] then
        cooldown_set[current_uri] = true
        cooled_unique = 1
    end
    for i = #(recent or {}), 1, -1 do
        if cooled_unique >= cooldown_target then
            break
        end
        local uri = recent[i]
        if uri and not cooldown_set[uri] then
            cooldown_set[uri] = true
            cooled_unique = cooled_unique + 1
        end
    end

    local fresh = {}
    local cooldown = {}
    for _, entry in ipairs(eligible) do
        if cooldown_set[entry.path] then
            cooldown[#cooldown + 1] = entry
        else
            fresh[#fresh + 1] = entry
        end
    end

    fresh = util.preference_shuffle(fresh, tracks, random_unit)
    cooldown = util.preference_shuffle(cooldown, tracks, random_unit)

    local deck = {}
    for _, entry in ipairs(fresh) do
        deck[#deck + 1] = entry
    end
    for _, entry in ipairs(cooldown) do
        deck[#deck + 1] = entry
    end

    return deck, {
        eligible = #eligible,
        blacklisted = blacklisted,
        cooled = #cooldown
    }
end

local function seed_random()
    local seed = os.time() + math.floor((os.clock() or 0) * 1000000)
    math.randomseed(seed)
    math.random()
    math.random()
    math.random()
end

local function random_unit()
    if vlc and vlc.rand and type(vlc.rand.number) == "function" then
        local number = safe_call(vlc.rand.number)
        if type(number) == "number" then
            return (number % 2147483648) / 2147483648
        end
    end
    return math.random()
end

local function dir_separator()
    if vlc and vlc.config and type(vlc.config.dir_separator) == "function" then
        return vlc.config.dir_separator()
    end
    return package.config:sub(1, 1)
end

local function file_exists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
        return true
    end
    return false
end

local function ensure_json()
    if HistoryShuffle.json then
        return HistoryShuffle.json
    end

    if vlc and vlc.json and type(vlc.json.encode) == "function" and type(vlc.json.decode) == "function" then
        HistoryShuffle.json = {
            encode = vlc.json.encode,
            decode = function(text)
                return vlc.json.decode(text)
            end
        }
        return HistoryShuffle.json
    end

    local ok, dkjson = pcall(require, "dkjson")
    if not ok or not dkjson then
        error("VLC's bundled dkjson module could not be loaded")
    end
    HistoryShuffle.json = {
        encode = function(value)
            return dkjson.encode(value, { indent = true })
        end,
        decode = function(text)
            local value, _, decode_error = dkjson.decode(text, 1, nil)
            if decode_error then
                error(decode_error)
            end
            return value
        end
    }
    return HistoryShuffle.json
end

local function blank_state()
    return {
        schema_version = HistoryShuffle.SCHEMA_VERSION,
        tracks = {},
        recent = {},
        shuffle_count = 0,
        shuffle_attempts = 0,
        continuous = HistoryShuffle.config.continuous_default
    }
end

local function normalize_track(track)
    track = type(track) == "table" and track or {}
    local rating = tonumber(track.user_rating)
    local blacklisted = track.blacklisted == true
    if rating and rating < 0 then
        blacklisted = true
        rating = nil
    end
    if rating then
        rating = util.clamp(rating, 0, 10)
    end
    return {
        starts = math.max(0, tonumber(track.starts or track.playcount) or 0),
        completed = math.max(0, tonumber(track.completed or track.playcount) or 0),
        skips = math.max(0, tonumber(track.skips or track.skipcount) or 0),
        user_rating = rating,
        blacklisted = blacklisted,
        last_started_at = tonumber(track.last_started_at or track.time) or 0,
        last_finished_at = tonumber(track.last_finished_at) or 0,
        last_percent = util.clamp(tonumber(track.last_percent) or 0, 0, 1)
    }
end

local function normalize_state(decoded)
    local state = blank_state()
    if type(decoded) ~= "table" then
        return state
    end

    local source_tracks = decoded.tracks
    if type(source_tracks) ~= "table" then
        source_tracks = decoded.data
    end
    if type(source_tracks) ~= "table" then
        source_tracks = decoded
    end

    for uri, track in pairs(source_tracks) do
        if type(uri) == "string" and type(track) == "table" then
            state.tracks[uri] = normalize_track(track)
        end
    end

    if type(decoded.recent) == "table" then
        for _, uri in ipairs(decoded.recent) do
            if type(uri) == "string" then
                state.recent[#state.recent + 1] = uri
            end
        end
    end
    while #state.recent > HistoryShuffle.config.recent_limit do
        table.remove(state.recent, 1)
    end

    state.shuffle_count = math.max(0, tonumber(decoded.shuffle_count) or 0)
    state.shuffle_attempts = math.max(state.shuffle_count, tonumber(decoded.shuffle_attempts) or 0)
    if type(decoded.continuous) == "boolean" then
        state.continuous = decoded.continuous
    end
    state.last_shuffle_at = tonumber(decoded.last_shuffle_at)
    state.last_shuffle_size = tonumber(decoded.last_shuffle_size)
    state.last_shuffle_source = decoded.last_shuffle_source
    state.last_shuffle_first = decoded.last_shuffle_first
    state.last_shuffle_verified = decoded.last_shuffle_verified == true
    state.last_shuffle_error = decoded.last_shuffle_error
    return state
end

local function read_json_file(path)
    local file, open_error = io.open(path, "r")
    if not file then
        return nil, open_error
    end
    local content = file:read("*all")
    file:close()
    if not content or content == "" then
        return nil, "file is empty"
    end
    local ok, decoded = pcall(ensure_json().decode, content)
    if not ok then
        return nil, decoded
    end
    return decoded, nil
end

function HistoryShuffle.save_state()
    local ok, save_error = pcall(function()
        local json = ensure_json()
        HistoryShuffle.state.schema_version = HistoryShuffle.SCHEMA_VERSION
        local content = json.encode(HistoryShuffle.state)
        local temp_file = HistoryShuffle.data_file .. ".tmp"
        local backup_file = HistoryShuffle.data_file .. ".bak"

        local file = assert(io.open(temp_file, "w"), "unable to open temporary history file")
        file:write(content)
        file:flush()
        file:close()

        os.remove(backup_file)
        local had_original = file_exists(HistoryShuffle.data_file)
        if had_original then
            local backed_up = os.rename(HistoryShuffle.data_file, backup_file)
            if not backed_up then
                os.remove(temp_file)
                error("unable to rotate the previous history file")
            end
        end

        local installed = os.rename(temp_file, HistoryShuffle.data_file)
        if not installed then
            if had_original then
                os.rename(backup_file, HistoryShuffle.data_file)
            end
            os.remove(temp_file)
            error("unable to install the new history file")
        end
    end)

    if not ok then
        log_error("Could not save history: " .. tostring(save_error))
        HistoryShuffle.set_status("ACTIVE, but history save failed: " .. tostring(save_error))
        return false
    end
    return true
end

function HistoryShuffle.load_state()
    local decoded, load_error = read_json_file(HistoryShuffle.data_file)
    local recovered_backup = false
    local migrated_legacy = false
    local backup_file = HistoryShuffle.data_file .. ".bak"
    if not decoded and file_exists(backup_file) then
        local backup_error = nil
        decoded, backup_error = read_json_file(backup_file)
        if decoded then
            recovered_backup = true
            log_warn("Recovered history from the backup file after the primary file failed: " .. tostring(load_error))
        else
            load_error = tostring(load_error) .. "; backup also failed: " .. tostring(backup_error)
        end
    end
    if not decoded and file_exists(HistoryShuffle.legacy_data_file) then
        decoded, load_error = read_json_file(HistoryShuffle.legacy_data_file)
        migrated_legacy = decoded ~= nil
    end

    if decoded then
        HistoryShuffle.state = normalize_state(decoded)
        log_info("History loaded: " .. tostring(#HistoryShuffle.state.recent) .. " recent entries")
    else
        HistoryShuffle.state = blank_state()
        if load_error then
            log_warn("Starting with a new history database: " .. tostring(load_error))
        else
            log_info("Creating the first history database")
        end
    end

    if migrated_legacy then
        log_info("Migrated legacy better_playlist_data.json")
    end
    if recovered_backup and file_exists(HistoryShuffle.data_file) then
        local corrupt_file = HistoryShuffle.data_file .. ".corrupt-" .. tostring(os.time())
        os.rename(HistoryShuffle.data_file, corrupt_file)
        log_warn("Preserved the unreadable primary database as " .. corrupt_file)
    end
    HistoryShuffle.save_state()
    if recovered_backup then
        -- A second rotation leaves both the primary and .bak as valid JSON.
        HistoryShuffle.save_state()
    end
end

local function decoded_uri(uri)
    if vlc and vlc.strings and type(vlc.strings.decode_uri) == "function" then
        return safe_call(vlc.strings.decode_uri, uri) or uri
    end
    return uri
end

local function display_name(uri)
    local readable = decoded_uri(uri or "")
    if vlc and vlc.strings and type(vlc.strings.basename) == "function" then
        return safe_call(vlc.strings.basename, readable) or readable
    end
    return readable:match("([^/\\]+)$") or readable
end

function HistoryShuffle.ensure_track(uri)
    local track = HistoryShuffle.state.tracks[uri]
    if not track then
        local legacy_key = decoded_uri(uri)
        if legacy_key ~= uri and HistoryShuffle.state.tracks[legacy_key] then
            track = normalize_track(HistoryShuffle.state.tracks[legacy_key])
            HistoryShuffle.state.tracks[legacy_key] = nil
        else
            track = normalize_track({})
        end
        HistoryShuffle.state.tracks[uri] = track
    end
    return track
end

local function current_item()
    if vlc and vlc.player and type(vlc.player.item) == "function" then
        local item = safe_call(vlc.player.item)
        if item then
            return item
        end
    end
    if vlc and vlc.input and type(vlc.input.item) == "function" then
        return safe_call(vlc.input.item)
    end
    return nil
end

local function item_uri(item)
    if not item then
        return nil
    end
    return safe_call(function()
        return item:uri()
    end)
end

local function item_duration(item)
    if not item then
        return 0
    end
    return tonumber(safe_call(function()
        return item:duration()
    end)) or 0
end

local function current_position()
    if vlc and vlc.player and type(vlc.player.get_position) == "function" then
        local position = tonumber(safe_call(vlc.player.get_position))
        if position then
            return util.clamp(position, 0, 1)
        end
    end
    if vlc and vlc.object and type(vlc.object.input) == "function" and vlc.var then
        local input = safe_call(vlc.object.input)
        if input then
            local position = tonumber(safe_call(vlc.var.get, input, "position"))
            if position then
                return util.clamp(position, 0, 1)
            end
        end
    end
    return 0
end

local function playback_status()
    if vlc and vlc.playlist and type(vlc.playlist.status) == "function" then
        return safe_call(vlc.playlist.status) or "unknown"
    end
    if vlc and vlc.player and type(vlc.player.is_playing) == "function" then
        return safe_call(vlc.player.is_playing) and "playing" or "paused"
    end
    if vlc and vlc.input and type(vlc.input.is_playing) == "function" then
        return safe_call(vlc.input.is_playing) and "playing" or "paused"
    end
    return "unknown"
end

local function update_session_timing(session, status, now)
    if not session then
        return
    end
    now = now or os.time()
    local is_playing = status == "playing"
    if session.playing_since and not is_playing then
        session.listened_seconds = (session.listened_seconds or 0) + math.max(0, now - session.playing_since)
        session.playing_since = nil
    elseif not session.playing_since and is_playing then
        session.playing_since = now
    end
end

local function push_recent(uri)
    local recent = HistoryShuffle.state.recent
    for i = #recent, 1, -1 do
        if recent[i] == uri then
            table.remove(recent, i)
        end
    end
    recent[#recent + 1] = uri
    while #recent > HistoryShuffle.config.recent_limit do
        table.remove(recent, 1)
    end
end

function HistoryShuffle.begin_session(item)
    local uri = item_uri(item)
    if not uri or uri == "" then
        return
    end
    local track = HistoryShuffle.ensure_track(uri)
    track.starts = track.starts + 1
    track.last_started_at = os.time()
    push_recent(uri)
    HistoryShuffle.session = {
        uri = uri,
        started_at = os.time(),
        duration = item_duration(item),
        max_position = current_position(),
        listened_seconds = 0,
        playing_since = playback_status() == "playing" and os.time() or nil
    }
    log_info("Now tracking: " .. display_name(uri))
    HistoryShuffle.save_state()
    HistoryShuffle.refresh_dashboard()
end

function HistoryShuffle.finalize_session(reason)
    local session = HistoryShuffle.session
    if not session then
        return nil
    end
    reason = reason or "input-change"
    local now = os.time()
    update_session_timing(session, "stopped", now)
    local track = HistoryShuffle.ensure_track(session.uri)
    local listened = math.max(0, session.listened_seconds or 0)
    local inferred = 0
    if session.duration and session.duration > 0 then
        inferred = util.clamp(listened / session.duration, 0, 1)
    end
    local percent = math.max(session.max_position or 0, inferred)
    track.last_percent = percent
    track.last_finished_at = now
    local completed = percent >= HistoryShuffle.config.completed_threshold
    if completed then
        track.completed = track.completed + 1
    elseif reason == "input-change" and listened >= HistoryShuffle.config.minimum_skip_seconds then
        track.skips = track.skips + 1
    end
    HistoryShuffle.session = nil
    HistoryShuffle.save_state()
    return {
        completed = completed,
        percent = percent,
        listened_seconds = listened,
        reason = reason
    }
end

function HistoryShuffle.sync_input()
    local item = current_item()
    local uri = item_uri(item)
    if HistoryShuffle.session and HistoryShuffle.session.uri == uri then
        update_session_timing(HistoryShuffle.session, playback_status(), os.time())
        HistoryShuffle.session.max_position = math.max(
            HistoryShuffle.session.max_position or 0,
            current_position()
        )
        return
    end
    local finalized = nil
    if HistoryShuffle.session then
        finalized = HistoryShuffle.finalize_session("input-change")
    end
    if item and uri then
        HistoryShuffle.begin_session(item)
    elseif HistoryShuffle.active and HistoryShuffle.state.continuous and not HistoryShuffle.is_shuffling and finalized and finalized.completed then
        HistoryShuffle.shuffle(HistoryShuffle.last_source or "playlist", "automatic")
    end
end

local function normalize_playlist_entry(node)
    if not node then
        return nil
    end
    local item = node.item
    local uri = item_uri(item) or node.path
    if not uri or uri == "" or uri:lower():match("^vlc://nop/?$") then
        return nil
    end
    local name = node.name
    if (not name or name == "") and item then
        name = safe_call(function()
            return item:name()
        end)
    end
    local duration = tonumber(node.duration) or item_duration(item)
    return {
        path = uri,
        name = name,
        duration = duration
    }
end

local function collect_playlist_entries(nodes, result)
    for _, node in ipairs(nodes or {}) do
        -- VLC gives folder nodes an input item and a URI (often vlc://nop).
        -- Children identify a folder; visit them before considering its URI.
        if node and type(node.children) == "table" then
            collect_playlist_entries(node.children, result)
        else
            local entry = normalize_playlist_entry(node)
            if entry then
                result[#result + 1] = entry
            end
        end
    end
end

function HistoryShuffle.get_playlist_entries(source)
    local entries = {}
    local tree = nil
    if source == "library" then
        tree = safe_call(vlc.playlist.get, "ml", false)
        if not tree then
            tree = safe_call(vlc.playlist.get, "media library", false)
        end
    else
        tree = safe_call(vlc.playlist.get, "normal", false)
        if not tree then
            tree = safe_call(vlc.playlist.get, "playlist", false)
        end
    end
    if tree and tree.children then
        collect_playlist_entries(tree.children, entries)
    end
    return entries
end

local function disable_competing_modes()
    safe_call(vlc.playlist.random, "off")
    safe_call(vlc.playlist.repeat_, "off")
    safe_call(vlc.playlist.loop, "off")
end

local function show_osd(message)
    if vlc and vlc.osd and type(vlc.osd.message) == "function" then
        safe_call(vlc.osd.message, message, nil, "top-right", 4000000)
    end
end

local function required_call(name, fn, ...)
    if type(fn) ~= "function" then
        return false, name .. " is unavailable in this VLC build"
    end
    local ok, result = pcall(fn, ...)
    if not ok then
        return false, name .. " failed: " .. tostring(result)
    end
    return true, result
end

function HistoryShuffle.replace_playlist(entries)
    local ok, call_error = required_call("playlist.stop", vlc.playlist.stop)
    if not ok then
        return false, {}, call_error
    end
    ok, call_error = required_call("playlist.clear", vlc.playlist.clear)
    if not ok then
        return false, {}, call_error
    end
    disable_competing_modes()
    ok, call_error = required_call("playlist.enqueue", vlc.playlist.enqueue, entries)
    if not ok then
        return false, HistoryShuffle.get_playlist_entries("playlist"), call_error
    end
    local installed = HistoryShuffle.get_playlist_entries("playlist")
    if not util.same_entry_sequence(entries, installed) then
        return false, installed, "VLC read-back order differs from the generated deck"
    end
    return true, installed, nil
end

function HistoryShuffle.shuffle(source, reason)
    source = source or "playlist"
    reason = reason or "manual"
    if HistoryShuffle.is_shuffling then
        log_warn("Ignored a nested shuffle request")
        return false
    end
    local entries = HistoryShuffle.get_playlist_entries(source)
    if #entries == 0 then
        local label = source == "library" and "VLC media library" or "current playlist"
        HistoryShuffle.set_status("ACTIVE - no items found in the " .. label .. ".")
        show_osd("History Shuffle: no items found")
        return false
    end

    for _, entry in ipairs(entries) do
        HistoryShuffle.ensure_track(entry.path)
    end

    local item = current_item()
    local current_uri = item_uri(item)
    local deck, stats = util.build_shuffle_deck(
        entries,
        HistoryShuffle.state.tracks,
        HistoryShuffle.state.recent,
        random_unit,
        current_uri
    )

    if #deck == 0 then
        HistoryShuffle.set_status("ACTIVE - every item in this source is blacklisted.")
        show_osd("History Shuffle: all items are blacklisted")
        return false
    end

    local previous_playlist = HistoryShuffle.get_playlist_entries("playlist")
    HistoryShuffle.is_shuffling = true
    HistoryShuffle.finalize_session("reshuffle")
    HistoryShuffle.state.shuffle_attempts = (HistoryShuffle.state.shuffle_attempts or 0) + 1
    local verified, installed_deck, replace_error = HistoryShuffle.replace_playlist(deck)

    HistoryShuffle.state.last_shuffle_at = os.time()
    HistoryShuffle.state.last_shuffle_size = #deck
    HistoryShuffle.state.last_shuffle_source = source
    HistoryShuffle.state.last_shuffle_first = deck[1] and deck[1].path or nil
    HistoryShuffle.state.last_shuffle_verified = verified
    HistoryShuffle.state.last_shuffle_error = replace_error

    if not verified then
        local restored, restored_deck, restore_error = HistoryShuffle.replace_playlist(previous_playlist)
        HistoryShuffle.is_shuffling = false
        HistoryShuffle.save_state()
        local recovery = restored and "the previous playlist was restored" or ("rollback also failed: " .. tostring(restore_error))
        local message = string.format(
            "ACTIVE - shuffle attempt FAILED (%s); VLC reported %d of %d ordered items; %s.",
            tostring(replace_error),
            #installed_deck,
            #deck,
            recovery
        )
        HistoryShuffle.set_status(message)
        log_error(message)
        show_osd("History Shuffle FAILED - previous playlist " .. (restored and "restored" or "needs attention"))
        if restored and #restored_deck > 0 then
            safe_call(vlc.playlist.play)
        end
        return false
    end

    HistoryShuffle.state.shuffle_count = HistoryShuffle.state.shuffle_count + 1
    HistoryShuffle.last_source = source
    HistoryShuffle.is_shuffling = false
    HistoryShuffle.save_state()

    local verification_text = "exact order verified in VLC"
    local message = string.format(
        "ACTIVE - shuffle #%d built a %d-item deck (%d cooled, %d blacklisted); %s%s.",
        HistoryShuffle.state.shuffle_count,
        #deck,
        stats.cooled,
        stats.blacklisted,
        verification_text,
        reason == "automatic" and "; next continuous deck" or ""
    )
    HistoryShuffle.set_status(message)
    log_info(message)
    show_osd("History Shuffle ON - " .. tostring(#deck) .. " items, no repeats in this deck")
    safe_call(vlc.playlist.play)
    return true
end

function HistoryShuffle.set_status(message)
    HistoryShuffle.last_status = tostring(message)
    if HistoryShuffle.status_label then
        safe_call(function()
            HistoryShuffle.status_label:set_text(HistoryShuffle.last_status)
        end)
    end
    HistoryShuffle.refresh_dashboard()
end

local function count_tracks()
    local count = 0
    local blacklisted = 0
    for _, track in pairs(HistoryShuffle.state.tracks) do
        count = count + 1
        if track.blacklisted then
            blacklisted = blacklisted + 1
        end
    end
    return count, blacklisted
end

function HistoryShuffle.refresh_dashboard()
    local track_count, blacklisted = count_tracks()
    if HistoryShuffle.queue_label then
        safe_call(function()
            local receipt = "No successful shuffle recorded yet."
            if HistoryShuffle.state.last_shuffle_at then
                receipt = string.format(
                    "Last shuffle: %s | %d items | %s | source: %s | first: %s",
                    os.date("%Y-%m-%d %H:%M:%S", HistoryShuffle.state.last_shuffle_at),
                    HistoryShuffle.state.last_shuffle_size or 0,
                    HistoryShuffle.state.last_shuffle_verified and "VERIFIED" or "NOT VERIFIED",
                    HistoryShuffle.state.last_shuffle_source or "unknown",
                    display_name(HistoryShuffle.state.last_shuffle_first or "")
                )
            end
            HistoryShuffle.queue_label:set_text(receipt)
        end)
    end
    if HistoryShuffle.history_label then
        safe_call(function()
            HistoryShuffle.history_label:set_text(string.format(
                "History: %d tracked | %d recent | %d blacklisted | continuous decks: %s",
                track_count,
                #HistoryShuffle.state.recent,
                blacklisted,
                HistoryShuffle.state.continuous and "ON" or "OFF"
            ))
        end)
    end
    if HistoryShuffle.data_label then
        safe_call(function()
            HistoryShuffle.data_label:set_text("Data: " .. tostring(HistoryShuffle.data_file))
        end)
    end
end

function HistoryShuffle.show_control_panel()
    if HistoryShuffle.dialog then
        safe_call(function()
            HistoryShuffle.dialog:show()
        end)
        HistoryShuffle.refresh_dashboard()
        return
    end

    local dialog = vlc.dialog("History Shuffle - ACTIVE - v" .. HistoryShuffle.VERSION)
    HistoryShuffle.dialog = dialog
    dialog:add_html("<h2>History Shuffle is ACTIVE</h2><p>One complete deck, recent-item cooldown, and persistent history.</p>", 1, 1, 4, 1)
    HistoryShuffle.status_label = dialog:add_label(HistoryShuffle.last_status, 1, 2, 4, 1)
    HistoryShuffle.queue_label = dialog:add_label("No successful shuffle recorded yet.", 1, 3, 4, 1)
    HistoryShuffle.history_label = dialog:add_label("History: loading...", 1, 4, 4, 1)
    HistoryShuffle.data_label = dialog:add_label("Data: " .. tostring(HistoryShuffle.data_file), 1, 5, 4, 1)

    dialog:add_button("Shuffle current playlist", function()
        HistoryShuffle.shuffle("playlist")
    end, 1, 6, 2, 1)
    dialog:add_button("Load media library + shuffle", function()
        HistoryShuffle.shuffle("library")
    end, 3, 6, 2, 1)
    dialog:add_button("Rate current", HistoryShuffle.rate_current, 1, 7, 1, 1)
    dialog:add_button("Toggle blacklist", HistoryShuffle.toggle_blacklist_current, 2, 7, 1, 1)
    dialog:add_button("Recent history", HistoryShuffle.show_recent, 3, 7, 1, 1)
    dialog:add_button("Export / Import", HistoryShuffle.show_transfer, 4, 7, 1, 1)
    dialog:add_button("Toggle continuous decks", HistoryShuffle.toggle_continuous, 1, 8, 4, 1)
    dialog:add_button("Hide panel (still ACTIVE)", function()
        dialog:hide()
    end, 1, 9, 2, 1)
    dialog:add_button("Turn History Shuffle OFF", function()
        vlc.deactivate()
    end, 3, 9, 2, 1)
    dialog:show()
    HistoryShuffle.refresh_dashboard()
end

function HistoryShuffle.toggle_continuous()
    HistoryShuffle.state.continuous = not HistoryShuffle.state.continuous
    HistoryShuffle.save_state()
    local mode = HistoryShuffle.state.continuous and "ON" or "OFF"
    HistoryShuffle.set_status("ACTIVE - continuous decks are " .. mode .. ".")
    show_osd("History Shuffle: continuous decks " .. mode)
end

function HistoryShuffle.rate_current()
    local item = current_item()
    local uri = item_uri(item)
    if not uri then
        HistoryShuffle.set_status("ACTIVE - play an item before rating it.")
        return
    end
    local track = HistoryShuffle.ensure_track(uri)
    local dialog = vlc.dialog("Rate current item")
    dialog:add_label("Rating 0-10 for: " .. display_name(uri), 1, 1, 2, 1)
    local input = dialog:add_text_input(track.user_rating and tostring(track.user_rating) or "5", 1, 2, 2, 1)
    dialog:add_button("Save rating", function()
        local rating = tonumber(input:get_text())
        if not rating or rating < 0 or rating > 10 then
            dialog:add_label("Enter a number from 0 through 10.", 1, 4, 2, 1)
            return
        end
        track.user_rating = rating
        HistoryShuffle.save_state()
        HistoryShuffle.set_status("ACTIVE - saved rating " .. tostring(rating) .. " for " .. display_name(uri) .. ".")
        dialog:delete()
    end, 1, 3, 1, 1)
    dialog:add_button("Clear rating", function()
        track.user_rating = nil
        HistoryShuffle.save_state()
        HistoryShuffle.set_status("ACTIVE - cleared rating for " .. display_name(uri) .. ".")
        dialog:delete()
    end, 2, 3, 1, 1)
    dialog:show()
end

function HistoryShuffle.toggle_blacklist_current()
    local item = current_item()
    local uri = item_uri(item)
    if not uri then
        HistoryShuffle.set_status("ACTIVE - play an item before changing its blacklist state.")
        return
    end
    local track = HistoryShuffle.ensure_track(uri)
    track.blacklisted = not track.blacklisted
    HistoryShuffle.save_state()
    local action = track.blacklisted and "blacklisted" or "removed from the blacklist"
    HistoryShuffle.set_status("ACTIVE - " .. display_name(uri) .. " was " .. action .. ".")
    show_osd("History Shuffle: " .. action)
end

function HistoryShuffle.show_recent()
    local dialog = vlc.dialog("History Shuffle - recent items")
    local first = math.max(1, #HistoryShuffle.state.recent - 24)
    local row = 1
    if #HistoryShuffle.state.recent == 0 then
        dialog:add_label("No playback has been recorded yet.", 1, row)
    else
        for i = #HistoryShuffle.state.recent, first, -1 do
            local uri = HistoryShuffle.state.recent[i]
            local track = HistoryShuffle.state.tracks[uri] or {}
            dialog:add_label(string.format(
                "%d. %s | starts %d | complete %d | skips %d",
                row,
                display_name(uri),
                track.starts or 0,
                track.completed or 0,
                track.skips or 0
            ), 1, row)
            row = row + 1
        end
    end
    dialog:show()
end

local function default_export_path()
    local base = vlc.config.homedir()
    return base .. dir_separator() .. "history_shuffle_export.json"
end

local function merge_track(existing, imported)
    local incoming = normalize_track(imported)
    existing.starts = math.max(existing.starts or 0, incoming.starts)
    existing.completed = math.max(existing.completed or 0, incoming.completed)
    existing.skips = math.max(existing.skips or 0, incoming.skips)
    existing.last_started_at = math.max(existing.last_started_at or 0, incoming.last_started_at)
    existing.last_finished_at = math.max(existing.last_finished_at or 0, incoming.last_finished_at)
    existing.last_percent = math.max(existing.last_percent or 0, incoming.last_percent)
    if incoming.user_rating ~= nil then
        existing.user_rating = incoming.user_rating
    end
    if incoming.blacklisted then
        existing.blacklisted = true
    end
end

function HistoryShuffle.export_to(path)
    local ok, export_error = pcall(function()
        local file = assert(io.open(path, "w"), "unable to open export path")
        file:write(ensure_json().encode({
            exported_by = "History Shuffle " .. HistoryShuffle.VERSION,
            exported_at = os.time(),
            schema_version = HistoryShuffle.SCHEMA_VERSION,
            tracks = HistoryShuffle.state.tracks,
            recent = HistoryShuffle.state.recent
        }))
        file:close()
    end)
    if not ok then
        return false, export_error
    end
    return true, nil
end

function HistoryShuffle.import_from(path)
    local decoded, import_error = read_json_file(path)
    if not decoded then
        return false, import_error
    end
    local imported = normalize_state(decoded)
    for uri, track in pairs(imported.tracks) do
        merge_track(HistoryShuffle.ensure_track(uri), track)
    end
    for _, uri in ipairs(imported.recent) do
        push_recent(uri)
    end
    HistoryShuffle.save_state()
    return true, nil
end

function HistoryShuffle.show_transfer()
    local dialog = vlc.dialog("History Shuffle - export / import")
    dialog:add_label("JSON file path:", 1, 1, 2, 1)
    local input = dialog:add_text_input(default_export_path(), 1, 2, 2, 1)
    dialog:add_button("Export", function()
        local ok, transfer_error = HistoryShuffle.export_to(input:get_text())
        if ok then
            HistoryShuffle.set_status("ACTIVE - history exported to " .. input:get_text())
            dialog:delete()
        else
            dialog:add_label("Export failed: " .. tostring(transfer_error), 1, 4, 2, 1)
        end
    end, 1, 3, 1, 1)
    dialog:add_button("Import + merge", function()
        local ok, transfer_error = HistoryShuffle.import_from(input:get_text())
        if ok then
            HistoryShuffle.set_status("ACTIVE - history imported and merged.")
            dialog:delete()
        else
            dialog:add_label("Import failed: " .. tostring(transfer_error), 1, 4, 2, 1)
        end
    end, 2, 3, 1, 1)
    dialog:show()
end

function descriptor()
    return {
        title = "History Shuffle",
        version = HistoryShuffle.VERSION,
        author = "R. Crandon and contributors",
        url = "https://github.com/rcrandon/VLC-MediaPlayer-History-Shuffle",
        shortdesc = "History Shuffle - no-repeat, history-aware decks",
        description = "Builds a complete no-repeat deck, cools down recently played media, and records a verifiable shuffle receipt.",
        capabilities = { "menu", "input-listener", "playing-listener" }
    }
end

function activate()
    seed_random()
    local data_dir = vlc.config.userdatadir()
    HistoryShuffle.data_file = data_dir .. dir_separator() .. "history_shuffle_data.json"
    HistoryShuffle.legacy_data_file = data_dir .. dir_separator() .. "better_playlist_data.json"
    log_info("Activating v" .. HistoryShuffle.VERSION)
    log_info("Data file: " .. HistoryShuffle.data_file)
    HistoryShuffle.load_state()
    HistoryShuffle.active = true
    HistoryShuffle.last_source = HistoryShuffle.state.last_shuffle_source or "playlist"
    disable_competing_modes()
    HistoryShuffle.set_status("ACTIVE - installed correctly; preparing the first deck...")
    HistoryShuffle.show_control_panel()
    HistoryShuffle.sync_input()

    local entries = HistoryShuffle.get_playlist_entries("playlist")
    if #entries > 0 then
        HistoryShuffle.shuffle("playlist")
    else
        HistoryShuffle.set_status("ACTIVE - add media, then choose Shuffle current playlist (or load the media library).")
        show_osd("History Shuffle ON - add media to begin")
    end
end

function deactivate()
    HistoryShuffle.active = false
    HistoryShuffle.finalize_session("deactivate")
    HistoryShuffle.save_state()
    if HistoryShuffle.dialog then
        safe_call(function()
            HistoryShuffle.dialog:delete()
        end)
    end
    HistoryShuffle.dialog = nil
    HistoryShuffle.status_label = nil
    HistoryShuffle.queue_label = nil
    HistoryShuffle.history_label = nil
    HistoryShuffle.data_label = nil
    log_info("OFF")
    show_osd("History Shuffle OFF")
end

function close()
    -- Clicking the native window X is an explicit OFF action. Use the panel's
    -- Hide button when the extension should keep tracking in the background.
    vlc.deactivate()
end

function input_changed()
    HistoryShuffle.sync_input()
end

function meta_changed()
    -- VLC 3 emits this alongside input-listener events even though it is
    -- not advertised as a separate extension capability.
    HistoryShuffle.sync_input()
end

function playing_changed()
    HistoryShuffle.sync_input()
end

function menu()
    return {
        "Status: ACTIVE (v" .. HistoryShuffle.VERSION .. ")",
        "Shuffle current playlist now",
        "Load media library + shuffle",
        "Toggle continuous decks (currently " .. (HistoryShuffle.state.continuous and "ON" or "OFF") .. ")",
        "Rate current item",
        "Toggle blacklist for current item",
        "Show recent history",
        "Export / import history"
    }
end

function trigger_menu(id)
    if id == 1 then
        HistoryShuffle.show_control_panel()
    elseif id == 2 then
        HistoryShuffle.shuffle("playlist")
    elseif id == 3 then
        HistoryShuffle.shuffle("library")
    elseif id == 4 then
        HistoryShuffle.toggle_continuous()
    elseif id == 5 then
        HistoryShuffle.rate_current()
    elseif id == 6 then
        HistoryShuffle.toggle_blacklist_current()
    elseif id == 7 then
        HistoryShuffle.show_recent()
    elseif id == 8 then
        HistoryShuffle.show_transfer()
    end
end

-- Unit-test hook. VLC never defines HISTORY_SHUFFLE_TEST.
if HISTORY_SHUFFLE_TEST == true then
    return {
        util = util,
        normalize_state = normalize_state,
        normalize_track = normalize_track,
        update_session_timing = update_session_timing,
        shuffle = HistoryShuffle.shuffle,
        replace_playlist = HistoryShuffle.replace_playlist,
        get_playlist_entries = HistoryShuffle.get_playlist_entries,
        load_state = HistoryShuffle.load_state,
        get_state = function() return HistoryShuffle.state end,
        config = HistoryShuffle.config
    }
end
