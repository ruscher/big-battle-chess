class_name ChessNotation
extends RefCounted
## Standard Algebraic Notation (SAN) and PGN helpers.


## SAN for a legal move in `pos` (the move is not applied permanently).
static func move_to_san(pos: ChessPosition, move: int) -> String:
	var from := Chess.move_from(move)
	var to := Chess.move_to(move)
	var flags := Chess.move_flags(move)
	var piece := pos.squares[from]
	var type := piece & 7
	var san := ""
	if flags & Chess.FLAG_CASTLE:
		san = "O-O" if to > from else "O-O-O"
	else:
		var capture := Chess.is_capture(move)
		if type == Chess.PAWN:
			if capture:
				san = Chess.FILES[from & 7] + "x"
			san += Chess.square_name(to)
			var promo := Chess.move_promo(move)
			if promo != 0:
				san += "=" + Chess.PIECE_CHARS[promo]
		else:
			san = Chess.PIECE_CHARS[type] + _disambiguation(pos, move, type)
			if capture:
				san += "x"
			san += Chess.square_name(to)
	if pos.make_move(move):
		if pos.is_in_check():
			san += "#" if not pos.has_legal_move() else "+"
		pos.unmake_move()
	return san


static func _disambiguation(pos: ChessPosition, move: int, type: int) -> String:
	var from := Chess.move_from(move)
	var to := Chess.move_to(move)
	var same_file := false
	var same_rank := false
	var ambiguous := false
	for other in pos.generate_legal_moves():
		var other_from := Chess.move_from(other)
		if other_from == from or Chess.move_to(other) != to:
			continue
		if (pos.squares[other_from] & 7) != type:
			continue
		ambiguous = true
		if (other_from & 7) == (from & 7):
			same_file = true
		if (other_from >> 3) == (from >> 3):
			same_rank = true
	if not ambiguous:
		return ""
	if not same_file:
		return Chess.FILES[from & 7]
	if not same_rank:
		return str((from >> 3) + 1)
	return Chess.square_name(from)


## Parses SAN (or UCI as a fallback) against the legal moves of `pos`.
## Returns Chess.NO_MOVE when no legal move matches.
static func san_to_move(pos: ChessPosition, text: String) -> int:
	var clean := _strip_annotations(text)
	if clean.is_empty():
		return Chess.NO_MOVE
	clean = clean.replace("0-0-0", "O-O-O").replace("0-0", "O-O")
	var legal := pos.generate_legal_moves()
	for move in legal:
		if _strip_annotations(move_to_san(pos, move)) == clean:
			return move
	# Lenient fallbacks: missing "=" in promotions ("e8Q") and UCI ("e7e8q").
	for move in legal:
		var san := _strip_annotations(move_to_san(pos, move))
		if san.replace("=", "") == clean.replace("=", ""):
			return move
		if Chess.move_to_uci(move) == clean.to_lower():
			return move
	return Chess.NO_MOVE


static func _strip_annotations(text: String) -> String:
	var result := text.strip_edges()
	while not result.is_empty() and result[-1] in ["+", "#", "!", "?"]:
		result = result.left(-1)
	return result


## Splits PGN text into tag pairs and SAN tokens.
## Returns {"tags": Dictionary, "moves": PackedStringArray, "result": String}.
static func parse_pgn(text: String) -> Dictionary:
	var tags := {}
	var body := PackedStringArray()
	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if line.begins_with("[") and line.ends_with("]"):
			var inner := line.substr(1, line.length() - 2)
			var space := inner.find(" ")
			if space > 0:
				tags[inner.left(space)] = inner.substr(space + 1).strip_edges().trim_prefix("\"").trim_suffix("\"")
		elif not line.begins_with("%"):
			# ";" starts a comment that runs to the end of the line.
			var semicolon := line.find(";")
			body.append(line if semicolon < 0 else line.left(semicolon))
	var movetext := " ".join(body)
	# Remove comments, variations and NAGs.
	var cleaned := ""
	var depth_brace := 0
	var depth_paren := 0
	for c in movetext:
		if c == "{":
			depth_brace += 1
		elif c == "}":
			depth_brace = maxi(0, depth_brace - 1)
		elif depth_brace > 0:
			continue
		elif c == "(":
			depth_paren += 1
		elif c == ")":
			depth_paren = maxi(0, depth_paren - 1)
		elif depth_paren > 0:
			continue
		else:
			cleaned += c
	var moves := PackedStringArray()
	var result := "*"
	for token in cleaned.split(" ", false):
		if token in ["1-0", "0-1", "1/2-1/2", "*"]:
			result = token
			continue
		if token.begins_with("$"):
			continue
		# Strip move numbers such as "12." or "12..." (possibly glued: "12.e4").
		var t := token
		var dot := t.rfind(".")
		if dot >= 0 and t.left(dot).replace(".", "").is_valid_int():
			t = t.substr(dot + 1)
		if t.is_empty():
			continue
		moves.append(t)
	return {"tags": tags, "moves": moves, "result": result}
