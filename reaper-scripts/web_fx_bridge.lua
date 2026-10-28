-- web_fx_bridge.lua
-- Exposes track FX (names, bypass, parameters) to the REAPER web remote (faders.html)
-- via ExtState, and applies FX / visibility commands sent from the page.
--
-- State:    ExtState WEBFX/state  = JSON (strings percent-encoded, so no quotes/backslashes)
--           ExtState WEBFX/alive  = timestamp, so the page can tell the bridge is running
-- Commands: ExtState WEBFX/cmd0..cmd7 = "seq|op|a|b|c|d" (written round-robin by the page)
--   op=p  track fx param value   -> p|track|fx|param|normalized
--   op=b  fx enabled             -> b|track|fx|0/1
--   op=v  track visible          -> v|track|0/1
--   op=o  open fx floating UI    -> o|track|fx
--   op=e  ReaEQ band enabled     -> e|track|fx|band|0/1
--   op=y  ReaEQ band type        -> y|track|fx|band|type
--   ExtState WEBFX/lut = JSON {guid:{param:[129 numeric samples of 0..1]}} for ReaEQ/ReaComp,
--   so the page can convert between normalized values and Hz/dB/ms.

local SEC = "WEBFX"
local MAX_PARAMS = 64
local last_seq = -1
local last_state = ""
local last_build = 0
local lut_cache = {}   -- guid -> json fragment
local last_lut = ""
local LUT_N = 128
-- single instance: a newer launch takes ownership and older loops exit
local token = string.format("%.6f", reaper.time_precise())
reaper.SetExtState(SEC, "owner", token, false)

local function enc(s)
  return (tostring(s):gsub("[^%w%-%._~ ]", function(c) return string.format("%%%02X", c:byte()) end))
end

local function track_at(idx)
  if idx == 0 then return reaper.GetMasterTrack(0) end
  return reaper.GetTrack(0, idx - 1)
end

local function fx_kind(name)
  if name:find("ReaEQ") then return "eq" end
  if name:find("ReaComp") then return "comp" end
  return ""
end

local function num(s)
  if s:find("%-inf") then return -150 end
  if s:find("inf") then return 1000 end
  return tonumber(s:match("[-+]?%d+%.?%d*")) or 0
end

local function build_lut(tr, f, np)
  local ps = {}
  for p = 0, math.min(np, MAX_PARAMS) - 1 do
    local vals = {}
    for k = 0, LUT_N do
      local _, s = reaper.TrackFX_FormatParamValueNormalized(tr, f, p, k / LUT_N, "")
      vals[#vals + 1] = string.format("%.6g", num(s))
    end
    ps[#ps + 1] = string.format('"%d":[%s]', p, table.concat(vals, ","))
  end
  return "{" .. table.concat(ps, ",") .. "}"
end

-- channel spec -> "1-2" / "3" (1-based); low 10 bits = first channel, bits 10+ = count code (0 stereo, 1 mono, n = 2n ch)
local function chans(v, hw)
  v = math.floor(v)
  if v < 0 then return "-" end
  local idx, code = v & 1023, (v >> 10) & 1023
  local pre = ""
  if hw and idx & 512 ~= 0 then idx = idx & 511; pre = "RA" end
  local n = code == 0 and 2 or code == 1 and 1 or code * 2
  return pre .. (n == 1 and tostring(idx + 1) or (idx + 1) .. "-" .. (idx + n))
end

-- routing labels in web-API order: hardware outputs first, then sends; receives separately
local function routing(tr)
  local sd, rc = {}, {}
  for _, cat in ipairs({ 1, 0 }) do
    for k = 0, reaper.GetTrackNumSends(tr, cat) - 1 do
      local src = reaper.GetTrackSendInfo_Value(tr, cat, k, "I_SRCCHAN")
      local dst = reaper.GetTrackSendInfo_Value(tr, cat, k, "I_DSTCHAN")
      sd[#sd + 1] = '"' .. chans(src) .. ">" .. chans(dst, cat == 1) .. '"'
    end
  end
  for k = 0, reaper.GetTrackNumSends(tr, -1) - 1 do
    local src = reaper.GetTrackSendInfo_Value(tr, -1, k, "I_SRCCHAN")
    local dst = reaper.GetTrackSendInfo_Value(tr, -1, k, "I_DSTCHAN")
    rc[#rc + 1] = '"' .. chans(src) .. ">" .. chans(dst) .. '"'
  end
  return table.concat(sd, ","), table.concat(rc, ",")
end

local function build_state()
  local out, luts = {}, {}
  local n = reaper.CountTracks(0)
  for t = 0, n do
    local tr = track_at(t)
    if tr then
      local vis = reaper.GetMediaTrackInfo_Value(tr, "B_SHOWINTCP") > 0.5
               or reaper.GetMediaTrackInfo_Value(tr, "B_SHOWINMIXER") > 0.5
      if t == 0 then vis = true end
      local fxs = {}
      for f = 0, reaper.TrackFX_GetCount(tr) - 1 do
        local _, name = reaper.TrackFX_GetFXName(tr, f, "")
        local params = {}
        local np = reaper.TrackFX_GetNumParams(tr, f)
        for p = 0, math.min(np, MAX_PARAMS) - 1 do
          local _, pn = reaper.TrackFX_GetParamName(tr, f, p, "")
          local v = reaper.TrackFX_GetParamNormalized(tr, f, p)
          local _, fv = reaper.TrackFX_GetFormattedParamValue(tr, f, p, "")
          params[#params + 1] = string.format('["%s",%.4f,"%s"]', enc(pn), v, enc(fv))
        end
        local kind = fx_kind(name)
        local guid = reaper.TrackFX_GetFXGUID(tr, f) or ""
        local extra = ""
        if kind == "eq" then
          local bt, be = {}, {}
          for b = 0, 15 do
            local ok, ty = reaper.TrackFX_GetNamedConfigParm(tr, f, "BANDTYPE" .. b)
            if not ok then break end
            local _, en = reaper.TrackFX_GetNamedConfigParm(tr, f, "BANDENABLED" .. b)
            bt[#bt + 1] = tonumber(ty) or 8
            be[#be + 1] = tonumber(en) or 1
          end
          extra = string.format(',"bt":[%s],"be":[%s]', table.concat(bt, ","), table.concat(be, ","))
        elseif kind == "comp" then
          local _, gr = reaper.TrackFX_GetNamedConfigParm(tr, f, "GainReduction_dB")
          extra = string.format(',"gr":%.2f', tonumber(gr) or 0)
        end
        if kind ~= "" then
          if not lut_cache[guid] then lut_cache[guid] = build_lut(tr, f, np) end
          luts[#luts + 1] = '"' .. guid .. '":' .. lut_cache[guid]
        end
        fxs[#fxs + 1] = string.format('{"n":"%s","e":%d,"np":%d,"k":"%s","g":"%s"%s,"p":[%s]}',
          enc(name), reaper.TrackFX_GetEnabled(tr, f) and 1 or 0, np, kind, guid, extra, table.concat(params, ","))
      end
      local ce = reaper.GetMediaTrackInfo_Value(tr, "I_FXEN")
      local sd, rc = routing(tr)
      out[#out + 1] = string.format('"%d":{"v":%d,"ce":%d,"sd":[%s],"rc":[%s],"fx":[%s]}',
        t, vis and 1 or 0, ce, sd, rc, table.concat(fxs, ","))
    end
  end
  local lut = "{" .. table.concat(luts, ",") .. "}"
  if lut ~= last_lut then
    last_lut = lut
    reaper.SetExtState(SEC, "lut", lut, false)
  end
  return "{" .. table.concat(out, ",") .. "}"
end

local function apply(op, a)
  local tr = track_at(tonumber(a[1]) or -1)
  if not tr then return end
  if op == "p" then
    reaper.TrackFX_SetParamNormalized(tr, tonumber(a[2]), tonumber(a[3]), tonumber(a[4]))
  elseif op == "b" then
    reaper.TrackFX_SetEnabled(tr, tonumber(a[2]), a[3] == "1")
  elseif op == "v" then
    local v = tonumber(a[2]) or 1
    reaper.SetMediaTrackInfo_Value(tr, "B_SHOWINTCP", v)
    reaper.SetMediaTrackInfo_Value(tr, "B_SHOWINMIXER", v)
    reaper.TrackList_AdjustWindows(false)
    reaper.Undo_OnStateChangeEx(v == 1 and "Web: show track" or "Web: hide track", 1, -1)
  elseif op == "e" then
    reaper.TrackFX_SetNamedConfigParm(tr, tonumber(a[2]), "BANDENABLED" .. a[3], a[4])
  elseif op == "y" then
    reaper.TrackFX_SetNamedConfigParm(tr, tonumber(a[2]), "BANDTYPE" .. a[3], a[4])
  elseif op == "o" then
    reaper.TrackFX_Show(tr, tonumber(a[2]), 3)
  end
end

local function poll_cmds()
  local cmds = {}
  for i = 0, 7 do
    local s = reaper.GetExtState(SEC, "cmd" .. i)
    if s ~= "" then
      local parts = {}
      for x in (s .. "|"):gmatch("([^|]*)|") do parts[#parts + 1] = x end
      local seq = tonumber(parts[1])
      -- page reload restarts seq at a random base; accept anything not yet seen
      if seq and seq ~= last_seq then cmds[#cmds + 1] = { seq = seq, parts = parts } end
      reaper.DeleteExtState(SEC, "cmd" .. i, false)
    end
  end
  table.sort(cmds, function(x, y) return x.seq < y.seq end)
  for _, c in ipairs(cmds) do
    local op = c.parts[2]
    local args = {}
    for k = 3, #c.parts do args[#args + 1] = c.parts[k] end
    apply(op, args)
    last_seq = c.seq
  end
  return #cmds > 0
end

-- rate the FX actually run at: the running audio device, else the project setting
local function sample_rate()
  local ok, sr = reaper.GetAudioDeviceInfo("SRATE")
  sr = ok and tonumber(sr) or 0
  if sr <= 0 then sr = reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false) end
  if sr <= 0 then sr = 48000 end
  return sr
end

local function loop()
  if reaper.GetExtState(SEC, "owner") ~= token then return end
  local changed = poll_cmds()
  local now = reaper.time_precise()
  if changed or now - last_build > 0.15 then
    last_build = now
    local s = build_state()
    if s ~= last_state then
      last_state = s
      reaper.SetExtState(SEC, "state", s, false)
    end
    reaper.SetExtState(SEC, "alive", string.format("%.1f", now), false)
    reaper.SetExtState(SEC, "srate", string.format("%d", sample_rate()), false)
  end
  reaper.defer(loop)
end

reaper.atexit(function()
  if reaper.GetExtState(SEC, "owner") ~= token then return end
  reaper.DeleteExtState(SEC, "alive", false)
  reaper.DeleteExtState(SEC, "state", false)
  reaper.DeleteExtState(SEC, "lut", false)
  reaper.DeleteExtState(SEC, "srate", false)
end)

loop()
