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

-- セット全体の強さを返す（ジョーカーを含む場合はジョーカー強さを使用）
function CardData.getSetStrength(cards, isRevolution)
	for _, c in ipairs(cards) do
		if c.suit == CardData.SUIT.JOKER then
			return isRevolution and 0 or CardData.JOKER_STRENGTH
		end
	end
	return CardData.getStrength(cards[1], isRevolution)
end

-- played（配列）が field（配列）より強いか判定
-- 枚数が異なる場合は false を返す
function CardData.beats(played, field, isRevolution)
	if #played ~= #field then return false end
	if #played == 0 then return false end
	return CardData.getSetStrength(played, isRevolution)
		 > CardData.getSetStrength(field, isRevolution)
end

-- ============================================================
-- バリデーション
-- ============================================================

-- 出せるカードセットかチェック（全て同じ数字、またはジョーカー1枚 + 同じ数字）
function CardData.isValidSet(cards)
	if #cards == 0 then return false end
	if #cards == 1 then return true end
	-- ジョーカーは1枚だけワイルドカードとして使用可能
	local jokerCount = 0
	local baseNumber = nil
	for _, c in ipairs(cards) do
		if c.suit == CardData.SUIT.JOKER then
			jokerCount = jokerCount + 1
		else
			if baseNumber == nil then
				baseNumber = c.number
			elseif c.number ~= baseNumber then
				return false
			end
		end
	end
	return jokerCount <= 1
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

-- 手札から最強の N 枚を返す（階級交換で下位プレイヤー用）
function CardData.getStrongestCards(hand, count, isRevolution)
	local sorted = CardData.sortHand(hand, isRevolution)
	local result = {}
	for i = math.max(1, #sorted - count + 1), #sorted do
		table.insert(result, sorted[i])
	end
	return result
end

-- ============================================================
-- 特殊ルール判定
-- ============================================================

-- スペ3返し：ジョーカー1枚出しに対してスペードの3で返せるか
function CardData.isSpade3Return(played, field)
	if #played ~= 1 or #field ~= 1 then return false end
	return played[1].suit == CardData.SUIT.SPADE and played[1].number == 3
		and field[1].suit == CardData.SUIT.JOKER
end

-- 8切り：出したカードが全て8か（ジョーカー不可）
function CardData.isEightCut(cards)
	if #cards == 0 then return false end
	for _, c in ipairs(cards) do
		if c.suit == CardData.SUIT.JOKER or c.number ~= 8 then return false end
	end
	return true
end

-- 革命：ジョーカーを含まない同じ数字4枚
function CardData.isRevolutionPlay(cards)
	if #cards ~= 4 then return false end
	local baseNumber = nil
	for _, c in ipairs(cards) do
		if c.suit == CardData.SUIT.JOKER then return false end
		if baseNumber == nil then
			baseNumber = c.number
		elseif c.number ~= baseNumber then
			return false
		end
	end
	return true
end

-- 反則あがり判定
-- isEightCutPlay     : 出した手が8切りを発動したか
-- isSpade3ReturnPlay : 出した手がスペ3返しだったか
function CardData.isFoulWin(cards, isEightCutPlay, isSpade3ReturnPlay, isRevolution)
	if #cards == 0 then return false end
	-- ジョーカーを含む手でのあがり → 反則
	for _, c in ipairs(cards) do
		if c.suit == CardData.SUIT.JOKER then return true end
	end
	-- 8切り発動でのあがり → 反則
	if isEightCutPlay then return true end
	-- スペ3返しでのあがり → 反則
	if isSpade3ReturnPlay then return true end
	-- 最強数字カード（強さ13）でのあがり → 反則
	-- 通常時: 2（strength=13）、革命中: 3（strength=14-1=13）
	local strength = CardData.getSetStrength(cards, isRevolution)
	return strength == 13
end

return CardData
