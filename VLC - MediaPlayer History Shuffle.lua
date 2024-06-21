-- Global variables
local played = {} -- holds all music items from the current playlist
local store = {} -- holds all music items from the database
local day_in_seconds = 60 * 60 * 24
local last_played = ""
local prefix = "[HShuffle] "
local data_file = ""

-- Helper functions
function calculate_like(playcount, skipcount)
  local like = 100 + (playcount * 3) - (skipcount * 5)
  return math.max(0, math.min(like, 200))
end

function adjust_like_on_skip(like)
  return math.max(0, like * 0.95)
end

function adjust_like_on_full_play(like)
  return math.min(200, like + 10)
end

function descriptor()
  return {
    title = "VLC MediaPlayer History Shuffle",
    version = "1.1.0",
    shortdesc = "Shuffle Media Player",
    description = "Shuffles Media Player items based on song likes and listening history",
    author = "R. Crandon",
    capabilities = { "playing-listener" }
  }
end

function activate()
  vlc.msg.info(prefix .. "starting")
  math.randomseed(os.time())
  data_file = vlc.config.userdatadir() .. vlc.config.dir_separator() .. "better_playlist_data.csv"
  vlc.msg.info(prefix .. "using data file " .. data_file)
  load_data_file()
  init_playlist()
  randomize_playlist()
  vlc.playlist.repeat_("off")
end

function deactivate()
  vlc.msg.info(prefix .. "deactivating.. Bye!")
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
        played[path] = calculate_like(store[path].playcount, store[path].skipcount)
      else
        played[path] = 100
        store[path] = { playcount = 0, skipcount = 0, time = time }
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
    local total_weight = 0
    for _, item in ipairs(queue) do
      total_weight = total_weight + item.weight
    end

    while #queue > 0 do
      local rand = math.random() * total_weight
      local sum = 0
      for i, item in ipairs(queue) do
        sum = sum + item.weight
        if sum >= rand then
          vlc.playlist.enqueue({{path = item.path}})
          total_weight = total_weight - item.weight
          table.remove(queue, i)
          break
        end
      end
    end
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
    file, err = io.open(data_file, "w")
    if err then
      vlc.msg.err(prefix .. "unable to open data file.. exiting")
      vlc.deactivate()
      return
    end
  else
    vlc.msg.info(prefix .. "data file successfully opened")
    for line in file:lines() do
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
        if time < total * 0.9 then
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
