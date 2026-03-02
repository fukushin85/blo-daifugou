# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## ツールチェーン

このプロジェクトは **Aftman**（ツールチェーンマネージャー）と **Rojo**（Roblox Studio 同期ツール）を使用する。

```bash
# ツールのインストール（初回のみ）
aftman install

# Rojo バージョン確認
rojo --version   # 7.7.0-rc.1
```

## 開発フロー

```bash
# Studio と同期して開発（Roblox Studio 側で Rojo プラグインの Connect が必要）
rojo serve

# .rbxlx ファイルとしてビルド（Studio なしで確認する場合）
rojo build -o "042_BLO_daifugou.rbxlx"
```

動作確認は Roblox Studio の Play ボタンで行う。自動テストやリントの仕組みはない。

## アーキテクチャ

### Rojo プロジェクト構成（default.project.json）

| src パス | Roblox サービス |
|---|---|
| `src/server/` | `ServerScriptService.Server` |
| `src/client/` | `StarterPlayer.StarterPlayerScripts.Client` |
| `src/shared/` | `ReplicatedStorage.Shared` |

- Baseplate は Z ファイティング防止のため除去済み（default.project.json に含まない）

### ゲームロジック構成

**サーバー・クライアント分離モデル**：ゲーム状態管理はすべてサーバー側で処理し、クライアントは入力を送るのみ。

```
DaifugouGame.client.luau  ──PlayerAction──▶  GameManager.server.luau
                           ◀─GameStateSync─
                           ◀─GameResult────
```

- `GameData.luau`（shared）：カード定義、役判定ロジック。サーバー・クライアント双方から `require` して使う。
- `GameManager.server.luau`：起動時に RemoteEvent を ReplicatedStorage に作成する。ゲーム状態（手札・場の状態・ターン管理）をサーバー側のみで保持。
- `DaifugouGame.client.luau`：カード選択・プレイの入力を受け付け `PlayerAction:FireServer()` で送信。UI（手札表示・場の表示）を管理。

設計書（[GameDesign.md](GameDesign.md)）にゲームルール・RemoteEvent 仕様・UI設計を記載している。
仕様の変更/修正を指示された場合は、GameDesign.mdに変更を反映した後に、GameDesign.mdの内容に従って実装を行う。
