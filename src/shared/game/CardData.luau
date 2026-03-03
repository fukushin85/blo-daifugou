-- CardData.luau
-- カード定義・デッキ生成・強さ比較
-- サーバー・クライアント双方から require される

local CardData = {}

-- ============================================================
-- 定数
-- ============================================================

CardData.SUIT = {
	SPADE   = 1,
	HEART   = 2,
	DIAMOND = 3,
	CLUB    = 4,
	JOKER   = 5,
}

CardData.SUIT_SYMBOL = {
	[1] = "♠",
	[2] = "♥",
	[3] = "♦",
	[4] = "♣",
	[5] = "JK",
}

-- 数字の強さ値（3が最弱=1、2が最強=13）
-- 数字の実値: J=11, Q=12, K=13, A=14, 2=2, Joker=0
CardData.NUMBER_STRENGTH = {
	[3]=1, [4]=2, [5]=3, [6]=4, [7]=5,
	[8]=6, [9]=7, [10]=8, [11]=9, [12]=10,
	[13]=11, [14]=12, [2]=13,
}

CardData.NUMBER_NAME = {
	[2]="2", [3]="3", [4]="4", [5]="5", [6]="6",
	[7]="7", [8]="8", [9]="9", [10]="10",
	[11]="J", [12]="Q", [13]="K", [14]="A",
	[0]="JK",
}

CardData.JOKER_STRENGTH = 14  -- 通常時: 全カード中最強

-- ============================================================
-- デッキ操作
-- ============================================================

-- 53枚のデッキを生成する
function CardData.createDeck()
	local deck = {}
	local suits   = { 1, 2, 3, 4 }
	local numbers = { 3,4,5,6,7,8,9,10,11,12,13,14,2 }

	for _, suit in ipairs(suits) do
		for _, number in ipairs(numbers) do
			table.insert(deck, { suit = suit, number = number })
		end
	end
	-- ジョーカー
	table.insert(deck, { suit = CardData.SUIT.JOKER, number = 0 })
	return deck
end

-- Fisher-Yates シャッフル（元のデッキを変更しない）
function CardData.shuffle(deck)
	local d = {}
	for _, c in ipairs(deck) do table.insert(d, c) end
	for i = #d, 2, -1 do
		local j = math.random(1, i)
		d[i], d[j] = d[j], d[i]
	end
	return d
end

-- ============================================================
-- 強さ比較
-- ============================================================

-- カード1枚の強さ値を返す（革命状態を考慮）
function CardData.getStrength(card, isRevolution)
	if card.suit == CardData.SUIT.JOKER then
		-- 革命中: ジョーカーは最弱（GameDesign: 強 ← 3…2, ジョーカー → 弱）
		return isRevolution and 0 or CardData.JOKER_STRENGTH
	end
	local base = CardData.NUMBER_STRENGTH[card.number]
	if isRevolution then
		-- 通常の最大強さ13を基準に逆転: 3→13, 2→1
		return 14 - base
	end
	return base
end

-- played（配列）が field（配列）より強いか判定
-- 枚数が異なる場合は false を返す
function CardData.beats(played, field, isRevolution)
	if #played ~= #field then return false end
	if #played == 0 then return false end
	-- 同枚数のセット同士はカード1枚の強さで比較（全て同数字）
	return CardData.getStrength(played[1], isRevolution)
		 > CardData.getStrength(field[1], isRevolution)
end

-- ============================================================
-- バリデーション
-- ============================================================

-- 出せるカードセットかチェック（Phase 1: 全て同じ数字）
function CardData.isValidSet(cards)
	if #cards == 0 then return false end
	if #cards == 1 then return true end
	local firstNumber = cards[1].number
	for i = 2, #cards do
		if cards[i].number ~= firstNumber then return false end
	end
	return true
end

-- ============================================================
-- 表示用
-- ============================================================

function CardData.cardToString(card)
	if card.suit == CardData.SUIT.JOKER then return "JOKER" end
	return CardData.SUIT_SYMBOL[card.suit] .. CardData.NUMBER_NAME[card.number]
end

-- 手札を強さ昇順でソートして返す（元を変更しない）
function CardData.sortHand(hand, isRevolution)
	local sorted = {}
	for _, c in ipairs(hand) do table.insert(sorted, c) end
	table.sort(sorted, function(a, b)
		return CardData.getStrength(a, isRevolution) < CardData.getStrength(b, isRevolution)
	end)
	return sorted
end

return CardData
