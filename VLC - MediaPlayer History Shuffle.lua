-- HShuffle: VLC History-based Shuffle Extension
local HShuffle = {
    -- Data storage
    played = {}, -- holds all music items from the current playlist
    store = {},  -- holds all music items from the database
    last_played = "",
    data_file = "",
    
    -- Constants
    DAY_IN_SECONDS = 60 * 60 * 24,
    PREFIX = "[HShuffle] ",
    VERSION = "2.0.0",
    
    -- Configuration
    config = {
        min_like = 0,
        max_like = 200,
        play_increment = 10,
        skip_decrement = 5,
        skip_threshold = 0.9,
        blacklist_threshold = -50  -- Songs below this rating are excluded from shuffle
    }
}

-- Utility functions
local util = {}

function util.calculate_like(playcount, skipcount, user_rating)
    local like = 100 + (playcount * 3) - (skipcount * 5)
    if user_rating then
        like = like + user_rating * 10
    end
    return math.max(HShuffle.config.min_like, math.min(like, HShuffle.config.max_like))
end

function util.adjust_like_on_skip(like)
    return math.max(HShuffle.config.min_like, like - HShuffle.config.skip_decrement)
end

function util.adjust_like_on_full_play(like)
    return math.min(HShuffle.config.max_like, like + HShuffle.config.play_increment)
end

function descriptor()
    return {
        title = "VLC MediaPlayer History Shuffle",
        version = HShuffle.VERSION,
        shortdesc = "Shuffle Media Player",
        description = "Shuffles Media Player items based on song likes and listening history",
        author = "R. Crandon",
        capabilities = { "playing-listener", "menu" }
    }
end

function activate()
    vlc.msg.info(HShuffle.PREFIX .. "starting")
    math.randomseed(os.time())
    HShuffle.data_file = vlc.config.userdatadir() .. vlc.config.dir_separator() .. "better_playlist_data.json"
    vlc.msg.info(HShuffle.PREFIX .. "using data file " .. HShuffle.data_file)
    HShuffle.load_data_file()
    HShuffle.init_playlist()
    HShuffle.randomize_playlist()
    vlc.playlist.repeat_("off")
end

function deactivate()
    vlc.msg.info(HShuffle.PREFIX .. "deactivating.. Bye!")
    HShuffle.save_data_file()
end

function HShuffle.load_media_library()
    vlc.msg.dbg(HShuffle.PREFIX .. "loading media library playlist")
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

function HShuffle.init_playlist()
    vlc.msg.dbg(HShuffle.PREFIX .. "initializing playlist")
    HShuffle.load_media_library()
    local time = os.time()
    local playlist = vlc.playlist.get("playlist", false).children
    local changed = false

    for _, item in ipairs(playlist) do
        if item and item.item then
            local path = item.item:uri()
            path = vlc.strings.decode_uri(path)
            if HShuffle.store[path] then
                HShuffle.played[path] = util.calculate_like(HShuffle.store[path].playcount, HShuffle.store[path].skipcount, HShuffle.store[path].user_rating)
            else
                HShuffle.played[path] = 100
                HShuffle.store[path] = { playcount = 0, skipcount = 0, time = time, user_rating = nil }
                changed = true
            end

            local elapsed_days = math.floor(os.difftime(time, HShuffle.store[path].time) / HShuffle.DAY_IN_SECONDS)
            if elapsed_days >= 1 then
                HShuffle.store[path].time = HShuffle.store[path].time + elapsed_days * HShuffle.DAY_IN_SECONDS
                changed = true
            end
        end
    end

    if changed then
        HShuffle.save_data_file()
    end
end

function HShuffle.randomize_playlist()
    vlc.msg.dbg(HShuffle.PREFIX .. "randomizing playlist")
    vlc.playlist.stop()

    local queue = {}
    for path, weight in pairs(HShuffle.played) do
        -- Exclude blacklisted songs (those below the blacklist threshold)
        if weight >= HShuffle.config.blacklist_threshold then
            table.insert(queue, { path = path, weight = weight })
        else
            vlc.msg.dbg(HShuffle.PREFIX .. "Excluding blacklisted song: " .. vlc.strings.basename(path))
        end
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

    vlc.playlist.play()
end

function HShuffle.load_data_file()
    local file, err = io.open(HShuffle.data_file, "r")
    HShuffle.store = {}
    if err then
        vlc.msg.warn(HShuffle.PREFIX .. "data file does not exist, creating...")
        HShuffle.save_data_file()
    else
        vlc.msg.info(HShuffle.PREFIX .. "data file successfully opened")
        local content = file:read("*all")
        io.close(file)
        local success, data = pcall(vlc.json.decode, content)
        if success then
            HShuffle.store = data
        else
            vlc.msg.warn(HShuffle.PREFIX .. "invalid data file, creating new one")
            HShuffle.save_data_file()
        end
    end
end

function HShuffle.save_data_file()
    local success, err = pcall(function()
        local temp_file = HShuffle.data_file .. ".tmp"
        local file = io.open(temp_file, "w")
        if not file then
            error("Unable to open temp file for writing")
        end
        
        local content = vlc.json.encode(HShuffle.store)
        file:write(content)
        file:close()
        
        -- Atomic rename on most systems
        local success = os.rename(temp_file, HShuffle.data_file)
        if not success then
            os.remove(temp_file)
            error("Unable to rename temp file to data file")
        end
    end)
    
    if not success then
        vlc.msg.err(HShuffle.PREFIX .. "Failed to save data file: " .. (err or "unknown error"))
    end
end

function playing_changed()
    local item = vlc.input.item()
    if item then
        local time = vlc.var.get(vlc.object.input(), "time")
        local total = item:duration()
        local path = vlc.strings.decode_uri(item:uri())

        if HShuffle.last_played ~= path then
            vlc.msg.info(HShuffle.PREFIX .. "song ended: " .. item:name())
            HShuffle.last_played = path

            time = math.floor(time / 1000000)
            total = math.floor(total)

            if HShuffle.store[path] then
                if time < total * HShuffle.config.skip_threshold then
                    vlc.msg.info(HShuffle.PREFIX .. "skipped song at " .. (math.floor(time / total * 10000 + 0.5) / 100) .. "%")
                    HShuffle.store[path].skipcount = HShuffle.store[path].skipcount + 1
                    HShuffle.played[path] = util.adjust_like_on_skip(HShuffle.played[path])
                else
                    HShuffle.store[path].playcount = HShuffle.store[path].playcount + 1
                    HShuffle.played[path] = util.adjust_like_on_full_play(HShuffle.played[path])
                end

                HShuffle.store[path].time = os.time()
                HShuffle.save_data_file()
            end
            
            -- Clear last_played to allow re-triggering same song in future sessions
            HShuffle.last_played = nil
        end
    end
end

function meta_changed() end

function menu()
    return {
        "View Ratings",
        "Set Rating for Current Song",
        "Export Ratings Data",
        "Import Ratings Data",
        "Blacklist Current Song",
        "View Blacklisted Songs"
    }
end

function trigger_menu(id)
    if id == 1 then
        HShuffle.view_ratings()
    elseif id == 2 then
        HShuffle.set_rating_for_current_song()
    elseif id == 3 then
        HShuffle.export_ratings()
    elseif id == 4 then
        HShuffle.import_ratings()
    elseif id == 5 then
        HShuffle.blacklist_current_song()
    elseif id == 6 then
        HShuffle.view_blacklisted_songs()
    end
end

function HShuffle.view_ratings()
    local d = vlc.dialog("Song Ratings")
    local y = 1
    for path, data in pairs(HShuffle.store) do
        local like = util.calculate_like(data.playcount, data.skipcount, data.user_rating)
        d:add_label(string.format("%s: %d", vlc.strings.basename(path), like), 1, y)
        y = y + 1
    end
    d:show()
end

function HShuffle.set_rating_for_current_song()
    local item = vlc.input.item()
    if item then
        local path = vlc.strings.decode_uri(item:uri())
        local d = vlc.dialog("Set Rating")
        d:add_label("Enter rating (0-10) for: " .. vlc.strings.basename(path), 1, 1)
        local input = d:add_text_input("", 2, 1)
        d:add_button("Set", function()
            local rating = tonumber(input:get_text())
            if rating and rating >= 0 and rating <= 10 then
                HShuffle.store[path].user_rating = rating
                HShuffle.played[path] = util.calculate_like(HShuffle.store[path].playcount, HShuffle.store[path].skipcount, rating)
                HShuffle.save_data_file()
                d:delete()
            else
                d:add_label("Invalid input. Please enter a number between 0 and 10.", 1, 3)
            end
        end, 1, 2)
        d:show()
    else
        vlc.msg.info(HShuffle.PREFIX .. "No song currently playing")
    end
end

function HShuffle.export_ratings()
    local d = vlc.dialog("Export Ratings")
    d:add_label("Export ratings data to file:", 1, 1)
    local path_input = d:add_text_input("ratings_export.json", 2, 1)
    d:add_button("Export", function()
        local export_file = path_input:get_text()
        if export_file and export_file ~= "" then
            local success, err = pcall(function()
                local file = io.open(export_file, "w")
                if not file then
                    error("Unable to open export file for writing")
                end
                
                local export_data = {
                    version = HShuffle.VERSION,
                    exported_at = os.time(),
                    data = HShuffle.store
                }
                
                local content = vlc.json.encode(export_data)
                file:write(content)
                file:close()
            end)
            
            if success then
                d:add_label("Export successful!", 1, 3)
                vlc.msg.info(HShuffle.PREFIX .. "Ratings exported to " .. export_file)
            else
                d:add_label("Export failed: " .. (err or "unknown error"), 1, 3)
            end
        else
            d:add_label("Please enter a valid filename", 1, 3)
        end
    end, 1, 2)
    d:show()
end

function HShuffle.blacklist_current_song()
    local item = vlc.input.item()
    if item then
        local path = vlc.strings.decode_uri(item:uri())
        local d = vlc.dialog("Blacklist Song")
        d:add_label("Blacklist: " .. vlc.strings.basename(path), 1, 1)
        d:add_label("This will set the song rating below the blacklist threshold.", 1, 2)
        d:add_button("Blacklist", function()
            if HShuffle.store[path] then
                -- Set rating below blacklist threshold to exclude from shuffle
                HShuffle.store[path].user_rating = -10  -- This will result in negative like rating
                HShuffle.played[path] = util.calculate_like(HShuffle.store[path].playcount, HShuffle.store[path].skipcount, -10)
                HShuffle.save_data_file()
                vlc.msg.info(HShuffle.PREFIX .. "Song blacklisted: " .. vlc.strings.basename(path))
                d:delete()
            else
                d:add_label("Error: Song not found in database", 1, 4)
            end
        end, 1, 3)
        d:add_button("Cancel", function()
            d:delete()
        end, 2, 3)
        d:show()
    else
        vlc.msg.info(HShuffle.PREFIX .. "No song currently playing")
    end
end

function HShuffle.view_blacklisted_songs()
    local d = vlc.dialog("Blacklisted Songs")
    local y = 1
    local found_blacklisted = false
    
    for path, data in pairs(HShuffle.store) do
        local like = util.calculate_like(data.playcount, data.skipcount, data.user_rating)
        if like < HShuffle.config.blacklist_threshold then
            d:add_label(string.format("%s (Rating: %d)", vlc.strings.basename(path), like), 1, y)
            y = y + 1
            found_blacklisted = true
        end
    end
    
    if not found_blacklisted then
        d:add_label("No blacklisted songs found", 1, 1)
    end
    
    d:show()
end

function HShuffle.import_ratings()
    local d = vlc.dialog("Import Ratings")
    d:add_label("Import ratings data from file:", 1, 1)
    local path_input = d:add_text_input("ratings_export.json", 2, 1)
    d:add_button("Import", function()
        local import_file = path_input:get_text()
        if import_file and import_file ~= "" then
            local success, err = pcall(function()
                local file = io.open(import_file, "r")
                if not file then
                    error("Unable to open import file for reading")
                end
                
                local content = file:read("*all")
                file:close()
                
                local import_data = vlc.json.decode(content)
                if import_data and import_data.data then
                    -- Merge imported data with existing data
                    for path, data in pairs(import_data.data) do
                        if HShuffle.store[path] then
                            -- Keep higher play counts and ratings
                            HShuffle.store[path].playcount = math.max(HShuffle.store[path].playcount or 0, data.playcount or 0)
                            HShuffle.store[path].skipcount = math.max(HShuffle.store[path].skipcount or 0, data.skipcount or 0)
                            if data.user_rating then
                                HShuffle.store[path].user_rating = data.user_rating
                            end
                        else
                            HShuffle.store[path] = data
                        end
                    end
                    HShuffle.save_data_file()
                else
                    error("Invalid import file format")
                end
            end)
            
            if success then
                d:add_label("Import successful!", 1, 3)
                vlc.msg.info(HShuffle.PREFIX .. "Ratings imported from " .. import_file)
            else
                d:add_label("Import failed: " .. (err or "unknown error"), 1, 3)
            end
        else
            d:add_label("Please enter a valid filename", 1, 3)
        end
    end, 1, 2)
    d:show()
end

function HShuffle.blacklist_current_song()
    local item = vlc.input.item()
    if item then
        local path = vlc.strings.decode_uri(item:uri())
        local d = vlc.dialog("Blacklist Song")
        d:add_label("Blacklist: " .. vlc.strings.basename(path), 1, 1)
        d:add_label("This will set the song rating below the blacklist threshold.", 1, 2)
        d:add_button("Blacklist", function()
            if HShuffle.store[path] then
                -- Set rating below blacklist threshold to exclude from shuffle
                HShuffle.store[path].user_rating = -10  -- This will result in negative like rating
                HShuffle.played[path] = util.calculate_like(HShuffle.store[path].playcount, HShuffle.store[path].skipcount, -10)
                HShuffle.save_data_file()
                vlc.msg.info(HShuffle.PREFIX .. "Song blacklisted: " .. vlc.strings.basename(path))
                d:delete()
            else
                d:add_label("Error: Song not found in database", 1, 4)
            end
        end, 1, 3)
        d:add_button("Cancel", function()
            d:delete()
        end, 2, 3)
        d:show()
    else
        vlc.msg.info(HShuffle.PREFIX .. "No song currently playing")
    end
end

function HShuffle.view_blacklisted_songs()
    local d = vlc.dialog("Blacklisted Songs")
    local y = 1
    local found_blacklisted = false
    
    for path, data in pairs(HShuffle.store) do
        local like = util.calculate_like(data.playcount, data.skipcount, data.user_rating)
        if like < HShuffle.config.blacklist_threshold then
            d:add_label(string.format("%s (Rating: %d)", vlc.strings.basename(path), like), 1, y)
            y = y + 1
            found_blacklisted = true
        end
    end
    
    if not found_blacklisted then
        d:add_label("No blacklisted songs found", 1, 1)
    end
    
    d:show()
end
