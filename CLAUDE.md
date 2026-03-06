# CLAUDE.md

## ツールチェーン

- **Aftman** + **Rojo 7.7.0-rc.1**（`aftman install` で導入）
- 動作確認は `rojo serve` → Roblox Studio の Play ボタン。自動テスト・リントなし
- Studio上のパーツは Rojo 同期対象外。編集後は「ファイル → コピーをダウンロード」で保存

## アーキテクチャ

| src パス | Roblox サービス |
|---|---|
| `src/server/` | `ServerScriptService.Server` |
| `src/client/` | `StarterPlayer.StarterPlayerScripts.Client` |
| `src/shared/` | `ReplicatedStorage.Shared` |

**サーバー・クライアント分離モデル**：状態管理はサーバー、クライアントは入力送信のみ。

| ファイル | 役割 |
|---|---|
| `src/server/game/GameManager.server.luau` | ゲーム状態管理・ターン制御・RemoteEvent生成 |
| `src/client/game/DaifugouGame.client.luau` | 手札UI・カード選択・アクション送信 |
| `src/shared/game/CardData.luau` | カード定義・強さ比較・役判定（サーバー・クライアント共用） |

ゲームルール・RemoteEvent仕様・カード定数の詳細は [GameDesign.md](GameDesign.md) を参照。

## 開発ルール

- デバッグ機能を追加・変更した場合は、[GameDesign.md](GameDesign.md) の「デバッグ機能」セクションにも反映すること。
- 実装やバグ修正をコミットする際、影響する確認項目を [CHECKLIST.md](CHECKLIST.md) に追加・更新すること。
