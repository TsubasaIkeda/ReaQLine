--[[
  @description ReaQLine - live cue and section controller
  @version 0.1.0
  @author QuanTRIOS
  @provides
    reaqline/config.lua
    reaqline/imgui.lua
    reaqline/model.lua
    reaqline/transport.lua
    reaqline/widgets.lua
    reaqline/ui_live.lua
    reaqline/ui_edit.lua
    reaqline/ui.lua
    [data] toolbar_icons/toolbar_reaqline.png > toolbar_icons/toolbar_reaqline.png
    [data] toolbar_icons/toolbar_reaqline_x2.png > toolbar_icons/toolbar_reaqline_x2.png
  @changelog
    初回リリース
--]]

--[[
  ReaQLine.lua
  REAPER 内で完結するライブ進行コントローラ

  プロジェクト構造の前提:
    リージョン = 曲。曲順はタイムライン上の並び順で確定する。
    マーカー   = 曲内のセクション (Intro / A / B / Chorus 等)
    セクションの終端は、次のマーカー位置、なければリージョン終端。
    曲順を変更する場合は REAPER 側でリージョンを移動し、再スキャンする。

  操作:
    GO    … 選択曲の先頭から再生。リージョン終端で自動停止する。
            停止時に選択が次曲へ移るので、GO を押すだけで続行できる。
    NEXT  … リピートを解除する。シークは発生せず、再生はそのまま
            セクション終端を越えて次のセクションへ進む。
            REAPER 標準の「Transport: Toggle repeat」と等価。
    STOP  … 即時停止。再生中は GO の位置が STOP に変わる。
    スクリプト外で再生が始まった場合は、再生位置から曲を特定して自動的に
    管理下へ取り込む。

  ループ:
    スクリプトは、再生中のセクションに合わせて REAPER のループ範囲
    (タイムセレクション)を更新し続ける。リピートの ON/OFF には関与しない。
    オペレータは、回したいセクションを鳴らしている最中に標準アクションを
    叩けばそのセクションが回り、もう一度叩けば抜ける。
    フットスイッチや MIDI は標準アクションに割り当てればよく、
    スクリプトへの MIDI アサインは不要。
    LOOP 指定のあるセクションのみ、進入時に自動でリピートを ON にする。

  FOLLOW:
    チェックを入れた曲は、前の曲が終わったときに自動で始まる。
    リージョンが隣接していればシーク無しで連続、離れていればシークする。

  依存:
    ReaImGui v0.9 以上   (ReaPack / ReaTeam Extensions)
    js_ReaScriptAPI      (ReaPack / ReaTeam Extensions) — キー透過に必須

  前提と注意:
    - リージョンが時間軸上で重複していないこと。
    - セクションは曲名+セクション名で識別する。同一曲内での同名セクション、
      および同名リージョンは不可。
    - 曲終端での停止は defer 検出のため、最大で1フレーム(約30ms)行き過ぎる。
      FOLLOW を使わない曲の後ろには無音を1秒程度確保しておくこと。
    - Preferences > Audio > Playback の
      「Stop playback at end of loop if repeat is disabled」は OFF にすること。
      ON だとループを抜けた時点で停止してしまう。
    - 日本語のリージョン名/マーカー名は、ReaImGui のバージョンによっては
      グリフが不足して表示できない場合がある。文字化けする場合は
      ReaImGui を更新するか、名前をローマ字にすること。

  保存先:
    ループ設定と FOLLOW 設定は SetProjExtState でプロジェクトに、
    ドッキング状態は SetExtState でグローバルに保存される。

  ファイル構成:
    ReaQLine.lua           このファイル。状態を持ち、各モジュールを繋ぐ。
    reaqline/config.lua    定数と配色
    reaqline/imgui.lua     ReaImGui 初期化、フォント、キーボード制御
    reaqline/model.lua     プロジェクト走査、設定の保存と復元
    reaqline/transport.lua 再生制御、ループ範囲、進行管理
    reaqline/widgets.lua   描画の共通部品
    reaqline/ui_live.lua   本番タブ
    reaqline/ui_edit.lua   編集タブ
    reaqline/ui.lua        ウィンドウ枠、ドッキング、フォーカス返却
--]]

--------------------------------------------------------------------------------
-- モジュール検索パス
--   スクリプト自身のディレクトリを package.path に追加する。
--------------------------------------------------------------------------------

local SEP  = package.config:sub(1, 1)
local SRC  = debug.getinfo(1, 'S').source:sub(2)
local DIR  = SRC:match('(.*' .. SEP .. ')') or ('.' .. SEP)
package.path = DIR .. '?.lua;' .. package.path

local CFG = require 'reaqline.config'

--------------------------------------------------------------------------------
-- 依存チェック
--------------------------------------------------------------------------------

-- js_ReaScriptAPI: キーボードショートカットの透過に必須。
-- ReaImGui のウィンドウは OS ウィンドウであり、フォーカスを持つ間は
-- REAPER にキーが届かない。ImGui の設定では解決できない。
if not reaper.APIExists('JS_Window_SetFocus') then
  reaper.MB('js_ReaScriptAPI が必要です。\n\n' ..
            'Extensions > ReaPack > Browse packages... から\n' ..
            '「js_ReaScriptAPI」をインストールし、REAPER を再起動してください。',
            CFG.SCRIPT_NAME, 0)
  return
end

local Gui = require 'reaqline.imgui'

local ImGui, err = Gui.load()
if not ImGui then
  reaper.MB(err, CFG.SCRIPT_NAME, 0)
  return
end

Gui.createContext()
Gui.createFonts()
Gui.setupKeyboard()

--------------------------------------------------------------------------------
-- 共有状態
--   曲順はリージョンのタイムライン順で確定するため、
--   セットリストを別に保持しない。songs のインデックスがそのまま曲番号。
--------------------------------------------------------------------------------

local S = {
  songs        = {},
  loop_flags   = {},    -- ["曲名\tセクション名"] = true
  follow_flags = {},    -- ["曲名"] = true

  sel_song     = 1,
  sel_section  = 1,

  playing_idx  = nil,
  play_song    = nil,
  cur_section  = nil,
  loop_active  = nil,

  status_msg   = '',
  show_debug   = false,
  adopt_block  = false, -- 停止処理の直後に再取り込みしないための抑止

  -- REAPER のトランスポート状態(毎フレーム更新)
  tp = { playing = false, paused = false, recording = false,
         repeat_on = false, pos = 0 },

  -- 追従用の観測値。停止中はこれらが変化した時だけ選択を更新する。
  last_cursor  = -1,
  last_ts_s    = -1,
  last_ts_e    = -1,

  -- 次フレームで表を選択行までスクロールする
  scroll_song  = false,
  scroll_sec   = false,

  dock_id      = 0,
  apply_dock   = true,
}

--------------------------------------------------------------------------------
-- モジュールの初期化
--------------------------------------------------------------------------------

local Model  = require 'reaqline.model'
local Trans  = require 'reaqline.transport'
local UILive = require 'reaqline.ui_live'
local UIEdit = require 'reaqline.ui_edit'
local UI     = require 'reaqline.ui'

Model.init(S)
Trans.init(S)
UILive.init(S)
UIEdit.init(S)
UI.init(S, reaper.GetMainHwnd())

Model.loadFlags()
Model.rescan()
UI.loadDock()

--------------------------------------------------------------------------------
-- メインループ
--------------------------------------------------------------------------------

local function loop()
  -- 毎フレーム、キーボード捕捉を解除しておく
  Gui.releaseKeyboard()

  Trans.update()

  local open = UI.frame()

  -- 描画確定後にフォーカスを REAPER 本体へ返す
  UI.returnFocusToReaper()

  if open then
    reaper.defer(loop)
  end
end

--------------------------------------------------------------------------------
-- 終了処理
--------------------------------------------------------------------------------

local function onExit()
  -- リピートはオペレータが直接操作するものなので、終了時に変更しない。
end

reaper.atexit(onExit)
reaper.defer(loop)
