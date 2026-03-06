-- GameManager.server.luau
-- ゲーム状態管理・カード配布・ターン制御・勝利判定
-- Phase 1: ゲームコア（特殊ルールなし、簡易NPC付き）

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- CardData は ReplicatedStorage.Shared.game.CardData にマップされる
local CardData = require(ReplicatedStorage.Shared.game.CardData)

-- ============================================================
-- RemoteEvent 生成
-- ============================================================

local function makeEvent(name)
	local e = Instance.new("RemoteEvent")
	e.Name = name
	e.Parent = ReplicatedStorage
	return e
end

local PlayerAction    = makeEvent("PlayerAction")
local GameStateSync   = makeEvent("GameStateSync")
local GamePhaseChanged = makeEvent("GamePhaseChanged")
local DebugAction     = makeEvent("DebugAction")
local CardExchange    = makeEvent("CardExchange")

-- ============================================================
-- 定数
-- ============================================================

local PLAYER_COUNT = 4
local NPC_THINK_TIME = 0.8              -- NPC が「考える」演出の秒数
local TOTAL_ROUNDS = 4
local ROUND_POINTS       = { 50, 30, 10, 0 }   -- 1〜3ラウンド目
local FINAL_ROUND_POINTS = { 70, 30, 10, 0 }   -- 4ラウンド目
local RESULT_DISPLAY_SEC = 5                    -- 結果表示秒数

-- ============================================================
-- 状態
-- ============================================================

-- players[i] = { id, name, isNPC, isFinished }
-- hands[id]  = { {suit, number}, ... }
local state = {
	phase         = "waiting",
	players       = {},
	hands         = {},
	field         = {},       -- 現在の場のカード
	fieldOwnerId  = nil,      -- 場のカードを出したプレイヤーID
	currentId     = nil,      -- 現在のターンのプレイヤーID
	passCount     = 0,        -- 最後の出し以降の連続パス数
	rankings      = {},       -- 正常あがり順 [rank] = playerId
	foulRankings  = {},       -- 反則あがり順（ゲーム終了時に末尾に追加）
	isRevolution  = false,
	notification  = nil,      -- クライアントへの通知メッセージ（送信後クリア）
	roundNumber   = 1,        -- 現在のラウンド (1-4)
	scores        = {},       -- {[playerId] = 累計ポイント}
	prevRankings  = {},       -- 前ラウンドの rankings（階級交換ペア決定用）
	exchangeState = nil,      -- 交換中の状態 { pending = {[playerId]={targetId,count}} }
	rules = {                 -- 特殊ルール設定（Phase 5 でロビーから上書き）
		revolution = true,
		eightCut   = true,
		spade3     = true,
	},
}

-- 前方宣言（ラウンドループで相互参照するため）
local startNextRound
local startCardExchange
local completeExchange

-- ============================================================
-- ユーティリティ
-- ============================================================

local function getPlayer(id)
	for _, p in ipairs(state.players) do
		if p.id == id then return p end
	end
	return nil
end

local function getActivePlayers()
	local active = {}
	for _, p in ipairs(state.players) do
		if not p.isFinished then
			table.insert(active, p)
		end
	end
	return active
end

local function getRobloxPlayer(playerInfo)
	if playerInfo.isNPC then return nil end
	return Players:FindFirstChild(playerInfo.name)
end

-- afterId の次のアクティブプレイヤーIDを返す（リングバッファ）
local function getNextActiveId(afterId)
	local n = #state.players
	local pos = 1
	for i, p in ipairs(state.players) do
		if p.id == afterId then pos = i; break end
	end
	for offset = 1, n do
		local idx = ((pos - 1 + offset) % n) + 1
		local p = state.players[idx]
		if not p.isFinished then return p.id end
	end
	return nil
end

-- ============================================================
-- ゲーム状態の送信
-- ============================================================

local function syncAll()
	local notification = state.notification
	state.notification = nil  -- 1回送信したらクリア

	local playerList = {}
	for _, p in ipairs(state.players) do
		table.insert(playerList, {
			name        = p.name,
			handCount   = #(state.hands[p.id] or {}),
			isFinished  = p.isFinished,
		})
	end

	for _, p in ipairs(state.players) do
		local rp = getRobloxPlayer(p)
		if rp then
			-- 交換フェーズ中の個別情報
			local exInfo = nil
			if state.exchangeState then
				local pending = state.exchangeState.pending[p.id]
				if pending then
					local target = getPlayer(pending.targetId)
					exInfo = {
						mustGiveCount = pending.count,
						targetName    = target and target.name or "",
					}
				end
			end

			GameStateSync:FireClient(rp, {
				hand         = state.hands[p.id] or {},
				field        = state.field,
				fieldCount   = #state.field,
				turn         = state.currentId and (getPlayer(state.currentId) or {}).name or "",
				players      = playerList,
				isRevolution = state.isRevolution,
				rankings     = state.rankings,
				notification = notification,
				roundNumber  = state.roundNumber,
				scores       = state.scores,
				exchangeInfo = exInfo,
			})
		end
	end
end

local function broadcastPhase(phase, extraData)
	local data = { phase = phase }
	if extraData then
		for k, v in pairs(extraData) do
			data[k] = v
		end
	end
	for _, p in ipairs(state.players) do
		local rp = getRobloxPlayer(p)
		if rp then
			GamePhaseChanged:FireClient(rp, data)
		end
	end
end

-- ============================================================
-- カード操作ユーティリティ
-- ============================================================

-- 手札から指定カードを除いた残りを返す（元を変更しない）
local function removeCards(hand, cards)
	local remaining = {}
	local toRemove = {}
	for _, c in ipairs(cards) do table.insert(toRemove, c) end

	for _, hc in ipairs(hand) do
		local found = false
		for i, rc in ipairs(toRemove) do
			if hc.suit == rc.suit and hc.number == rc.number then
				table.remove(toRemove, i)
				found = true
				break
			end
		end
		if not found then table.insert(remaining, hc) end
	end
	return remaining
end

-- 手札が指定カードを全て含むか確認
local function handContains(hand, cards)
	local copy = {}
	for _, c in ipairs(hand) do table.insert(copy, c) end

	for _, needed in ipairs(cards) do
		local found = false
		for i, hc in ipairs(copy) do
			if hc.suit == needed.suit and hc.number == needed.number then
				table.remove(copy, i)
				found = true
				break
			end
		end
		if not found then return false end
	end
	return true
end

-- 他プレイヤーの手札から条件に合うカードを1枚奪って返す（なければ nil）
local function stealCard(toId, predicate)
	for _, p in ipairs(state.players) do
		if p.id ~= toId then
			local hand = state.hands[p.id] or {}
			for i, c in ipairs(hand) do
				if predicate(c) then
					table.remove(hand, i)
					return c
				end
			end
		end
	end
	return nil
end

-- ============================================================
-- 順位管理
-- ============================================================

local function finishPlayer(playerId)
	local p = getPlayer(playerId)
	if not p or p.isFinished then return end
	p.isFinished = true
	table.insert(state.rankings, playerId)
	local rankNames = { "大富豪", "富豪", "貧民", "大貧民" }
	local rank = rankNames[#state.rankings] or tostring(#state.rankings) .. "位"
	local notif = p.name .. " が上がり！（" .. rank .. "）"
	state.notification = state.notification and (state.notification .. "  " .. notif) or notif
end

-- 反則あがり処理：強制最下位化
local function handleFoulWin(playerId)
	local p = getPlayer(playerId)
	if not p or p.isFinished then return end
	p.isFinished = true
	table.insert(state.foulRankings, playerId)
	state.notification = p.name .. " が反則あがり！最下位になりました"
end

-- ラウンドのポイント加算
local function addRoundPoints(rankings, roundNumber)
	local pts = (roundNumber == TOTAL_ROUNDS) and FINAL_ROUND_POINTS or ROUND_POINTS
	for i, playerId in ipairs(rankings) do
		state.scores[playerId] = (state.scores[playerId] or 0) + (pts[i] or 0)
	end
end

-- ラウンド終了判定。終了なら true を返す
local function checkGameEnd()
	local active = getActivePlayers()
	if #active <= 1 then
		if #active == 1 then
			finishPlayer(active[1].id)
		end
		-- 反則あがりプレイヤーを末尾（最下位）に追加
		for _, foulId in ipairs(state.foulRankings) do
			table.insert(state.rankings, foulId)
		end

		-- ポイント加算
		addRoundPoints(state.rankings, state.roundNumber)

		-- ラウンド結果データを構築
		local rankNames = { "大富豪", "富豪", "貧民", "大貧民" }
		local pts = (state.roundNumber == TOTAL_ROUNDS) and FINAL_ROUND_POINTS or ROUND_POINTS
		local roundResult = {}
		for i, pid in ipairs(state.rankings) do
			local p = getPlayer(pid)
			table.insert(roundResult, {
				name   = p and p.name or "?",
				rank   = rankNames[i] or tostring(i),
				points = pts[i] or 0,
			})
		end

		state.phase = "result"
		broadcastPhase("result", {
			roundNumber = state.roundNumber,
			roundResult = roundResult,
			scores      = state.scores,
			displaySec  = RESULT_DISPLAY_SEC,
		})
		syncAll()

		-- 次ラウンドへ自動遷移 or 最終結果
		if state.roundNumber < TOTAL_ROUNDS then
			task.delay(RESULT_DISPLAY_SEC, function()
				startNextRound()
			end)
		else
			task.delay(RESULT_DISPLAY_SEC, function()
				state.phase = "finalResult"
				-- スコア降順で最終順位を計算
				local finalRanking = {}
				for _, p in ipairs(state.players) do
					table.insert(finalRanking, { name = p.name, score = state.scores[p.id] or 0 })
				end
				table.sort(finalRanking, function(a, b) return a.score > b.score end)
				broadcastPhase("finalResult", {
					finalRanking = finalRanking,
					scores       = state.scores,
				})
			end)
		end
		return true
	end
	return false
end

-- ============================================================
-- バリデーション
-- ============================================================

local function validatePlay(playerId, cards)
	if state.currentId ~= playerId then
		return false, "Not your turn"
	end
	if #cards == 0 then
		return false, "No cards selected"
	end
	if not handContains(state.hands[playerId], cards) then
		return false, "Card not in hand"
	end
	if not CardData.isValidSet(cards) then
		return false, "Invalid card set"
	end
	if #state.field > 0 then
		-- スペ3返しは通常の強さ比較を免除
		if state.rules.spade3 and CardData.isSpade3Return(cards, state.field) then
			return true, nil
		end
		if #cards ~= #state.field then
			return false, "Must play same count as field"
		end
		if not CardData.beats(cards, state.field, state.isRevolution) then
			return false, "Cards must be stronger than field"
		end
	end
	return true, nil
end

-- ============================================================
-- プレイ・パス実行
-- ============================================================

local function doPlay(playerId, cards)
	-- 特殊ルール判定
	local isEightCutPlay     = state.rules.eightCut  and CardData.isEightCut(cards)
	local isSpade3ReturnPlay = state.rules.spade3    and CardData.isSpade3Return(cards, state.field)
	local isRevPlay          = state.rules.revolution and CardData.isRevolutionPlay(cards)

	-- 手札からカードを除去
	state.hands[playerId] = removeCards(state.hands[playerId], cards)

	-- 反則あがり判定は革命トグル前の状態で行う
	local handEmpty = (#state.hands[playerId] == 0)
	local isFoul = handEmpty
		and CardData.isFoulWin(cards, isEightCutPlay, isSpade3ReturnPlay, state.isRevolution)

	-- 革命トグル
	if isRevPlay then
		state.isRevolution = not state.isRevolution
		local notif = state.isRevolution and "革命！" or "逆革命！"
		-- 既存通知があれば末尾に追記（8切り同時など）
		state.notification = state.notification and (state.notification .. "  " .. notif) or notif
	end

	-- 場を更新
	state.field        = cards
	state.fieldOwnerId = playerId
	state.passCount    = 0

	if handEmpty then
		if isFoul then
			-- 反則あがり: 強制最下位・場リセット・次プレイヤーへ
			handleFoulWin(playerId)
			state.field        = {}
			state.fieldOwnerId = nil
			state.currentId    = getNextActiveId(playerId)
			if checkGameEnd() then return end
		else
			-- 正常あがり
			finishPlayer(playerId)
			if checkGameEnd() then return end
			state.currentId = getNextActiveId(playerId)
		end
	elseif isEightCutPlay then
		-- 8切り: 出したカードを一度表示してから場リセット
		local notif = "8切り！"
		state.notification = state.notification and (state.notification .. "  " .. notif) or notif
		state.currentId = playerId
		syncAll()
		-- 遅延で場リセット（NPC思考時間 0.8s より前に完了する）
		task.delay(0.5, function()
			if state.phase ~= "playing" then return end
			state.field        = {}
			state.fieldOwnerId = nil
			state.passCount    = 0
			syncAll()
		end)
		return
	else
		state.currentId = getNextActiveId(playerId)
	end

	syncAll()
end

local function doPass(playerId)
	state.passCount = state.passCount + 1

	local active      = getActivePlayers()
	local fieldOwner  = state.fieldOwnerId and getPlayer(state.fieldOwnerId)
	local ownerActive = fieldOwner and not fieldOwner.isFinished

	-- オーナー以外の全員がパスしたら場をリセット
	local passesNeeded = ownerActive and (#active - 1) or #active

	if state.passCount >= passesNeeded then
		state.notification = "場が流れました"
		state.field       = {}
		state.passCount   = 0
		state.currentId   = ownerActive and state.fieldOwnerId or getNextActiveId(playerId)
		state.fieldOwnerId = nil
	else
		state.currentId = getNextActiveId(playerId)
	end

	syncAll()
end

-- ============================================================
-- NPC AI（Phase 1: 最弱の有効手を出す、なければパス）
-- ============================================================

local function npcChooseCards(hand, field, isRevolution)
	-- スペ3返し: 場がジョーカー1枚なら♠3で返す
	if state.rules.spade3 and #field == 1 and field[1].suit == CardData.SUIT.JOKER then
		for _, c in ipairs(hand) do
			if c.suit == CardData.SUIT.SPADE and c.number == 3 then
				return { c }
			end
		end
	end

	if #field == 0 then
		-- 空き場: 最弱の1枚を出す
		local sorted = CardData.sortHand(hand, isRevolution)
		return { sorted[1] }
	end

	local neededCount = #field

	-- 同じ数字でグループ化
	local groups = {}
	for _, card in ipairs(hand) do
		local key = card.number
		if not groups[key] then groups[key] = {} end
		table.insert(groups[key], card)
	end

	-- 有効な手（場より強く枚数が同じ）を収集
	local validPlays = {}
	for _, group in pairs(groups) do
		if #group >= neededCount then
			local subset = {}
			for i = 1, neededCount do
				table.insert(subset, group[i])
			end
			if CardData.beats(subset, field, isRevolution) then
				table.insert(validPlays, subset)
			end
		end
	end

	if #validPlays == 0 then return nil end

	-- 強さ昇順でソート（getSetStrength でジョーカー考慮）
	table.sort(validPlays, function(a, b)
		return CardData.getSetStrength(a, isRevolution)
			 < CardData.getSetStrength(b, isRevolution)
	end)

	-- 最後の1手で反則あがりになる場合は回避を試みる
	if neededCount == #hand then
		for _, play in ipairs(validPlays) do
			local isEC = state.rules.eightCut and CardData.isEightCut(play)
			local isSR = state.rules.spade3   and CardData.isSpade3Return(play, field)
			if not CardData.isFoulWin(play, isEC, isSR, isRevolution) then
				return play
			end
		end
	end

	return validPlays[1]
end

-- NPC のターンを処理する（再帰的に次の NPC も処理）
local function processNpcTurn(playerId)
	task.wait(NPC_THINK_TIME)

	if state.phase ~= "playing" then return end
	if state.currentId ~= playerId then return end

	local cards = npcChooseCards(
		state.hands[playerId],
		state.field,
		state.isRevolution
	)

	if cards then
		doPlay(playerId, cards)
	else
		doPass(playerId)
	end

	-- 次もNPCなら続けて処理
	if state.phase == "playing" then
		local next = getPlayer(state.currentId)
		if next and next.isNPC then
			processNpcTurn(next.id)
		end
	end
end

-- ============================================================
-- カード配布
-- ============================================================

-- startPlayerId: 配布開始プレイヤー（余りカードが最初に渡る。nil なら player[1]）
local function dealCards(startPlayerId)
	local deck = CardData.shuffle(CardData.createDeck())
	for _, p in ipairs(state.players) do
		state.hands[p.id] = {}
	end
	-- 開始位置を決定
	local startIdx = 1
	if startPlayerId then
		for i, p in ipairs(state.players) do
			if p.id == startPlayerId then startIdx = i; break end
		end
	end
	-- ラウンドロビンで配る（startIdx のプレイヤーから開始）
	for i, card in ipairs(deck) do
		local idx = ((startIdx - 2 + i) % PLAYER_COUNT) + 1
		table.insert(state.hands[state.players[idx].id], card)
	end
	-- 各プレイヤーの手札をソート
	for _, p in ipairs(state.players) do
		state.hands[p.id] = CardData.sortHand(state.hands[p.id], false)
	end
end

-- ♦3 を持つプレイヤーの ID を返す
local function findDiamondThree()
	for _, p in ipairs(state.players) do
		for _, card in ipairs(state.hands[p.id] or {}) do
			if card.suit == CardData.SUIT.DIAMOND and card.number == 3 then
				return p.id
			end
		end
	end
	return state.players[1].id  -- フォールバック
end

-- ============================================================
-- ラウンドループ・階級交換
-- ============================================================

-- 交換完了 → ♦3保持者から playing 開始
completeExchange = function()
	state.exchangeState = nil
	-- 全手札をソート
	for _, p in ipairs(state.players) do
		state.hands[p.id] = CardData.sortHand(state.hands[p.id], false)
	end
	-- ♦3 保持者から開始
	state.currentId = findDiamondThree()
	local starter = getPlayer(state.currentId)
	state.notification = "♦3 を持つ " .. (starter and starter.name or "?") .. " からスタート"
	state.phase     = "playing"
	broadcastPhase("playing")
	syncAll()
	-- 最初のターンが NPC なら自動処理
	local first = getPlayer(state.currentId)
	if first and first.isNPC then
		task.spawn(function()
			processNpcTurn(state.currentId)
		end)
	end
end

-- 階級交換を開始（下位→上位の自動転送 + 上位の選択待ち）
startCardExchange = function()
	local prev = state.prevRankings
	if #prev < PLAYER_COUNT then
		completeExchange()
		return
	end

	local daifugoId    = prev[1]  -- 大富豪
	local fugoId       = prev[2]  -- 富豪
	local hinminId     = prev[3]  -- 貧民
	local daihinminId  = prev[4]  -- 大貧民

	-- Phase A: 下位 → 上位の自動転送
	-- 大貧民 → 大富豪: 最強2枚
	local strongest2 = CardData.getStrongestCards(state.hands[daihinminId], 2, false)
	state.hands[daihinminId] = removeCards(state.hands[daihinminId], strongest2)
	for _, c in ipairs(strongest2) do
		table.insert(state.hands[daifugoId], c)
	end
	state.hands[daifugoId] = CardData.sortHand(state.hands[daifugoId], false)

	-- 貧民 → 富豪: 最強1枚
	local strongest1 = CardData.getStrongestCards(state.hands[hinminId], 1, false)
	state.hands[hinminId] = removeCards(state.hands[hinminId], strongest1)
	for _, c in ipairs(strongest1) do
		table.insert(state.hands[fugoId], c)
	end
	state.hands[fugoId] = CardData.sortHand(state.hands[fugoId], false)

	-- Phase B: 上位 → 下位の選択
	state.exchangeState = { pending = {} }

	-- 大富豪: 2枚選択
	local daifugo = getPlayer(daifugoId)
	if daifugo.isNPC then
		local sorted = CardData.sortHand(state.hands[daifugoId], false)
		local weakest = {}
		for i = 1, math.min(2, #sorted) do table.insert(weakest, sorted[i]) end
		state.hands[daifugoId] = removeCards(state.hands[daifugoId], weakest)
		for _, c in ipairs(weakest) do table.insert(state.hands[daihinminId], c) end
	else
		state.exchangeState.pending[daifugoId] = { targetId = daihinminId, count = 2 }
	end

	-- 富豪: 1枚選択
	local fugo = getPlayer(fugoId)
	if fugo.isNPC then
		local sorted = CardData.sortHand(state.hands[fugoId], false)
		local weakest = { sorted[1] }
		state.hands[fugoId] = removeCards(state.hands[fugoId], weakest)
		for _, c in ipairs(weakest) do table.insert(state.hands[hinminId], c) end
	else
		state.exchangeState.pending[fugoId] = { targetId = hinminId, count = 1 }
	end

	-- 全員 NPC なら即完了、人間がいれば交換フェーズへ
	local hasPending = false
	for _ in pairs(state.exchangeState.pending) do hasPending = true; break end

	if not hasPending then
		completeExchange()
	else
		state.phase = "cardExchange"
		broadcastPhase("cardExchange")
		syncAll()
	end
end

-- 次のラウンドを開始
startNextRound = function()
	state.roundNumber = state.roundNumber + 1
	-- 前ラウンドの順位を保存
	state.prevRankings = {}
	for _, pid in ipairs(state.rankings) do
		table.insert(state.prevRankings, pid)
	end

	-- ラウンド状態リセット
	state.rankings     = {}
	state.foulRankings = {}
	state.field        = {}
	state.fieldOwnerId = nil
	state.passCount    = 0
	state.isRevolution = false
	state.notification = nil
	state.exchangeState = nil
	for _, p in ipairs(state.players) do
		p.isFinished = false
	end

	-- 大貧民（前ラウンド4位）から配布
	local daihinminId = state.prevRankings[PLAYER_COUNT]
	dealCards(daihinminId)

	state.phase = "dealing"
	broadcastPhase("dealing", { roundNumber = state.roundNumber })

	-- 階級交換へ
	startCardExchange()
end

-- ============================================================
-- ゲーム開始
-- ============================================================

local function startGame(humanPlayer)
	state.players = {
		{ id = 1, name = humanPlayer.Name, isNPC = false, isFinished = false },
		{ id = 2, name = "NPC_A",           isNPC = true,  isFinished = false },
		{ id = 3, name = "NPC_B",           isNPC = true,  isFinished = false },
		{ id = 4, name = "NPC_C",           isNPC = true,  isFinished = false },
	}
	state.hands         = {}
	state.field         = {}
	state.fieldOwnerId  = nil
	state.passCount     = 0
	state.rankings      = {}
	state.foulRankings  = {}
	state.isRevolution  = false
	state.notification  = nil
	state.roundNumber   = 1
	state.prevRankings  = {}
	state.exchangeState = nil
	state.scores        = {}
	for _, p in ipairs(state.players) do
		state.scores[p.id] = 0
	end

	dealCards()

	state.currentId = findDiamondThree()
	local starter = getPlayer(state.currentId)
	state.notification = "♦3 を持つ " .. (starter and starter.name or "?") .. " からスタート"
	state.phase     = "playing"

	broadcastPhase("playing")
	syncAll()

	-- 最初のターンが NPC なら自動処理を開始
	local first = getPlayer(state.currentId)
	if first and first.isNPC then
		task.spawn(function()
			processNpcTurn(state.currentId)
		end)
	end
end

-- ============================================================
-- RemoteEvent ハンドラ
-- ============================================================

PlayerAction.OnServerEvent:Connect(function(robloxPlayer, data)
	if state.phase ~= "playing" then return end

	-- 送信元プレイヤーを特定
	local playerInfo = nil
	for _, p in ipairs(state.players) do
		if not p.isNPC and p.name == robloxPlayer.Name then
			playerInfo = p
			break
		end
	end
	if not playerInfo then return end

	if data.type == "play" then
		local ok, err = validatePlay(playerInfo.id, data.cards)
		if not ok then
			warn("[GameManager] Invalid play from " .. robloxPlayer.Name .. ": " .. tostring(err))
			syncAll()  -- クライアント状態をリセット
			return
		end
		doPlay(playerInfo.id, data.cards)

	elseif data.type == "pass" then
		if state.currentId ~= playerInfo.id then return end
		doPass(playerInfo.id)
	end

	-- 次が NPC なら自動処理
	if state.phase == "playing" then
		local next = getPlayer(state.currentId)
		if next and next.isNPC then
			task.spawn(function()
				processNpcTurn(state.currentId)
			end)
		end
	end
end)

-- ============================================================
-- 階級交換ハンドラ
-- ============================================================

CardExchange.OnServerEvent:Connect(function(robloxPlayer, data)
	if state.phase ~= "cardExchange" then return end
	if not state.exchangeState then return end

	local playerInfo = nil
	for _, p in ipairs(state.players) do
		if not p.isNPC and p.name == robloxPlayer.Name then
			playerInfo = p
			break
		end
	end
	if not playerInfo then return end

	local pending = state.exchangeState.pending[playerInfo.id]
	if not pending then return end

	local cards = data.cards
	if not cards or #cards ~= pending.count then
		warn("[GameManager] Invalid exchange count from " .. robloxPlayer.Name)
		syncAll()
		return
	end

	if not handContains(state.hands[playerInfo.id], cards) then
		warn("[GameManager] Exchange cards not in hand: " .. robloxPlayer.Name)
		syncAll()
		return
	end

	-- カードを転送
	state.hands[playerInfo.id] = removeCards(state.hands[playerInfo.id], cards)
	for _, c in ipairs(cards) do
		table.insert(state.hands[pending.targetId], c)
	end

	-- pending から削除
	state.exchangeState.pending[playerInfo.id] = nil

	-- 全員完了チェック
	local hasPending = false
	for _ in pairs(state.exchangeState.pending) do hasPending = true; break end

	if not hasPending then
		completeExchange()
	else
		syncAll()
	end
end)

-- ============================================================
-- デバッグ用ハンドラ
-- ============================================================

DebugAction.OnServerEvent:Connect(function(robloxPlayer, actionType)
	if state.phase ~= "playing" then return end

	local playerInfo = nil
	for _, p in ipairs(state.players) do
		if not p.isNPC and p.name == robloxPlayer.Name then
			playerInfo = p
			break
		end
	end
	if not playerInfo then return end

	local myId = playerInfo.id
	local added = false

	if actionType == "add8" then
		local c = stealCard(myId, function(card)
			return card.number == 8 and card.suit ~= CardData.SUIT.JOKER
		end)
		if c then table.insert(state.hands[myId], c); added = true end

	elseif actionType == "addSpade3" then
		local c = stealCard(myId, function(card)
			return card.suit == CardData.SUIT.SPADE and card.number == 3
		end)
		if c then table.insert(state.hands[myId], c); added = true end

	elseif actionType == "addJoker" then
		local c = stealCard(myId, function(card)
			return card.suit == CardData.SUIT.JOKER
		end)
		if c then table.insert(state.hands[myId], c); added = true end

	elseif actionType == "add4x10" then
		for _ = 1, 4 do
			local c = stealCard(myId, function(card)
				return card.number == 10 and card.suit ~= CardData.SUIT.JOKER
			end)
			if c then table.insert(state.hands[myId], c); added = true end
		end

	elseif actionType == "allTo1" then
		-- 全プレイヤーの手札を1枚だけ残す
		for _, p in ipairs(state.players) do
			if not p.isFinished then
				local hand = state.hands[p.id]
				if hand and #hand > 1 then
					state.hands[p.id] = { hand[1] }
					added = true
				end
			end
		end
	end

	if added then
		state.hands[myId] = CardData.sortHand(state.hands[myId], false)
		syncAll()
	end
end)

-- ============================================================
-- プレイヤー参加時にゲーム開始
-- ============================================================

Players.PlayerAdded:Connect(function(player)
	if state.phase == "waiting" then
		task.wait(1)
		startGame(player)
	end
end)

-- スクリプトがプレイヤー参加後にロードされた場合のフォールバック
for _, player in ipairs(Players:GetPlayers()) do
	if state.phase == "waiting" then
		task.wait(1)
		startGame(player)
		break
	end
end
