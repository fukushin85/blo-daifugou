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

-- ============================================================
-- 定数
-- ============================================================

local PLAYER_COUNT = 4
local NPC_THINK_TIME = 0.8  -- NPC が「考える」演出の秒数

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
	rankings      = {},       -- 上がり順 [rank] = playerId
	isRevolution  = false,
}

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
			GameStateSync:FireClient(rp, {
				hand         = state.hands[p.id] or {},
				field        = state.field,
				fieldCount   = #state.field,
				turn         = state.currentId and (getPlayer(state.currentId) or {}).name or "",
				players      = playerList,
				isRevolution = state.isRevolution,
				rankings     = state.rankings,
			})
		end
	end
end

local function broadcastPhase(phase)
	for _, p in ipairs(state.players) do
		local rp = getRobloxPlayer(p)
		if rp then
			GamePhaseChanged:FireClient(rp, { phase = phase })
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

-- ============================================================
-- 順位管理
-- ============================================================

local function finishPlayer(playerId)
	local p = getPlayer(playerId)
	if not p or p.isFinished then return end
	p.isFinished = true
	table.insert(state.rankings, playerId)
end

-- ゲーム終了判定。終了なら true を返す
local function checkGameEnd()
	local active = getActivePlayers()
	if #active <= 1 then
		if #active == 1 then
			finishPlayer(active[1].id)
		end
		state.phase = "result"
		broadcastPhase("result")
		syncAll()
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
		return false, "Cards must all be the same number"
	end
	if #state.field > 0 then
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
	state.hands[playerId] = removeCards(state.hands[playerId], cards)
	state.field       = cards
	state.fieldOwnerId = playerId
	state.passCount   = 0

	if #state.hands[playerId] == 0 then
		finishPlayer(playerId)
		if checkGameEnd() then return end
	end

	state.currentId = getNextActiveId(playerId)
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

	-- 最も弱い有効手を選ぶ
	table.sort(validPlays, function(a, b)
		return CardData.getStrength(a[1], isRevolution)
			 < CardData.getStrength(b[1], isRevolution)
	end)
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

local function dealCards()
	local deck = CardData.shuffle(CardData.createDeck())
	for _, p in ipairs(state.players) do
		state.hands[p.id] = {}
	end
	-- ラウンドロビンで配る
	for i, card in ipairs(deck) do
		local idx      = ((i - 1) % PLAYER_COUNT) + 1
		local playerId = state.players[idx].id
		table.insert(state.hands[playerId], card)
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
-- ゲーム開始
-- ============================================================

local function startGame(humanPlayer)
	state.players = {
		{ id = 1, name = humanPlayer.Name, isNPC = false, isFinished = false },
		{ id = 2, name = "NPC_A",           isNPC = true,  isFinished = false },
		{ id = 3, name = "NPC_B",           isNPC = true,  isFinished = false },
		{ id = 4, name = "NPC_C",           isNPC = true,  isFinished = false },
	}
	state.hands        = {}
	state.field        = {}
	state.fieldOwnerId = nil
	state.passCount    = 0
	state.rankings     = {}
	state.isRevolution = false

	dealCards()

	state.currentId = findDiamondThree()
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
