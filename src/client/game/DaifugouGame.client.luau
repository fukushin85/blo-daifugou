-- DaifugouGame.client.luau
-- 手札UI・カード選択・アクション送信
-- Phase 1: テキストベースの機能的UI

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService     = game:GetService("TweenService")

local CardData = require(ReplicatedStorage.Shared.game.CardData)

local localPlayer = Players.LocalPlayer

local NOTIF_DISPLAY_SEC = 1.5  -- 通知ラベルの表示秒数

-- RemoteEvent（GameManager が生成するまで待つ）
local function waitForEvent(name)
	local e = ReplicatedStorage:WaitForChild(name, 30)
	assert(e, "[DaifugouGame] RemoteEvent not found: " .. name)
	return e
end

local PlayerAction     = waitForEvent("PlayerAction")
local GameStateSync    = waitForEvent("GameStateSync")
local GamePhaseChanged = waitForEvent("GamePhaseChanged")
local DebugAction      = waitForEvent("DebugAction")
local CardExchange     = waitForEvent("CardExchange")

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

-- 通知ラベル（革命・反則あがりなど、3秒表示）
local notifLabel = makeLabel("", UDim2.new(1, 0, 0.06, 0), UDim2.new(0, 0, 0.38, 0), screenGui,
	Color3.fromRGB(180, 60, 0))
notifLabel.Visible = false
notifLabel.ZIndex = 5

-- 結果表示オーバーレイ（result / finalResult フェーズで使用）
local resultFrame = Instance.new("Frame")
resultFrame.Size = UDim2.new(0.6, 0, 0.6, 0)
resultFrame.Position = UDim2.new(0.2, 0, 0.15, 0)
resultFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 40)
resultFrame.BackgroundTransparency = 0.1
resultFrame.Visible = false
resultFrame.ZIndex = 15
resultFrame.Parent = screenGui

local resultTitle = makeLabel("", UDim2.new(1, 0, 0.15, 0), UDim2.new(0, 0, 0, 0), resultFrame,
	Color3.fromRGB(40, 40, 80))
resultTitle.ZIndex = 16

local resultBody = makeLabel("", UDim2.new(1, 0, 0.78, 0), UDim2.new(0, 0, 0.15, 0), resultFrame,
	Color3.fromRGB(20, 20, 40))
resultBody.ZIndex = 16
resultBody.TextYAlignment = Enum.TextYAlignment.Top

-- タイマーバー（result 下部に表示）
local timerBarBg = Instance.new("Frame")
timerBarBg.Size = UDim2.new(0.9, 0, 0.04, 0)
timerBarBg.Position = UDim2.new(0.05, 0, 0.93, 0)
timerBarBg.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
timerBarBg.ZIndex = 16
timerBarBg.Parent = resultFrame

local timerBar = Instance.new("Frame")
timerBar.Size = UDim2.new(1, 0, 1, 0)
timerBar.Position = UDim2.new(0, 0, 0, 0)
timerBar.BackgroundColor3 = Color3.fromRGB(100, 180, 255)
timerBar.ZIndex = 17
timerBar.Parent = timerBarBg

-- ---- デバッグUI ----

local debugBtn = makeButton("DEBUG", UDim2.fromOffset(80, 26), UDim2.new(0.5, -40, 0, 2), screenGui)
debugBtn.BackgroundColor3 = Color3.fromRGB(80, 60, 100)
debugBtn.ZIndex = 20

local debugMenu = Instance.new("Frame")
debugMenu.Size = UDim2.fromOffset(210, 10)  -- 高さは AutomaticSize で自動調整
debugMenu.AutomaticSize = Enum.AutomaticSize.Y
debugMenu.Position = UDim2.new(0.5, -105, 0, 30)
debugMenu.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
debugMenu.BackgroundTransparency = 0.1
debugMenu.Visible = false
debugMenu.ZIndex = 20
debugMenu.Parent = screenGui

local debugPad = Instance.new("UIPadding")
debugPad.PaddingTop    = UDim.new(0, 4)
debugPad.PaddingBottom = UDim.new(0, 4)
debugPad.PaddingLeft   = UDim.new(0, 4)
debugPad.PaddingRight  = UDim.new(0, 4)
debugPad.Parent = debugMenu

local debugLayout = Instance.new("UIListLayout")
debugLayout.FillDirection = Enum.FillDirection.Vertical
debugLayout.Padding = UDim.new(0, 4)
debugLayout.Parent = debugMenu

local debugItems = {
	{ "8 を追加",      "add8"      },
	{ "♠3 を追加",    "addSpade3" },
	{ "Joker を追加",  "addJoker"  },
	{ "10 を 4 枚追加", "add4x10"  },
	{ "全員 残り1枚",  "allTo1"    },
	{ "反則: 2で上がり",      "foul2"       },
	{ "反則: 8切りで上がり",  "foul8"       },
	{ "反則: スペ3で上がり",  "foulSpade3"  },
	{ "反則: Jokerで上がり",  "foulJoker"   },
	{ "反則: 全員8で1枚",    "foulAll8"    },
	{ "反則: 革命+3で上がり", "foulRev3"   },
}

for _, item in ipairs(debugItems) do
	local btn = Instance.new("TextButton")
	btn.Text = item[1]
	btn.Size = UDim2.new(1, 0, 0, 34)
	btn.BackgroundColor3 = Color3.fromRGB(70, 70, 90)
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.TextScaled = true
	btn.Font = Enum.Font.Gotham
	btn.ZIndex = 21
	btn.Parent = debugMenu
	local action = item[2]
	btn.MouseButton1Click:Connect(function()
		debugMenu.Visible = false
		DebugAction:FireServer(action)
	end)
end

debugBtn.MouseButton1Click:Connect(function()
	debugMenu.Visible = not debugMenu.Visible
end)

-- ============================================================
-- 状態
-- ============================================================

local myHand        = {}   -- 現在の手札
local selectedCards = {}   -- 選択中のカード（suit+number で識別）
local isMyTurn      = false
local cardButtons   = {}   -- カードボタンの参照
local exchangeMode  = false  -- 階級交換モード
local exchangeInfo  = nil    -- { mustGiveCount, targetName }
local cachedPlayers = {}     -- プレイヤー名リスト（結果表示用）

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
	local isJoker = (card.suit == CardData.SUIT.JOKER)

	-- すでに選択済み → 解除
	if selectedCards[key] then
		selectedCards[key] = nil
		return
	end

	-- 交換モード: 同じ数字制限なし、枚数制限のみ
	if exchangeMode then
		local count = 0
		for _ in pairs(selectedCards) do count = count + 1 end
		if exchangeInfo and count >= exchangeInfo.mustGiveCount then
			-- 枚数上限 → 追加しない
			return
		end
		selectedCards[key] = card
		return
	end

	if isJoker then
		-- ジョーカーはどの選択にもワイルドカードとして追加可能
		selectedCards[key] = card
		return
	end

	-- 非ジョーカー: 選択中の非ジョーカーカードのベース数字を確認
	local baseNumber = nil
	for _, sc in pairs(selectedCards) do
		if sc.suit ~= CardData.SUIT.JOKER then
			baseNumber = sc.number
			break
		end
	end

	-- 異なる数字のカードをクリック → 選択をリセットして新しいカードだけ選択
	if baseNumber ~= nil and card.number ~= baseNumber then
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
			if not isMyTurn and not exchangeMode then return end
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
	local showQuick = (isMyTurn or exchangeMode) and count > 0
	quickSubmitBtn.Visible = showQuick
	if showQuick then
		if exchangeMode then
			local need = exchangeInfo and exchangeInfo.mustGiveCount or 0
			quickSubmitBtn.Text = "交換（" .. count .. "/" .. need .. "枚）"
		else
			quickSubmitBtn.Text = "出す（" .. count .. "枚）"
		end

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
	-- 全プレイヤー情報を更新（自分含む）
	for _, child in ipairs(opponentFrame:GetChildren()) do
		child:Destroy()
	end

	for i, p in ipairs(players) do
		local isCurrentTurn = (p.name == currentTurn)
		local isMe = (p.name == localPlayer.Name)
		local label = Instance.new("TextLabel")
		label.Size     = UDim2.new(1 / #players, -4, 1, 0)
		label.Position = UDim2.new((i - 1) / #players, 2, 0, 0)
		local status = p.rank and ("(" .. p.rank .. ")") or (p.isFinished and "（上がり）" or (tostring(p.handCount) .. "枚"))
		local nameStr = isMe and ("★" .. p.name) or p.name
		label.Text     = (isCurrentTurn and "▶ " or "") .. nameStr .. ": " .. status
		label.BackgroundColor3 = isCurrentTurn
			and (isMe and Color3.fromRGB(220, 100, 100) or Color3.fromRGB(80, 190, 220))
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

	-- ターン表示（ラウンド番号・自分の順位込み）
	local isMyTurnNow = (data.turn == localPlayer.Name)
	isMyTurn = isMyTurnNow
	local roundStr = "R" .. (data.roundNumber or 1) .. "/4  "
	-- 自分の順位を取得
	local myRank = nil
	for _, p in ipairs(data.players) do
		if p.name == localPlayer.Name and p.rank then
			myRank = p.rank
			break
		end
	end
	local myRankStr = myRank and ("  [" .. myRank .. "]") or ""
	if isMyTurnNow then
		turnLabel.Text = roundStr .. "★ あなたのターン" .. myRankStr
	else
		turnLabel.Text = roundStr .. "ターン: " .. (data.turn or "-") .. myRankStr
	end

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

	-- 順位・スコア表示（毎回一括で組み立て）
	local infoParts = {}
	if #data.rankings > 0 then
		local rankNames = { "大富豪", "富豪", "貧民", "大貧民" }
		local rParts = {}
		for i = 1, #data.rankings do
			table.insert(rParts, (rankNames[i] or tostring(i)))
		end
		table.insert(infoParts, "上がり順: " .. table.concat(rParts, " → "))
	end
	if data.scores then
		local scoreTexts = {}
		for i, p in ipairs(data.players) do
			local sc = data.scores[i] or 0
			table.insert(scoreTexts, p.name .. ":" .. sc .. "pt")
		end
		table.insert(infoParts, table.concat(scoreTexts, "  "))
	end
	if #infoParts > 0 then
		rankingsLabel.Text = table.concat(infoParts, "    ")
		rankingsLabel.Visible = true
	end

	-- プレイヤー名キャッシュ更新（結果表示用）
	cachedPlayers = {}
	for _, p in ipairs(data.players) do
		table.insert(cachedPlayers, p.name)
	end

	-- 交換情報の更新（GamePhaseChanged より後に届く場合があるため、ここで交換モードを有効化）
	if data.exchangeInfo then
		exchangeInfo = data.exchangeInfo
		if not exchangeMode and exchangeInfo.mustGiveCount then
			exchangeMode = true
			messageLabel.Text = exchangeInfo.targetName .. " に " .. exchangeInfo.mustGiveCount .. " 枚渡してください"
			messageLabel.Visible = true
			submitBtn.Text = "交換する"
			submitBtn.BackgroundColor3 = Color3.fromRGB(60, 120, 200)
			submitBtn.Active = true
			passBtn.Visible = false
			clearSelection()
		end
	else
		exchangeInfo = nil
	end

	-- 通知表示（革命・反則あがりなど）
	if data.notification and data.notification ~= "" then
		notifLabel.Text = data.notification
		notifLabel.Visible = true
		task.delay(NOTIF_DISPLAY_SEC, function()
			notifLabel.Visible = false
		end)
	end

	-- 手札を再描画（選択状態を維持）
	refreshCardButtons()

	-- ボタン有効/無効（交換モード中はボタン制御しない）
	if not exchangeMode then
		setButtonsEnabled(isMyTurnNow)
	end

	-- 自分のターンでなく交換モードでもなければ選択をリセット
	if not isMyTurnNow and not exchangeMode then
		clearSelection()
	end
end)

-- ============================================================
-- GamePhaseChanged 受信
-- ============================================================

GamePhaseChanged.OnClientEvent:Connect(function(data)
	if data.phase == "dealing" then
		-- ラウンド開始
		resultFrame.Visible = false
		messageLabel.Text = "ラウンド " .. (data.roundNumber or "") .. " カード配布中…"
		messageLabel.Visible = true
		setButtonsEnabled(false)
		exchangeMode = false
		exchangeInfo = nil
		clearSelection()

	elseif data.phase == "cardExchange" then
		-- 階級交換フェーズ
		resultFrame.Visible = false
		messageLabel.Visible = false
		if exchangeInfo and exchangeInfo.mustGiveCount then
			-- 上位プレイヤー: カードを選んで交換
			exchangeMode = true
			messageLabel.Text = exchangeInfo.targetName .. " に " .. exchangeInfo.mustGiveCount .. " 枚渡してください"
			messageLabel.Visible = true
			submitBtn.Text = "交換する"
			submitBtn.BackgroundColor3 = Color3.fromRGB(60, 120, 200)
			submitBtn.Active = true
			passBtn.Visible = false
		else
			-- 下位プレイヤー or 関係ないプレイヤー: 待機
			exchangeMode = false
			messageLabel.Text = "階級交換中…"
			messageLabel.Visible = true
			setButtonsEnabled(false)
		end
		clearSelection()
		refreshCardButtons()

	elseif data.phase == "playing" then
		-- ゲーム中
		resultFrame.Visible = false
		messageLabel.Visible = false
		exchangeMode = false
		exchangeInfo = nil
		submitBtn.Text = "出す"
		passBtn.Visible = true

	elseif data.phase == "result" then
		-- ラウンド結果表示
		setButtonsEnabled(false)
		exchangeMode = false
		local rn = data.roundNumber or 0
		resultTitle.Text = "ラウンド " .. rn .. " 結果"

		local lines = {}
		if data.roundResult then
			for _, entry in ipairs(data.roundResult) do
				table.insert(lines, entry.rank .. ": " .. entry.name .. "  (+" .. entry.points .. "pt)")
			end
		end
		-- 累計スコア
		if data.scores then
			table.insert(lines, "")
			table.insert(lines, "--- 累計スコア ---")
			for i, p in ipairs(cachedPlayers) do
				local sc = data.scores[i] or 0
				table.insert(lines, p .. ": " .. sc .. "pt")
			end
		end
		resultBody.Text = table.concat(lines, "\n")
		resultFrame.Visible = true

		-- タイマーバーアニメーション
		local sec = data.displaySec or 5
		timerBar.Size = UDim2.new(1, 0, 1, 0)
		timerBarBg.Visible = true
		local tween = TweenService:Create(timerBar,
			TweenInfo.new(sec, Enum.EasingStyle.Linear),
			{ Size = UDim2.new(0, 0, 1, 0) })
		tween:Play()

	elseif data.phase == "finalResult" then
		-- セット最終結果
		setButtonsEnabled(false)
		exchangeMode = false
		resultTitle.Text = "最終結果"

		local lines = {}
		if data.finalRanking then
			for i, entry in ipairs(data.finalRanking) do
				table.insert(lines, i .. "位: " .. entry.name .. "  " .. entry.score .. "pt")
			end
		end
		resultBody.Text = table.concat(lines, "\n")
		timerBarBg.Visible = false
		resultFrame.Visible = true
	end
end)

-- ============================================================
-- ボタン操作
-- ============================================================

local function doSubmit()
	local cards = getSelectedList()
	if #cards == 0 then return end

	if exchangeMode then
		-- 交換モード: 必要枚数チェック
		if not exchangeInfo or #cards ~= exchangeInfo.mustGiveCount then return end
		clearSelection()
		exchangeMode = false
		refreshCardButtons()
		CardExchange:FireServer({ cards = cards })
		messageLabel.Text = "交換完了 待機中…"
		setButtonsEnabled(false)
	else
		if not isMyTurn then return end
		clearSelection()
		refreshCardButtons()
		PlayerAction:FireServer({ type = "play", cards = cards })
	end
end

quickSubmitBtn.MouseButton1Click:Connect(doSubmit)
submitBtn.MouseButton1Click:Connect(doSubmit)

passBtn.MouseButton1Click:Connect(function()
	if not isMyTurn then return end

	clearSelection()
	refreshCardButtons()

	PlayerAction:FireServer({ type = "pass" })
end)
