-- DaifugouGame.client.luau
-- 手札UI・カード選択・アクション送信
-- Phase 1: テキストベースの機能的UI

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CardData = require(ReplicatedStorage.Shared.game.CardData)

local localPlayer = Players.LocalPlayer

-- RemoteEvent（GameManager が生成するまで待つ）
local function waitForEvent(name)
	local e = ReplicatedStorage:WaitForChild(name, 30)
	assert(e, "[DaifugouGame] RemoteEvent not found: " .. name)
	return e
end

local PlayerAction     = waitForEvent("PlayerAction")
local GameStateSync    = waitForEvent("GameStateSync")
local GamePhaseChanged = waitForEvent("GamePhaseChanged")

-- ============================================================
-- UI 構築
-- ============================================================

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DaifugouGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = localPlayer.PlayerGui

-- ---- 共通スタイル ----
local function makeLabel(text, size, position, parent, color)
	local label = Instance.new("TextLabel")
	label.Text = text
	label.Size = size
	label.Position = position
	label.BackgroundTransparency = 0.5
	label.BackgroundColor3 = color or Color3.fromRGB(30, 30, 30)
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = parent
	return label
end

local function makeButton(text, size, position, parent)
	local btn = Instance.new("TextButton")
	btn.Text = text
	btn.Size = size
	btn.Position = position
	btn.BackgroundColor3 = Color3.fromRGB(60, 120, 200)
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.TextScaled = true
	btn.Font = Enum.Font.GothamBold
	btn.Parent = parent
	return btn
end

-- ---- レイアウト ----

-- 情報エリア（上部）
local infoFrame = Instance.new("Frame")
infoFrame.Size = UDim2.new(1, 0, 0.12, 0)
infoFrame.Position = UDim2.new(0, 0, 0, 0)
infoFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 40)
infoFrame.BackgroundTransparency = 0.3
infoFrame.Parent = screenGui

local turnLabel = makeLabel("ターン: -", UDim2.new(0.5, 0, 1, 0), UDim2.new(0, 0, 0, 0), infoFrame)
local revolutionLabel = makeLabel("", UDim2.new(0.5, 0, 1, 0), UDim2.new(0.5, 0, 0, 0), infoFrame,
	Color3.fromRGB(150, 20, 20))

-- 相手の手札枚数エリア
local opponentFrame = Instance.new("Frame")
opponentFrame.Size = UDim2.new(1, 0, 0.1, 0)
opponentFrame.Position = UDim2.new(0, 0, 0.12, 0)
opponentFrame.BackgroundTransparency = 1
opponentFrame.Parent = screenGui

-- 場のカードエリア（中央）
local fieldFrame = Instance.new("Frame")
fieldFrame.Size = UDim2.new(1, 0, 0.3, 0)
fieldFrame.Position = UDim2.new(0, 0, 0.22, 0)
fieldFrame.BackgroundColor3 = Color3.fromRGB(0, 80, 0)
fieldFrame.BackgroundTransparency = 0.5
fieldFrame.Parent = screenGui

local fieldLabel = makeLabel("（場は空）", UDim2.new(1, 0, 1, 0), UDim2.new(0, 0, 0, 0), fieldFrame)

-- 順位表示エリア
local rankingsLabel = makeLabel("", UDim2.new(1, 0, 0.08, 0), UDim2.new(0, 0, 0.52, 0), screenGui,
	Color3.fromRGB(20, 60, 20))

-- カード上部の「出す」ボタン（選択中のみ表示・位置は動的に設定）
local quickSubmitBtn = makeButton("出す", UDim2.fromOffset(120, 40), UDim2.fromOffset(0, 0), screenGui)
quickSubmitBtn.Visible = false
quickSubmitBtn.ZIndex = 10
quickSubmitBtn.BackgroundColor3 = Color3.fromRGB(220, 80, 40)

-- 手札エリア（下部）
local handFrame = Instance.new("ScrollingFrame")
handFrame.Size = UDim2.new(1, 0, 0.2, 0)
handFrame.Position = UDim2.new(0, 0, 0.62, 0)
handFrame.BackgroundColor3 = Color3.fromRGB(10, 50, 10)
handFrame.BackgroundTransparency = 0.3
handFrame.ScrollBarThickness = 6
handFrame.CanvasSize = UDim2.new(0, 0, 0, 0)  -- 動的に調整
handFrame.Parent = screenGui

local handLayout = Instance.new("UIListLayout")
handLayout.FillDirection = Enum.FillDirection.Horizontal
handLayout.SortOrder = Enum.SortOrder.LayoutOrder
handLayout.Padding = UDim.new(0, 4)
handLayout.Parent = handFrame

-- アクションボタンエリア
local actionFrame = Instance.new("Frame")
actionFrame.Size = UDim2.new(1, 0, 0.1, 0)
actionFrame.Position = UDim2.new(0, 0, 0.88, 0)
actionFrame.BackgroundTransparency = 1
actionFrame.Parent = screenGui

local submitBtn = makeButton("出す", UDim2.new(0.3, 0, 1, 0), UDim2.new(0.1, 0, 0, 0), actionFrame)
local passBtn   = makeButton("パス", UDim2.new(0.3, 0, 1, 0), UDim2.new(0.6, 0, 0, 0), actionFrame)

-- メッセージ表示用ラベル（結果など）
local messageLabel = makeLabel("", UDim2.new(1, 0, 0.08, 0), UDim2.new(0, 0, 0.44, 0), screenGui,
	Color3.fromRGB(80, 40, 0))
messageLabel.Visible = false

-- ============================================================
-- 状態
-- ============================================================

local myHand        = {}   -- 現在の手札
local selectedCards = {}   -- 選択中のカード（suit+number で識別）
local isMyTurn      = false
local cardButtons   = {}   -- カードボタンの参照

-- ============================================================
-- カード選択管理
-- ============================================================

local function cardKey(card)
	return tostring(card.suit) .. "_" .. tostring(card.number)
end

local function isSelected(card)
	return selectedCards[cardKey(card)] ~= nil
end

local function toggleSelect(card)
	local key = cardKey(card)

	-- すでに選択済み → 解除
	if selectedCards[key] then
		selectedCards[key] = nil
		return
	end

	-- 現在の選択カードの数字を取得
	local selectedNumber = nil
	for _, sc in pairs(selectedCards) do
		selectedNumber = sc.number
		break
	end

	-- 選択済みカードと数字が異なる → 選択をリセットして新しいカードだけ選択
	if selectedNumber ~= nil and card.number ~= selectedNumber then
		selectedCards = {}
	end

	selectedCards[key] = card
end

local function getSelectedList()
	local list = {}
	for _, card in pairs(selectedCards) do
		table.insert(list, card)
	end
	return list
end

local function clearSelection()
	selectedCards = {}
end

-- ============================================================
-- UI 更新
-- ============================================================

local function refreshCardButtons()
	-- 既存のボタンをすべて削除
	for _, btn in ipairs(cardButtons) do
		btn:Destroy()
	end
	cardButtons = {}

	local CARD_WIDTH  = 70
	local CARD_HEIGHT = 90

	for i, card in ipairs(myHand) do
		local isJoker = card.suit == CardData.SUIT.JOKER
		local isRed   = card.suit == CardData.SUIT.HEART or card.suit == CardData.SUIT.DIAMOND

		local btn = Instance.new("TextButton")
		btn.Size     = UDim2.new(0, CARD_WIDTH, 0, CARD_HEIGHT)
		btn.Text     = CardData.cardToString(card)
		btn.Font     = Enum.Font.GothamBold
		btn.TextScaled = true
		btn.LayoutOrder = i
		btn.BackgroundColor3 = isSelected(card)
			and Color3.fromRGB(255, 220, 50)
			or  Color3.fromRGB(240, 240, 240)
		btn.TextColor3 = isJoker and Color3.fromRGB(100, 0, 200)
			or isRed and Color3.fromRGB(200, 0, 0)
			or Color3.fromRGB(0, 0, 0)
		btn.Parent = handFrame

		local capturedCard = card
		btn.MouseButton1Click:Connect(function()
			if not isMyTurn then return end
			toggleSelect(capturedCard)
			refreshCardButtons()
		end)

		table.insert(cardButtons, btn)
	end

	-- スクロール幅を調整
	handFrame.CanvasSize = UDim2.new(0, #myHand * (CARD_WIDTH + 4), 0, 0)

	-- カード上部「出す」ボタンの表示更新
	local count = 0
	for _ in pairs(selectedCards) do count = count + 1 end
	local showQuick = isMyTurn and count > 0
	quickSubmitBtn.Visible = showQuick
	if showQuick then
		quickSubmitBtn.Text = "出す（" .. count .. "枚）"

		-- AbsolutePosition はフレーム描画後に確定するため次フレームで計算
		task.defer(function()
			if not quickSubmitBtn.Visible then return end

			local CARD_TOTAL_WIDTH = CARD_WIDTH + 4  -- カード幅 + パディング
			local BTN_WIDTH = 120
			local BTN_HEIGHT = 40

			-- 選択カードのインデックス範囲を取得
			local minIdx, maxIdx = math.huge, 0
			for i, card in ipairs(myHand) do
				if isSelected(card) then
					if i < minIdx then minIdx = i end
					if i > maxIdx then maxIdx = i end
				end
			end
			if maxIdx == 0 then return end

			-- 選択カード群のキャンバス上の中央 x（カード左端基準）
			local canvasLeft   = (minIdx - 1) * CARD_TOTAL_WIDTH
			local canvasRight  = (maxIdx - 1) * CARD_TOTAL_WIDTH + CARD_WIDTH
			local canvasCenter = (canvasLeft + canvasRight) / 2

			-- スクリーン x（スクロールオフセットを引く）
			local frameX      = handFrame.AbsolutePosition.X
			local scrollX     = handFrame.CanvasPosition.X
			local screenCenterX = frameX + canvasCenter - scrollX

			-- はみ出し防止
			local screenW = workspace.CurrentCamera.ViewportSize.X
			local btnLeft = math.clamp(screenCenterX - BTN_WIDTH / 2, 0, screenW - BTN_WIDTH)

			-- Y は handFrame の直上
			local btnY = handFrame.AbsolutePosition.Y - BTN_HEIGHT - 6

			quickSubmitBtn.Position = UDim2.fromOffset(btnLeft, btnY)
		end)
	end
end

local function refreshOpponents(players, currentTurn)
	-- 相手プレイヤー情報を更新
	for _, child in ipairs(opponentFrame:GetChildren()) do
		child:Destroy()
	end

	local others = {}
	for _, p in ipairs(players) do
		if p.name ~= localPlayer.Name then
			table.insert(others, p)
		end
	end

	for i, p in ipairs(others) do
		local isCurrentTurn = (p.name == currentTurn)
		local label = Instance.new("TextLabel")
		label.Size     = UDim2.new(1 / #others, -4, 1, 0)
		label.Position = UDim2.new((i - 1) / #others, 2, 0, 0)
		local status = p.isFinished and "（上がり）" or (tostring(p.handCount) .. "枚")
		label.Text     = (isCurrentTurn and "▶ " or "") .. p.name .. ": " .. status
		label.BackgroundColor3 = isCurrentTurn
			and Color3.fromRGB(80, 190, 220)   -- 手番中: 水色
			or  Color3.fromRGB(40, 40, 60)
		label.BackgroundTransparency = isCurrentTurn and 0 or 0.3
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.TextScaled = true
		label.Font = isCurrentTurn and Enum.Font.GothamBold or Enum.Font.Gotham
		label.Parent = opponentFrame
	end
end

local function setButtonsEnabled(enabled)
	submitBtn.BackgroundColor3 = enabled
		and Color3.fromRGB(60, 120, 200)
		or  Color3.fromRGB(100, 100, 100)
	passBtn.BackgroundColor3 = enabled
		and Color3.fromRGB(60, 120, 200)
		or  Color3.fromRGB(100, 100, 100)
	submitBtn.Active = enabled
	passBtn.Active   = enabled
end

-- ============================================================
-- GameStateSync 受信
-- ============================================================

GameStateSync.OnClientEvent:Connect(function(data)
	myHand = data.hand or {}

	-- ターン表示
	local isMyTurnNow = (data.turn == localPlayer.Name)
	isMyTurn = isMyTurnNow
	turnLabel.Text = isMyTurnNow
		and "★ あなたのターン"
		or  "ターン: " .. (data.turn or "-")

	-- 革命表示
	revolutionLabel.Text = data.isRevolution and "🔥 革命中！" or ""

	-- 場のカード表示
	if #data.field == 0 then
		fieldLabel.Text = "（場は空）"
	else
		local fieldStr = ""
		for _, card in ipairs(data.field) do
			fieldStr = fieldStr .. CardData.cardToString(card) .. "  "
		end
		fieldLabel.Text = fieldStr
	end

	-- 相手の手札枚数（手番プレイヤーをハイライト）
	refreshOpponents(data.players, data.turn)

	-- 順位表示（rankings は playerName の配列として扱う、Phase 1 簡易版）
	if #data.rankings > 0 then
		local rankNames = { "大富豪", "富豪", "貧民", "大貧民" }
		local parts = {}
		for i = 1, #data.rankings do
			table.insert(parts, (rankNames[i] or tostring(i)))
		end
		rankingsLabel.Text = "上がり順: " .. table.concat(parts, " → ")
		rankingsLabel.Visible = true
	end

	-- 手札を再描画（選択状態を維持）
	refreshCardButtons()

	-- ボタン有効/無効
	setButtonsEnabled(isMyTurnNow)

	-- 自分のターンでなければ選択をリセット
	if not isMyTurnNow then
		clearSelection()
	end
end)

-- ============================================================
-- GamePhaseChanged 受信
-- ============================================================

GamePhaseChanged.OnClientEvent:Connect(function(data)
	if data.phase == "result" then
		messageLabel.Text = "ゲーム終了！"
		messageLabel.Visible = true
		setButtonsEnabled(false)
	elseif data.phase == "playing" then
		messageLabel.Visible = false
	end
end)

-- ============================================================
-- ボタン操作
-- ============================================================

quickSubmitBtn.MouseButton1Click:Connect(function()
	if not isMyTurn then return end

	local cards = getSelectedList()
	if #cards == 0 then return end

	clearSelection()
	refreshCardButtons()

	PlayerAction:FireServer({ type = "play", cards = cards })
end)

submitBtn.MouseButton1Click:Connect(function()
	if not isMyTurn then return end

	local cards = getSelectedList()
	if #cards == 0 then return end

	clearSelection()
	refreshCardButtons()

	PlayerAction:FireServer({ type = "play", cards = cards })
end)

passBtn.MouseButton1Click:Connect(function()
	if not isMyTurn then return end

	clearSelection()
	refreshCardButtons()

	PlayerAction:FireServer({ type = "pass" })
end)
