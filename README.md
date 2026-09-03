# MornAIMeter

Claude Code / Codex CLI / Antigravity の利用枠 (usage) をメニューバーの円グラフで見る、Mac
ローカル完結の常駐アプリです。

![メニューバー](docs/menubar.png)
![ポップオーバー](docs/popover.png)

## Homebrew での導入

```bash
brew install --cask matsufriends/tap/mornaimeter
```

更新は `brew upgrade --cask mornaimeter`。

## 前提

- Claude Code (`claude login`)、Codex CLI (`codex login`)、Antigravity CLI (`agy` で一度
  ログイン) にログイン済みであること。使っていないものは未ログインでも構いません
  (その枠だけ表示されません)。
- このアプリは各 CLI がログイン時に保存したトークンを読み、Anthropic / OpenAI / Google の
  公式 usage API に残り枠を問い合わせています。
- 初回起動時に macOS がアクセス許可ダイアログを 1 回表示します。「常に許可」を選ぶと
  以後は表示されません。
- Antigravity のトークンが切れているときは、アプリが裏で `agy` を数秒だけ起動して更新
  します (ターミナルは開きません)。

## 開発

```bash
bash build-app.sh          # build/MornAIMeter.app を生成
swift build -c release
swift test
```
