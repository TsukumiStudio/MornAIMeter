# MornAIMeter 画像素材

- `ogp.psd`: 1200 × 630。MornStorage の `design/ogp.psd` と同じ配置・フォント・レイアウト。
- `icon.psd`: 1024 × 1024、クリーム色 (253,247,230) の不透明背景。

画像の書き出し (PNG など) は行わない。すべて PSD 内で再編集する。

## ogp.psd の構成

- 背景 (`背景`, `背景 の配色`, `背景・グリッド` グループ) は MornStorage の `design/ogp.psd` からレイヤー構造ごと複製。
- 前景はすべて編集可能なレイヤー。文字は文字レイヤー、図形は「べた塗り + ベクターマスク」のシェイプレイヤー。
  - `ロゴ`: 円グラフのマーク 3 枚 (輪郭・扇形・経過線) + `Brand rich` (HelveticaNeue-Bold 38px)
  - `見出し`: `Hero first` (HiraginoSans-W6 70px) / `Hero second` (HiraginoSans-W6 64px)
  - `説明文`: `Copy first` (HiraginoSans-W3 25px)
  - `Homebrew` / `macOS タグ`: ピル (角丸 19px) + 文字 (22px)。文字幅 + 左右 22px でピル幅を決め、間隔 11px
  - `フッター`: `Hairline footer` (2px) + `Footer studio` (HelveticaNeue-Medium 20px)
  - `利用画面`: ウィンドウ (568,110 / 562×408 / 角丸 14、ドロップシャドウ) + タイトルバー + 信号灯 + メニューバー帯 (円グラフアイコン 2 つ) + 3 段のカード (ラベル・残り%・バー・リセット時刻の文字レイヤー)
- 配色は MornStorage と同じ: 濃オリーブ (66,78,22)、オリーブ (99,116,18)、ライム (200,209,72)、セージ (161,169,110)、青アクセント (118,167,220)。

## icon.psd の構成

- `背景`: べた塗りシェイプ (クリーム)。
- `円グラフ` グループ: `輪郭` (オリーブ 113,120,44 半径 352) / `残り (内側)` (セージ 半径 296) / `扇形` (ライム、12 時から時計回りに 65%) / `経過線` (青、幅 40) / `中心` (青)。
- メニューバーアイコン (`tools/make-icon.swift`) と同じモチーフ。`Resources/AppIcon.icns` は従来どおり `tools/make-icns.sh` で生成しており、この PSD からは書き出していない。
