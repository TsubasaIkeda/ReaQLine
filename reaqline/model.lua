--[[
  reaqline/model.lua
  プロジェクト構造の読み取りと、設定の保存・復元。

  前提:
    リージョン = 曲。曲順はタイムライン上の並び順で確定する。
    マーカー   = 曲内のセクション。
    セクションの終端は、次のマーカー位置、なければリージョン終端。

  曲順の情報はスクリプト側に持たない。
  ループ設定は「曲名 + セクション名」、FOLLOW 設定は「曲名」で識別するため、
  マーカーやリージョンを時間軸上で移動しても設定は維持される。
--]]

local CFG = require 'reaqline.config'

local M = {}
local S    -- 共有状態

function M.init(state)
  S = state
end

--------------------------------------------------------------------------------
-- 設定の保存 / 復元
--------------------------------------------------------------------------------

function M.loopKey(song_name, section_name)
  return song_name .. '\t' .. section_name
end

local function saveSet(key, set)
  local buf = {}
  for k, v in pairs(set) do
    if v then buf[#buf + 1] = k end
  end
  table.sort(buf)
  reaper.SetProjExtState(0, CFG.EXT_SECTION, key, table.concat(buf, '\n'))
end

local function loadSet(key)
  local out = {}
  local _, str = reaper.GetProjExtState(0, CFG.EXT_SECTION, key)
  if not str or str == '' then return out end
  for line in str:gmatch('[^\n]+') do
    out[line] = true
  end
  return out
end

function M.saveLoopFlags()   saveSet(CFG.KEY_LOOPS,  S.loop_flags)   end
function M.saveFollowFlags() saveSet(CFG.KEY_FOLLOW, S.follow_flags) end

function M.loadFlags()
  S.loop_flags   = loadSet(CFG.KEY_LOOPS)
  S.follow_flags = loadSet(CFG.KEY_FOLLOW)
end

--------------------------------------------------------------------------------
-- 走査
--------------------------------------------------------------------------------

-- リージョンとマーカーを一度に走査し、マーカーを内包するリージョンへ割り当てる。
-- どのリージョンにも含まれないマーカーは無視する(曲間の作業用マーカー等)。
function M.scan()
  local list    = {}
  local markers = {}

  local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
  local total = num_markers + num_regions

  for i = 0, total - 1 do
    local retval, isrgn, pos, rgnend, name, idx = reaper.EnumProjectMarkers3(0, i)
    if retval then
      if isrgn then
        list[#list + 1] = {
          name     = (name ~= '' and name) or ('Region ' .. tostring(idx)),
          pos      = pos,
          rgnend   = rgnend,
          sections = {},
        }
      else
        markers[#markers + 1] = {
          name = (name ~= '' and name) or ('Marker ' .. tostring(idx)),
          pos  = pos,
        }
      end
    end
  end

  for _, m in ipairs(markers) do
    for _, r in ipairs(list) do
      if m.pos >= r.pos - 1e-6 and m.pos < r.rgnend then
        r.sections[#r.sections + 1] = { name = m.name, pos = m.pos }
        break
      end
    end
  end

  for _, r in ipairs(list) do
    r.follow = S.follow_flags[r.name] == true
    table.sort(r.sections, function(a, b) return a.pos < b.pos end)
    for i, s in ipairs(r.sections) do
      local nxt = r.sections[i + 1]
      s.endpos = nxt and nxt.pos or r.rgnend
      s.index  = i
      s.loop   = S.loop_flags[M.loopKey(r.name, s.name)] == true
    end
  end

  return list
end

function M.rescan()
  S.songs = M.scan()
  if S.sel_song > #S.songs then
    S.sel_song = math.max(1, #S.songs)
  end
  S.status_msg = string.format('%d 曲を検出', #S.songs)
end

--------------------------------------------------------------------------------
-- 位置からの検索
--------------------------------------------------------------------------------

-- 指定位置が属するセクションを返す。最初のマーカーより手前は nil。
function M.sectionAt(song, pos)
  if not song then return nil end
  local found = nil
  for _, s in ipairs(song.sections) do
    if pos >= s.pos - 1e-6 then found = s else break end
  end
  return found
end

-- セクションの次を返す。無ければ nil。
function M.nextSectionOf(song, section)
  if not song or not section then return nil end
  return song.sections[section.index + 1]
end

function M.songIndexAt(pos)
  for i, s in ipairs(S.songs) do
    if pos >= s.pos - 1e-6 and pos < s.rgnend then return i end
  end
  return nil
end

-- 表示対象の曲。再生中はその曲、停止中は選択曲。
function M.paneTargetSong()
  return S.play_song or S.songs[S.sel_song]
end

return M
