-- Global variables
local played = {} -- holds all music items from the current playlist
local store = {} -- holds all music items from the database
local day_in_seconds = 60 * 60 * 24
local last_played = ""
local prefix = "[HShuffle] "
local data_file = ""
local config = {
    min_like = 0,
    max_like = 200,
    play_increment = 10,
    skip_decrement = 5,
    skip_threshold = 0.9
}

-- Helper functions
function calculate_like(playcount, skipcount, user_rating)
    local like = 100 + (playcount * 3) - (skipcount * 5)
    if user_rating then
        like = like + user_rating * 10
    end
    return math.max(config.min_like, math.min(like, config.max_like))
end

function adjust_like_on_skip(like)
    return math.max(config.min_like, like - config.skip_decrement)
end

function adjust_like_on_full_play(like)
    return math.min(config.max_like, like + config.play_increment)
end

function descriptor()
    return {
        title = "VLC MediaPlayer History Shuffle",
        version = "1.2.0",
        shortdesc = "Shuffle Media Player",
        description = "Shuffles Media Player items based on song likes and listening history",
        author = "R. Crandon",
        capabilities = { "playing-listener", "menu" }
    }
end

function activate()
    vlc.msg.info(prefix .. "starting")
    math.randomseed(os.time())
    data_file = vlc.config.userdatadir() .. vlc.config.dir_separator() .. "better_playlist_data.json"
    vlc.msg.info(prefix .. "using data file " .. data_file)
    load_data_file()
    init_playlist()
    randomize_playlist()
    vlc.playlist.repeat_("off")
end

function deactivate()
    vlc.msg.info(prefix .. "deactivating.. Bye!")
    save_data_file()
end

function load_media_library()
    vlc.msg.dbg(prefix .. "loading media library playlist")
    local ml = vlc.media.library()
    local playlist = ml:items()
    vlc.playlist.clear()
    for _, item in ipairs(playlist) do
        if item then
            local path = item:uri()
            path = vlc.strings.decode_uri(path)
            vlc.playlist.enqueue({{path = path}})
        end
    end
end

function init_playlist()
    vlc.msg.dbg(prefix .. "initializing playlist")
    load_media_library()
    local time = os.time()
    local playlist = vlc.playlist.get("playlist", false).children
    local changed = false

    for _, item in ipairs(playlist) do
        if item and item.item then
            local path = item.item:uri()
            path = vlc.strings.decode_uri(path)
            if store[path] then
                played[path] = calculate_like(store[path].playcount, store[path].skipcount, store[path].user_rating)
            else
                played[path] = 100
                store[path] = { playcount = 0, skipcount = 0, time = time, user_rating = nil }
                changed = true
            end

            local elapsed_days = math.floor(os.difftime(time, store[path].time) / day_in_seconds)
            if elapsed_days >= 1 then
                store[path].time = store[path].time + elapsed_days * day_in_seconds
                changed = true
            end
        end
    end

    if changed then
        save_data_file()
    end
end

function randomize_playlist()
    vlc.msg.dbg(prefix .. "randomizing playlist")
    vlc.playlist.stop()

    local queue = {}
    for path, weight in pairs(played) do
        table.insert(queue, { path = path, weight = weight })
    end

    if #queue > 0 then
        vlc.playlist.clear()
        table.sort(queue, function(a, b) return a.weight > b.weight end)
        
        local total_weight = 0
        for _, item in ipairs(queue) do
            total_weight = total_weight + item.weight
        end

        local new_playlist = {}
        while #queue > 0 do
            local rand = math.random() * total_weight
            local sum = 0
            for i, item in ipairs(queue) do
                sum = sum + item.weight
                if sum >= rand then
                    table.insert(new_playlist, {path = item.path})
                    total_weight = total_weight - item.weight
                    table.remove(queue, i)
                    break
                end
            end
        end

        vlc.playlist.enqueue(new_playlist)
    end

    while vlc.playlist.current() ~= nil do
        vlc.misc.mwait(100)
    end
    vlc.playlist.play()
end

function load_data_file()
    local file, err = io.open(data_file, "r")
    store = {}
    if err then
        vlc.msg.warn(prefix .. "data file does not exist, creating...")
        save_data_file()
    else
        vlc.msg.info(prefix .. "data file successfully opened")
        local content = file:read("*all")
        io.close(file)
        local success, data = pcall(vlc.json.decode, content)
        if success then
            store = data
        else
            vlc.msg.warn(prefix .. "invalid data file, creating new one")
            save_data_file()
        end
    end
end

function save_data_file()
    local file, err = io.open(data_file, "w")
    if err then
        vlc.msg.err(prefix .. "Unable to open data file for writing")
    else
        local content = vlc.json.encode(store)
        file:write(content)
        io.close(file)
    end
end

function playing_changed()
    local item = vlc.input.item()
    if item then
        local time = vlc.var.get(vlc.object.input(), "time")
        local total = item:duration()
        local path = vlc.strings.decode_uri(item:uri())

        if last_played ~= path then
            vlc.msg.info(prefix .. "song ended: " .. item:name())
            last_played = path

            time = math.floor(time / 1000000)
            total = math.floor(total)

            if store[path] then
                if time < total * config.skip_threshold then
                    vlc.msg.info(prefix .. "skipped song at " .. (math.floor(time / total * 10000 + 0.5) / 100) .. "%")
                    store[path].skipcount = store[path].skipcount + 1
                    played[path] = adjust_like_on_skip(played[path])
                else
                    store[path].playcount = store[path].playcount + 1
                    played[path] = adjust_like_on_full_play(played[path])
                end

                store[path].time = os.time()
                save_data_file()
            end
        end
    end
end

function meta_changed() end

function menu()
    return {
        "View Ratings",
        "Set Rating for Current Song"
    }
end

function trigger_menu(id)
    if id == 1 then
        view_ratings()
    elseif id == 2 then
        set_rating_for_current_song()
    end
end

function view_ratings()
    local d = vlc.dialog("Song Ratings")
    local y = 1
    for path, data in pairs(store) do
        local like = calculate_like(data.playcount, data.skipcount, data.user_rating)
        d:add_label(string.format("%s: %d", vlc.strings.basename(path), like), 1, y)
        y = y + 1
    end
    d:show()
end

function set_rating_for_current_song()
    local item = vlc.input.item()
    if item then
        local path = vlc.strings.decode_uri(item:uri())
        local d = vlc.dialog("Set Rating")
        d:add_label("Enter rating (0-10) for: " .. vlc.strings.basename(path), 1, 1)
        local input = d:add_text_input("", 2, 1)
        d:add_button("Set", function()
            local rating = tonumber(input:get_text())
            if rating and rating >= 0 and rating <= 10 then
                store[path].user_rating = rating
                played[path] = calculate_like(store[path].playcount, store[path].skipcount, rating)
                save_data_file()
                d:delete()
            else
                d:add_label("Invalid input. Please enter a number between 0 and 10.", 1, 3)
            end
        end, 1, 2)
        d:show()
    else
        vlc.msg.info(prefix .. "No song currently playing")
    end
end
