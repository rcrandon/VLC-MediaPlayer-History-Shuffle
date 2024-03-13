local played = {} -- holds all music items from the current playlist
local store = {} -- holds all music items from the database

-- constant for seconds in one day
local day_in_seconds = 60 * 60 * 24

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
    title = "VLC MediaPlayer History Shuffle",
    version = "1.0.0",
    shortdesc = "Shuffle Media Player",
    description = "Shuffles Media Player items based on song likes and listening history",
    author = "R. Crandon",
    capabilities = { "playing-listener" }
  }
end

function activate()
  vlc.msg.info(prefix .. "starting")

  -- init the random generator
  -- not crypto secure, but we have no crypto here :)
  math.randomseed(os.time())

  path_separator = package.config:sub(1,1)

  data_file = vlc.config.userdatadir() .. path_separator .. "better_playlist_data.csv"
  vlc.msg.info(prefix .. "using data file " .. data_file)

  load_data_file()
  init_playlist()
  randomize_playlist()
  vlc.playlist.repeat_("off")
end

function deactivate()
  vlc.msg.info(prefix .. "deactivating.. Bye!")
end

-- Load the media library playlist
function load_media_library()
  vlc.msg.dbg(prefix .. "loading media library playlist")

  -- Load playlist items from the media library file (ml.xspf)
  local playlist = vlc.playlist.get("playlist", false).children
  vlc.playlist.clear()

  -- Bug Fix 1: Add error handling for media library file
  if playlist then
    for _, item in ipairs(playlist) do
      if item and item.item then
        local path = item.item:uri()
        path = vlc.strings.decode_uri(path)
        vlc.playlist.enqueue({{path = path}})
      end
    end
  else
    vlc.msg.err(prefix .. "failed to load media library playlist")
  end
end

function init_playlist()
  vlc.msg.dbg(prefix .. "initializing playlist")

  -- Load playlist items from the media library file (ml.xspf)
  load_media_library()

  local time = os.time() -- current time for comparison of last played
  local playlist = vlc.playlist.get("playlist", false).children
  local changed = false -- do we have any updates for the db?

  -- Bug Fix 2: Check for nil values
  for _, item in ipairs(playlist) do
    if item and item.item then
      local path = item.item:uri()
      path = vlc.strings.decode_uri(path)

      -- Bug Fix 3: Update the played table correctly
      if store[path] then
        played[path] = calculate_like(store[path].playcount, store[path].skipcount)
      else
        played[path] = 100
        store[path] = { playcount = 0, skipcount = 0, time = time }
        changed = true
      end

      -- increase the rating after some days
      local elapsed_days = math.floor(os.difftime(time, store[path].time) / day_in_seconds)
      if elapsed_days >= 1 then
        store[path].time = store[path].time + elapsed_days * day_in_seconds
        changed = true
      end
    end
  end

  -- save changes
  if changed then
    save_data_file()
  end
end

-- randomizes the playlist based on the ratings
-- higher ratings have a higher chance to be higher up
-- in the playlist
function randomize_playlist()
  vlc.msg.dbg(prefix .. "randomizing playlist")
  vlc.playlist.stop() -- stop the current song, takes some time

  -- create a table with all songs
  local queue = {}

  -- add songs to queue
  for path, weight in pairs(played) do
    table.insert(queue, { path = path, weight = weight })
  end

  -- Bug Fix 4: Handle empty playlist
  if #queue > 0 then
    -- sort in descending order
    table.sort(queue, function(a, b) return a.weight > b.weight end)

    -- clear the playlist before adding items back
    vlc.playlist.clear()

    -- add items to the playlist based on their weights
    for _, item in ipairs(queue) do
      vlc.playlist.enqueue({{path = item.path}})
    end
  end

  -- wait until the current song stops playing
  -- to start the song at the beginning of the playlist
  while vlc.playlist.current() ~= nil do
    vlc.misc.mwait(100)
  end
  vlc.playlist.play()
end

-- IO operations --

-- Loads the data from the data file
function load_data_file()
  -- open file
  local file, err = io.open(data_file, "r")
  store = {}
  if err then
    vlc.msg.warn(prefix .. "data file does not exist, creating...")
    file, err = io.open(data_file, "w")
    if err then
      vlc.msg.err(prefix .. "unable to open data file.. exiting")
      vlc.deactivate()
      return
    end
  else
    -- file successfully opened
    vlc.msg.info(prefix .. "data file successfully opened")
    for line in file:lines() do
      -- csv layout is `path,playcount,skipcount,timestamp`
      local fields = {}
      for field in line:gmatch("[^,]+") do
        table.insert(fields, field)
      end
      if #fields == 4 then
        local path, playcount, skipcount, timestamp = unpack(fields)
        store[path] = {
          playcount = tonumber(playcount),
          skipcount = tonumber(skipcount),
          time = tonumber(timestamp)
        }
      else
        vlc.msg.warn(prefix .. "invalid line in data file: " .. line)
      end
    end
  end
  io.close(file)
end

function save_data_file()
  local file, err = io.open(data_file, "w")
  if err then
    vlc.msg.err(prefix .. "Unable to open data file.. exiting")
    vlc.deactivate()
    return
  else
    for path, item in pairs(store) do
      file:write(string.format("%s,%d,%d,%d\n", path, item.playcount, item.skipcount, item.time))
    end
  end
  io.close(file)
end

-- Listeners --

-- called when the playing status changes
-- detects if playing items are skipped or ending normally
-- derates the songs accordingly
function playing_changed()
  local item = vlc.input.item()

  -- Bug Fix 5: Check for nil values in playing_changed()
  if item ~= nil then
    local time = vlc.var.get(vlc.object.input(), "time")
    local total = item:duration()
    local path = vlc.strings.decode_uri(item:uri())

    if last_played ~= path then
      vlc.msg.info(prefix .. "song ended: " .. item:name())
      last_played = path

      time = math.floor(time / 1000000)
      total = math.floor(total)

      -- when the current time == total time,
      -- then the song ended normally
      -- if there is remaining time, the song was skipped
      if store[path] then
        if time < total * 0.9 then
          vlc.msg.info(prefix .. "skipped song at " .. (math.floor(time / total * 10000 + 0.5) / 100) .. "%")

          store[path].skipcount = store[path].skipcount + 1
          played[path] = adjust_like_on_skip(played[path])
        else
          store[path].playcount = store[path].playcount + 1
          played[path] = adjust_like_on_full_play(played[path])
        end

        -- save the song in the database with updated time
        store[path].time = os.time()
        save_data_file()
      end
    end
  end
end

function meta_changed() end
