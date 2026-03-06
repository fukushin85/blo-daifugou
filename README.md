# 042_BLO_daifugou

Roblox 大富豪ゲーム。[Rojo](https://github.com/rojo-rbx/rojo) 7.7.0-rc.1 を使用。

## セットアップ

### 前提

- [Aftman](https://github.com/LPGhatguy/aftman) がインストール済みであること
- Roblox Studio がインストール済みであること

### 手順

1. ツールをインストール（Rojo 等）:

```bash
aftman install
```

2. プレースファイルをビルド:

```bash
rojo build -o BLO_daifugou.rbxl
```

3. 生成された `BLO_daifugou.rbxl` を Roblox Studio で開く

4. Rojo サーバーを起動し、Studio の Rojo プラグインから接続:

```bash
rojo serve
```

5. Studio の Play ボタンで動作確認

## ドキュメント

- [GameDesign.md](GameDesign.md) — ゲームルール・UI設計・RemoteEvent仕様
- [ImplementationDesign.md](ImplementationDesign.md) — アーキテクチャ・実装フェーズ
- [CHECKLIST.md](CHECKLIST.md) — 手動確認チェックリスト
