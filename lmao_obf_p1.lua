--[[
    HongSondev Chess Trainer v5 - Server Edition
    Hoạt động trên mọi môi trường (Studio + Server thường)
    Không phụ thuộc RemoteFunction, ModuleScript hay auth
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local LOCAL_PLAYER = Players.LocalPlayer
local GUI_NAME = "2DBoard"

-- Engine defaults
local SEARCH_MAX_DEPTH = 16
local SEARCH_TIME_BUDGET = 4.00
local QUIESCENCE_DEPTH = 8
local REFRESH_DEBOUNCE = 0.14
local TT_MAX_ENTRIES = 180000
local YIELD_EVERY_NODES = 3072
local PONDER_BUDGET_FACTOR = 1.35
local PONDER_MIN_BUDGET = 2.25
local MOVE_GUIDE_THICKNESS = 6
local MOVE_GUIDE_GLOW = 14
local ASPIRATION_START = 55
local MATE_SCORE = 1000000
local MIN_STABLE_DEPTH = 4
local STABLE_DEPTHS_REQUIRED = 2
local HARD_BUDGET_MULTIPLIER = 2.0
local HARD_BUDGET_CAP = 16.0

local GREEN_FROM = Color3.fromRGB(46, 160, 67)
local GREEN_TO = Color3.fromRGB(35, 200, 83)
local PANEL_BG = Color3.fromRGB(20, 24, 28)
local PANEL_TEXT = Color3.fromRGB(245, 247, 250)
local PANEL_MUTED = Color3.fromRGB(173, 181, 189)

-- ============================================================================
-- KIỂM TRA MÔI TRƯỜNG - TỰ ĐỘNG THÍCH ỨNG
-- ============================================================================

local function isStudio()
    return RunService:IsStudio()
end

local function isServer()
    return not isStudio() and RunService:IsRunning()
end

local function getEnvironment()
    if isStudio() then return "Studio" end
    if isServer() then return "Server" end
    return "Unknown"
end

-- ============================================================================
-- KHỞI TẠO KHÔNG PHỤ THUỘC
-- ============================================================================

local FILES = "abcdefgh"

local PIECE_CODE = {
    White_Pawn = "wP",
    White_Knight = "wN",
    White_Bishop = "wB",
    White_Rook = "wR",
    White_Queen = "wQ",
    White_King = "wK",
    Black_Pawn = "bP",
    Black_Knight = "bN",
    Black_Bishop = "bB",
    Black_Rook = "bR",
    Black_Queen = "bQ",
    Black_King = "bK",
}

local PIECE_VALUE = {
    P = 100,
    N = 320,
    B = 330,
    R = 500,
    Q = 900,
    K = 20000,
}

local KNIGHT_DELTAS = {
    { 1, 2 }, { 2, 1 }, { 2, -1 }, { 1, -2 },
    { -1, -2 }, { -2, -1 }, { -2, 1 }, { -1, 2 },
}

local KING_DELTAS = {
    { 1, 1 }, { 1, 0 }, { 1, -1 }, { 0, 1 },
    { 0, -1 }, { -1, 1 }, { -1, 0 }, { -1, -1 },
}

local BISHOP_DIRS = { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
local ROOK_DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
local QUEEN_DIRS = {
    { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 },
    { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
}

local state = {
    boardGui = nil,
    main = nil,
    boardFrame = nil,
    piecesFrame = nil,
    sideMode = "Auto",
    playerSide = "w",
    trackedSide = "w",
    lastBoard = nil,
    lastPositionKey = nil,
    refreshSerial = 0,
    analysisGeneration = 0,
    searchRunning = false,
    pondering = false,
    lastRenderedKey = nil,
    connections = {},
    panel = nil,
    statusLabel = nil,
    statsLabel = nil,
    modeButton = nil,
    uiBackend = "Built-in",
    collapsed = false,
    floatingToggle = nil,
    searchBudget = SEARCH_TIME_BUDGET,
    engineStats = { nodes = 0, ttHits = 0, cutoffs = 0, qNodes = 0, elapsed = 0 },
    lastMove = nil,
    castling = {
        wK = true, wQ = true,
        bK = true, bQ = true,
    },
}

local function disconnectAll()
    for _, connection in ipairs(state.connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    table.clear(state.connections)
end

local function inBounds(file, rank)
    return file >= 1 and file <= 8 and rank >= 1 and rank <= 8
end

local function toSquare(file, rank)
    if not inBounds(file, rank) then
        return nil
    end
    return string.sub(FILES, file, file) .. tostring(rank)
end

local function fromSquare(square)
    if type(square) ~= "string" or not string.match(square, "^[a-h][1-8]$") then
        return nil, nil
    end
    local file = string.find(FILES, string.sub(square, 1, 1), 1, true)
    local rank = tonumber(string.sub(square, 2, 2))
    return file, rank
end

local function opposite(side)
    return side == "w" and "b" or "w"
end

local function shallowCopyBoard(board)
    local copy = {}
    for square, piece in pairs(board) do
        copy[square] = piece
    end
    return copy
end

local function copyPosition(position)
    return {
        board = shallowCopyBoard(position.board),
        side = position.side,
        lastMove = position.lastMove and {
            from = position.lastMove.from,
            to = position.lastMove.to,
            piece = position.lastMove.piece,
            doublePawn = position.lastMove.doublePawn,
        } or nil,
        castling = {
            wK = position.castling.wK,
            wQ = position.castling.wQ,
            bK = position.castling.bK,
            bQ = position.castling.bQ,
        },
    }
end

local function pieceSide(piece)
    return piece and string.sub(piece, 1, 1) or nil
end

local function pieceType(piece)
    return piece and string.sub(piece, 2, 2) or nil
end

local function findKing(board, side)
    local wanted = side .. "K"
    for square, piece in pairs(board) do
        if piece == wanted then
            return square
        end
    end
    return nil
end

local function isSquareAttacked(board, square, bySide)
    local targetFile, targetRank = fromSquare(square)
    if not targetFile then
        return false
    end

    local pawnSourceRank = targetRank - (bySide == "w" and 1 or -1)
    for _, df in ipairs({ -1, 1 }) do
        local source = toSquare(targetFile + df, pawnSourceRank)
        if source and board[source] == bySide .. "P" then
            return true
        end
    end

    for _, delta in ipairs(KNIGHT_DELTAS) do
        local source = toSquare(targetFile + delta[1], targetRank + delta[2])
        if source and board[source] == bySide .. "N" then
            return true
        end
    end

    for _, delta in ipairs(KING_DELTAS) do
        local source = toSquare(targetFile + delta[1], targetRank + delta[2])
        if source and board[source] == bySide .. "K" then
            return true
        end
    end

    local function rayAttacked(directions, rookLike)
        for _, direction in ipairs(directions) do
            local file = targetFile + direction[1]
            local rank = targetRank + direction[2]
            while inBounds(file, rank) do
                local source = toSquare(file, rank)
                local piece = board[source]
                if piece then
                    if pieceSide(piece) == bySide then
                        local kind = pieceType(piece)
                        if kind == "Q" or (rookLike and kind == "R") or ((not rookLike) and kind == "B") then
                            return true
                        end
                    end
                    break
                end
                file = file + direction[1]
                rank = rank + direction[2]
            end
        end
        return false
    end

    if rayAttacked(ROOK_DIRS, true) then
        return true
    end
    if rayAttacked(BISHOP_DIRS, false) then
        return true
    end

    return false
end

local function inCheck(position, side)
    local kingSquare = findKing(position.board, side)
    if not kingSquare then
        return true
    end
    return isSquareAttacked(position.board, kingSquare, opposite(side))
end

local function addMove(moves, from, to, extra)
    local move = {
        from = from,
        to = to,
        promotion = nil,
        castle = nil,
        enPassant = false,
    }
    if extra then
        for key, value in pairs(extra) do
            move[key] = value
        end
    end
    table.insert(moves, move)
end

local function generatePseudoMoves(position, side)
    local board = position.board
    local moves = {}

    for from, piece in pairs(board) do
        if pieceSide(piece) == side then
            local kind = pieceType(piece)
            local file, rank = fromSquare(from)

            if kind == "P" then
                local direction = side == "w" and 1 or -1
                local startRank = side == "w" and 2 or 7
                local promotionRank = side == "w" and 8 or 1
                local one = toSquare(file, rank + direction)

                if one and not board[one] then
                    addMove(moves, from, one, rank + direction == promotionRank and { promotion = "Q" } or nil)

                    local two = toSquare(file, rank + (direction * 2))
                    if rank == startRank and two and not board[two] then
                        addMove(moves, from, two, { doublePawn = true })
                    end
                end

                for _, df in ipairs({ -1, 1 }) do
                    local target = toSquare(file + df, rank + direction)
                    if target then
                        local targetPiece = board[target]
                        if targetPiece and pieceSide(targetPiece) == opposite(side) then
                            addMove(moves, from, target, rank + direction == promotionRank and { promotion = "Q" } or nil)
                        elseif position.lastMove and position.lastMove.doublePawn then
                            local adjacent = toSquare(file + df, rank)
                            if adjacent == position.lastMove.to and board[adjacent] == opposite(side) .. "P" then
                                addMove(moves, from, target, { enPassant = true })
                            end
                        end
                    end
                end

            elseif kind == "N" then
                for _, delta in ipairs(KNIGHT_DELTAS) do
                    local target = toSquare(file + delta[1], rank + delta[2])
                    if target then
                        local targetPiece = board[target]
                        if not targetPiece or pieceSide(targetPiece) ~= side then
                            addMove(moves, from, target)
                        end
                    end
                end

            elseif kind == "B" or kind == "R" or kind == "Q" then
                local directions = kind == "B" and BISHOP_DIRS or (kind == "R" and ROOK_DIRS or QUEEN_DIRS)
                for _, direction in ipairs(directions) do
                    local nextFile = file + direction[1]
                    local nextRank = rank + direction[2]
                    while inBounds(nextFile, nextRank) do
                        local target = toSquare(nextFile, nextRank)
                        local targetPiece = board[target]
                        if targetPiece then
                            if pieceSide(targetPiece) ~= side then
                                addMove(moves, from, target)
                            end
                            break
                        end
                        addMove(moves, from, target)
                        nextFile = nextFile + direction[1]
                        nextRank = nextRank + direction[2]
                    end
                end

            elseif kind == "K" then
                for _, delta in ipairs(KING_DELTAS) do
                    local target = toSquare(file + delta[1], rank + delta[2])
                    if target then
                        local targetPiece = board[target]
                        if not targetPiece or pieceSide(targetPiece) ~= side then
                            addMove(moves, from, target)
                        end
                    end
                end

                local homeRank = side == "w" and 1 or 8
                local kingHome = "e" .. tostring(homeRank)
                if from == kingHome and not inCheck(position, side) then
                    local kingSideKey = side .. "K"
                    if position.castling[kingSideKey]
                        and board["h" .. tostring(homeRank)] == side .. "R"
                        and not board["f" .. tostring(homeRank)]
                        and not board["g" .. tostring(homeRank)]
                        and not isSquareAttacked(board, "f" .. tostring(homeRank), opposite(side))
                        and not isSquareAttacked(board, "g" .. tostring(homeRank), opposite(side)) then
                        addMove(moves, from, "g" .. tostring(homeRank), { castle = "K" })
                    end

                    local queenSideKey = side .. "Q"
                    if position.castling[queenSideKey]
                        and board["a" .. tostring(homeRank)] == side .. "R"
                        and not board["b" .. tostring(homeRank)]
                        and not board["c" .. tostring(homeRank)]
                        and not board["d" .. tostring(homeRank)]
                        and not isSquareAttacked(board, "d" .. tostring(homeRank), opposite(side))
                        and not isSquareAttacked(board, "c" .. tostring(homeRank), opposite(side)) then
                        addMove(moves, from, "c" .. tostring(homeRank), { castle = "Q" })
                    end
                end
            end
        end
    end

    return moves
end

local function applyMove(position, move)
    local nextPosition = copyPosition(position)
    local board = nextPosition.board
    local movingPiece = board[move.from]
    local capturedPiece = board[move.to]
    local side = pieceSide(movingPiece)
    local kind = pieceType(movingPiece)

    board[move.from] = nil

    if move.enPassant then
        local toFile, toRank = fromSquare(move.to)
        local capturedSquare = toSquare(toFile, toRank + (side == "w" and -1 or 1))
        capturedPiece = board[capturedSquare]
        board[capturedSquare] = nil
    end

    board[move.to] = move.promotion and (side .. move.promotion) or movingPiece

    if move.castle then
        local rank = side == "w" and "1" or "8"
        if move.castle == "K" then
            board["f" .. rank] = board["h" .. rank]
            board["h" .. rank] = nil
        else
            board["d" .. rank] = board["a" .. rank]
            board["a" .. rank] = nil
        end
    end

    if kind == "K" then
        nextPosition.castling[side .. "K"] = false
        nextPosition.castling[side .. "Q"] = false
    elseif kind == "R" then
        if move.from == "h1" then nextPosition.castling.wK = false end
        if move.from == "a1" then nextPosition.castling.wQ = false end
        if move.from == "h8" then nextPosition.castling.bK = false end
        if move.from == "a8" then nextPosition.castling.bQ = false end
    end

    if capturedPiece == "wR" then
        if move.to == "h1" then nextPosition.castling.wK = false end
        if move.to == "a1" then nextPosition.castling.wQ = false end
    elseif capturedPiece == "bR" then
        if move.to == "h8" then nextPosition.castling.bK = false end
        if move.to == "a8" then nextPosition.castling.bQ = false end
    end

    nextPosition.lastMove = {
        from = move.from,
        to = move.to,
        piece = movingPiece,
        doublePawn = move.doublePawn == true,
    }
    nextPosition.side = opposite(position.side)

    return nextPosition
end

local function generateLegalMoves(position, side)
    local legal = {}
    local pseudo = generatePseudoMoves(position, side)
    for _, move in ipairs(pseudo) do
        local nextPosition = applyMove(position, move)
        if not inCheck(nextPosition, side) then
            table.insert(legal, move)
        end
    end
    return legal
end

local function centerBonus(square)
    local file, rank = fromSquare(square)
    if not file then
        return 0
    end
    local dx = math.abs(4.5 - file)
    local dy = math.abs(4.5 - rank)
    return math.floor((4 - (dx + dy)) * 4)
end


local function countPseudoMobility(board, side)
    local count = 0
    for square, piece in pairs(board) do
        if pieceSide(piece) == side then
            local kind = pieceType(piece)
            local file, rank = fromSquare(square)

            if kind == "P" then
                local direction = side == "w" and 1 or -1
                local one = toSquare(file, rank + direction)
                if one and not board[one] then count = count + 1 end
                for _, df in ipairs({ -1, 1 }) do
                    local target = toSquare(file + df, rank + direction)
                    if target and board[target] and pieceSide(board[target]) ~= side then
                        count = count + 1
                    end
                end
            elseif kind == "N" then
                for _, delta in ipairs(KNIGHT_DELTAS) do
                    local target = toSquare(file + delta[1], rank + delta[2])
                    if target and (not board[target] or pieceSide(board[target]) ~= side) then
                        count = count + 1
                    end
                end
            elseif kind == "K" then
                for _, delta in ipairs(KING_DELTAS) do
                    local target = toSquare(file + delta[1], rank + delta[2])
                    if target and (not board[target] or pieceSide(board[target]) ~= side) then
                        count = count + 1
                    end
                end
            elseif kind == "B" or kind == "R" or kind == "Q" then
                local directions = kind == "B" and BISHOP_DIRS or (kind == "R" and ROOK_DIRS or QUEEN_DIRS)
                for _, direction in ipairs(directions) do
                    local f = file + direction[1]
                    local r = rank + direction[2]
                    while inBounds(f, r) do
                        local target = toSquare(f, r)
                        local targetPiece = board[target]
                        if targetPiece then
                            if pieceSide(targetPiece) ~= side then count = count + 1 end
                            break
                        end
                        count = count + 1
                        f = f + direction[1]
                        r = r + direction[2]
                    end
                end
            end
        end
    end
    return count
end

local function evaluate(position)
    local board = position.board
    local score = 0

    local bishops = { w = 0, b = 0 }
    local pawnFiles = { w = {}, b = {} }
    local pawns = { w = {}, b = {} }
    local rooks = { w = {}, b = {} }
    local kings = { w = nil, b = nil }
    local queens = { w = nil, b = nil }
    local nonPawnMaterial = { w = 0, b = 0 }
    local pieceCount = 0

    for file = 1, 8 do
        pawnFiles.w[file] = 0
        pawnFiles.b[file] = 0
    end

    local function mirrorRank(side, rank)
        return side == "w" and rank or (9 - rank)
    end

    local function pst(kind, side, file, rank)
        local r = mirrorRank(side, rank)
        local centerDist = math.abs(4.5 - file) + math.abs(4.5 - r)

        if kind == "P" then
            local advance = r - 2
            local bonus = advance * 10
            if file == 4 or file == 5 then bonus = bonus + 10 end
            if r >= 5 then bonus = bonus + (r - 4) * 8 end
            return bonus - math.floor(math.abs(4.5 - file) * 2)
        elseif kind == "N" then
            return math.floor(34 - centerDist * 11)
        elseif kind == "B" then
            return math.floor(24 - centerDist * 6 + (r >= 3 and 4 or 0))
        elseif kind == "R" then
            return (r == 7 and 24 or 0) + math.floor(6 - math.abs(4.5 - file) * 2)
        elseif kind == "Q" then
            return math.floor(8 - centerDist * 2)
        elseif kind == "K" then
            return 0
        end
        return 0
    end

    for square, piece in pairs(board) do
        pieceCount = pieceCount + 1
        local side = pieceSide(piece)
        local kind = pieceType(piece)
        local sign = side == "w" and 1 or -1
        local file, rank = fromSquare(square)
        local value = PIECE_VALUE[kind] or 0

        score = score + sign * (value + pst(kind, side, file, rank))

        if kind == "P" then
            pawnFiles[side][file] = pawnFiles[side][file] + 1
            pawns[side][#pawns[side] + 1] = square
        elseif kind == "B" then
            bishops[side] = bishops[side] + 1
            nonPawnMaterial[side] = nonPawnMaterial[side] + value
        elseif kind == "N" or kind == "R" or kind == "Q" then
            nonPawnMaterial[side] = nonPawnMaterial[side] + value
        end

        if kind == "R" then rooks[side][#rooks[side] + 1] = square end
        if kind == "K" then kings[side] = square end
        if kind == "Q" then queens[side] = square end
    end

    if bishops.w >= 2 then score = score + 42 end
    if bishops.b >= 2 then score = score - 42 end

    -- Pawn structure, passed/connected pawns and rook files.
    for _, side in ipairs({ "w", "b" }) do
        local sign = side == "w" and 1 or -1
        local enemy = opposite(side)

        for file = 1, 8 do
            local count = pawnFiles[side][file]
            if count > 1 then
                score = score - sign * (count - 1) * 18
            end
        end

        for _, square in ipairs(pawns[side]) do
            local file, rank = fromSquare(square)
            local left = file > 1 and pawnFiles[side][file - 1] or 0
            local right = file < 8 and pawnFiles[side][file + 1] or 0
            if left == 0 and right == 0 then
                score = score - sign * 14
            end

            local passed = true
            for ef = math.max(1, file - 1), math.min(8, file + 1) do
                for _, enemySq in ipairs(pawns[enemy]) do
                    local enemyFile, enemyRank = fromSquare(enemySq)
                    if enemyFile == ef then
                        if (side == "w" and enemyRank > rank) or (side == "b" and enemyRank < rank) then
                            passed = false
                            break
                        end
                    end
                end
                if not passed then break end
            end

            if passed then
                local adv = side == "w" and (rank - 2) or (7 - rank)
                score = score + sign * (26 + adv * adv * 4)
            end

            -- connected pawn
            for _, df in ipairs({ -1, 1 }) do
                local neighbor = toSquare(file + df, rank)
                if neighbor and board[neighbor] == side .. "P" then
                    score = score + sign * 6
                    break
                end
            end
        end

        for _, square in ipairs(rooks[side]) do
            local file, rank = fromSquare(square)
            local ownPawns = pawnFiles[side][file]
            local enemyPawns = pawnFiles[enemy][file]
            if ownPawns == 0 and enemyPawns == 0 then
                score = score + sign * 28
            elseif ownPawns == 0 then
                score = score + sign * 16
            end

            local seventh = side == "w" and 7 or 2
            if rank == seventh then score = score + sign * 20 end
        end
    end

    local totalNonPawn = nonPawnMaterial.w + nonPawnMaterial.b
    local endgame = totalNonPawn <= 2800 or pieceCount <= 12

    -- King safety / endgame king activity.
    for _, side in ipairs({ "w", "b" }) do
        local kingSquare = kings[side]
        if kingSquare then
            local sign = side == "w" and 1 or -1
            local file, rank = fromSquare(kingSquare)

            if endgame then
                score = score + sign * math.floor(centerBonus(kingSquare) * 3)
            else
                local forward = side == "w" and 1 or -1
                local shield = 0
                for df = -1, 1 do
                    local sq1 = toSquare(file + df, rank + forward)
                    local sq2 = toSquare(file + df, rank + forward * 2)
                    if sq1 and board[sq1] == side .. "P" then
                        shield = shield + 2
                    elseif sq2 and board[sq2] == side .. "P" then
                        shield = shield + 1
                    end
                end
                score = score + sign * shield * 11

                -- Open files around king are dangerous.
                for df = -1, 1 do
                    local f = file + df
                    if f >= 1 and f <= 8 and pawnFiles[side][f] == 0 then
                        score = score - sign * 13
                    end
                end
            end
        end
    end

    -- Development / early queen discipline.
    if pieceCount >= 26 then
        local undevelopedW = 0
        local undevelopedB = 0
        if board.b1 == "wN" then undevelopedW = undevelopedW + 1 end
        if board.g1 == "wN" then undevelopedW = undevelopedW + 1 end
        if board.c1 == "wB" then undevelopedW = undevelopedW + 1 end
        if board.f1 == "wB" then undevelopedW = undevelopedW + 1 end
        if board.b8 == "bN" then undevelopedB = undevelopedB + 1 end
        if board.g8 == "bN" then undevelopedB = undevelopedB + 1 end
        if board.c8 == "bB" then undevelopedB = undevelopedB + 1 end
        if board.f8 == "bB" then undevelopedB = undevelopedB + 1 end
        score = score - undevelopedW * 10 + undevelopedB * 10

        if queens.w and queens.w ~= "d1" then score = score - 8 end
        if queens.b and queens.b ~= "d8" then score = score + 8 end
    end

    -- Lightweight mobility.
    local whiteMob = countPseudoMobility(board, "w")
    local blackMob = countPseudoMobility(board, "b")
    score = score + (whiteMob - blackMob) * 2

    score = score + (position.side == "w" and 8 or -8)
    return math.floor(score)
end

local function moveIdentity(move)
    return move.from .. move.to .. (move.promotion or "") .. (move.castle or "")
end

local function enginePositionKey(position)
    local out = {}
    for rank = 1, 8 do
        for file = 1, 8 do
            local square = toSquare(file, rank)
            local piece = position.board[square]
            if piece then
                out[#out + 1] = square .. piece
            end
        end
    end
    out[#out + 1] = position.side
    local c = position.castling
    out[#out + 1] = (c.wK and "K" or "-") .. (c.wQ and "Q" or "-") .. (c.bK and "k" or "-") .. (c.bQ and "q" or "-")
    if position.lastMove and position.lastMove.doublePawn then
        out[#out + 1] = "ep:" .. position.lastMove.from .. position.lastMove.to
    end
    return table.concat(out, "|")
end

local TRANSPOSITION = {}
local TRANSPOSITION_COUNT = 0
local KILLERS = {}
local HISTORY = {}

local function resetSearchHeuristicsIfNeeded()
    if TRANSPOSITION_COUNT > TT_MAX_ENTRIES then
        table.clear(TRANSPOSITION)
        TRANSPOSITION_COUNT = 0
    end
    table.clear(KILLERS)
    table.clear(HISTORY)
end


local function hasNonPawnMaterial(position, side)
    for _, piece in pairs(position.board) do
        if pieceSide(piece) == side then
            local kind = pieceType(piece)
            if kind == "N" or kind == "B" or kind == "R" or kind == "Q" then
                return true
            end
        end
    end
    return false
end

local function isQuietMove(position, move)
    return position.board[move.to] == nil
        and not move.enPassant
        and not move.promotion
        and not move.castle
end

local function makeNullMove(position)
    local nextPosition = copyPosition(position)
    nextPosition.side = opposite(position.side)
    nextPosition.lastMove = nil
    return nextPosition
end

local function rememberKiller(ply, moveId)
    local killers = KILLERS[ply]
    if not killers then
        killers = { nil, nil }
        KILLERS[ply] = killers
    end
    if killers[1] ~= moveId then
        killers[2] = killers[1]
        killers[1] = moveId
    end
end

local function moveOrderingScore(position, move, ply, ttBest)
    local attacker = position.board[move.from]
    local victim = position.board[move.to]
    local id = moveIdentity(move)
    local score = 0

    if ttBest and id == ttBest then
        score = score + 10000000
    end
    if victim then
        score = score + 100000 + (PIECE_VALUE[pieceType(victim)] or 0) * 16 - (PIECE_VALUE[pieceType(attacker)] or 0)
    elseif move.enPassant then
        score = score + 100000 + PIECE_VALUE.P * 15
    end
    if move.promotion then
        score = score + 90000 + (PIECE_VALUE[move.promotion] or PIECE_VALUE.Q)
    end
    if move.castle then
        score = score + 1200
    end

    local killers = KILLERS[ply]
    if killers then
        if killers[1] == id then score = score + 8000 end
        if killers[2] == id then score = score + 6000 end
    end
    score = score + (HISTORY[position.side .. ":" .. id] or 0)

    local nextPosition = applyMove(position, move)
    if inCheck(nextPosition, nextPosition.side) then
        score = score + 3500
    end

    return score
end

local function orderedMoves(position, side, ply, ttBest)
    local moves = generateLegalMoves(position, side)
    table.sort(moves, function(a, b)
        return moveOrderingScore(position, a, ply or 0, ttBest) > moveOrderingScore(position, b, ply or 0, ttBest)
    end)
    return moves
end

local function maybeYield(deadline)
    local stats = state.engineStats
    if stats.nodes > 0 and stats.nodes % YIELD_EVERY_NODES == 0 then
        task.wait()
    end
    return os.clock() >= deadline
end

local function quiescence(position, alpha, beta, deadline, qDepth, ply, generation)
    if (generation and generation ~= state.analysisGeneration) or os.clock() >= deadline then
        return nil, true
    end

    state.engineStats.qNodes = state.engineStats.qNodes + 1
    state.engineStats.nodes = state.engineStats.nodes + 1
    if maybeYield(deadline) then
        return nil, true
    end

    local side = position.side
    local checked = inCheck(position, side)
    local standPat = evaluate(position)

    if qDepth >= QUIESCENCE_DEPTH and not checked then
        return standPat, false
    end

    if side == "w" then
        if not checked then
            if standPat >= beta then return standPat, false end
            if standPat > alpha then alpha = standPat end
        end
    else
        if not checked then
            if standPat <= alpha then return standPat, false end
            if standPat < beta then beta = standPat end
        end
    end

    local allMoves = orderedMoves(position, side, ply, nil)
    if #allMoves == 0 then
        if checked then
            return side == "w" and (-1000000 + ply) or (1000000 - ply), false
        end
        return 0, false
    end

    local tactical = {}
    for _, move in ipairs(allMoves) do
        local capture = position.board[move.to] ~= nil or move.enPassant
        local promotion = move.promotion ~= nil
        local givesCheck = false
        if not capture and not promotion and qDepth < 2 then
            local nextPosition = applyMove(position, move)
            givesCheck = inCheck(nextPosition, nextPosition.side)
        end
        if checked or capture or promotion or givesCheck then
            tactical[#tactical + 1] = move
        end
    end

    if #tactical == 0 then
        return standPat, false
    end

    if side == "w" then
        local best = checked and -math.huge or standPat
        for _, move in ipairs(tactical) do
            local value, timedOut = quiescence(applyMove(position, move), alpha, beta, deadline, qDepth + 1, ply + 1, generation)
            if timedOut then return nil, true end
            if value > best then best = value end
            if best > alpha then alpha = best end
            if alpha >= beta then
                state.engineStats.cutoffs = state.engineStats.cutoffs + 1
                break
            end
        end
        return best, false
    else
        local best = checked and math.huge or standPat
        for _, move in ipairs(tactical) do
            local value, timedOut = quiescence(applyMove(position, move), alpha, beta, deadline, qDepth + 1, ply + 1, generation)
            if timedOut then return nil, true end
            if value < best then best = value end
            if best < beta then beta = best end
            if alpha >= beta then
                state.engineStats.cutoffs = state.engineStats.cutoffs + 1
                break
            end
        end
        return best, false
    end
end

local function search(position, depth, alpha, beta, deadline, ply, allowNull, generation)
    if (generation and generation ~= state.analysisGeneration) or os.clock() >= deadline then
        return nil, true
    end

    state.engineStats.nodes = state.engineStats.nodes + 1
    if maybeYield(deadline) then
        return nil, true
    end

    local key = enginePositionKey(position)
    local alphaOriginal = alpha
    local betaOriginal = beta
    local tt = TRANSPOSITION[key]
    local ttBest = tt and tt.bestMove or nil

    if tt and tt.depth >= depth then
        state.engineStats.ttHits = state.engineStats.ttHits + 1
        if tt.flag == "EXACT" then
            return tt.score, false
        elseif tt.flag == "LOWER" then
            if tt.score > alpha then alpha = tt.score end
        elseif tt.flag == "UPPER" then
            if tt.score < beta then beta = tt.score end
        end
        if alpha >= beta then
            return tt.score, false
        end
    end

    local side = position.side
    local checked = inCheck(position, side)

    if depth <= 0 then
        return quiescence(position, alpha, beta, deadline, 0, ply, generation)
    end

    -- Null-move pruning.
    if allowNull ~= false and depth >= 4 and not checked and hasNonPawnMaterial(position, side) then
        local reduction = depth >= 7 and 3 or 2
        local nullScore, timedOut = search(makeNullMove(position), depth - 1 - reduction, alpha, beta, deadline, ply + 1, false, generation)
        if timedOut then return nil, true end
        if side == "w" and nullScore >= beta then
            state.engineStats.cutoffs = state.engineStats.cutoffs + 1
            return nullScore, false
        elseif side == "b" and nullScore <= alpha then
            state.engineStats.cutoffs = state.engineStats.cutoffs + 1
            return nullScore, false
        end
    end

    local moves = orderedMoves(position, side, ply, ttBest)
    if #moves == 0 then
        if checked then
            return side == "w" and (-MATE_SCORE + ply) or (MATE_SCORE - ply), false
        end
        return 0, false
    end

    local bestMoveId = nil
    local best = side == "w" and -math.huge or math.huge

    for index, move in ipairs(moves) do
        local nextPosition = applyMove(position, move)
        local quiet = isQuietMove(position, move)
        local givesCheck = inCheck(nextPosition, nextPosition.side)

        local reduction = 0
        if depth >= 4 and index >= 5 and quiet and not checked and not givesCheck then
            reduction = 1
            if depth >= 7 and index >= 9 then
                reduction = 2
            end
        end

        local value, timedOut

        if index == 1 then
            value, timedOut = search(nextPosition, depth - 1, alpha, beta, deadline, ply + 1, true, generation)
        elseif side == "w" then
            value, timedOut = search(nextPosition, math.max(0, depth - 1 - reduction), alpha, alpha + 1, deadline, ply + 1, true, generation)
            if not timedOut and value > alpha and value < beta then
                value, timedOut = search(nextPosition, depth - 1, alpha, beta, deadline, ply + 1, true, generation)
            end
        else
            value, timedOut = search(nextPosition, math.max(0, depth - 1 - reduction), beta - 1, beta, deadline, ply + 1, true, generation)
            if not timedOut and value < beta and value > alpha then
                value, timedOut = search(nextPosition, depth - 1, alpha, beta, deadline, ply + 1, true, generation)
            end
        end

        if timedOut then return nil, true end

        if side == "w" then
            if value > best then
                best = value
                bestMoveId = moveIdentity(move)
            end
            if best > alpha then alpha = best end
        else
            if value < best then
                best = value
                bestMoveId = moveIdentity(move)
            end
            if best < beta then beta = best end
        end

        if alpha >= beta then
            state.engineStats.cutoffs = state.engineStats.cutoffs + 1
            if quiet then
                local id = moveIdentity(move)
                rememberKiller(ply, id)
                local hkey = side .. ":" .. id
                HISTORY[hkey] = math.min(500000, (HISTORY[hkey] or 0) + depth * depth * 2)
            end
            break
        end
    end

    local flag = "EXACT"
    if best <= alphaOriginal then
        flag = "UPPER"
    elseif best >= betaOriginal then
        flag = "LOWER"
    end

    if not tt then TRANSPOSITION_COUNT = TRANSPOSITION_COUNT + 1 end
    TRANSPOSITION[key] = {
        depth = depth,
        score = best,
        flag = flag,
        bestMove = bestMoveId,
    }

    return best, false
end

local function findBestMove(position, budgetOverride, generation)
    resetSearchHeuristicsIfNeeded()
    state.engineStats = {
        nodes = 0,
        ttHits = 0,
        cutoffs = 0,
        qNodes = 0,
        elapsed = 0,
        stableDepths = 0,
        completedDepth = 0,
    }

    local started = os.clock()
    local softBudget = budgetOverride or state.searchBudget
    local softDeadline = started + softBudget
    local hardBudget = math.min(HARD_BUDGET_CAP, math.max(softBudget, softBudget * HARD_BUDGET_MULTIPLIER))
    local hardDeadline = started + hardBudget

    local rootKey = enginePositionKey(position)
    local rootTT = TRANSPOSITION[rootKey]
    local rootMoves = orderedMoves(position, position.side, 0, rootTT and rootTT.bestMove or nil)
    if #rootMoves == 0 then
        return nil, nil, 0, state.engineStats
    end

    local completedBest = rootMoves[1]
    local completedScore = nil
    local completedDepth = 0
    local previousBestId = nil
    local stableDepths = 0

    for depth = 1, SEARCH_MAX_DEPTH do
        if (generation and generation ~= state.analysisGeneration) or os.clock() >= hardDeadline then
            break
        end

        if completedBest then
            local bestId = moveIdentity(completedBest)
            table.sort(rootMoves, function(a, b)
                if moveIdentity(a) == bestId then return true end
                if moveIdentity(b) == bestId then return false end
                return moveOrderingScore(position, a, 0, rootTT and rootTT.bestMove or nil)
                    > moveOrderingScore(position, b, 0, rootTT and rootTT.bestMove or nil)
            end)
        end

        local aspiration = completedScore and ASPIRATION_START or math.huge
        local alpha = completedScore and (completedScore - aspiration) or -math.huge
        local beta = completedScore and (completedScore + aspiration) or math.huge
        local depthBest, depthScore, timedOut

        local function runRoot(a, b)
            local localBest = nil
            local localScore = position.side == "w" and -math.huge or math.huge
            local localTimedOut = false
            local localAlpha, localBeta = a, b

            for index, move in ipairs(rootMoves) do
                if (generation and generation ~= state.analysisGeneration) or os.clock() >= hardDeadline then
                    localTimedOut = true
                    break
                end

                local nextPosition = applyMove(position, move)
                local value, childTimedOut

                if index == 1 then
                    value, childTimedOut = search(nextPosition, depth - 1, localAlpha, localBeta, hardDeadline, 1, true, generation)
                elseif position.side == "w" then
                    value, childTimedOut = search(nextPosition, depth - 1, localAlpha, localAlpha + 1, hardDeadline, 1, true, generation)
                    if not childTimedOut and value > localAlpha and value < localBeta then
                        value, childTimedOut = search(nextPosition, depth - 1, localAlpha, localBeta, hardDeadline, 1, true, generation)
                    end
                else
                    value, childTimedOut = search(nextPosition, depth - 1, localBeta - 1, localBeta, hardDeadline, 1, true, generation)
                    if not childTimedOut and value < localBeta and value > localAlpha then
                        value, childTimedOut = search(nextPosition, depth - 1, localAlpha, localBeta, hardDeadline, 1, true, generation)
                    end
                end

                if childTimedOut then
                    localTimedOut = true
                    break
                end

                if (position.side == "w" and value > localScore)
                    or (position.side == "b" and value < localScore) then
                    localScore = value
                    localBest = move
                end

                if position.side == "w" then
                    if value > localAlpha then localAlpha = value end
                else
                    if value < localBeta then localBeta = value end
                end
            end

            return localBest, localScore, localTimedOut
        end

        depthBest, depthScore, timedOut = runRoot(alpha, beta)
        if timedOut then break end

        if completedScore and (depthScore <= alpha or depthScore >= beta) then
            depthBest, depthScore, timedOut = runRoot(-math.huge, math.huge)
            if timedOut then break end
        end

        if depthBest then
            local currentBestId = moveIdentity(depthBest)
            if currentBestId == previousBestId then
                stableDepths = stableDepths + 1
            else
                previousBestId = currentBestId
                stableDepths = 1
            end

            completedBest = depthBest
            completedScore = depthScore
            completedDepth = depth
            state.engineStats.stableDepths = stableDepths
            state.engineStats.completedDepth = depth

            TRANSPOSITION[rootKey] = {
                depth = depth,
                score = depthScore,
                flag = "EXACT",
                bestMove = currentBestId,
            }
        end

        if os.clock() >= softDeadline
            and completedDepth >= MIN_STABLE_DEPTH
            and stableDepths >= STABLE_DEPTHS_REQUIRED then
            break
        end
    end

    state.engineStats.elapsed = os.clock() - started
    state.engineStats.stableDepths = stableDepths
    state.engineStats.completedDepth = completedDepth
    return completedBest, completedScore, completedDepth, state.engineStats
end

local function clearHighlights()
    if not state.boardFrame then
        return
    end

    local guide = state.boardGui and state.boardGui:FindFirstChild("HongSondevMoveGuide")
    if guide then
        guide:Destroy()
    end

    for _, square in ipairs(state.boardFrame:GetChildren()) do
        local old = square:FindFirstChild("HongSondevHint")
        if old then
            old:Destroy()
        end
    end
end

local function addSquareHighlight(squareName, color, isTarget)
    if not state.boardFrame then
        return
    end
    local square = state.boardFrame:FindFirstChild(squareName)
    if not square or not square:IsA("GuiObject") then
        return
    end

    local overlay = Instance.new("Frame")
    overlay.Name = "HongSondevHint"
    overlay.Size = UDim2.fromScale(1, 1)
    overlay.Position = UDim2.fromScale(0, 0)
    overlay.BackgroundColor3 = color
    overlay.BackgroundTransparency = isTarget and 0.70 or 0.80
    overlay.BorderSizePixel = 0
    overlay.ZIndex = math.max((square.ZIndex or 1) + 8, 18)
    overlay.Parent = square

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0.18, 0)
    corner.Parent = overlay

    local ring = Instance.new("Frame")
    ring.Name = "Ring"
    ring.AnchorPoint = Vector2.new(0.5, 0.5)
    ring.Position = UDim2.fromScale(0.5, 0.5)
    ring.Size = UDim2.fromScale(isTarget and 0.58 or 0.34, isTarget and 0.58 or 0.34)
    ring.BackgroundTransparency = 1
    ring.ZIndex = overlay.ZIndex + 1
    ring.Parent = overlay

    local ringCorner = Instance.new("UICorner")
    ringCorner.CornerRadius = UDim.new(1, 0)
    ringCorner.Parent = ring

    local stroke = Instance.new("UIStroke")
    stroke.Thickness = isTarget and 4 or 3
    stroke.Transparency = isTarget and 0.03 or 0.20
    stroke.Color = color
    stroke.Parent = ring

    local dot = Instance.new("Frame")
    dot.AnchorPoint = Vector2.new(0.5, 0.5)
    dot.Position = UDim2.fromScale(0.5, 0.5)
    dot.Size = UDim2.fromScale(isTarget and 0.20 or 0.13, isTarget and 0.20 or 0.13)
    dot.BackgroundColor3 = color
    dot.BackgroundTransparency = 0.03
    dot.BorderSizePixel = 0
    dot.ZIndex = ring.ZIndex + 1
    dot.Parent = overlay

    local dotCorner = Instance.new("UICorner")
    dotCorner.CornerRadius = UDim.new(1, 0)
    dotCorner.Parent = dot

    if isTarget then
        local pulse = Instance.new("Frame")
        pulse.Name = "Pulse"
        pulse.AnchorPoint = Vector2.new(0.5, 0.5)
        pulse.Position = UDim2.fromScale(0.5, 0.5)
        pulse.Size = UDim2.fromScale(0.30, 0.30)
        pulse.BackgroundTransparency = 1
        pulse.ZIndex = overlay.ZIndex + 1
        pulse.Parent = overlay

        local pulseCorner = Instance.new("UICorner")
        pulseCorner.CornerRadius = UDim.new(1, 0)
        pulseCorner.Parent = pulse

        local pulseStroke = Instance.new("UIStroke")
        pulseStroke.Thickness = 3
        pulseStroke.Color = color
        pulseStroke.Transparency = 0.10
        pulseStroke.Parent = pulse

        TweenService:Create(
            pulse,
            TweenInfo.new(0.85, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, -1, true),
            { Size = UDim2.fromScale(0.82, 0.82) }
        ):Play()
        TweenService:Create(
            pulseStroke,
            TweenInfo.new(0.85, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, -1, true),
            { Transparency = 0.82 }
        ):Play()
    end
end

local function newGuideSegment(parent, name, center, length, thickness, rotation, color, transparency, zIndex)
    local segment = Instance.new("Frame")
    segment.Name = name
    segment.AnchorPoint = Vector2.new(0.5, 0.5)
    segment.Position = UDim2.fromOffset(center.X, center.Y)
    segment.Size = UDim2.fromOffset(math.max(1, length), thickness)
    segment.Rotation = rotation
    segment.BackgroundColor3 = color
    segment.BackgroundTransparency = transparency
    segment.BorderSizePixel = 0
    segment.ZIndex = zIndex
    segment.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = segment
    return segment
end

local function drawMoveGuide(fromSquareName, toSquareName)
    if not state.boardFrame then
        return
    end

    local fromSquare = state.boardFrame:FindFirstChild(fromSquareName)
    local toSquare = state.boardFrame:FindFirstChild(toSquareName)
    if not fromSquare or not toSquare or not fromSquare:IsA("GuiObject") or not toSquare:IsA("GuiObject") then
        return
    end

    local old = state.boardGui and state.boardGui:FindFirstChild("HongSondevMoveGuide")
    if old then old:Destroy() end

    local guide = Instance.new("Frame")
    guide.Name = "HongSondevMoveGuide"
    guide.Size = UDim2.fromOffset(state.boardFrame.AbsoluteSize.X, state.boardFrame.AbsoluteSize.Y)
    guide.Position = UDim2.fromOffset(state.boardFrame.AbsolutePosition.X, state.boardFrame.AbsolutePosition.Y)
    guide.BackgroundTransparency = 1
    guide.BorderSizePixel = 0
    guide.Active = false
    guide.ClipsDescendants = false
    guide.ZIndex = 60
    guide.Parent = state.boardGui

    local boardOrigin = state.boardFrame.AbsolutePosition
    local fromCenter = fromSquare.AbsolutePosition + (fromSquare.AbsoluteSize / 2) - boardOrigin
    local toCenter = toSquare.AbsolutePosition + (toSquare.AbsoluteSize / 2) - boardOrigin
    local delta = toCenter - fromCenter
    local distance = delta.Magnitude
    if distance < 2 then
        return
    end

    local direction = delta.Unit
    local angle = math.deg(math.atan2(delta.Y, delta.X))
    local squareSize = math.min(fromSquare.AbsoluteSize.X, fromSquare.AbsoluteSize.Y)
    local startInset = math.max(8, squareSize * 0.18)
    local endInset = math.max(13, squareSize * 0.24)
    local shaftStart = fromCenter + direction * startInset
    local shaftEnd = toCenter - direction * endInset
    local shaftDelta = shaftEnd - shaftStart
    local shaftLength = shaftDelta.Magnitude
    local shaftCenter = shaftStart + shaftDelta / 2

    local glow = newGuideSegment(
        guide,
        "Glow",
        shaftCenter,
        shaftLength,
        MOVE_GUIDE_GLOW,
        angle,
        GREEN_TO,
        0.78,
        61
    )
    local glowGradient = Instance.new("UIGradient")
    glowGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, GREEN_FROM),
        ColorSequenceKeypoint.new(1, GREEN_TO),
    })
    glowGradient.Parent = glow

    local shaft = newGuideSegment(
        guide,
        "Shaft",
        shaftCenter,
        shaftLength,
        MOVE_GUIDE_THICKNESS,
        angle,
        GREEN_TO,
        0.06,
        62
    )
    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, GREEN_FROM),
        ColorSequenceKeypoint.new(0.55, Color3.fromRGB(39, 218, 104)),
        ColorSequenceKeypoint.new(1, GREEN_TO),
    })
    gradient.Parent = shaft

    local headLength = math.clamp(squareSize * 0.26, 12, 24)
    local headCenterOffset = headLength * 0.37
    local back = -direction
    local perpendicular = Vector2.new(-direction.Y, direction.X)
    local spread = math.rad(34)
    local branchOffset = back * (math.cos(spread) * headCenterOffset)
    local lateral = perpendicular * (math.sin(spread) * headCenterOffset)

    local leftCenter = toCenter + branchOffset + lateral
    local rightCenter = toCenter + branchOffset - lateral

    newGuideSegment(guide, "HeadLGlow", leftCenter, headLength, MOVE_GUIDE_GLOW * 0.78, angle + 180 - 34, GREEN_TO, 0.80, 61)
    newGuideSegment(guide, "HeadRGlow", rightCenter, headLength, MOVE_GUIDE_GLOW * 0.78, angle + 180 + 34, GREEN_TO, 0.80, 61)
    newGuideSegment(guide, "HeadL", leftCenter, headLength, MOVE_GUIDE_THICKNESS, angle + 180 - 34, GREEN_TO, 0.02, 63)
    newGuideSegment(guide, "HeadR", rightCenter, headLength, MOVE_GUIDE_THICKNESS, angle + 180 + 34, GREEN_TO, 0.02, 63)

    addSquareHighlight(fromSquareName, GREEN_FROM, false)
    addSquareHighlight(toSquareName, GREEN_TO, true)
end

local function setStatus(text, muted)
    if state.statusLabel then
        state.statusLabel.Text = text
        state.statusLabel.TextColor3 = muted and PANEL_MUTED or PANEL_TEXT
    end
end

local function setEngineStats(text)
    if state.statsLabel then
        state.statsLabel.Text = text
    end
end

local function positionKey(board)
    local list = {}
    for square, piece in pairs(board) do
        table.insert(list, square .. piece)
    end
    table.sort(list)
    return table.concat(list, "|")
end

local function readBoardFromGui()
    local board = {}
    if not state.piecesFrame then
        return board
    end

    for _, pieceObject in ipairs(state.piecesFrame:GetChildren()) do
        local code = PIECE_CODE[pieceObject.Name]
        if code then
            local tile = pieceObject:FindFirstChild("tile")
            local visible = true
            if pieceObject:IsA("GuiObject") then
                visible = pieceObject.Visible
            end
            if tile and tile:IsA("StringValue") and visible and string.match(tile.Value, "^[a-h][1-8]$") then
                board[tile.Value] = code
            end
        end
    end

    return board
end

local function detectSideFromDragState()
    if not state.piecesFrame then
        return nil
    end

    local enabledWhite = 0
    local enabledBlack = 0

    for _, pieceObject in ipairs(state.piecesFrame:GetChildren()) do
        local code = PIECE_CODE[pieceObject.Name]
        if code then
            local drag = pieceObject:FindFirstChild("UIDragDetector")
            if drag and drag:IsA("UIDragDetector") and drag.Enabled then
                if string.sub(code, 1, 1) == "w" then
                    enabledWhite = enabledWhite + 1
                else
                    enabledBlack = enabledBlack + 1
                end
            end
        end
    end

    if enabledWhite > 0 and enabledBlack == 0 then
        return "w"
    elseif enabledBlack > 0 and enabledWhite == 0 then
        return "b"
    end
    return nil
end

local function detectPlayerSideFromGui()
    if not state.main then
        return nil
    end

    local playerInfo = state.main:FindFirstChild("PlayerInfo")
    local youDNR = playerInfo and playerInfo:FindFirstChild("YouDNR")
    if youDNR and youDNR:IsA("TextLabel") then
        local text = string.lower(youDNR.Text or "")
        if string.find(text, "white", 1, true) then
            return "w"
        elseif string.find(text, "black", 1, true) then
            return "b"
        end
    end

    if state.boardFrame then
        local a8 = state.boardFrame:FindFirstChild("a8")
        local h1 = state.boardFrame:FindFirstChild("h1")
        if a8 and h1 and a8:IsA("GuiObject") and h1:IsA("GuiObject") then
            local a8p = a8.Position
            local h1p = h1.Position
            if a8p.X.Scale < h1p.X.Scale and a8p.Y.Scale < h1p.Y.Scale then
                return "w"
            elseif a8p.X.Scale > h1p.X.Scale and a8p.Y.Scale > h1p.Y.Scale then
                return "b"
            end
        end
    end

    return nil
end

local function chosenPlayerSide()
    if state.sideMode == "White" then
        return "w"
    elseif state.sideMode == "Black" then
        return "b"
    end

    return detectPlayerSideFromGui() or state.playerSide or state.trackedSide
end

local function isStandardInitialPosition(board)
    local count = 0
    for _ in pairs(board) do
        count = count + 1
    end
    if count ~= 32 then
        return false
    end

    local back = { "R", "N", "B", "Q", "K", "B", "N", "R" }
    for file = 1, 8 do
        local f = string.sub(FILES, file, file)
        if board[f .. "1"] ~= "w" .. back[file] then return false end
        if board[f .. "2"] ~= "wP" then return false end
        if board[f .. "7"] ~= "bP" then return false end
        if board[f .. "8"] ~= "b" .. back[file] then return false end
    end
    return true
end

local function inferInitialCastling(board)
    local initial = isStandardInitialPosition(board)
    state.castling.wK = initial
    state.castling.wQ = initial
    state.castling.bK = initial
    state.castling.bQ = initial
end

local function updateHistoryFromBoard(previousBoard, board)
    if not previousBoard then
        return
    end

    local changed = {}
    for file = 1, 8 do
        for rank = 1, 8 do
            local square = toSquare(file, rank)
            if previousBoard[square] ~= board[square] then
                table.insert(changed, square)
            end
        end
    end

    if #changed == 0 then
        return
    end

    if previousBoard.e1 == "wK" and board.e1 ~= "wK" then
        state.castling.wK = false
        state.castling.wQ = false
    end
    if previousBoard.e8 == "bK" and board.e8 ~= "bK" then
        state.castling.bK = false
        state.castling.bQ = false
    end
    if previousBoard.h1 == "wR" and board.h1 ~= "wR" then state.castling.wK = false end
    if previousBoard.a1 == "wR" and board.a1 ~= "wR" then state.castling.wQ = false end
    if previousBoard.h8 == "bR" and board.h8 ~= "bR" then state.castling.bK = false end
    if previousBoard.a8 == "bR" and board.a8 ~= "bR" then state.castling.bQ = false end

    local inferred = nil

    for _, from in ipairs(changed) do
        local oldPiece = previousBoard[from]
        if oldPiece then
            local oldSide = pieceSide(oldPiece)
            local oldKind = pieceType(oldPiece)
            for _, to in ipairs(changed) do
                if to ~= from then
                    local newPiece = board[to]
                    if newPiece and pieceSide(newPiece) == oldSide then
                        local newKind = pieceType(newPiece)
                        local samePiece = newPiece == oldPiece
                        local promotion = oldKind == "P" and (newKind == "Q" or newKind == "R" or newKind == "B" or newKind == "N")
                        if samePiece or promotion then
                            local fromFile, fromRank = fromSquare(from)
                            local toFile, toRank = fromSquare(to)
                            inferred = {
                                from = from,
                                to = to,
                                piece = oldPiece,
                                doublePawn = oldKind == "P" and fromFile == toFile and math.abs(toRank - fromRank) == 2,
                            }
                            state.trackedSide = opposite(oldSide)
                            break
                        end
                    end
                end
            end
        end
        if inferred then break end
    end

    state.lastMove = inferred
end

local scheduleRefresh


local function ensureFloatingToggle()
    if state.floatingToggle and state.floatingToggle.Parent then
        return state.floatingToggle
    end
    if not state.boardGui then return nil end

    local button = Instance.new("TextButton")
    button.Name = "HongSondevTrainerToggle"
    button.Size = UDim2.fromOffset(42, 30)
    button.Position = UDim2.new(0.012, 0, 0.5, -15)
    button.BackgroundColor3 = Color3.fromRGB(31, 36, 42)
    button.BorderSizePixel = 0
    button.Text = "♟"
    button.TextColor3 = PANEL_TEXT
    button.TextSize = 17
    button.Font = Enum.Font.GothamBold
    button.Visible = false
    button.ZIndex = 300
    button.Parent = state.boardGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = button

    button.MouseButton1Click:Connect(function()
        state.collapsed = false
        button.Visible = false
        if state.panel then
            state.panel.Visible = true
        end
    end)

    state.floatingToggle = button
    return button
end

local function collapseUi()
    state.collapsed = true
    local toggle = ensureFloatingToggle()
    if state.panel then state.panel.Visible = false end
    if toggle then toggle.Visible = true end
end

local function makeDraggable(frame, handle)
    handle = handle or frame
    frame.Active = true
    handle.Active = true

    local dragging = false
    local dragStart
    local startPos
    local dragInput

    local began = handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    local changed = handle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    local globalChanged = UserInputService.InputChanged:Connect(function(input)
        if dragging and input == dragInput and frame.Parent then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)

    table.insert(state.connections, began)
    table.insert(state.connections, changed)
    table.insert(state.connections, globalChanged)
end

local function createNativePanel()
    if state.panel then
        state.panel:Destroy()
    end

    local panel = Instance.new("Frame")
    panel.Name = "HongSondevTrainerPanel"
    panel.AnchorPoint = Vector2.new(0, 0.5)
    panel.Position = UDim2.new(0.012, 0, 0.5, 0)
    panel.Size = UDim2.fromOffset(360, 148)
    panel.BackgroundColor3 = PANEL_BG
    panel.BackgroundTransparency = 0.06
    panel.BorderSizePixel = 0
    panel.ZIndex = 100
    panel.Parent = state.boardGui
    state.panel = panel
    state.uiBackend = "Native"

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = panel

    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 1
    stroke.Transparency = 0.45
    stroke.Color = Color3.fromRGB(104, 117, 130)
    stroke.Parent = panel

    local header = Instance.new("Frame")
    header.Name = "Header"
    header.BackgroundTransparency = 1
    header.Size = UDim2.new(1, 0, 0, 34)
    header.ZIndex = 101
    header.Parent = panel

    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Position = UDim2.fromOffset(12, 6)
    title.Size = UDim2.new(1, -58, 0, 24)
    title.Text = "Chess Trainer v5 · Strict Engine"
    title.TextColor3 = PANEL_TEXT
    title.Font = Enum.Font.GothamBold
    title.TextSize = 15
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.ZIndex = 102
    title.Parent = header

    local collapse = Instance.new("TextButton")
    collapse.Position = UDim2.new(1, -38, 0, 5)
    collapse.Size = UDim2.fromOffset(28, 24)
    collapse.BackgroundColor3 = Color3.fromRGB(42, 48, 54)
    collapse.BorderSizePixel = 0
    collapse.Text = "—"
    collapse.TextColor3 = PANEL_TEXT
    collapse.TextSize = 16
    collapse.Font = Enum.Font.GothamBold
    collapse.ZIndex = 103
    collapse.Parent = header
    local cc = Instance.new("UICorner")
    cc.CornerRadius = UDim.new(0, 7)
    cc.Parent = collapse
    collapse.MouseButton1Click:Connect(collapseUi)

    local statusLabel = Instance.new("TextLabel")
    statusLabel.BackgroundTransparency = 1
    statusLabel.Position = UDim2.fromOffset(12, 38)
    statusLabel.Size = UDim2.new(1, -24, 0, 48)
    statusLabel.Text = "Đang đọc toàn bộ bàn cờ..."
    statusLabel.TextWrapped = true
    statusLabel.TextColor3 = PANEL_MUTED
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.TextSize = 13
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.TextYAlignment = Enum.TextYAlignment.Top
    statusLabel.ZIndex = 101
    statusLabel.Parent = panel
    state.statusLabel = statusLabel

    local statsLabel = Instance.new("TextLabel")
    statsLabel.BackgroundTransparency = 1
    statsLabel.Position = UDim2.fromOffset(12, 78)
    statsLabel.Size = UDim2.new(1, -24, 0, 18)
    statsLabel.Text = "Đang khởi tạo engine..."
    statsLabel.TextTruncate = Enum.TextTruncate.AtEnd
    statsLabel.TextColor3 = PANEL_MUTED
    statsLabel.Font = Enum.Font.Gotham
    statsLabel.TextSize = 10
    statsLabel.TextXAlignment = Enum.TextXAlignment.Left
    statsLabel.ZIndex = 101
    statsLabel.Parent = panel
    state.statsLabel = statsLabel

    local modeButton = Instance.new("TextButton")
    modeButton.Position = UDim2.fromOffset(12, 103)
    modeButton.Size = UDim2.fromOffset(118, 30)
    modeButton.BackgroundColor3 = Color3.fromRGB(42, 48, 54)
    modeButton.BorderSizePixel = 0
    modeButton.TextColor3 = PANEL_TEXT
    modeButton.Font = Enum.Font.GothamMedium
    modeButton.TextSize = 12
    modeButton.Text = "Phe: Auto"
    modeButton.ZIndex = 101
    modeButton.Parent = panel
    state.modeButton = modeButton

    local refreshButton = Instance.new("TextButton")
    refreshButton.Position = UDim2.fromOffset(138, 103)
    refreshButton.Size = UDim2.fromOffset(94, 30)
    refreshButton.BackgroundColor3 = Color3.fromRGB(42, 48, 54)
    refreshButton.BorderSizePixel = 0
    refreshButton.Text = "Tính lại"
    refreshButton.TextColor3 = PANEL_TEXT
    refreshButton.Font = Enum.Font.GothamMedium
    refreshButton.TextSize = 12
    refreshButton.ZIndex = 101
    refreshButton.Parent = panel

    local strengthButton = Instance.new("TextButton")
    strengthButton.Position = UDim2.fromOffset(240, 103)
    strengthButton.Size = UDim2.fromOffset(106, 30)
    strengthButton.BackgroundColor3 = Color3.fromRGB(42, 48, 54)
    strengthButton.BorderSizePixel = 0
    strengthButton.Text = "Mạnh 4s"
    strengthButton.TextColor3 = PANEL_TEXT
    strengthButton.Font = Enum.Font.GothamMedium
    strengthButton.TextSize = 12
    strengthButton.ZIndex = 101
    strengthButton.Parent = panel

    for _, button in ipairs({ modeButton, refreshButton, strengthButton }) do
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 7)
        c.Parent = button
    end

    makeDraggable(panel, header)

    modeButton.MouseButton1Click:Connect(function()
        if state.sideMode == "Auto" then
            state.sideMode = "White"
        elseif state.sideMode == "White" then
            state.sideMode = "Black"
        else
            state.sideMode = "Auto"
        end
        modeButton.Text = "Phe: " .. state.sideMode
        scheduleRefresh(true)
    end)

    refreshButton.MouseButton1Click:Connect(function()
        scheduleRefresh(true)
    end)

    local strengths = {
        { 1.00, "Nhanh 1s" },
        { 2.00, "Cân bằng 2s" },
        { 4.00, "Mạnh 4s" },
        { 6.00, "Rất mạnh 6s" },
        { 8.00, "Tối đa 8s" },
    }
    local strengthIndex = 3
    strengthButton.MouseButton1Click:Connect(function()
        strengthIndex = strengthIndex % #strengths + 1
        state.searchBudget = strengths[strengthIndex][1]
        strengthButton.Text = strengths[strengthIndex][2]
        scheduleRefresh(true)
    end)
end

local function createPanel()
    state.statusLabel = nil
    state.statsLabel = nil
    state.modeButton = nil
    if state.panel then
        state.panel:Destroy()
        state.panel = nil
    end
    createNativePanel()
    state.uiBackend = "Built-in"
end

local function buildPositionFromCurrentBoard(board, side)
    return {
        board = shallowCopyBoard(board),
        side = side,
        lastMove = state.lastMove,
        castling = {
            wK = state.castling.wK,
            wQ = state.castling.wQ,
            bK = state.castling.bK,
            bQ = state.castling.bQ,
        },
    }
end

local function ponderSilently(position, generation)
    if state.pondering then return end
    state.pondering = true

    task.spawn(function()
        local budget = math.max(PONDER_MIN_BUDGET, state.searchBudget * PONDER_BUDGET_FACTOR)
        findBestMove(position, budget, generation)
        if generation == state.analysisGeneration then
            state.pondering = false
        else
            state.pondering = false
        end
    end)
end

local function currentBoardFingerprint(board, side)
    local out = {}
    for rank = 1, 8 do
        for file = 1, 8 do
            local square = toSquare(file, rank)
            local piece = board[square]
            if piece then
                out[#out + 1] = square .. piece
            end
        end
    end
    out[#out + 1] = side
    return table.concat(out, "|")
end

local function calculateAndRender(serial)
    local board = readBoardFromGui()
    local key = positionKey(board)
    local playerSide = chosenPlayerSide()
    local detectedTurn = detectSideFromDragState()
    local sideToMove = detectedTurn or state.trackedSide or playerSide

    state.playerSide = playerSide

    if not findKing(board, "w") then
        clearHighlights()
        setStatus("Không tìm thấy vua Trắng trong Pieces/*/tile.", true)
        return
    end
    if not findKing(board, "b") then
        clearHighlights()
        setStatus("Không tìm thấy vua Đen trong Pieces/*/tile.", true)
        return
    end

    if state.lastPositionKey == nil then
        inferInitialCastling(board)
        state.trackedSide = sideToMove
    elseif key ~= state.lastPositionKey then
        updateHistoryFromBoard(state.lastBoard, board)
        if detectedTurn then state.trackedSide = detectedTurn end
    end

    state.lastPositionKey = key
    state.lastBoard = shallowCopyBoard(board)

    playerSide = chosenPlayerSide()
    sideToMove = detectedTurn or state.trackedSide or playerSide

    -- Opponent turn: only ponder, never render.
    if state.sideMode == "Auto" and sideToMove ~= playerSide then
        clearHighlights()
        setStatus((playerSide == "w" and "Bạn: Trắng" or "Bạn: Đen") .. " · đang chờ đối thủ.", true)

        local opponentPosition = buildPositionFromCurrentBoard(board, sideToMove)
        ponderSilently(opponentPosition, state.analysisGeneration)
        return
    end

    local side = playerSide
    if state.sideMode == "White" then side = "w" end
    if state.sideMode == "Black" then side = "b" end

    local position = buildPositionFromCurrentBoard(board, side)
    local fingerprint = currentBoardFingerprint(board, side)
    local generation = state.analysisGeneration

    clearHighlights()
    setStatus((side == "w" and "Trắng" or "Đen") .. " · đang phân tích toàn bộ bàn cờ...", true)
    state.searchRunning = true

    task.spawn(function()
        local bestMove, score, depth, stats = findBestMove(position, nil, generation)

        if serial ~= state.refreshSerial or generation ~= state.analysisGeneration then
            state.searchRunning = false
            return
        end

        local liveBoard = readBoardFromGui()
        local liveTurn = detectSideFromDragState() or state.trackedSide or playerSide
        local liveFingerprint = currentBoardFingerprint(liveBoard, side)

        if liveFingerprint ~= fingerprint then
            state.searchRunning = false
            return
        end

        if state.sideMode == "Auto" and liveTurn ~= playerSide then
            state.searchRunning = false
            clearHighlights()
            return
        end

        state.searchRunning = false
        clearHighlights()

        if not bestMove then
            if inCheck(position, side) then
                setStatus((side == "w" and "Trắng" or "Đen") .. ": chiếu hết / không còn nước hợp lệ.", false)
            else
                setStatus((side == "w" and "Trắng" or "Đen") .. ": hòa / không còn nước hợp lệ.", false)
            end
            return
        end

        drawMoveGuide(bestMove.from, bestMove.to)
        state.lastRenderedKey = fingerprint

        local scoreText = score and string.format("%+.2f", score / 100) or "?"
        local sideText = side == "w" and "Trắng" or "Đen"
        setStatus(string.format("%s: %s → %s · depth %d · eval %s", sideText, bestMove.from, bestMove.to, depth, scoreText), false)

        if stats then
            setEngineStats(string.format(
                "%d nodes · %d qnodes · %d TT hits · %d cutoffs · depth %d · stable %d · %.2fs · %s",
                stats.nodes, stats.qNodes, stats.ttHits, stats.cutoffs,
                stats.completedDepth or depth, stats.stableDepths or 0,
                stats.elapsed, state.uiBackend
            ))
        end
    end)
end

local debounceToken = 0
scheduleRefresh = function(immediate)
    state.analysisGeneration = state.analysisGeneration + 1
    state.refreshSerial = state.refreshSerial + 1
    local serial = state.refreshSerial

    debounceToken = debounceToken + 1
    local token = debounceToken

    local function run()
        if token ~= debounceToken then return end
        calculateAndRender(serial)
    end

    if immediate then
        task.defer(run)
    else
        task.delay(REFRESH_DEBOUNCE, run)
    end
end

local function watchPiece(pieceObject)
    if not PIECE_CODE[pieceObject.Name] then
        return
    end

    local tile = pieceObject:FindFirstChild("tile")
    if tile and tile:IsA("StringValue") then
        table.insert(state.connections, tile:GetPropertyChangedSignal("Value"):Connect(scheduleRefresh))
    end

    if pieceObject:IsA("GuiObject") then
        table.insert(state.connections, pieceObject:GetPropertyChangedSignal("Visible"):Connect(scheduleRefresh))
    end

    local drag = pieceObject:FindFirstChild("UIDragDetector")
    if drag and drag:IsA("UIDragDetector") then
        table.insert(state.connections, drag:GetPropertyChangedSignal("Enabled"):Connect(function()
            local detected = detectSideFromDragState()
            if detected then
                state.trackedSide = detected
            end
            scheduleRefresh()
        end))
    end
end

local function bindBoard(boardGui)
    disconnectAll()
    state.boardGui = boardGui
    state.main = boardGui:WaitForChild("Main", 10)
    if not state.main then
        warn("[HongSondev Chess Trainer] Main not found")
        return false
    end

    state.boardFrame = state.main:WaitForChild("Board", 10)
    state.piecesFrame = state.main:WaitForChild("Pieces", 10)
    if not state.boardFrame or not state.piecesFrame then
        warn("[HongSondev Chess Trainer] Board/Pieces not found")
        return false
    end

    createPanel()

    for _, child in ipairs(state.piecesFrame:GetChildren()) do
        watchPiece(child)
    end

    table.insert(state.connections, state.piecesFrame.ChildAdded:Connect(function(child)
        task.defer(function()
            watchPiece(child)
            scheduleRefresh()
        end)
    end))

    table.insert(state.connections, state.piecesFrame.ChildRemoved:Connect(scheduleRefresh))

    local playerInfo = state.main:FindFirstChild("PlayerInfo")
    local youDNR = playerInfo and playerInfo:FindFirstChild("YouDNR")
    if youDNR and youDNR:IsA("TextLabel") then
        table.insert(state.connections, youDNR:GetPropertyChangedSignal("Text"):Connect(function()
            local detectedPlayer = detectPlayerSideFromGui()
            if detectedPlayer then
                state.playerSide = detectedPlayer
            end
            scheduleRefresh()
        end))
    end

    local detected = detectSideFromDragState()
    if detected then
        state.trackedSide = detected
    end
    local detectedPlayer = detectPlayerSideFromGui()
    if detectedPlayer then
        state.playerSide = detectedPlayer
    end

    scheduleRefresh()
    return true
end

local function boot()
    local playerGui = LOCAL_PLAYER:WaitForChild("PlayerGui")
    local boardGui = playerGui:FindFirstChild(GUI_NAME)
    if not boardGui then
        boardGui = playerGui:WaitForChild(GUI_NAME, 30)
    end

    if not boardGui then
        warn("[HongSondev Chess Trainer] PlayerGui/2DBoard not found within 30 seconds.")
        return
    end

    local env = getEnvironment()
    print(string.format("[HongSondev Chess Trainer] Chạy trên môi trường: %s", env))

    bindBoard(boardGui)

    table.insert(state.connections, playerGui.ChildAdded:Connect(function(child)
        if child.Name == GUI_NAME and child ~= state.boardGui then
            task.defer(function()
                bindBoard(child)
            end)
        end
    end))
end

boot()
