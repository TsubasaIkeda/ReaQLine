--[[
  reaqline/transport.lua
  再生制御、ループ範囲の追従、曲末処理、再生位置への追従。

  ループの考え方:
    スクリプトは、再生中のセクションに合わせて REAPER のループ範囲
    (タイムセレクション)を更新し続ける。リピートの ON/OFF には関与しない。

    オペレータは、回したいセクションを鳴らしている最中に REAPER 標準の
    「Transport: Toggle repeat」を叩けばそのセクションが回り、
    もう一度叩けば抜ける。スクリプトへの MIDI アサインは不要。

    ループ動作自体は REAPER のオーディオエンジンが処理するため、
    サンプル精度で defer のジッタの影響を受けない。

    セクションに LOOP 指定がある場合のみ、そこへ入った時点で自動的に
    リピートを ON にする。指定が無いセクションではリピートに触れない。
--]]

local CFG   = require 'reaqline.config'
local Model = require 'reaqline.model'

local M = {}
local S

function M.init(state)
  S = state
end

--------------------------------------------------------------------------------
-- ループ範囲とリピート
--------------------------------------------------------------------------------

-- 自分で書き換えた範囲は追従の対象外にする(last_ts_* を同期)。
function M.setLoopRange(a, b)
  reaper.GetSet_LoopTimeRange(true, true, a, b, false)
  S.last_ts_s, S.last_ts_e = a, b
end

function M.syncLoopRange(section)
  if not section then return end
  M.setLoopRange(section.pos, section.endpos)
end

function M.repeatOn()  reaper.GetSetRepeat(1) end
function M.repeatOff() reaper.GetSetRepeat(0) end

--------------------------------------------------------------------------------
-- 開始 / 停止
--------------------------------------------------------------------------------

function M.startAt(index)
  local s = S.songs[index]
  if not s then return end

  M.repeatOff()

  S.playing_idx = index
  S.play_song   = s
  S.cur_section = nil
  S.sel_song    = index
  S.status_msg  = '再生: ' .. s.name

  reaper.SetEditCurPos(s.pos, true, false)

  -- 曲頭のセクション範囲を先に用意しておく
  local first = s.sections[1]
  if first and s.pos >= first.pos - 1e-6 then
    M.setLoopRange(first.pos, first.endpos)
  else
    M.setLoopRange(s.pos, first and first.pos or s.rgnend)
  end

  if not S.tp.playing then reaper.CSurf_OnPlay() end
end

function M.stopAll(msg)
  M.repeatOff()
  reaper.OnStopButton()

  -- 停止指示直後は GetPlayState がまだ再生中を返す場合があるため、
  -- 実際に停止するまで再取り込みを止める
  S.adopt_block = true

  S.playing_idx = nil
  S.play_song   = nil
  S.cur_section = nil
  S.loop_active = nil
  S.status_msg  = msg or '停止'
end

--------------------------------------------------------------------------------
-- 曲末処理
--   次の曲が FOLLOW 指定の場合
--     リージョンが隣接している場合 … 何もせず再生を継続し、管理対象だけ
--                                    切り替える。シークが無いので継ぎ目が出ない。
--     間隔が空いている場合         … 次曲の頭へシークして再生を継続する。
--   FOLLOW 指定でない場合
--     停止し、編集カーソルを次曲の頭へ移動する。
--     カーソル追従により次曲が選択状態になる。
--------------------------------------------------------------------------------

function M.handleSongEnd()
  local idx  = S.playing_idx
  local name = S.play_song and S.play_song.name or ''
  local nxt  = idx and S.songs[idx + 1] or nil

  if nxt and nxt.follow then
    local gap = nxt.pos - S.play_song.rgnend

    M.repeatOff()
    S.playing_idx = idx + 1
    S.play_song   = nxt
    S.cur_section = nil
    S.sel_song    = S.playing_idx
    S.sel_section = 1
    S.scroll_song = true
    S.scroll_sec  = true

    if gap > CFG.ADJ_TOL then
      reaper.SetEditCurPos(nxt.pos, true, true)
      S.status_msg = string.format('FOLLOW(シーク): %s  →  %s', name, nxt.name)
    else
      S.status_msg = string.format('FOLLOW(連続): %s  →  %s', name, nxt.name)
    end
    return
  end

  M.stopAll('曲終了: ' .. name)

  if nxt then
    -- 停止処理でカーソルが動く場合があるため、停止後に移動させる
    reaper.SetEditCurPos(nxt.pos, true, false)
    S.sel_song    = idx + 1
    S.sel_section = 1
    S.scroll_song = true
    S.scroll_sec  = true
    S.status_msg  = S.status_msg .. '  →  次: ' .. nxt.name
  end
end

--------------------------------------------------------------------------------
-- その他の操作
--------------------------------------------------------------------------------

-- ループから抜ける。リピートを切るだけで、シークは発生しない。
-- 同じことは REAPER 標準の「Transport: Toggle repeat」でも行える。
function M.requestNext()
  if S.tp.repeat_on then
    M.repeatOff()
    S.status_msg = 'ループ解除'
  else
    S.status_msg = 'ループしていません'
  end
end

-- スクリプト外で始まった再生を、自動的に管理下に取り込む。
function M.adopt()
  local idx = Model.songIndexAt(S.tp.pos)
  if not idx then return end
  S.playing_idx = idx
  S.play_song   = S.songs[idx]
  S.sel_song    = idx
  S.cur_section = Model.sectionAt(S.play_song, S.tp.pos)
  S.loop_active = nil
  S.status_msg  = '再生を取り込み: ' .. S.play_song.name
end

-- リハーサル用。セクション頭へ即時シーク。
function M.seekToSection(song, section)
  if not song or not section then return end
  M.repeatOff()
  reaper.SetEditCurPos(section.pos, true, true)
  S.cur_section = section
  S.status_msg  = 'セクションへ移動: ' .. section.name
end

--------------------------------------------------------------------------------
-- 再生位置 / カーソルへの追従 (常時有効・無効化不可)
--   再生中 … 再生位置を基準にする
--   停止中 … 編集カーソルとタイムセレクションの変化を基準にする
--   停止中は「実際に動いた時だけ」反応するため、選択操作とは競合しない。
--
--   セクションの選択は「次のセクション」に置く。
--   現在地は表の '>' マークで示されるため、現在と次が同時に読める。
--------------------------------------------------------------------------------

function M.followPlayhead()
  local target = nil

  if S.tp.playing then
    target = S.tp.pos
    -- 停止に戻った瞬間に誤検出しないよう、観測値を同期しておく
    S.last_cursor = reaper.GetCursorPosition()
    S.last_ts_s, S.last_ts_e = reaper.GetSet_LoopTimeRange(false, true, 0, 0, false)
  else
    local cpos = reaper.GetCursorPosition()
    if math.abs(cpos - S.last_cursor) > 1e-9 then
      S.last_cursor = cpos
      target = cpos
    end

    -- ルーラーのリージョンレーンをクリックした場合はタイムセレクションが動く。
    local ts_s, ts_e = reaper.GetSet_LoopTimeRange(false, true, 0, 0, false)
    if math.abs(ts_s - S.last_ts_s) > 1e-9 or math.abs(ts_e - S.last_ts_e) > 1e-9 then
      S.last_ts_s, S.last_ts_e = ts_s, ts_e
      if ts_e > ts_s then target = ts_s end
    end
  end

  if not target then return end

  local idx = Model.songIndexAt(target)
  if not idx then return end

  if S.sel_song ~= idx then
    S.sel_song    = idx
    S.scroll_song = true
  end

  local song = S.songs[idx]
  local sec  = Model.sectionAt(song, target)
  local n    = #song.sections
  local si   = (sec and sec.index or 0) + 1
  if si > n then si = n end
  if si < 1 then si = 1 end

  if n > 0 and S.sel_section ~= si then
    S.sel_section = si
    S.scroll_sec  = true
  end
end

--------------------------------------------------------------------------------
-- 毎フレームの進行管理
--------------------------------------------------------------------------------

function M.update()
  local st = reaper.GetPlayState()
  local tp = S.tp
  tp.playing   = (st & 1) ~= 0
  tp.paused    = (st & 2) ~= 0
  tp.recording = (st & 4) ~= 0
  -- リピートは REAPER 側で直接操作されうるので、毎フレーム観測する
  tp.repeat_on = reaper.GetSetRepeat(-1) == 1
  tp.pos       = tp.playing and reaper.GetPlayPosition() or reaper.GetCursorPosition()

  M.followPlayhead()

  if not tp.playing then S.adopt_block = false end

  -- 管理外で再生されている場合は自動的に取り込む
  if tp.playing and not S.playing_idx and not S.adopt_block then
    M.adopt()
  end

  if not S.playing_idx or not S.play_song then return end

  -- ユーザーが REAPER 側で停止した場合に追従する
  if not tp.playing then
    M.stopAll('停止されました')
    return
  end

  -- 曲終端で停止。ループ中は終端を越えないためここには到達しない。
  if tp.pos >= S.play_song.rgnend - CFG.END_EPS then
    M.handleSongEnd()
    return
  end

  -- セクションが変わった時に、ループ範囲をそのセクションへ合わせる。
  -- リピート中は同一セクション内で折り返すため、ここは発火しない。
  -- したがって「セクションを跨いだ」= リピートは切られていた、と言える。
  local sec = Model.sectionAt(S.play_song, tp.pos)
  if sec ~= S.cur_section then
    S.cur_section = sec
    if sec then
      M.syncLoopRange(sec)
      if sec.loop then M.repeatOn() end
    end
  end

  -- 表示用。リピートが有効で、かつ範囲が現在のセクションを指している状態。
  S.loop_active = (tp.repeat_on and S.cur_section) or nil
end

return M
