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

**注意**：Studio上で配置したパーツは Rojo では同期されない。パーツ編集後は「ファイル → コピーをダウンロード」でローカル保存すること。

## アーキテクチャ

### Rojo プロジェクト構成（[default.project.json](default.project.json)）

| src パス | Roblox サービス |
|---|---|
| `src/server/` | `ServerScriptService.Server` |
| `src/client/` | `StarterPlayer.StarterPlayerScripts.Client` |
| `src/shared/` | `ReplicatedStorage.Shared` |

- Baseplate は Z ファイティング防止のため除去済み（default.project.json に含まない）
- `FilteringEnabled: true`・`SoundService.RespectFilteringEnabled: true` が設定済み

### ゲームロジック構成

**サーバー・クライアント分離モデル**：ゲーム状態管理はすべてサーバー側で処理し、クライアントは入力を送るのみ。

```
DaifugouGame.client.luau  ──PlayerAction──▶  GameManager.server.luau
                           ──CardExchange──▶
                           ◀─GameStateSync─
                           ◀─GamePhaseChanged─
```

| ファイル | 役割 |
|---|---|
| `src/server/GameManager.server.luau` | ゲーム状態管理・バリデーション・ターン制御。起動時に RemoteEvent を ReplicatedStorage に生成 |
| `src/client/DaifugouGame.client.luau` | 手札UI・カード選択・アクション送信（`PlayerAction:FireServer()`）|
| `src/shared/CardData.luau` | カード定義・強さ比較・役判定ロジック。サーバー・クライアント双方から `require` |

### RemoteEvent 仕様

| イベント名 | 方向 | データ |
|---|---|---|
| `PlayerAction` | Client → Server | `{type: "play", cards: [{suit, number}]}` または `{type: "pass"}` |
| `CardExchange` | Client → Server | `{cards: [{suit, number}]}` （階級交換フェーズのみ） |
| `GameStateSync` | Server → Client | 手札・場・ターン・革命状態など（自分の手札は本人のみ） |
| `GamePhaseChanged` | Server → Client | `{phase: "waiting"/"dealing"/"playing"/"result"}` |

### カード強さ・定数（CardData.luau）

```lua
SUIT   = { SPADE=1, HEART=2, DIAMOND=3, CLUB=4, JOKER=5 }
NUMBER = { [3]=1, [4]=2, ..., A=12, [2]=13 }  -- 革命中は大小逆転
JOKER_STRENGTH = 14
```

特殊ルール：**革命**（4枚カルテットで強弱逆転）、**8切り**（8を出したら場リセット）、**スペ3返し**（ジョーカー1枚出しにスペ3で対抗可能）。

詳細は [GameDesign.md](GameDesign.md) を参照。
