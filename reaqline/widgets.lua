--[[
  reaqline/widgets.lua
  描画まわりの小さな共通部品。UI モジュールから使う。
--]]

local CFG = require 'reaqline.config'
local Gui = require 'reaqline.imgui'

local M = {}

function M.fmtTime(sec)
  if not sec or sec < 0 then return '--:--' end
  local m = math.floor(sec / 60)
  local s = math.floor(sec % 60)
  return string.format('%d:%02d', m, s)
end

function M.clamp(v, lo, hi)
  if v < lo then return lo elseif v > hi then return hi else return v end
end

function M.textCol(color, str)
  local ImGui, ctx = Gui.ImGui, Gui.ctx
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, color)
  ImGui.Text(ctx, str)
  ImGui.PopStyleColor(ctx)
end

-- 色付きボタン。enabled=false なら灰色にし、押しても何も起きない。
function M.bigButton(label, w, h, base, hover, enabled)
  local ImGui, ctx = Gui.ImGui, Gui.ctx
  local c = enabled and base  or CFG.COL.idle
  local d = enabled and hover or CFG.COL.idle
  ImGui.PushStyleColor(ctx, ImGui.Col_Button,        c)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, d)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive,  d)
  local clicked = ImGui.Button(ctx, label, w, h)
  ImGui.PopStyleColor(ctx, 3)
  return clicked and enabled
end

-- 表の共通フラグ
function M.tableFlags()
  local ImGui = Gui.ImGui
  return ImGui.TableFlags_RowBg
       | ImGui.TableFlags_Borders
       | ImGui.TableFlags_ScrollY
       | ImGui.TableFlags_SizingStretchProp
end

return M
