HISTORY_SHUFFLE_TEST = true
local standard_rawget = rawget
rawget = nil -- Match VLC's restricted extension sandbox during file-scope execution.
local module = assert(dofile("VLC - MediaPlayer History Shuffle.lua"))
rawget = standard_rawget
local util = module.util

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

assert_equal(type(meta_changed), "function", "VLC 3 input listeners must provide meta_changed")

-- Folder nodes have their own input item and URI in VLC. These are structural
-- placeholders, not the media contained within the folder.
vlc = { playlist = { get = function()
    return { children = {
        { path = "vlc://nop", item = { uri = function() return "vlc://nop" end }, children = {
            { path = "file:///nested-a.mp4" },
            { path = "file:///folder", children = { { path = "file:///nested-b.mkv" } } }
        } },
        { path = "vlc://nop", children = {} },
        { path = "vlc://nop" },
        { path = "file:///flat-c.mp4" }
    } }
end } }
local nested_entries = module.get_playlist_entries("library")
assert_equal(#nested_entries, 3, "nested folders must yield their media leaves")
assert_equal(nested_entries[1].path, "file:///nested-a.mp4", "first nested media leaf")
assert_equal(nested_entries[2].path, "file:///nested-b.mkv", "deeply nested media leaf")
assert_equal(nested_entries[3].path, "file:///flat-c.mp4", "flat media remains included")
vlc = nil

local values = { 0.91, 0.12, 0.73, 0.35, 0.64, 0.27, 0.82, 0.44, 0.56, 0.18 }
local cursor = 0
local function deterministic_random()
    cursor = cursor + 1
    return values[((cursor - 1) % #values) + 1]
end

local entries = {}
local tracks = {}
for i = 1, 12 do
    local uri = "file:///video-" .. tostring(i) .. ".mp4"
    entries[i] = { path = uri, name = "video-" .. tostring(i) }
    tracks[uri] = { user_rating = 5, blacklisted = false }
end
tracks["file:///video-6.mp4"].blacklisted = true

local recent = {
    "file:///video-10.mp4",
    "file:///video-11.mp4",
    "file:///video-12.mp4"
}

local deck, stats = util.build_shuffle_deck(
    entries,
    tracks,
    recent,
    deterministic_random,
    "file:///video-12.mp4"
)

assert_equal(#deck, 11, "deck must contain every eligible entry exactly once")
assert_equal(stats.blacklisted, 1, "blacklist count")
assert_equal(stats.cooled, 3, "recent cooldown count")

local seen = {}
for _, entry in ipairs(deck) do
    if seen[entry.path] then
        error("duplicate deck entry: " .. entry.path)
    end
    seen[entry.path] = true
end
assert_equal(seen["file:///video-6.mp4"], nil, "blacklisted entry must be absent")
assert_equal(util.same_entry_multiset(entries, entries), true, "identical decks must verify")
assert_equal(util.same_entry_multiset(entries, deck), false, "different decks must not verify")
assert_equal(util.same_entry_sequence(entries, entries), true, "identical order must verify")
local reversed = {}
for i = #entries, 1, -1 do
    reversed[#reversed + 1] = entries[i]
end
assert_equal(util.same_entry_sequence(entries, reversed), false, "reversed order must fail exact verification")

local cooled_start = #deck - stats.cooled + 1
for i = cooled_start, #deck do
    local uri = deck[i].path
    if uri ~= "file:///video-10.mp4" and uri ~= "file:///video-11.mp4" and uri ~= "file:///video-12.mp4" then
        error("cooldown tail contains a non-recent item: " .. uri)
    end
end

local _, absent_current_stats = util.build_shuffle_deck(
    entries,
    tracks,
    recent,
    deterministic_random,
    "file:///not-in-this-playlist.mp4"
)
assert_equal(absent_current_stats.cooled, 3, "an absent current URI must not consume a cooldown slot")

local timing = { listened_seconds = 10, playing_since = 100 }
module.update_session_timing(timing, "paused", 115)
assert_equal(timing.listened_seconds, 25, "pause transition must bank only active listening time")
assert_equal(timing.playing_since, nil, "pause transition must stop the listening clock")
module.update_session_timing(timing, "paused", 200)
assert_equal(timing.listened_seconds, 25, "paused wall time must not count as listening")
module.update_session_timing(timing, "playing", 220)
assert_equal(timing.playing_since, 220, "resume must restart the listening clock")

local legacy = module.normalize_state({
    ["C:/video.mp4"] = { playcount = 4, skipcount = 2, time = 123, user_rating = -20 }
})
assert_equal(legacy.tracks["C:/video.mp4"].completed, 4, "legacy playcount migration")
assert_equal(legacy.tracks["C:/video.mp4"].skips, 2, "legacy skipcount migration")
assert_equal(legacy.tracks["C:/video.mp4"].blacklisted, true, "legacy blacklist migration")

-- Exercise activation against VLC 3-style APIs. This catches discovery-time and
-- first-run persistence errors that pure shuffle tests cannot see.
local enqueued = nil
local random_mode = nil
local loop_mode = nil
local played = false
local playback_state = "stopped"
local corrupt_next_enqueue = false
local function fake_item(uri)
    return {
        uri = function() return uri end,
        name = function() return uri:match("([^/]+)$") end,
        duration = function() return 120 end
    }
end

local fake_children = {}
for i = 1, 8 do
    fake_children[i] = { item = fake_item("file:///activation-" .. tostring(i) .. ".mp4") }
end

local function fake_widget(initial)
    return {
        value = initial,
        set_text = function(self, text) self.value = text end,
        get_text = function(self) return self.value end
    }
end

local function fake_dialog()
    return {
        add_html = function() return fake_widget("") end,
        add_label = function(_, text) return fake_widget(text) end,
        add_button = function() return fake_widget("") end,
        add_text_input = function(_, text) return fake_widget(text) end,
        show = function() end,
        delete = function() end
    }
end

local memory_files = {}
io.open = function(path, mode)
    mode = mode or "r"
    if mode == "r" then
        if memory_files[path] == nil then
            return nil, "not found"
        end
        return {
            read = function() return memory_files[path] end,
            close = function() end
        }
    end
    if mode == "w" then
        local buffer = ""
        return {
            write = function(_, text) buffer = buffer .. tostring(text) end,
            flush = function() end,
            close = function() memory_files[path] = buffer end
        }
    end
    return nil, "unsupported mode"
end
os.remove = function(path)
    memory_files[path] = nil
    return true
end
os.rename = function(source, destination)
    if memory_files[source] == nil or memory_files[destination] ~= nil then
        return nil, "rename failed"
    end
    memory_files[destination] = memory_files[source]
    memory_files[source] = nil
    return true
end

vlc = {
    msg = { info = function() end, warn = function() end, err = function() end },
    config = {
        userdatadir = function() return "tests" end,
        dir_separator = function() return "/" end,
        homedir = function() return "tests" end
    },
    json = {
        encode = function() return "{}" end,
        decode = function(text)
            if text ~= "{}" then error("invalid JSON") end
            return {}
        end
    },
    rand = { number = (function()
        local number = 1000
        return function()
            number = (number * 1103515245 + 12345) % 2147483648
            return number
        end
    end)() },
    playlist = {
        get = function() return { children = fake_children } end,
        stop = function() playback_state = "stopped" end,
        clear = function() fake_children = {} end,
        random = function(mode) random_mode = mode end,
        repeat_ = function() end,
        loop = function(mode) loop_mode = mode end,
        status = function() return playback_state end,
        enqueue = function(deck)
            enqueued = deck
            local installed = {}
            for i, entry in ipairs(deck) do
                installed[i] = {
                    item = fake_item(entry.path),
                    path = entry.path,
                    name = entry.name,
                    duration = entry.duration
                }
            end
            if corrupt_next_enqueue and #installed > 1 then
                installed[1], installed[#installed] = installed[#installed], installed[1]
                corrupt_next_enqueue = false
            end
            fake_children = installed
        end,
        play = function() played = true; playback_state = "playing" end
    },
    input = { item = function() return nil end },
    strings = {
        decode_uri = function(uri) return uri end,
        basename = function(uri) return uri:match("([^/]+)$") end
    },
    osd = { message = function() end },
    dialog = fake_dialog,
    deactivate = function() end
}

activate()
assert_equal(#enqueued, 8, "activation must enqueue one complete deck")
assert_equal(random_mode, "off", "VLC's competing random mode must be disabled")
assert_equal(loop_mode, "off", "VLC's fixed-order loop mode must be disabled")
assert_equal(played, true, "activation must start the generated deck")
assert_equal(memory_files["tests/history_shuffle_data.json"] ~= nil, true, "activation must create its history database")
assert_equal(module.get_state().last_shuffle_verified, true, "activation receipt must verify exact VLC order")

memory_files["tests/history_shuffle_data.json"] = "broken"
memory_files["tests/history_shuffle_data.json.bak"] = "{}"
module.load_state()
assert_equal(memory_files["tests/history_shuffle_data.json"], "{}", "backup recovery must rewrite a valid primary database")
assert_equal(memory_files["tests/history_shuffle_data.json.bak"], "{}", "backup recovery must leave a valid backup database")
local preserved_corrupt = false
for path, _ in pairs(memory_files) do
    if path:match("history_shuffle_data%.json%.corrupt%-%d+") then
        preserved_corrupt = true
    end
end
assert_equal(preserved_corrupt, true, "backup recovery must preserve the unreadable primary database")

local activated_seen = {}
for _, entry in ipairs(enqueued) do
    if activated_seen[entry.path] then
        error("activation enqueued a duplicate: " .. entry.path)
    end
    activated_seen[entry.path] = true
end

local before_failed_shuffle = {}
for i, node in ipairs(fake_children) do
    before_failed_shuffle[i] = { path = node.item:uri() }
end
local successful_count = module.get_state().shuffle_count
corrupt_next_enqueue = true
assert_equal(module.shuffle("playlist"), false, "a corrupted VLC read-back must fail the shuffle")
local after_rollback = {}
for i, node in ipairs(fake_children) do
    after_rollback[i] = { path = node.item:uri() }
end
assert_equal(util.same_entry_sequence(before_failed_shuffle, after_rollback), true, "failed shuffle must restore the previous order")
assert_equal(module.get_state().shuffle_count, successful_count, "failed shuffle must not increment the success counter")

deactivate()

print("History Shuffle tests passed")
