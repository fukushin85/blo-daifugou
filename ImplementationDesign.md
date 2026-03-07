# ImplementationDesign.md — 042_BLO_daifugou

## アーキテクチャ方針

### ロビーとゲームの分離

ロビーシステムは将来別のExperienceでも流用できるよう、ゲームロジックに依存しない汎用設計とする。

```
[ ロビー層（汎用） ]                [ ゲーム層（大富豪固有） ]
  LobbyManager                         GameManager
  LobbyClient           ←インターフェース→  DaifugouGame
  RoomConfig（型定義）                  CardData
                                        DaifugouConfig（ゲーム設定定義）
```

### ロビー⇔ゲーム間のインターフェース

ロビーはゲーム固有の内容を解釈せず、`gameConfig` をそのままゲームに渡す。

```lua
-- RoomConfig（汎用型）
{
  humanCount: number,    -- 人間プレイヤー数
  gameConfig: table,     -- ゲーム固有設定（ロビーは中身を解釈しない）
}

-- 大富豪の gameConfig
{
  revolution: boolean,
  eightCut: boolean,
  spade3: boolean,
}
```

ロビーとゲームの接続点は2つ：
- **ゲーム開始**：ロビーが `GameManager.start(roomConfig)` を呼ぶ
- **ゲーム終了**：ゲームが `LobbyManager.returnToLobby(players)` を呼ぶ

別のExperienceを作る場合は `game/` フォルダを丸ごと差し替え、`DaifugouConfig` を新しいゲームのConfigに置き換えるだけで対応できる。

---

## ファイル構成

```
src/
├── server/
│   ├── lobby/
│   │   └── LobbyManager.server.luau    # エリア検出・ルーム管理・カウントダウン（汎用）
│   └── game/
│       └── GameManager.server.luau     # 大富豪ゲーム状態管理（大富豪固有）
├── client/
│   ├── lobby/
│   │   └── LobbyClient.client.luau     # ロビーUI・ルーム設定UI表示（汎用）
│   └── game/
│       └── DaifugouGame.client.luau    # 手札UI・カード操作（大富豪固有）
└── shared/
    ├── lobby/
    │   └── RoomConfig.luau             # ルーム設定の型定義（汎用）
    └── game/
        ├── CardData.luau               # カード定義・強さ比較・役判定（大富豪固有）
        └── DaifugouConfig.luau         # ゲーム設定定義・デフォルト値（大富豪固有）
```

---

## 実装フェーズ

### Phase 1 — ゲームコア（最小動作）

**目標**：Studio Play で1ラウンド遊べる（簡易NPC付き・特殊ルールなし・ロビーなし）

- [x] `CardData.luau`: カード定義・デッキ生成・強さ比較
- [x] `GameManager`: カード配布（53枚均等）・ターン進行・勝利判定
- [x] `GameManager`: RemoteEvent の生成と接続（`PlayerAction` / `GameStateSync` / `GamePhaseChanged`）
- [x] `GameManager`: 簡易NPC（最弱有効手を出す、なければパス）
- [x] `DaifugouGame.client`: 手札表示・カード選択・「出す」「パス」送信
- [x] `DaifugouGame.client`: `GameStateSync` 受信時のUI更新
- [ ] Studio Play で動作確認（人間1人 + NPC3人で1ゲーム完走）

### Phase 2 — 特殊ルール

**目標**：全特殊ルールが正しく動作する

- [x] 革命（4枚カルテット → 強弱逆転・逆革命）
- [x] 8切り（8を出したら場リセット・同プレイヤー続行）
- [x] スペ3返し（ジョーカー1枚出しに♠3で対抗）
- [x] 反則あがり判定（最強カード・8切り・スペ3返し・ジョーカー）
- [x] 反則あがり時の処理（最下位化・ゲーム継続）
- [ ] 各ルールの動作確認

### Phase 3 — セット・ポイント制・階級交換

**目標**：4ラウンドのセットが完走できる

- [ ] ラウンドカウント管理（1〜4）
- [ ] ポイント計算・累計スコア管理
- [ ] ラウンド結果表示（`Result` フェーズ）
- [ ] セット最終結果表示（`FinalResult` フェーズ）
- [ ] 2ラウンド目以降の階級交換（`CardExchange` RemoteEvent）
- [ ] `GameStateSync` に `roundNumber` / `scores` を追加
- [ ] 動作確認（4ラウンド完走・ポイント正常集計）

### Phase 4 — NPC AI

**目標**：NPCがゲームを自動進行できる

- [x] NPC プレイヤーの管理（サーバー側で自動操作）
- [x] NPC の基本戦略（出せる最小のカードを出す・出せなければパス）
- [x] NPC の階級交換（大富豪時：最小カードを渡す）
- [ ] 動作確認（NPC3人 + 人間1人で4ラウンド完走）

### Phase 5 — ロビーシステム

**目標**：ロビーからゲームを起動できる

- [ ] `RoomConfig.luau`: 汎用ルーム設定型の定義
- [ ] `DaifugouConfig.luau`: 大富豪固有設定の定義・デフォルト値
- [ ] `LobbyManager`: 円形エリアの検出（プレイヤーの出入り監視）
- [ ] `LobbyManager`: ルーム作成・カウントダウン管理
- [ ] `LobbyManager`: 作成者離脱時のキャンセル処理
- [ ] `LobbyClient`: ルーム設定UI（人数選択・特殊ルールトグル）
- [ ] `LobbyClient`: カウントダウンUI（参加者リスト・残り時間）
- [ ] ロビー⇔ゲームの接続（`GameManager.start()` / `LobbyManager.returnToLobby()`）
- [ ] ゲーム中のロビーキャラクター操作ロック
- [ ] RemoteEvent 追加（`CreateRoom` / `JoinRoom` / `RoomStateChanged`）
- [ ] 動作確認（ロビー → ルーム作成 → ゲーム → ロビー復帰）

### Phase 6 — UIポリッシュ

**目標**：見た目が整った状態にする

- [ ] 革命中バナー・エフェクト表示
- [ ] 上がり時アニメーション（「上がり！」表示）
- [ ] ラウンド終了時のポイント加算アニメーション
- [ ] カード選択ハイライト
- [ ] 自分のターン以外のボタングレーアウト

---

## 設計変更ログ

| 日付 | 変更内容 |
|---|---|
| 2026-03-03 | 初版作成。ロビーとゲームを分離したフォルダ構成を採用 |
