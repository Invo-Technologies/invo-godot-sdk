class_name InvoQr
extends RefCounted
## Minimal QR Code encoder (ISO/IEC 18004) in pure GDScript, used to render the
## phone-approval QR in the in-game wallet.
##
## Byte mode only (the text is UTF-8 encoded), versions 1-15, all four error
## correction levels, full mask evaluation (lowest penalty wins). That covers
## the approval URLs, which are https links well under 200 bytes.
##
##   var tex: ImageTexture = InvoQr.to_texture("https://invo.network/approve?c=ABCD-EFGH")
##   var rows: Array = InvoQr.encode("hello", "Q")  # Array of PackedByteArray, 1 = dark

const MIN_VERSION: int = 1
const MAX_VERSION: int = 15

## Index 0 = level L, 1 = M, 2 = Q, 3 = H. Column = version (column 0 unused).
const _ECC_CODEWORDS_PER_BLOCK: Array = [
	[-1, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22],
	[-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24],
	[-1, 13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30],
	[-1, 17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24],
]
const _NUM_EC_BLOCKS: Array = [
	[-1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6],
	[-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10],
	[-1, 1, 1, 2, 2, 4, 4, 6, 6, 8, 8, 8, 10, 12, 16, 12],
	[-1, 1, 1, 2, 4, 4, 4, 5, 6, 8, 8, 11, 11, 16, 16, 18],
]
## The 2-bit level indicator stored in the format info, per level L, M, Q, H.
const _FORMAT_ECC_BITS: Array = [1, 0, 3, 2]
const _ECC_NAMES: String = "LMQH"

const _PENALTY_N1: int = 3
const _PENALTY_N2: int = 3
const _PENALTY_N3: int = 40
const _PENALTY_N4: int = 10

static var _gf_exp: PackedByteArray = PackedByteArray()
static var _gf_log: PackedByteArray = PackedByteArray()


## Encodes [param text] (UTF-8, byte mode) at error correction level [param ecc]
## ("L", "M", "Q" or "H"), using the smallest version 1-15 that fits.
## Returns a square Array of PackedByteArray rows (row-major, 1 = dark), without
## the quiet zone. Returns [] and pushes an error when the text does not fit or
## the level is unknown.
static func encode(text: String, ecc: String = "M") -> Array:
	var level: int = _ECC_NAMES.find(ecc.strip_edges().to_upper())
	if ecc.strip_edges().length() != 1 or level < 0:
		push_error("InvoQr: unknown error correction level '%s' (use L, M, Q or H)" % ecc)
		return []
	var data: PackedByteArray = text.to_utf8_buffer()
	var version: int = -1
	for v: int in range(MIN_VERSION, MAX_VERSION + 1):
		if _data_bits_needed(v, data.size()) <= _num_data_codewords(v, level) * 8:
			version = v
			break
	if version < 0:
		push_error("InvoQr: %d bytes does not fit in a version %d QR code at level %s"
				% [data.size(), MAX_VERSION, _ECC_NAMES[level]])
		return []
	var codewords: PackedByteArray = _add_ecc_and_interleave(
			_build_data_codewords(data, version, level), version, level)
	var size: int = version * 4 + 17
	var modules: PackedByteArray = PackedByteArray()
	modules.resize(size * size)
	var is_function: PackedByteArray = PackedByteArray()
	is_function.resize(size * size)
	_draw_function_patterns(modules, is_function, size, version, level)
	_draw_codewords(modules, is_function, size, codewords)

	var best_mask: int = 0
	var best_penalty: int = -1
	for mask: int in 8:
		_apply_mask(modules, is_function, size, mask)
		_draw_format_bits(modules, is_function, size, level, mask)
		var penalty: int = _penalty_score(modules, size)
		if best_penalty < 0 or penalty < best_penalty:
			best_penalty = penalty
			best_mask = mask
		_apply_mask(modules, is_function, size, mask)  # XOR again to undo
	_apply_mask(modules, is_function, size, best_mask)
	_draw_format_bits(modules, is_function, size, level, best_mask)

	var rows: Array = []
	for y: int in size:
		rows.append(modules.slice(y * size, (y + 1) * size))
	return rows


## Renders a matrix from [method encode] to an RGBA8 image, [param module_px]
## pixels per module, with a [param quiet_modules]-wide light border (the spec
## asks for 4). Returns null for an empty matrix.
static func to_image(matrix: Array, module_px: int = 6, quiet_modules: int = 4,
		dark: Color = Color.BLACK, light: Color = Color.WHITE) -> Image:
	if matrix.is_empty() or module_px < 1:
		push_error("InvoQr: nothing to render (empty matrix or module_px < 1)")
		return null
	var size: int = matrix.size()
	var quiet: int = maxi(quiet_modules, 0)
	var px: int = (size + quiet * 2) * module_px
	var img: Image = Image.create_empty(px, px, false, Image.FORMAT_RGBA8)
	img.fill(light)
	for y: int in size:
		var row: PackedByteArray = matrix[y] as PackedByteArray
		for x: int in size:
			if row[x] != 0:
				img.fill_rect(Rect2i((x + quiet) * module_px, (y + quiet) * module_px,
						module_px, module_px), dark)
	return img


## Encodes [param text] at level M and returns it as a texture with a 4-module
## quiet zone, ready for a TextureRect (use TEXTURE_FILTER_NEAREST to keep it
## crisp when scaled). Returns null when the text does not fit.
static func to_texture(text: String, module_px: int = 6) -> ImageTexture:
	var matrix: Array = encode(text)
	if matrix.is_empty():
		return null
	var img: Image = to_image(matrix, module_px)
	if img == null:
		return null
	return ImageTexture.create_from_image(img)


# ---- Capacity ----

## Modules available for data + ECC bits (everything that is not a function pattern).
static func _num_raw_data_modules(version: int) -> int:
	var result: int = (16 * version + 128) * version + 64
	if version >= 2:
		var num_align: int = version / 7 + 2
		result -= (25 * num_align - 10) * num_align - 55
		if version >= 7:
			result -= 36
	return result


static func _num_data_codewords(version: int, level: int) -> int:
	return _num_raw_data_modules(version) / 8 \
			- int(_ECC_CODEWORDS_PER_BLOCK[level][version]) * int(_NUM_EC_BLOCKS[level][version])


static func _char_count_bits(version: int) -> int:
	return 8 if version <= 9 else 16


static func _data_bits_needed(version: int, byte_count: int) -> int:
	if byte_count >= (1 << _char_count_bits(version)):
		return 1 << 30  # count does not fit in the indicator
	return 4 + _char_count_bits(version) + byte_count * 8


# ---- Data codewords ----

static func _build_data_codewords(data: PackedByteArray, version: int, level: int) -> PackedByteArray:
	var capacity_bits: int = _num_data_codewords(version, level) * 8
	var bits: PackedByteArray = PackedByteArray()  # one bit per entry
	_append_bits(bits, 0x4, 4)  # byte mode indicator
	_append_bits(bits, data.size(), _char_count_bits(version))
	for b: int in data:
		_append_bits(bits, b, 8)
	_append_bits(bits, 0, mini(4, capacity_bits - bits.size()))  # terminator
	_append_bits(bits, 0, (8 - bits.size() % 8) % 8)
	var pad: int = 0xEC
	while bits.size() < capacity_bits:
		_append_bits(bits, pad, 8)
		pad = 0x11 if pad == 0xEC else 0xEC
	var out: PackedByteArray = PackedByteArray()
	out.resize(bits.size() / 8)
	for i: int in bits.size():
		out[i >> 3] = out[i >> 3] | (bits[i] << (7 - (i & 7)))
	return out


static func _append_bits(bits: PackedByteArray, value: int, count: int) -> void:
	for i: int in range(count - 1, -1, -1):
		bits.append((value >> i) & 1)


static func _add_ecc_and_interleave(data: PackedByteArray, version: int, level: int) -> PackedByteArray:
	var num_blocks: int = _NUM_EC_BLOCKS[level][version]
	var ecc_len: int = _ECC_CODEWORDS_PER_BLOCK[level][version]
	var raw_codewords: int = _num_raw_data_modules(version) / 8
	var num_short_blocks: int = num_blocks - raw_codewords % num_blocks
	var short_data_len: int = raw_codewords / num_blocks - ecc_len
	var divisor: PackedByteArray = _rs_divisor(ecc_len)
	var data_blocks: Array = []
	var ecc_blocks: Array = []
	var k: int = 0
	for i: int in num_blocks:
		var length: int = short_data_len + (0 if i < num_short_blocks else 1)
		var block: PackedByteArray = data.slice(k, k + length)
		k += length
		data_blocks.append(block)
		ecc_blocks.append(_rs_remainder(block, divisor))
	var out: PackedByteArray = PackedByteArray()
	for i: int in short_data_len + 1:
		for block: PackedByteArray in data_blocks:
			if i < block.size():
				out.append(block[i])
	for i: int in ecc_len:
		for block: PackedByteArray in ecc_blocks:
			out.append(block[i])
	return out


# ---- Reed-Solomon over GF(256), primitive polynomial 0x11D ----

static func _gf_init() -> void:
	if not _gf_exp.is_empty():
		return
	_gf_exp.resize(256)
	_gf_log.resize(256)
	var x: int = 1
	for i: int in 255:
		_gf_exp[i] = x
		_gf_log[x] = i
		x <<= 1
		if x & 0x100:
			x ^= 0x11D
	_gf_exp[255] = _gf_exp[0]


static func _gf_mul(a: int, b: int) -> int:
	if a == 0 or b == 0:
		return 0
	return _gf_exp[(_gf_log[a] + _gf_log[b]) % 255]


## Generator polynomial coefficients (highest power first, leading 1 dropped).
static func _rs_divisor(degree: int) -> PackedByteArray:
	_gf_init()
	var result: PackedByteArray = PackedByteArray()
	result.resize(degree)
	result[degree - 1] = 1
	var root: int = 1
	for i: int in degree:
		for j: int in degree:
			result[j] = _gf_mul(result[j], root)
			if j + 1 < degree:
				result[j] = result[j] ^ result[j + 1]
		root = _gf_mul(root, 2)
	return result


static func _rs_remainder(data: PackedByteArray, divisor: PackedByteArray) -> PackedByteArray:
	var degree: int = divisor.size()
	var result: PackedByteArray = PackedByteArray()
	result.resize(degree)
	for b: int in data:
		var factor: int = b ^ result[0]
		for j: int in degree - 1:
			result[j] = result[j + 1]
		result[degree - 1] = 0
		for j: int in degree:
			result[j] = result[j] ^ _gf_mul(divisor[j], factor)
	return result


# ---- Matrix drawing ----

static func _set_function(modules: PackedByteArray, is_function: PackedByteArray, size: int,
		x: int, y: int, dark: bool) -> void:
	modules[y * size + x] = 1 if dark else 0
	is_function[y * size + x] = 1


static func _alignment_positions(version: int) -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	if version == 1:
		return result
	var num_align: int = version / 7 + 2
	var step: int = (version * 8 + num_align * 3 + 5) / (num_align * 4 - 4) * 2
	result.resize(num_align)
	result[0] = 6
	var pos: int = version * 4 + 17 - 7
	for i: int in range(num_align - 1, 0, -1):
		result[i] = pos
		pos -= step
	return result


static func _draw_function_patterns(modules: PackedByteArray, is_function: PackedByteArray,
		size: int, version: int, level: int) -> void:
	# Timing patterns.
	for i: int in size:
		_set_function(modules, is_function, size, 6, i, i % 2 == 0)
		_set_function(modules, is_function, size, i, 6, i % 2 == 0)
	# Finder patterns with their separators.
	for centre: Vector2i in [Vector2i(3, 3), Vector2i(size - 4, 3), Vector2i(3, size - 4)]:
		for dy: int in range(-4, 5):
			for dx: int in range(-4, 5):
				var x: int = centre.x + dx
				var y: int = centre.y + dy
				if x >= 0 and x < size and y >= 0 and y < size:
					var dist: int = maxi(absi(dx), absi(dy))
					_set_function(modules, is_function, size, x, y, dist != 2 and dist != 4)
	# Alignment patterns (skipping the three that would overlap finders).
	var align: PackedInt32Array = _alignment_positions(version)
	var n: int = align.size()
	for i: int in n:
		for j: int in n:
			if (i == 0 and j == 0) or (i == 0 and j == n - 1) or (i == n - 1 and j == 0):
				continue
			for dy: int in range(-2, 3):
				for dx: int in range(-2, 3):
					_set_function(modules, is_function, size, align[i] + dx, align[j] + dy,
							maxi(absi(dx), absi(dy)) != 1)
	# Reserve the format areas (real bits are drawn once the mask is known).
	_draw_format_bits(modules, is_function, size, level, 0)
	# Version information (versions 7+).
	if version >= 7:
		var rem: int = version
		for i: int in 12:
			rem = (rem << 1) ^ ((rem >> 11) * 0x1F25)
		var bits: int = (version << 12) | rem
		for i: int in 18:
			var dark: bool = ((bits >> i) & 1) != 0
			var a: int = size - 11 + i % 3
			var b: int = i / 3
			_set_function(modules, is_function, size, a, b, dark)
			_set_function(modules, is_function, size, b, a, dark)


static func _draw_format_bits(modules: PackedByteArray, is_function: PackedByteArray,
		size: int, level: int, mask: int) -> void:
	var data: int = (int(_FORMAT_ECC_BITS[level]) << 3) | mask
	var rem: int = data
	for i: int in 10:
		rem = (rem << 1) ^ ((rem >> 9) * 0x537)
	var bits: int = ((data << 10) | rem) ^ 0x5412
	# First copy, around the top-left finder.
	for i: int in 6:
		_set_function(modules, is_function, size, 8, i, ((bits >> i) & 1) != 0)
	_set_function(modules, is_function, size, 8, 7, ((bits >> 6) & 1) != 0)
	_set_function(modules, is_function, size, 8, 8, ((bits >> 7) & 1) != 0)
	_set_function(modules, is_function, size, 7, 8, ((bits >> 8) & 1) != 0)
	for i: int in range(9, 15):
		_set_function(modules, is_function, size, 14 - i, 8, ((bits >> i) & 1) != 0)
	# Second copy, split between the top-right and bottom-left finders.
	for i: int in 8:
		_set_function(modules, is_function, size, size - 1 - i, 8, ((bits >> i) & 1) != 0)
	for i: int in range(8, 15):
		_set_function(modules, is_function, size, 8, size - 15 + i, ((bits >> i) & 1) != 0)
	_set_function(modules, is_function, size, 8, size - 8, true)  # always-dark module


## Places codeword bits in the two-column zigzag from the bottom-right corner.
static func _draw_codewords(modules: PackedByteArray, is_function: PackedByteArray,
		size: int, codewords: PackedByteArray) -> void:
	var total_bits: int = codewords.size() * 8
	var i: int = 0
	var right: int = size - 1
	while right >= 1:
		if right == 6:
			right = 5  # skip the vertical timing column
		var upward: bool = ((right + 1) & 2) == 0
		for vert: int in size:
			var y: int = size - 1 - vert if upward else vert
			for j: int in 2:
				var x: int = right - j
				if is_function[y * size + x] == 0 and i < total_bits:
					modules[y * size + x] = (codewords[i >> 3] >> (7 - (i & 7))) & 1
					i += 1
		right -= 2


## XORs the data area with mask pattern [param mask]; applying it twice undoes it.
static func _apply_mask(modules: PackedByteArray, is_function: PackedByteArray,
		size: int, mask: int) -> void:
	for y: int in size:
		for x: int in size:
			var idx: int = y * size + x
			if is_function[idx] != 0:
				continue
			var invert: bool
			match mask:
				0: invert = (x + y) % 2 == 0
				1: invert = y % 2 == 0
				2: invert = x % 3 == 0
				3: invert = (x + y) % 3 == 0
				4: invert = (x / 3 + y / 2) % 2 == 0
				5: invert = (x * y) % 2 + (x * y) % 3 == 0
				6: invert = ((x * y) % 2 + (x * y) % 3) % 2 == 0
				_: invert = ((x + y) % 2 + (x * y) % 3) % 2 == 0
			if invert:
				modules[idx] = modules[idx] ^ 1


# ---- Mask penalty (ISO/IEC 18004 section 7.8.3) ----

static func _penalty_score(modules: PackedByteArray, size: int) -> int:
	var result: int = 0
	# N1 (runs of 5+ same colour) and N3 (1:1:3:1:1 finder-like), rows then columns.
	for horizontal: bool in [true, false]:
		for a: int in size:
			var line: PackedByteArray = PackedByteArray()
			line.resize(size)
			for b: int in size:
				line[b] = modules[a * size + b] if horizontal else modules[b * size + a]
			result += _line_penalty(line)
	# N2: 2x2 blocks of one colour.
	for y: int in size - 1:
		for x: int in size - 1:
			var c: int = modules[y * size + x]
			if c == modules[y * size + x + 1] and c == modules[(y + 1) * size + x] \
					and c == modules[(y + 1) * size + x + 1]:
				result += _PENALTY_N2
	# N4: dark/light balance, 10 points per 5% away from 50%.
	var dark: int = 0
	for m: int in modules:
		dark += m
	var total: int = size * size
	var k: int = (absi(dark * 20 - total * 10) + total - 1) / total - 1
	result += k * _PENALTY_N4
	return result


## N1 (runs of 5+ same colour) and N3 (1:1:3:1:1 finder-like patterns with 4
## light modules on a side) for one row or column. The area outside the symbol
## counts as light (quiet zone). N3 follows the run-length method used by
## Nayuki's reference qrcodegen, so mask choices agree with it.
static func _line_penalty(line: PackedByteArray) -> int:
	var size: int = line.size()
	var result: int = 0
	var history: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0, 0])
	var run_color: int = 0
	var run: int = 0
	for i: int in size:
		if line[i] == run_color:
			run += 1
			if run == 5:
				result += _PENALTY_N1
			elif run > 5:
				result += 1
		else:
			_push_run(history, run, size)
			if run_color == 0:
				result += _finder_like_count(history) * _PENALTY_N3
			run_color = line[i]
			run = 1
	# Close the line: flush a trailing dark run, then the light quiet zone.
	if run_color == 1:
		_push_run(history, run, size)
		run = 0
	_push_run(history, run + size, size)
	result += _finder_like_count(history) * _PENALTY_N3
	return result


static func _push_run(history: PackedInt32Array, run: int, size: int) -> void:
	var length: int = run + size if history[0] == 0 else run  # leading quiet zone
	for i: int in range(history.size() - 1, 0, -1):
		history[i] = history[i - 1]
	history[0] = length


## history[0] is the most recent (light) run; history[1..5] the candidate pattern.
static func _finder_like_count(history: PackedInt32Array) -> int:
	var n: int = history[1]
	var core: bool = n > 0 and history[2] == n and history[3] == n * 3 \
			and history[4] == n and history[5] == n
	var count: int = 0
	if core and history[0] >= n * 4 and history[6] >= n:
		count += 1
	if core and history[6] >= n * 4 and history[0] >= n:
		count += 1
	return count
