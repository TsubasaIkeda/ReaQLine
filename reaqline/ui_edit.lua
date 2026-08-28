--[[
  reaqline/ui_edit.lua
  編集タブ。曲一覧とセクション表。

  FOLLOW … その曲は「前の曲が終わったら自動で始まる」。
  LOOP   … そのセクションへ入った時点で自動的にリピートを ON にする。
           指定が無いセクションではリピートに触れないので、
           オペレータの手動操作と衝突しない。

  レイアウトは幅に応じて縦積み / 横並びが切り替わる。
--]]

local CFG   = require 'reaqline.config'
local Gui   = require 'reaqline.imgui'
local W     = require 'reaqline.widgets'
local Model = require 'reaqline.model'
local Trans = require 'reaqline.transport'

local M = {}
local S

function M.init(state) S = state end

--------------------------------------------------------------------------------
-- 曲一覧
--------------------------------------------------------------------------------

local function drawSongList(w, h)
  local ImGui, ctx = Gui.ImGui, Gui.ctx
  local COL = CFG.COL

  ImGui.Text(ctx, '曲 (リージョン順)')

  if ImGui.BeginTable(ctx, 'songtbl', 5, W.tableFlags(), w, h) then
    ImGui.TableSetupColumn(ctx, '#',      ImGui.TableColumnFlags_WidthFixed, 32)
    ImGui.TableSetupColumn(ctx, '曲名',   ImGui.TableColumnFlags_WidthStretch)
    ImGui.TableSetupColumn(ctx, '長さ',   ImGui.TableColumnFlags_WidthFixed, 56)
    ImGui.TableSetupColumn(ctx, 'FOLLOW', ImGui.TableColumnFlags_WidthFixed, 60)
    ImGui.TableSetupColumn(ctx, 'LOOP',   ImGui.TableColumnFlags_WidthFixed, 48)
    ImGui.TableSetupScrollFreeze(ctx, 0, 1)
    ImGui.TableHeadersRow(ctx)

    for i, s in ipairs(S.songs) do
      ImGui.TableNextRow(ctx)
      ImGui.PushID(ctx, i)

      local nloop = 0
      for _, sec in ipairs(s.sections) do
        if sec.loop then nloop = nloop + 1 end
      end

      ImGui.TableSetColumnIndex(ctx, 0)
      if S.playing_idx == i then
        W.textCol(COL.loop_text, '>')
      else
        ImGui.Text(ctx, string.format('%02d', i))
      end

      ImGui.TableSetColumnIndex(ctx, 1)
      if ImGui.Selectable(ctx, s.name, S.sel_song == i) then
        S.sel_song    = i
        S.sel_section = 1
      end
      if S.sel_song == i and S.scroll_song then
        ImGui.SetScrollHereY(ctx, 0.5)
      end
      if ImGui.IsItemHovered(ctx) and ImGui.IsMouseDoubleClicked(ctx, 0) then
        Trans.startAt(i)
      end

      ImGui.TableSetColumnIndex(ctx, 2)
      ImGui.Text(ctx, W.fmtTime(s.rgnend - s.pos))

      -- FOLLOW: この曲は前の曲に続いて自動で始まる。
      ImGui.TableSetColumnIndex(ctx, 3)
      local fchanged, fv = ImGui.Checkbox(ctx, '##follow', s.follow)
      if fchanged then
        s.follow = fv
        S.follow_flags[s.name] = fv or nil
        Model.saveFollowFlags()
      end
      -- 1曲目に FOLLOW を付けても効果が無いので注意を出す
      if i == 1 and s.follow then
        ImGui.SameLine(ctx)
        W.textCol(COL.warn_text, '!')
      end

      ImGui.TableSetColumnIndex(ctx, 4)
      if nloop > 0 then
        W.textCol(COL.loop_text, tostring(nloop))
      else
        W.textCol(COL.dim_text, '-')
      end

      ImGui.PopID(ctx)
    end

    ImGui.EndTable(ctx)
    S.scroll_song = false
  end
end

--------------------------------------------------------------------------------
-- セクション表
--------------------------------------------------------------------------------

local function drawSectionTable(w, h)
  local ImGui, ctx = Gui.ImGui, Gui.ctx
  local COL = CFG.COL

  local song = Model.paneTargetSong()

  ImGui.Text(ctx, 'セクション (マーカー)')
  ImGui.SameLine(ctx)
  W.textCol(COL.dim_text, '   > = 現在地 / 選択行 = 次のセクション')

  if ImGui.BeginTable(ctx, 'sectbl', 5, W.tableFlags(), w, h) then
    ImGui.TableSetupColumn(ctx, '',           ImGui.TableColumnFlags_WidthFixed, 20)
    ImGui.TableSetupColumn(ctx, 'LOOP',       ImGui.TableColumnFlags_WidthFixed, 44)
    ImGui.TableSetupColumn(ctx, 'セクション', ImGui.TableColumnFlags_WidthStretch)
    ImGui.TableSetupColumn(ctx, '開始',       ImGui.TableColumnFlags_WidthFixed, 56)
    ImGui.TableSetupColumn(ctx, '長さ',       ImGui.TableColumnFlags_WidthFixed, 56)
    ImGui.TableSetupScrollFreeze(ctx, 0, 1)
    ImGui.TableHeadersRow(ctx)

    if song then
      for i, sec in ipairs(song.sections) do
        ImGui.TableNextRow(ctx)
        ImGui.PushID(ctx, i)

        -- 現在位置マーク
        ImGui.TableSetColumnIndex(ctx, 0)
        if S.loop_active == sec then
          W.textCol(COL.loop_text, '@')
        elseif S.cur_section == sec then
          ImGui.Text(ctx, '>')
        else
          ImGui.Text(ctx, ' ')
        end

        -- ループ設定。表の中で直接切り替える。
        ImGui.TableSetColumnIndex(ctx, 1)
        local changed, v = ImGui.Checkbox(ctx, '##loop', sec.loop)
        if changed then
          sec.loop = v
          S.loop_flags[Model.loopKey(song.name, sec.name)] = v or nil
          Model.saveLoopFlags()
          -- 再生中の当該セクションに対する変更を即座に反映する
          if S.cur_section == sec then
            if v then Trans.repeatOn() else Trans.repeatOff() end
          end
        end

        ImGui.TableSetColumnIndex(ctx, 2)
        if ImGui.Selectable(ctx, sec.name, S.sel_section == i) then
          S.sel_section = i
        end
        if S.sel_section == i and S.scroll_sec then
          ImGui.SetScrollHereY(ctx, 0.5)
        end
        if ImGui.IsItemHovered(ctx) and ImGui.IsMouseDoubleClicked(ctx, 0) then
          Trans.seekToSection(song, sec)
        end

        ImGui.TableSetColumnIndex(ctx, 3)
        ImGui.Text(ctx, W.fmtTime(sec.pos - song.pos))

        ImGui.TableSetColumnIndex(ctx, 4)
        ImGui.Text(ctx, W.fmtTime(sec.endpos - sec.pos))

        ImGui.PopID(ctx)
      end
    end

    ImGui.EndTable(ctx)
    S.scroll_sec = false
  end

  local sec = song and song.sections[S.sel_section]
  if sec and ImGui.Button(ctx, 'このセクションへ移動') then
    Trans.seekToSection(song, sec)
  end
end

--------------------------------------------------------------------------------
-- タブ本体
--------------------------------------------------------------------------------

function M.draw()
  local ImGui, ctx = Gui.ImGui, Gui.ctx
  local COL = CFG.COL

  local avail_w, avail_h = ImGui.GetContentRegionAvail(ctx)

  if ImGui.Button(ctx, '再スキャン') then Model.rescan() end
  ImGui.SameLine(ctx)
  W.textCol(COL.dim_text, '曲順の変更はタイムライン側で行う')

  local body_h = avail_h - 60
  if body_h < 120 then body_h = 120 end

  if avail_w < CFG.BP_STACK then
    -- 狭い時は縦積み
    drawSongList(-1, body_h * 0.45)
    drawSectionTable(-1, body_h * 0.55 - 30)
  else
    -- 広い時は横並び
    local gap = 8
    local lw  = (avail_w - gap) * 0.42
    local rw  = (avail_w - gap) * 0.58

    ImGui.BeginGroup(ctx)
    drawSongList(lw, body_h)
    ImGui.EndGroup(ctx)

    ImGui.SameLine(ctx, 0, gap)

    ImGui.BeginGroup(ctx)
    drawSectionTable(rw, body_h)
    ImGui.EndGroup(ctx)
  end
end

return M
