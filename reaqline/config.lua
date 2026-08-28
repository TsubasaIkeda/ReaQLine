--[[
  reaqline/config.lua
  定数と配色。他モジュールへの依存を持たない純粋なデータ。
--]]

local M = {}

M.SCRIPT_NAME = 'ReaQLine'
M.VERSION     = '0.1.0'

-- 保存先のキー
M.EXT_SECTION = 'REAQLINE'
M.KEY_LOOPS   = 'SECTION_LOOPS_V1'   -- ["曲名\tセクション名"] の行
M.KEY_FOLLOW  = 'SONG_FOLLOW_V1'     -- ["曲名"] の行
M.KEY_DOCK    = 'DOCK_ID'

-- 配色
--   装飾ではなく状態表示に限定する。
--   緑 = 再生 / 琥珀 = ループ / 赤 = 停止・残りわずか
M.COL = {
  go        = 0x2E7D32FF,
  go_hi     = 0x388E3CFF,
  next      = 0xB8860BFF,
  next_hi   = 0xD4A017FF,
  stop      = 0x8B2E2EFF,
  stop_hi   = 0xA33A3AFF,
  idle      = 0x3A3A3AFF,
  loop_text = 0xFFC65CFF,
  warn_text = 0xFF6B6BFF,
  dim_text  = 0x9A9A9AFF,
  rec_text  = 0xFF4D4DFF,
  bar       = 0x4A9EFFFF,
  bar_loop  = 0xFFC65CFF,
}

-- 判定しきい値
M.WARN_SEC       = 10    -- 残り何秒から警告色にするか
M.END_EPS        = 0.02  -- 曲終端とみなす許容(秒)
M.ADJ_TOL        = 0.10  -- 次のリージョンが「隣接している」とみなす間隔(秒)
M.FOCUS_INTERVAL = 0.15  -- フォーカス返却の間引き(秒)

-- レイアウト切替のしきい値(px)
M.BP_NARROW = 560   -- これ未満は最小フォント
M.BP_WIDE   = 820   -- これ以上は最大フォント
M.BP_STACK  = 720   -- 編集タブを縦積みにする幅

-- フォントサイズ
M.FONT_SIZES = { s = 16, m = 20, l = 26, xl = 34, xxl = 44 }

return M
