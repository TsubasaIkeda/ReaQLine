--[[
  reaqline/imgui.lua
  ReaImGui の読み込み、コンテキスト生成、フォント、キーボード制御。

  バージョン差の吸収をここに集約する。
    - シムのバージョン指定 (0.10 / 0.9)
    - CreateFont / Attach / PushFont の引数仕様
    - キーボードナビゲーション関連の設定名
--]]

local CFG = require 'reaqline.config'

local M = {}

--------------------------------------------------------------------------------
-- ReaImGui の読み込み
--------------------------------------------------------------------------------

-- 失敗時は nil とエラーメッセージを返す。呼び出し側で終了処理を行う。
function M.load()
  if not reaper.ImGui_GetBuiltinPath then
    return nil, 'ReaImGui v0.9 以上が必要です。ReaPack からインストールしてください。'
  end

  package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path

  local ImGui
  for _, ver in ipairs({ '0.10', '0.9' }) do
    local ok, mod = pcall(function() return require 'imgui' (ver) end)
    if ok and mod then ImGui = mod break end
  end

  if not ImGui then
    return nil, 'ReaImGui の読み込みに失敗しました。ReaPack で更新してください。'
  end

  M.ImGui = ImGui
  return ImGui
end

--------------------------------------------------------------------------------
-- コンテキスト
--------------------------------------------------------------------------------

function M.createContext()
  M.ctx = M.ImGui.CreateContext(CFG.SCRIPT_NAME)
  return M.ctx
end

--------------------------------------------------------------------------------
-- フォント
--   v0.9  : CreateFont(name, size) でサイズ固定。PushFont(ctx, font)
--   v0.10 : フォントはサイズ非依存。PushFont(ctx, font, size)
--   どちらでも動くよう、生成時にサイズも保持し Push はラッパー経由にする。
--------------------------------------------------------------------------------

function M.createFonts()
  local ImGui, ctx = M.ImGui, M.ctx

  local function makeFont(size)
    return { f = ImGui.CreateFont('sans-serif', size), size = size }
  end

  local fonts = {}
  for name, size in pairs(CFG.FONT_SIZES) do
    fonts[name] = makeFont(size)
  end

  -- v0.9 では使用前に Attach が必要。v0.10 では不要。
  for _, e in pairs(fonts) do
    pcall(function() ImGui.Attach(ctx, e.f) end)
  end

  M.fonts = fonts
  return fonts
end

local font_mode = nil   -- 3 = v0.10 系 / 2 = v0.9 系

function M.pushFont(e)
  if not e then return end
  local ImGui, ctx = M.ImGui, M.ctx

  if font_mode == nil then
    -- 3引数(サイズ指定)を先に試す。成功していればプッシュ済み。
    if pcall(ImGui.PushFont, ctx, e.f, e.size) then
      font_mode = 3
      return
    end
    font_mode = 2
  end

  if font_mode == 3 then
    ImGui.PushFont(ctx, e.f, e.size)
  else
    ImGui.PushFont(ctx, e.f)
  end
end

function M.popFont()
  M.ImGui.PopFont(M.ctx)
end

-- ウィンドウ幅から、見出し用と本文用のフォントを選ぶ
function M.pickFonts(w)
  local F = M.fonts
  if w < CFG.BP_NARROW then
    return F.l,   F.m
  elseif w < CFG.BP_WIDE then
    return F.xl,  F.l
  else
    return F.xxl, F.xl
  end
end

--------------------------------------------------------------------------------
-- キーボード制御
--   ImGui 側でキーを消費させないための設定。
--   ただしこれだけでは OS のウィンドウフォーカスまでは解決できないため、
--   実際の透過は focus.lua のフォーカス返却が担う。
--------------------------------------------------------------------------------

M.kb_report = {}

local function note(txt)
  M.kb_report[#M.kb_report + 1] = txt
end

function M.setupKeyboard()
  local ImGui, ctx = M.ImGui, M.ctx

  -- キーボードナビゲーション機能自体を無効化する。
  -- 有効なままだと ImGui が矢印キー/Space/Enter 等を消費する。
  pcall(function()
    if ImGui.ConfigVar_Flags and ImGui.ConfigFlags_NavEnableKeyboard then
      local flags   = ImGui.GetConfigVar(ctx, ImGui.ConfigVar_Flags)
      local cleared = flags & ~ImGui.ConfigFlags_NavEnableKeyboard
      ImGui.SetConfigVar(ctx, ImGui.ConfigVar_Flags, cleared)
      note(string.format('NavEnableKeyboard off (%d->%d)', flags, cleared))
    else
      note('ConfigFlags_NavEnableKeyboard なし')
    end
  end)

  -- ナビゲーションによるグローバルなキーボード捕捉を無効化(v0.10)
  pcall(function()
    if ImGui.ConfigVar_NavCaptureKeyboard then
      ImGui.SetConfigVar(ctx, ImGui.ConfigVar_NavCaptureKeyboard, 0)
      note('NavCaptureKeyboard=0')
    else
      note('ConfigVar_NavCaptureKeyboard なし')
    end
  end)

  -- 旧バージョン(v0.8 以前)向けフラグ
  pcall(function()
    if ImGui.ConfigVar_Flags and ImGui.ConfigFlags_NavNoCaptureKeyboard then
      local flags = ImGui.GetConfigVar(ctx, ImGui.ConfigVar_Flags)
      ImGui.SetConfigVar(ctx, ImGui.ConfigVar_Flags,
                         flags | ImGui.ConfigFlags_NavNoCaptureKeyboard)
      note('NavNoCaptureKeyboard on')
    end
  end)
end

-- 毎フレームの上書き。フレームの先頭で呼ぶ。
function M.releaseKeyboard()
  pcall(function()
    M.ImGui.SetNextFrameWantCaptureKeyboard(M.ctx, false)
  end)
end

return M
