--[[
  reaqline/ui_live.lua
  本番タブ。大きな表示とボタンのみ。運用中はこちらを使う。

  ボタン構成は REAPER の再生状況に応じて変わる。
    停止中 … [GO] [NEXT(無効)]
    再生中 … [STOP] [NEXT]
  管理外で始まった再生は自動的に取り込まれるため、専用の操作は不要。
--]]

local CFG   = require 'reaqline.config'
local Gui   = require 'reaqline.imgui'
local W     = require 'reaqline.widgets'
local Model = require 'reaqline.model'
local Trans = require 'reaqline.transport'

local M = {}
local S

function M.init(state) S = state end

-- 現在のトランスポート状態を短い文字列で返す
local function transportLabel()
  local COL = CFG.COL
  if S.tp.recording then return 'REC',   COL.rec_text end
  if S.tp.paused    then return 'PAUSE', COL.dim_text end
  if S.tp.playing   then return 'PLAY',  COL.dim_text end
  return 'STOP', COL.dim_text
end

function M.draw()
  local ImGui, ctx = Gui.ImGui, Gui.ctx
  local COL = CFG.COL

  local avail_w       = ImGui.GetContentRegionAvail(ctx)
  local f_head, f_body = Gui.pickFonts(avail_w)

  local managed = S.play_song ~= nil and S.tp.playing
  local pos     = S.tp.pos

  ImGui.Dummy(ctx, 0, 4)

  -- 状態バッジ
  local tl, tcol = transportLabel()
  W.textCol(tcol, tl)

  -- 曲名
  Gui.pushFont(f_head)
  if managed then
    ImGui.Text(ctx, string.format('%02d  %s', S.playing_idx, S.play_song.name))
  else
    local s = S.songs[S.sel_song]
    W.textCol(COL.dim_text,
              s and string.format('%02d  %s', S.sel_song, s.name)
                or '(曲がありません)')
  end
  Gui.popFont()

  ImGui.Dummy(ctx, 0, 2)

  -- セクションと残り時間。幅が狭い時は折り返す。
  Gui.pushFont(f_body)
  if managed then
    local sec_name = S.cur_section and S.cur_section.name or '(先頭)'
    local sec_rem  = S.cur_section and (S.cur_section.endpos - pos) or nil
    local song_rem = S.play_song.rgnend - pos

    if S.loop_active then
      W.textCol(COL.loop_text, 'LOOP  ' .. sec_name)
    else
      ImGui.Text(ctx, sec_name)
    end

    local wrap = avail_w < CFG.BP_NARROW
    if not wrap then ImGui.SameLine(ctx) end

    local col = (sec_rem and sec_rem <= CFG.WARN_SEC and not S.loop_active)
                and COL.warn_text or COL.dim_text
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, col)
    ImGui.Text(ctx, string.format('%s残り %s',
                                  wrap and '' or '   ', W.fmtTime(sec_rem)))
    ImGui.PopStyleColor(ctx)

    ImGui.SameLine(ctx)
    local scol = (song_rem <= CFG.WARN_SEC) and COL.warn_text or COL.dim_text
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, scol)
    ImGui.Text(ctx, string.format('   曲残り %s', W.fmtTime(song_rem)))
    ImGui.PopStyleColor(ctx)
  else
    W.textCol(COL.dim_text, '待機')
  end
  Gui.popFont()

  ImGui.Dummy(ctx, 0, 4)

  -- プログレスバー。高さも幅に追従させる。
  local bar_h = W.clamp(avail_w / 40, 12, 26)
  local sec_frac, song_frac = 0, 0
  if managed then
    if S.cur_section then
      local len = S.cur_section.endpos - S.cur_section.pos
      if len > 0 then
        sec_frac = W.clamp((pos - S.cur_section.pos) / len, 0, 1)
      end
    end
    local slen = S.play_song.rgnend - S.play_song.pos
    if slen > 0 then
      song_frac = W.clamp((pos - S.play_song.pos) / slen, 0, 1)
    end
  end

  ImGui.PushStyleColor(ctx, ImGui.Col_PlotHistogram,
                       S.loop_active and COL.bar_loop or COL.bar)
  ImGui.ProgressBar(ctx, sec_frac, -1, bar_h, 'SECTION')
  ImGui.PopStyleColor(ctx)

  ImGui.PushStyleColor(ctx, ImGui.Col_PlotHistogram, COL.bar)
  ImGui.ProgressBar(ctx, song_frac, -1, bar_h * 0.65, 'SONG')
  ImGui.PopStyleColor(ctx)

  ImGui.Dummy(ctx, 0, 2)

  -- 次のセクション / 次の曲
  if managed then
    local nx = Model.nextSectionOf(S.play_song, S.cur_section)
    W.textCol(COL.dim_text, '次のセクション: ' .. (nx and nx.name or '(曲の終わり)'))

    local ns = S.songs[S.playing_idx + 1]
    if ns and ns.follow then
      W.textCol(COL.loop_text, '次の曲: ' .. ns.name .. '   [FOLLOW]')
    else
      W.textCol(COL.dim_text, '次の曲: ' .. (ns and ns.name or '(最終曲)'))
    end
  else
    local ns = S.songs[S.sel_song]
    W.textCol(COL.dim_text, '選択中: ' .. (ns and ns.name or '—'))
    W.textCol(COL.dim_text, ' ')
  end

  ImGui.Dummy(ctx, 0, 6)

  -- 操作ボタン
  local spacing = 8
  local bw      = (avail_w - spacing) / 2
  local bh      = W.clamp(avail_w / 11, 44, 88)

  Gui.pushFont(f_body)

  if S.tp.playing then
    if W.bigButton('STOP', bw, bh, COL.stop, COL.stop_hi, true) then
      Trans.stopAll()
    end
    ImGui.SameLine(ctx, 0, spacing)
    if W.bigButton('NEXT', bw, bh, COL.next, COL.next_hi, S.loop_active ~= nil) then
      Trans.requestNext()
    end
  else
    if W.bigButton('GO', bw, bh, COL.go, COL.go_hi, #S.songs > 0) then
      Trans.startAt(S.sel_song)
    end
    ImGui.SameLine(ctx, 0, spacing)
    W.bigButton('NEXT', bw, bh, COL.next, COL.next_hi, false)
  end

  Gui.popFont()
end

return M
