-- Loaded by VLC's own Lua 5.1 engine during the native smoke test.
local source = os.getenv("HISTORY_SHUFFLE_SOURCE")
if not source or source == "" then
    vlc.msg.err("[History Shuffle native check] missing HISTORY_SHUFFLE_SOURCE")
    vlc.misc.quit()
    return
end

local chunk, load_error = loadfile(source)
if not chunk then
    vlc.msg.err("[History Shuffle native check] LOAD FAILED: " .. tostring(load_error))
    vlc.misc.quit()
    return
end

local standard_rawget = rawget
rawget = nil -- VLC's extension sandbox does not expose this standard Lua helper.
local executed, execute_error = pcall(chunk)
rawget = standard_rawget
if not executed then
    vlc.msg.err("[History Shuffle native check] EXECUTION FAILED: " .. tostring(execute_error))
    vlc.misc.quit()
    return
end

if type(descriptor) ~= "function" then
    vlc.msg.err("[History Shuffle native check] DESCRIPTOR MISSING")
    vlc.misc.quit()
    return
end

local described, description = pcall(descriptor)
if not described or type(description) ~= "table" or description.title ~= "History Shuffle" then
    vlc.msg.err("[History Shuffle native check] DESCRIPTOR FAILED: " .. tostring(description))
    vlc.misc.quit()
    return
end

local json_ok = pcall(require, "dkjson")
if not json_ok then
    vlc.msg.err("[History Shuffle native check] DKJSON MISSING")
    vlc.misc.quit()
    return
end

vlc.msg.info("[History Shuffle native check] PASS v" .. tostring(description.version))
vlc.misc.quit()
