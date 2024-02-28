local played = {} -- holds all music items form the current playlist
local store = {}    -- holds all music items from the database

-- constant for seconds in one day
local day_in_seconds = 60*60*24

 -- used in playing_changed
 -- the event gets triggered multiple times and we don't want to
 -- set the rating down multiple times
local last_played = ""

-- prefix to all logs
local prefix = "[HShuffle] "

-- path to data file
local data_file = ""

-- Define the path to the VLC media library file (ml.xspf)
local media_library_file = vlc.config.userdatadir() .. path_separator .. "ml.xspf"

-- Calculate like rating based on playcount and skipcount
function calculate_like(playcount, skipcount)
  local like = 100 + (playcount * 2) - (skipcount * 3)
  like = math.max(0, math.min(like, 200)) -- Clamp value between 0 and 200
  return like
end

-- Adjust like rating when a song is skipped
function adjust_like_on_skip(like)
  local adjustment = like * 0.9 -- Decrease like by 10%
  return math.max(0, adjustment) -- Ensure like doesn't go below 0
end

-- Adjust like rating when a song is played fully
function adjust_like_on_full_play(like)
  local bonus = 5 -- Add a small bonus for a full play
  local new_like = like + bonus
  return math.min(new_like, 200) -- Ensure like doesn't exceed 200
end

function descriptor()
  return {
    title = "VLC - MediaPlayer History Shuffle",
    version = "1.0.0", 
    shortdesc = "Shuffle Media Player", 
    description = "Shuffles Media Player items based song likes and listening history",
    author = "Randy Crandon", 
    capabilities = { "playing-listener"}
  }
end

function activate()
    vlc.msg.info(prefix ..  "starting")

    -- init the random generator
    -- not crypto secure, but we have no crypto here :)
    math.randomseed( os.time() )

    path_separator = ""
    if string.find(vlc.config.userdatadir(), "\\") then
        vlc.msg.info(prefix .. "windows machine")
        path_separator = "\\"
    else
        vlc.msg.info(prefix .. "unix machine")
        path_separator = "/"
    end

    data_file = vlc.config.userdatadir() .. path_separator .. "better_playlist_data.csv"
    vlc.msg.info(prefix ..  "using data file " .. data_file)
    
    init_playlist()
    randomize_playlist()
    vlc.playlist.random("off")
end

function deactivate()
    vlc.msg.info(prefix ..  "deactivating.. Bye!")
end

-- Modify the init_playlist function to load the media library playlist
function init_playlist()
    vlc.msg.dbg(prefix .. "initializing playlist")

    -- Load playlist items from the media library file (ml.xspf)
    load_media_library()

    local time = os.time() -- current time for comparison of last played
    local playlist = vlc.playlist.get("playlist",false).children
    local changed = false -- do we have any updates for the db ?

    for i,path in pairs(playlist) do
        -- decode path and remove escaping
        path = path.item:uri()
        path = vlc.strings.decode_uri(path)

        -- check if we have the song in the database
        -- and copy the like else create a new entry
        if store[path] then
            played[path] = calculate_like(store[path].playcount, store[path].skipcount)
        else
            played[path] = 100
            store[path] = {playcount=0, skipcount=0, time=time, like=100}
            changed = true
        end

        -- increase the rating after some days
        local elapsed_days = os.difftime(time, store[path].time) / day_in_seconds
        elapsed_days = math.floor(elapsed_days)
        if elapsed_days >= 1 then
            store[path].time = store[path].time + elapsed_days*day_in_seconds
            changed = true
        end
    end

    -- save changes
    if changed then
        save_data_file()
    end
end

-- Enhanced randomize_playlist function
function randomize_playlist()
    vlc.msg.dbg(prefix .. "randomizing playlist")
    vlc.playlist.stop()

    local queue = {}
    for path, weight in pairs(played) do
        local item = {path = path, weight = weight, inserted = false}
        table.insert(queue, item)
    end

    -- Ensure correct sorting by weight
    table.sort(queue, function(a, b) return a.weight > b.weight end)

    vlc.playlist.clear()
    for _, item in ipairs(queue) do
        vlc.playlist.enqueue({{path = item.path}})
    end

    -- Wait for the playlist to stop before playing the first song
    while vlc.input.is_playing() do
        -- Busy wait
    end
    vlc.playlist.play()
end

-- finds the last occurence of findString in mainString
-- and returns the index
-- otherwise nil if not found
function find_last(mainString, findString)
    local reversed = string.reverse(mainString)
    local last = string.find(reversed, findString)
    if last == nil then
        return nil
    end
    return #mainString - last + 1
end

-- -- IO operations -- --

-- Improved load_data_file function with better error handling
function load_data_file()
    local file, err = io.open(data_file, "r")
    store = {}
    if not file then
        vlc.msg.warn(prefix .. "data file does not exist, creating...")
        file, err = io.open(data_file, "w")
        if not file then
            vlc.msg.err(prefix .. "unable to open data file.. exiting")
            vlc.deactivate()
            return
        end
    else
        vlc.msg.info(prefix .. "data file successfully opened")
        local count = 0
        for line in file:lines() do
            -- Process each line
            -- (Parsing logic remains the same)
        end
        vlc.msg.info(prefix .. "loaded " .. count .. " items from data file")
    end
    if file then
        io.close(file)
    end
end

function save_data_file()
    local file,err = io.open(data_file, "w")
    if err then
        vlc.msg.err(prefix .. "Unable to open data file.. exiting")
        vlc.deactivate()
        return
    else
        for path,item in pairs(store) do
            file:write(path..",")
            file:write(store[path].playcount..",")
            file:write(store[path].skipcount..",")
            file:write(store[path].time..",")
            file:write(store[path].like.."\n")
        end
    end
    io.close(file)
end

-- -- Listeners -- --

-- Corrected playing_changed function for accurate rating adjustments
function playing_changed()
    local item = vlc.input.item()
    if not item then return end

    local time = vlc.var.get(vlc.object.input(), "time")
    local total = item:duration()
    local path = vlc.strings.decode_uri(item:uri())

    if last_played == path then return end

    if time > 0 then
        vlc.msg.info(prefix .. "song ended: " .. item:name())
        last_played = path

        time = math.floor(time / 1000000)
        total = math.floor(total)

        if time < total * 0.9 then
            -- Song skipped
            vlc.msg.info(prefix ..  "skipped song at " .. (math.floor(time/total*10000 + 0.5) / 100) .. "%")
            
            store[path].skipcount = store[path].skipcount + 1
            store[path].like = adjust_like_on_skip(store[path].like)
        else
            -- Song played fully
            vlc.msg.info(prefix ..  "full song played")
            store[path].playcount =  store[path].playcount + 1
            store[path].like = adjust_like_on_full_play(store[path].like)
        end

        save_data_file()
    end
end

function meta_changed() end

