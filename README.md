# MornAIMeter

Claude Code / Codex CLI の利用枠 (usage) をメニューバーの円グラフで見る、Mac ローカル完結の
常駐アプリ。サーバー・Worker 一切不要。Claude Code / Codex CLI がローカルに持っている資格情報を
直接読んで各社の usage API を叩く。

メニューバーにはチェックが付いた枠だけを、Claude 5時間枠 / Claude 週次枠 / Claude 週次 (モデル別) /
Codex 週次枠 / Codex Spark (週次) の固定順で、枠1個につき直径16ptの小さな円グラフ画像を横並びにして表示する
(数字は出さない)。各円は使用率ぶんを12時位置から時計回りに扇形で塗り、枠の経過率 (resets_at から算出)
の位置に中心から円周へ1本の線を引く (経過率が取れない枠は線なし)。データ未取得・取得失敗時はその枠だけ
輪郭線のみの空円になり、何も選ばれていない時は全体でテキスト `--` を1つ出す。
画像は非テンプレート画像 (isTemplate=false) で描画する。輪郭と扇形は控えめなグレー (secondaryLabelColor)
で明暗に追従し、経過率の線はオレンジで固定表示する。
どの枠を出すかはポップオーバー下部のチェックボックス5つ (上記と同じ固定順) で切り替え、
既定は Claude 5時間枠のみ ON (Claude 週次 (モデル別) / Codex Spark は既定 OFF)。
チェック状態は UserDefaults に保存されて次回起動後も引き継がれる。

ポップオーバーは Claude 行 (5時間枠 / 週次枠 / 週次 (モデル名、例: `週次 (Fable)`) の3枚を横並び) /
Codex 行 (週次枠 / `Codex Spark` 固定名の2枚を横並び) の2行構成で、各行の左に固定幅の見出しを置く。
各カードの使用率バーには、枠の経過率 (resets_at から算出した「枠が始まってから今が何%地点か」) を示す
縦の目盛り線を重ねて表示する (resets_at が取れない枠は線なし)。各カードには『残り N%』を主数値、
『N% 使用』を添えとして表示し、『枠の経過 N%』と、使用率が経過率と比べて均等ペースからどれだけ
ずれているか (『ほぼ均等ペース』/『均等より Npt先行』/『均等より Npt余裕』、1pt超の先行は警告色) を表示する。

モデル別週次枠は Claude usage API の `limits` 配列から `kind: "weekly_scoped"` の先頭要素、
Codex Spark (週次) は wham usage API の `additional_rate_limits` 配列の先頭要素の
`rate_limit.secondary_window` (無ければ `primary_window` にフォールバック) を使う。
該当データが API に無い枠は、その枠だけ「データなし」表示になり他の枠には影響しない
(Codex 5時間枠のデータ取得自体は行うが、表示はしない)。

取得成功ごとに `~/Library/Application Support/MornAIMeter/history.jsonl` へ
1行1サンプルの JSON (`{"ts":ミリ秒epoch,"c5":Claude 5時間枠使用率,"c7":Claude 週次枠使用率,"cx":Codex 週次枠使用率,"cf":Claude 週次(モデル別)使用率,"cs":Codex Spark使用率}`、
取れなかった値は `null`) を追記する。どの値も取れなかった回は書かず、起動時に15日より古い行を落として
書き直す。現状は記録のみで、消費ペース等の表示には使っていない。

5分ごと、およびポップオーバーを開いたタイミング (前回取得から60秒以上空いている場合のみ) に再取得する。
usage API が 429 を返した枠は、応答の Retry-After ヘッダ (秒数指定・HTTP-date のどちらか、無ければ既定
300秒) が示す時刻まで、タイマー・ポップオーバー再表示のどちらの取得もスキップする。取得に失敗している間も
カードには直前に成功した値を表示し続け、その下に小さくエラー文を添える。

## ビルド・起動

```bash
bash build-app.sh          # build/MornAIMeter.app を生成
open build/MornAIMeter.app
```

`swift build` のみで完結し、Xcode プロジェクト (.xcodeproj) は作らない。
ad-hoc 署名のみで公証はしていないビルド。`Info.plist` は `LSUIElement=true` で Dock に出さず、
メニューバーのみに常駐する。

開発・テストは通常の Swift Package として:

```bash
swift build -c release
swift test
```

## 配布物 (Releases) からの入手

`v*` タグを push すると GitHub Actions が `MornAIMeter.app.zip` をビルドし、
同名タグの GitHub Release に添付する ([Releases](../../releases) から取得可能)。
タグを push し直すと既存 Release の zip は最新ビルドで差し替えられる。

```bash
# Releases から MornAIMeter.app.zip をダウンロード後
unzip MornAIMeter.app.zip
open MornAIMeter.app
```

署名は ad-hoc (`codesign --sign -`) のみで、Apple Developer ID 署名・公証はしていない。
そのため初回起動時に Gatekeeper に「開発元を確認できません」等でブロックされることがある。
その場合は次のいずれかで開く。

- Finder で `MornAIMeter.app` を右クリック→「開く」→ダイアログで「開く」を選択
- または `xattr -d com.apple.quarantine MornAIMeter.app` で quarantine 属性を外してから起動

## Homebrew での導入

```bash
brew install --cask matsufriends/tap/mornaimeter
```

ad-hoc 署名のため Gatekeeper にブロックされる場合は `--no-quarantine` を付けて入れる。

```bash
brew install --cask --no-quarantine matsufriends/tap/mornaimeter
```

更新は `brew upgrade --cask mornaimeter`。

cask は zip の sha256 を固定して参照するため、brew 対応後は既存タグの打ち直し (zip 差し替え) では
なく新しいタグを切って公開する運用にする (既存タグの zip を差し替えると sha256 不一致で
`brew install`/`upgrade` が失敗する)。

## 資格情報の読み取り元

- **Claude**: Keychain の generic password (service `Claude Code-credentials`) に入っている
  JSON の `.claudeAiOauth.accessToken` を読む (`claude login` 済みであること)。
- **Codex**: `~/.codex/auth.json` の `.tokens.access_token` / `.tokens.account_id` を読む
  (`codex login` 済みであること)。

どちらも Claude Code / Codex CLI 自身が普段の利用の中で更新してくれる前提で、
このアプリは値を読むだけ。

Claude の Keychain 読み取りは、アプリ内から Security フレームワークの API を直接呼ぶのではなく、
`security find-generic-password -s "Claude Code-credentials" -w` を `/usr/bin/security` コマンドとして
起動して標準出力から読む方式にしている。ad-hoc 署名のアプリはビルドごとに署名 (cdhash) が変わり、
アプリ自身が Keychain API を直に叩くと macOS が『常に許可』を覚えてくれず、再ビルドのたびに
許可ダイアログが再度出てしまう。`/usr/bin/security` は Apple 署名で安定しているため、
許可対象がこのコマンドになり、**初回起動時に1回だけ許可ダイアログが出て、『常に許可』を選べば
以後 (再ビルド後・別配布物でも) 出なくなる**。アクセストークンはメモリにキャッシュし、
API から 401 が返ったときと前回読み取りから1時間経過したときだけ Keychain を読み直す
(Keychain へのアクセス回数自体を減らして許可ダイアログの発生機会も抑える)。
