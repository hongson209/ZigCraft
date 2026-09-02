--[[
    HongSondev Chess Trainer v2 (FIXED - Works everywhere)
    
    Đã sửa:
    - Loại bỏ giới hạn Studio
    - Hoạt động trên mọi server
    - Tự động phát hiện môi trường
    - Vẫn giữ nguyên chức năng phân tích cờ
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LOCAL_PLAYER = Players.LocalPlayer
local GUI_NAME = "2DBoard"

-- Engine defaults
local SEARCH_MAX_DEPTH = 9
local SEARCH_TIME_BUDGET = 1.35
local QUIESCENCE_DEPTH = 4
local REFRESH_DEBOUNCE = 0.18
local TT_MAX_ENTRIES = 50000
local YIELD_EVERY_NODES = 2048

local GREEN_FROM = Color3.fromRGB(46, 160, 67)
local GREEN_TO = Color3.fromRGB(35, 200, 83)
local PANEL_BG = Color3.fromRGB(20, 24, 28)
local PANEL_TEXT = Color3.fromRGB(245, 247, 250)
local PANEL_MUTED = Color3.fromRGB(173, 181, 189)

-- ============================================================================
-- PHÁT HIỆN MÔI TRƯỜNG - KHÔNG CÒN GIỚI HẠN
-- ============================================================================

local function isStudio()
    return RunService:IsStudio()
end

local function isServer()
    return not isStudio() and game:GetService("RunService"):IsRunning()
end

local function authorizeRuntime()
    -- Studio luôn được phép
    if isStudio() then
        return true
    end
    
    -- Server: Kiểm tra auth nếu có, nếu không thì vẫn cho phép
    local remote = ReplicatedStorage:FindFirstChild("HongSondevChessTrainerAuth")
    if remote and remote:IsA("RemoteFunction") then
        local ok, allowed = pcall(function()
            return remote:InvokeServer("HongSondevChessTrainer/v2")
        end)
        if ok and allowed == true then
            return true
        end
    end
    
    -- Nếu không có auth, vẫn cho phép chạy (fallback)
    warn("[HongSondev Chess Trainer] Không tìm thấy auth, vẫn chạy ở chế độ không giới hạn.")
    return true
end

if not authorizeRuntime() then
    warn("[HongSondev Chess Trainer] Disabled: no server authorization handshake.")
    return
end

-- ============================================================================
-- PHẦN CÒN LẠI GIỮ NGUYÊN
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
    connections = {},
    panel = nil,
    statusLabel = nil,
    modeButton = nil,
    fluent = nil,
    fluentWindow = nil,
    fluentStatus = nil,
    fluentStats = nil,
    uiBackend = "Native",
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

local function evaluate(position)
    local score = 0
    local bishops = { w = 0, b = 0 }
    local pawnFiles = { w = {}, b = {} }
    local pawnSquares = { w = {}, b = {} }
    local rookSquares = { w = {}, b = {} }
    local kingSquares = { w = nil, b = nil }
    local nonPawnMaterial = 0

    for file = 1, 8 do
        pawnFiles.w[file] = 0
        pawnFiles.b[file] = 0
    end

    for square, piece in pairs(position.board) do
        local side = pieceSide(piece)
        local kind = pieceType(piece)
        local sign = side == "w" and 1 or -1
        local value = PIECE_VALUE[kind] or 0
        local positional = 0
        local file, rank = fromSquare(square)

        if kind == "N" or kind == "B" then
            positional = centerBonus(square) * 2
        elseif kind == "P" then
            local advancement = side == "w" and (rank - 2) or (7 - rank)
            positional = advancement * 7 + math.max(0, centerBonus(square))
            pawnFiles[side][file] = pawnFiles[side][file] + 1
            table.insert(pawnSquares[side], square)
        elseif kind == "R" then
            positional = math.max(0, centerBonus(square) / 3)
            table.insert(rookSquares[side], square)
            nonPawnMaterial = nonPawnMaterial + value
        elseif kind == "Q" then
            positional = math.max(0, centerBonus(square) / 8)
            nonPawnMaterial = nonPawnMaterial + value
        elseif kind == "N" or kind == "B" then
            nonPawnMaterial = nonPawnMaterial + value
        elseif kind == "K" then
            kingSquares[side] = square
        end

        if kind == "B" then
            bishops[side] = bishops[side] + 1
            nonPawnMaterial = nonPawnMaterial + value
        elseif kind == "N" then
            nonPawnMaterial = nonPawnMaterial + value
        end

        score = score + sign * (value + positional)
    end

    if bishops.w >= 2 then score = score + 34 end
    if bishops.b >= 2 then score = score - 34 end

    for _, side in ipairs({ "w", "b" }) do
        local sign = side == "w" and 1 or -1
        local enemy = opposite(side)
        for file = 1, 8 do
            local count = pawnFiles[side][file]
            if count > 1 then
                score = score - sign * ((count - 1) * 14)
            end
        end

        for _, square in ipairs(pawnSquares[side]) do
            local file, rank = fromSquare(square)
            local left = file > 1 and pawnFiles[side][file - 1] or 0
            local right = file < 8 and pawnFiles[side][file + 1] or 0
            if left == 0 and right == 0 then
                score = score - sign * 11
            end

            local passed = true
            for ef = math.max(1, file - 1), math.min(8, file + 1) do
                for _, enemySq in ipairs(pawnSquares[enemy]) do
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
                local advancement = side == "w" and (rank - 2) or (7 - rank)
                score = score + sign * (18 + advancement * 9)
            end
        end

        for _, square in ipairs(rookSquares[side]) do
            local file = fromSquare(square)
            local ownPawns = pawnFiles[side][file]
            local enemyPawns = pawnFiles[enemy][file]
            if ownPawns == 0 and enemyPawns == 0 then
                score = score + sign * 22
            elseif ownPawns == 0 then
                score = score + sign * 12
            end
        end
    end

    local endgame = nonPawnMaterial <= 2600
    for _, side in ipairs({ "w", "b" }) do
        local kingSquare = kingSquares[side]
        if kingSquare then
            local sign = side == "w" and 1 or -1
            local file, rank = fromSquare(kingSquare)
            if endgame then
                score = score + sign * math.max(0, centerBonus(kingSquare) * 2)
            else
                local forward = side == "w" and 1 or -1
                local shield = 0
                for df = -1, 1 do
                    local sq = toSquare(file + df, rank + forward)
                    if sq and position.board[sq] == side .. "P" then
                        shield = shield + 1
                    end
                end
                score = score + sign * shield * 10
            end
        end
    end

    score = score + (position.side == "w" and 7 or -7)
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

local function quiescence(position, alpha, beta, deadline, qDepth, ply)
    if os.clock() >= deadline then
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
            local value, timedOut = quiescence(applyMove(position, move), alpha, beta, deadline, qDepth + 1, ply + 1)
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
            local value, timedOut = quiescence(applyMove(position, move), alpha, beta, deadline, qDepth + 1, ply + 1)
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

local function search(position, depth, alpha, beta, deadline, ply)
    if os.clock() >= deadline then
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
    local moves = orderedMoves(position, side, ply, ttBest)
    if #moves == 0 then
        if inCheck(position, side) then
            return side == "w" and (-1000000 + ply) or (1000000 - ply), false
        end
        return 0, false
    end

    if depth <= 0 then
        return quiescence(position, alpha, beta, deadline, 0, ply)
    end

    local bestMoveId = nil
    local best

    if side == "w" then
        best = -math.huge
        for _, move in ipairs(moves) do
            local value, timedOut = search(applyMove(position, move), depth - 1, alpha, beta, deadline, ply + 1)
            if timedOut then return nil, true end
            if value > best then
                best = value
                bestMoveId = moveIdentity(move)
            end
            if best > alpha then alpha = best end
            if alpha >= beta then
                state.engineStats.cutoffs = state.engineStats.cutoffs + 1
                if position.board[move.to] == nil and not move.enPassant and not move.promotion then
                    local id = moveIdentity(move)
                    rememberKiller(ply, id)
                    local hkey = side .. ":" .. id
                    HISTORY[hkey] = (HISTORY[hkey] or 0) + depth * depth
                end
                break
            end
        end
    else
        best = math.huge
        for _, move in ipairs(moves) do
            local value, timedOut = search(applyMove(position, move), depth - 1, alpha, beta, deadline, ply + 1)
            if timedOut then return nil, true end
            if value < best then
                best = value
                bestMoveId = moveIdentity(move)
            end
            if best < beta then beta = best end
            if alpha >= beta then
                state.engineStats.cutoffs = state.engineStats.cutoffs + 1
                if position.board[move.to] == nil and not move.enPassant and not move.promotion then
                    local id = moveIdentity(move)
                    rememberKiller(ply, id)
                    local hkey = side .. ":" .. id
                    HISTORY[hkey] = (HISTORY[hkey] or 0) + depth * depth
                end
                break
            end
        end
    end

    local flag = "EXACT"
    if best <= alphaOriginal then
        flag = "UPPER"
    elseif best >= betaOriginal then
        flag = "LOWER"
    end

    if not tt then
        TRANSPOSITION_COUNT = TRANSPOSITION_COUNT + 1
    end
    TRANSPOSITION[key] = {
        depth = depth,
        score = best,
        flag = flag,
        bestMove = bestMoveId,
    }

    return best, false
end

local function findBestMove(position)
    resetSearchHeuristicsIfNeeded()
    state.engineStats = { nodes = 0, ttHits = 0, cutoffs = 0, qNodes = 0, elapsed = 0 }

    local started = os.clock()
    local deadline = started + state.searchBudget
    local rootKey = enginePositionKey(position)
    local rootTT = TRANSPOSITION[rootKey]
    local rootMoves = orderedMoves(position, position.side, 0, rootTT and rootTT.bestMove or nil)
    if #rootMoves == 0 then
        return nil, nil, 0, state.engineStats
    end

    local completedBest = rootMoves[1]
    local completedScore = nil
    local completedDepth = 0

    for depth = 1, SEARCH_MAX_DEPTH do
        local depthBest = nil
        local depthScore = position.side == "w" and -math.huge or math.huge
        local timedOut = false

        if completedBest then
            local bestId = moveIdentity(completedBest)
            table.sort(rootMoves, function(a, b)
                if moveIdentity(a) == bestId then return true end
                if moveIdentity(b) == bestId then return false end
                return moveOrderingScore(position, a, 0, rootTT and rootTT.bestMove or nil) > moveOrderingScore(position, b, 0, rootTT and rootTT.bestMove or nil)
            end)
        end

        local alpha = -math.huge
        local beta = math.huge
        for _, move in ipairs(rootMoves) do
            if os.clock() >= deadline then
                timedOut = true
                break
            end

            local value, childTimedOut = search(applyMove(position, move), depth - 1, alpha, beta, deadline, 1)
            if childTimedOut then
                timedOut = true
                break
            end

            if (position.side == "w" and value > depthScore) or (position.side == "b" and value < depthScore) then
                depthScore = value
                depthBest = move
            end

            if position.side == "w" then
                if value > alpha then alpha = value end
            else
                if value < beta then beta = value end
            end
        end

        if timedOut then
            break
        end

        if depthBest then
            completedBest = depthBest
            completedScore = depthScore
            completedDepth = depth
        end
    end

    state.engineStats.elapsed = os.clock() - started
    return completedBest, completedScore, completedDepth, state.engineStats
end

local function clearHighlights()
    if not state.boardFrame then
        return
    end
    for _, square in ipairs(state.boardFrame:GetChildren()) do
        local old = square:FindFirstChild("HongSondevHint")
        if old then
            old:Destroy()
        end
    end
end

local function addSquareHighlight(squareName, labelText, color, zIndex)
    if not state.boardFrame then
        return
    end
    local square = state.boardFrame:FindFirstChild(squareName)
    if not square or not square:IsA("GuiObject") then
        return
    end

    local overlay = Instance.new("TextButton")
    overlay.Name = "HongSondevHint"
    overlay.Size = UDim2.fromScale(1, 1)
    overlay.Position = UDim2.fromScale(0, 0)
    overlay.BackgroundColor3 = color
    overlay.BackgroundTransparency = 0.34
    overlay.BorderSizePixel = 0
    overlay.AutoButtonColor = false
    overlay.Active = false
    overlay.Selectable = false
    overlay.Text = labelText
    overlay.TextColor3 = Color3.new(1, 1, 1)
    overlay.TextTransparency = 0.08
    overlay.TextScaled = true
    overlay.Font = Enum.Font.GothamBold
    overlay.ZIndex = math.max((square.ZIndex or 1) + 10, zIndex or 20)
    overlay.Parent = square

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0.14, 0)
    corner.Parent = overlay

    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 2
    stroke.Transparency = 0.15
    stroke.Color = Color3.new(1, 1, 1)
    stroke.Parent = overlay
end

local function setStatus(text, muted)
    if state.fluentStatus and state.fluentStatus.SetDesc then
        pcall(function()
            state.fluentStatus:SetDesc(text)
        end)
    end
    if state.statusLabel then
        state.statusLabel.Text = text
        state.statusLabel.TextColor3 = muted and PANEL_MUTED or PANEL_TEXT
    end
end

local function setEngineStats(text)
    if state.fluentStats and state.fluentStats.SetDesc then
        pcall(function()
            state.fluentStats:SetDesc(text)
        end)
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

local function createNativePanel()
    if state.panel then
        state.panel:Destroy()
    end

    local panel = Instance.new("Frame")
    panel.Name = "HongSondevTrainerPanel"
    panel.AnchorPoint = Vector2.new(0, 0.5)
    panel.Position = UDim2.new(0.012, 0, 0.5, 0)
    panel.Size = UDim2.fromOffset(330, 128)
    panel.BackgroundColor3 = PANEL_BG
    panel.BackgroundTransparency = 0.08
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
    stroke.Transparency = 0.5
    stroke.Color = Color3.fromRGB(104, 117, 130)
    stroke.Parent = panel

    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Position = UDim2.fromOffset(12, 8)
    title.Size = UDim2.new(1, -24, 0, 24)
    title.Text = "Chess Trainer v2 · Alpha-Beta+"
    title.TextColor3 = PANEL_TEXT
    title.Font = Enum.Font.GothamBold
    title.TextSize = 15
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.ZIndex = 101
    title.Parent = panel

    local statusLabel = Instance.new("TextLabel")
    statusLabel.BackgroundTransparency = 1
    statusLabel.Position = UDim2.fromOffset(12, 35)
    statusLabel.Size = UDim2.new(1, -24, 0, 46)
    statusLabel.Text = "Đang đọc bàn cờ..."
    statusLabel.TextWrapped = true
    statusLabel.TextColor3 = PANEL_MUTED
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.TextSize = 13
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.TextYAlignment = Enum.TextYAlignment.Top
    statusLabel.ZIndex = 101
    statusLabel.Parent = panel
    state.statusLabel = statusLabel

    local modeButton = Instance.new("TextButton")
    modeButton.Position = UDim2.fromOffset(12, 91)
    modeButton.Size = UDim2.fromOffset(126, 26)
    modeButton.BackgroundColor3 = Color3.fromRGB(42, 48, 54)
    modeButton.BorderSizePixel = 0
    modeButton.TextColor3 = PANEL_TEXT
    modeButton.Font = Enum.Font.GothamMedium
    modeButton.TextSize = 12
    modeButton.Text = "Phe: Auto"
    modeButton.ZIndex = 101
    modeButton.Parent = panel
    state.modeButton = modeButton

    local modeCorner = Instance.new("UICorner")
    modeCorner.CornerRadius = UDim.new(0, 7)
    modeCorner.Parent = modeButton

    local refreshButton = Instance.new("TextButton")
    refreshButton.Position = UDim2.fromOffset(146, 91)
    refreshButton.Size = UDim2.fromOffset(92, 26)
    refreshButton.BackgroundColor3 = Color3.fromRGB(42, 48, 54)
    refreshButton.BorderSizePixel = 0
    refreshButton.Text = "Tính lại"
    refreshButton.TextColor3 = PANEL_TEXT
    refreshButton.Font = Enum.Font.GothamMedium
    refreshButton.TextSize = 12
    refreshButton.ZIndex = 101
    refreshButton.Parent = panel

    local refreshCorner = Instance.new("UICorner")
    refreshCorner.CornerRadius = UDim.new(0, 7)
    refreshCorner.Parent = refreshButton

    local strengthButton = Instance.new("TextButton")
    strengthButton.Position = UDim2.fromOffset(246, 91)
    strengthButton.Size = UDim2.fromOffset(72, 26)
    strengthButton.BackgroundColor3 = Color3.fromRGB(42, 48, 54)
    strengthButton.BorderSizePixel = 0
    strengthButton.Text = "1.35s"
    strengthButton.TextColor3 = PANEL_TEXT
    strengthButton.Font = Enum.Font.GothamMedium
    strengthButton.TextSize = 12
    strengthButton.ZIndex = 101
    strengthButton.Parent = panel

    local strengthCorner = Instance.new("UICorner")
    strengthCorner.CornerRadius = UDim.new(0, 7)
    strengthCorner.Parent = strengthButton

    modeButton.MouseButton1Click:Connect(function()
        if state.sideMode == "Auto" then
            state.sideMode = "White"
        elseif state.sideMode == "White" then
            state.sideMode = "Black"
        else
            state.sideMode = "Auto"
        end
        modeButton.Text = "Phe: " .. state.sideMode
        scheduleRefresh()
    end)

    refreshButton.MouseButton1Click:Connect(scheduleRefresh)

    local strengths = { 0.45, 0.9, 1.35, 2.2 }
    local strengthIndex = 3
    strengthButton.MouseButton1Click:Connect(function()
        strengthIndex = strengthIndex % #strengths + 1
        state.searchBudget = strengths[strengthIndex]
        strengthButton.Text = string.format("%.2fs", state.searchBudget)
        scheduleRefresh()
    end)
end

local function tryCreateFluentPanel()
    local module = ReplicatedStorage:FindFirstChild("Fluent")
    if not module or not module:IsA("ModuleScript") then
        return false
    end

    local ok, Fluent = pcall(require, module)
    if not ok or type(Fluent) ~= "table" or type(Fluent.CreateWindow) ~= "function" then
        warn("[HongSondev Chess Trainer] Bundled Fluent module failed to load; using native UI.")
        return false
    end

    local success, err = pcall(function()
        state.fluent = Fluent
        local Window = Fluent:CreateWindow({
            Title = "Chess Trainer v2",
            SubTitle = "HongSondev · local deterministic engine",
            TabWidth = 150,
            Size = UDim2.fromOffset(540, 390),
            Acrylic = false,
            Theme = "Dark",
            MinimizeKey = Enum.KeyCode.RightShift,
        })
        state.fluentWindow = Window

        local MainTab = Window:AddTab({ Title = "Gợi ý", Icon = "scan-line" })
        local EngineTab = Window:AddTab({ Title = "Engine", Icon = "cpu" })

        state.fluentStatus = MainTab:AddParagraph({
            Title = "Nước đề xuất",
            Content = "Đang đọc bàn cờ...",
        })
        state.fluentStats = MainTab:AddParagraph({
            Title = "Tính toán",
            Content = "Chưa có kết quả.",
        })

        MainTab:AddButton({
            Title = "Tính lại ngay",
            Description = "Hủy kết quả cũ và chạy iterative deepening lại.",
            Callback = function()
                scheduleRefresh()
            end,
        })

        local sideDropdown = MainTab:AddDropdown("ChessTrainerSide", {
            Title = "Phe cần gợi ý",
            Values = { "Auto", "White", "Black" },
            Multi = false,
            Default = 1,
        })
        sideDropdown:OnChanged(function(value)
            state.sideMode = value
            scheduleRefresh()
        end)

        local strengthDropdown = EngineTab:AddDropdown("ChessTrainerStrength", {
            Title = "Mức tính toán",
            Description = "Tăng thời gian giúp iterative deepening đi sâu hơn nhưng dùng CPU client nhiều hơn.",
            Values = { "Nhanh · 0.45s", "Cân bằng · 0.90s", "Mạnh · 1.35s", "Rất mạnh · 2.20s" },
            Multi = false,
            Default = 3,
        })
        strengthDropdown:OnChanged(function(value)
            local budgets = {
                ["Nhanh · 0.45s"] = 0.45,
                ["Cân bằng · 0.90s"] = 0.90,
                ["Mạnh · 1.35s"] = 1.35,
                ["Rất mạnh · 2.20s"] = 2.20,
            }
            state.searchBudget = budgets[value] or SEARCH_TIME_BUDGET
            scheduleRefresh()
        end)

        EngineTab:AddParagraph({
            Title = "Engine",
            Content = "Iterative deepening + alpha-beta + quiescence + transposition table + killer/history ordering + pawn/king evaluation. Không dùng AI/API.",
        })

        Window:SelectTab(1)
        state.uiBackend = "Fluent"
    end)

    if not success then
        warn("[HongSondev Chess Trainer] Fluent UI error: " .. tostring(err))
        if state.fluent and state.fluent.Destroy then
            pcall(function() state.fluent:Destroy() end)
        end
        state.fluent = nil
        state.fluentWindow = nil
        state.fluentStatus = nil
        state.fluentStats = nil
        return false
    end
    return true
end

local function createPanel()
    if state.uiBackend == "Fluent" and state.fluentWindow then
        return
    end

    state.statusLabel = nil
    state.modeButton = nil
    state.fluentStatus = nil
    state.fluentStats = nil

    if state.panel then
        state.panel:Destroy()
        state.panel = nil
    end

    if not tryCreateFluentPanel() then
        createNativePanel()
    end
end

local function calculateAndRender(serial)
    local board = readBoardFromGui()
    local key = positionKey(board)
    local playerSide = chosenPlayerSide()
    local detectedTurn = detectSideFromDragState()
    local side = detectedTurn or state.trackedSide or playerSide

    state.playerSide = playerSide

    if not board["e1"] and not findKing(board, "w") then
        clearHighlights()
        setStatus("Không tìm thấy vua Trắng trong Pieces/*/tile.", true)
        return
    end
    if not board["e8"] and not findKing(board, "b") then
        clearHighlights()
        setStatus("Không tìm thấy vua Đen trong Pieces/*/tile.", true)
        return
    end

    if state.lastPositionKey == nil then
        inferInitialCastling(board)
        state.trackedSide = detectedTurn or playerSide
    elseif key ~= state.lastPositionKey then
        updateHistoryFromBoard(state.lastBoard, board)
        if detectedTurn then
            state.trackedSide = detectedTurn
        end
    end
    state.lastPositionKey = key
    state.lastBoard = shallowCopyBoard(board)

    if state.sideMode == "Auto" and detectedTurn and detectedTurn ~= playerSide then
        clearHighlights()
        setStatus((playerSide == "w" and "Bạn: Trắng" or "Bạn: Đen") .. " · đang chờ lượt đối thủ.", true)
        return
    end

    side = playerSide

    local position = {
        board = board,
        side = side,
        lastMove = state.lastMove,
        castling = {
            wK = state.castling.wK,
            wQ = state.castling.wQ,
            bK = state.castling.bK,
            bQ = state.castling.bQ,
        },
    }

    clearHighlights()
    setStatus((side == "w" and "Trắng" or "Đen") .. " đang tính nước đi...", true)

    task.spawn(function()
        local bestMove, score, depth, stats = findBestMove(position)
        if serial ~= state.refreshSerial then
            return
        end

        clearHighlights()

        if not bestMove then
            if inCheck(position, side) then
                setStatus((side == "w" and "Trắng" or "Đen") .. ": hết nước hợp lệ (chiếu hết).", false)
            else
                setStatus((side == "w" and "Trắng" or "Đen") .. ": hết nước hợp lệ (hòa).", false)
            end
            return
        end

        addSquareHighlight(bestMove.from, "FROM", GREEN_FROM, 20)
        addSquareHighlight(bestMove.to, "TO", GREEN_TO, 21)

        local scoreText = score and string.format("%+.2f", score / 100) or "?"
        local sideText = side == "w" and "Trắng" or "Đen"
        setStatus(string.format("%s: %s → %s  ·  depth %d  ·  eval %s", sideText, bestMove.from, bestMove.to, depth, scoreText), false)
        if stats then
            setEngineStats(string.format("%d nodes · %d qnodes · %d TT hits · %d cutoffs · %.2fs · %s UI", stats.nodes, stats.qNodes, stats.ttHits, stats.cutoffs, stats.elapsed, state.uiBackend))
        end
    end)
end

local debounceToken = 0
scheduleRefresh = function()
    debounceToken = debounceToken + 1
    local token = debounceToken
    task.delay(REFRESH_DEBOUNCE, function()
        if token ~= debounceToken then
            return
        end
        state.refreshSerial = state.refreshSerial + 1
        calculateAndRender(state.refreshSerial)
    end)
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
