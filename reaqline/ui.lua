--[[
  reaqline/ui.lua
  ウィンドウ枠、タブ、フッター、ドッキング、フォーカス返却。

  フォーカス返却について:
    ReaImGui のウィンドウは実際の OS ウィンドウであり、フォーカスを持つ間は
    REAPER 本体にキー入力が届かない。ImGui 側の設定では解決できないため、
    UI を操作していない間はフォーカスを REAPER 本体へ返すことで
    全てのキーボードショートカットを通常どおり使えるようにする。
--]]

local CFG    = require 'reaqline.config'
local Gui    = require 'reaqline.imgui'
local W      = require 'reaqline.widgets'
local UILive = require 'reaqline.ui_live'
local UIEdit = require 'reaqline.ui_edit'

local M = {}
local S
local main_hwnd
local last_focus_return = 0

function M.init(state, hwnd)
  S = state
  main_hwnd = hwnd
end

--------------------------------------------------------------------------------
-- ドッキング
--   dock_id  0    … フロート
--            負値 … REAPER のドッカー (-1 は最後に使ったドッカー)
--------------------------------------------------------------------------------

function M.loadDock()
  S.dock_id    = tonumber(reaper.GetExtState(CFG.EXT_SECTION, CFG.KEY_DOCK)) or 0
  S.apply_dock = true
end

local function saveDock(id)
  reaper.SetExtState(CFG.EXT_SECTION, CFG.KEY_DOCK, tostring(id), true)
end

local function setDock(id)
  S.dock_id    = id
  S.apply_dock = true
  saveDock(id)
end

--------------------------------------------------------------------------------
-- フォーカス返却
--   操作中(項目がアクティブ / マウス押下中)は奪わない。壊れるため。
--------------------------------------------------------------------------------

function M.returnFocusToReaper()
  local ImGui, ctx = Gui.ImGui, Gui.ctx

  if ImGui.IsAnyItemActive(ctx) then return end
  if ImGui.IsAnyMouseDown(ctx)   then return end

  local focused = false
  pcall(function()
    focused = ImGui.IsWindowFocused(ctx, ImGui.FocusedFlags_AnyWindow)
  end)
  if not focused then return end

  local now = reaper.time_precise()
  if now - last_focus_return < CFG.FOCUS_INTERVAL then return end
  last_focus_return = now

  reaper.JS_Window_SetFocus(main_hwnd)
end

--------------------------------------------------------------------------------
-- フッター
--------------------------------------------------------------------------------

local function drawFooter()
  local ImGui, ctx = Gui.ImGui, Gui.ctx
  local COL = CFG.COL

  ImGui.Separator(ctx)

  if ImGui.Button(ctx, S.dock_id == 0 and 'ドッキング' or 'フロート') then
    setDock(S.dock_id == 0 and -1 or 0)
  end

  ImGui.SameLine(ctx)
  W.textCol(COL.dim_text, 'KEY: 透過')
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx,
      '操作していない間はキーボードフォーカスを REAPER 本体へ返します。\n' ..
      'REAPER の全ショートカットがそのまま使えます。')
  end

  ImGui.SameLine(ctx)
  local dchanged, dv = ImGui.Checkbox(ctx, 'DBG', S.show_debug)
  if dchanged then S.show_debug = dv end

  ImGui.SameLine(ctx)
  W.textCol(COL.dim_text, 'v' .. CFG.VERSION)

  ImGui.SameLine(ctx)
  W.textCol(COL.dim_text, S.status_msg)

  -- 切り分け用の内部状態表示
  if S.show_debug then
    W.textCol(COL.dim_text, 'KB  ' .. table.concat(Gui.kb_report, '  |  '))

    local nx = S.playing_idx and S.songs[S.playing_idx + 1] or nil
    local a  = nx and tostring(nx.follow) or '-'
    local e  = S.play_song and string.format('%.2f', S.play_song.rgnend) or '-'
    W.textCol(COL.dim_text, string.format(
      'DBG  %s  idx=%s  next.follow=%s  pos=%.2f  rgnend=%s  loop=%s  cur=%.2f  sel=%d/%d',
      S.tp.playing and 'PLAY(pos基準)' or 'STOP(cur基準)',
      tostring(S.playing_idx), a, S.tp.pos, e,
      tostring(S.loop_active ~= nil), S.last_cursor, S.sel_song, S.sel_section))
  end
end

--------------------------------------------------------------------------------
-- 1フレーム分の描画
--   戻り値: ウィンドウを開き続けるかどうか
--------------------------------------------------------------------------------

function M.frame()
  local ImGui, ctx = Gui.ImGui, Gui.ctx

  if S.apply_dock then
    ImGui.SetNextWindowDockID(ctx, S.dock_id, ImGui.Cond_Always)
    S.apply_dock = false
  end
  ImGui.SetNextWindowSize(ctx, 780, 540, ImGui.Cond_FirstUseEver)
  ImGui.SetNextWindowSizeConstraints(ctx, 380, 320, 4000, 4000)

  local visible, open = ImGui.Begin(ctx, CFG.SCRIPT_NAME, true)

  -- Begin() は戻り値に関わらず End() と対で呼ぶ必要がある。
  -- visible が false になるのは、ウィンドウが折りたたまれている時や
  -- ドッカーの別タブがアクティブな時。描画だけを visible で分岐させる。
  if visible then
    -- ユーザー操作でドック先が変わった場合は保存し直す
    local cur_dock = ImGui.GetWindowDockID(ctx)
    if cur_dock ~= S.dock_id then
      S.dock_id = cur_dock
      saveDock(cur_dock)
    end

    if ImGui.BeginTabBar(ctx, 'tabs') then
      if ImGui.BeginTabItem(ctx, '本番') then
        UILive.draw()
        ImGui.EndTabItem(ctx)
      end
      if ImGui.BeginTabItem(ctx, '編集') then
        UIEdit.draw()
        ImGui.EndTabItem(ctx)
      end
      ImGui.EndTabBar(ctx)
    end

    drawFooter()
  end

  ImGui.End(ctx)

  return open
end

return M
