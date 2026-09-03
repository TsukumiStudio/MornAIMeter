# MornAIMeter

Claude Code / Codex CLI の利用枠 (usage) をメニューバーの円グラフで見る、Mac ローカル完結の
常駐アプリ。

## Homebrew での導入

```bash
brew install --cask matsufriends/tap/mornaimeter
```

ad-hoc 署名のため初回起動が Gatekeeper にブロックされる場合は、quarantine 属性を外してから起動する。

```bash
xattr -d com.apple.quarantine /Applications/MornAIMeter.app
```

更新は `brew upgrade --cask mornaimeter`。

## 資格情報の読み取り元

- **Claude**: Keychain の generic password (service `Claude Code-credentials`) から読む
  (`claude login` 済みであること)。
- **Codex**: `~/.codex/auth.json` から読む (`codex login` 済みであること)。

どちらも読むだけで、書き換えは行わない。

## 開発

```bash
bash build-app.sh          # build/MornAIMeter.app を生成
swift build -c release
swift test
```

Xcode プロジェクト (.xcodeproj) は作らず、`swift build` のみで完結する。
