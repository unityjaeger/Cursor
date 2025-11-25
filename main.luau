--!native
--!optimize 2
--!strict

local RESERVED_BUFFER = buffer.create(1e6)

export type WriteCursor = {
	pos: number,
}

export type ReadCursor = {
	pos: number,
	buff: buffer
}

export type EnumContainer<T> = {
	map: {T},
	inverse: {[T]: number}
}

local function writei24(buff: buffer, offset: number, value: number): ()
	if value < 0 then
		value = value + 16777216
	end
	buffer.writeu16(buff, offset, value / 256)
	buffer.writeu8(buff, offset + 2, value)
end

local function readi24(buff: buffer, offset: number): number
	local value: number = 256 * buffer.readu16(buff, offset) + buffer.readu8(buff, offset + 2)
	if value >= 8388608 then
		return value - 16777216
	end
	return value
end

local function writeu24(buff: buffer, offset: number, value: number): ()
	buffer.writeu16(buff, offset, value / 256)
	buffer.writeu8(buff, offset + 2, value)
end

local function readu24(buff: buffer, offset: number): number
	return 256 * buffer.readu16(buff, offset) + buffer.readu8(buff, offset + 2)
end

local function writeu53(buff: buffer, offset: number, value: number): ()
	buffer.writeu32(buff, offset, value / 16777216)
	writeu24(buff, offset + 4, value)
end

local function readu53(buff: buffer, offset: number): number
	return 16777216 * buffer.readu32(buff, offset) + readu24(buff, offset + 4)
end

local function writei53(buff: buffer, offset: number, value: number): ()
	if value < 0 then
		value = value + 9007199254740992
	end
	buffer.writeu32(buff, offset, value / 16777216)
	writeu24(buff, offset + 4, value)
end

local function readi53(buff: buffer, offset: number): number
	local value: number = 16777216 * buffer.readu32(buff, offset) + readu24(buff, offset + 4)
	if value >= 4503599627370496 then
		value = value - 9007199254740992
	end
	return value
end

local function writef16(buff: buffer, offset: number, value: number): ()
	if value ~= value then
		buffer.writeu16(buff, offset, 0x7E01)
		return
	elseif value == 0 then
		buffer.writeu16(buff, offset, 0x0000)
		return
	end

	local sign = 0
	if value < 0 then
		sign = 0x8000
		value = -value
	end

	if value > 65504 then
		buffer.writeu16(buff, offset, bit32.bor(sign, 0x7C00))
		return
	end

	local fraction, exponent = math.frexp(value)
	if exponent < -13 then
		fraction = fraction * math.ldexp(1, exponent + 13)
		exponent = 0
	else
		exponent = exponent + 14
		fraction = (fraction * 2 - 1)
	end

	buffer.writeu16(buff, offset, bit32.bor(
		sign,
		bit32.lshift(exponent, 10),
		fraction * 1024
	))
end

local function readf16(buff: buffer, offset: number): number
	local value = buffer.readu16(buff, offset)

	local banded = bit32.band(value, 0x7C00)
	if value == 0 then
		return (bit32.band(value, 0x8000) ~= 0) and -0 or 0
	elseif value == 0x7C00 then
		return math.huge
	elseif value == 0xFC00 then
		return -math.huge
	elseif (banded == 0x7C00) and (bit32.band(value, 0x03FF) ~= 0) then
		return 0/0
	end

	local sign = bit32.band(value, 0x8000) == 0 and 1 or -1
	local exponent = bit32.rshift(banded, 10)
	local fraction = bit32.band(value, 0x03FF) / 1024

	if exponent == 0 then
		return sign * math.ldexp(fraction, -14)
	else
		return sign * math.ldexp(1 + fraction, exponent - 15)
	end
end


local function write_cursor(): WriteCursor
	return {
		pos = 0
	}
end

local function finalize(cursor: WriteCursor): buffer
	local buff = buffer.create(cursor.pos)
	buffer.copy(buff, 0, RESERVED_BUFFER, 0, cursor.pos)
	return buff
end

local function read_cursor(buff: buffer): ReadCursor
	return {
		pos = 0,
		buff = buff
	}
end

local function pushu8(cursor: WriteCursor, value: number)
	buffer.writeu8(RESERVED_BUFFER, cursor.pos, value)
	cursor.pos += 1
end

local function pushu16(cursor: WriteCursor, value: number)
	buffer.writeu16(RESERVED_BUFFER, cursor.pos, value)
	cursor.pos += 2
end

local function pushu24(cursor: WriteCursor, value: number)
	writeu24(RESERVED_BUFFER, cursor.pos, value)
	cursor.pos += 3
end

local function pushu32(cursor: WriteCursor, value: number)
	buffer.writeu32(RESERVED_BUFFER, cursor.pos, value)
	cursor.pos += 4
end

local function pushu53(cursor: WriteCursor, value: number)
	writeu53(RESERVED_BUFFER, cursor.pos, value)
	cursor.pos += 7
end

local function popu8(cursor: ReadCursor): number
	local value = buffer.readu8(cursor.buff, cursor.pos)
	cursor.pos += 1
	return value
end

local function popu16(cursor: ReadCursor): number
	local value = buffer.readu16(cursor.buff, cursor.pos)
	cursor.pos += 2
	return value
end

local function popu24(cursor: ReadCursor): number
	local value = readu24(cursor.buff, cursor.pos)
	cursor.pos += 3
	return value
end

local function popu32(cursor: ReadCursor): number
	local value = buffer.readu32(cursor.buff, cursor.pos)
	cursor.pos += 4
	return value
end

local function popu53(cursor: ReadCursor): number
	local value = readu53(cursor.buff, cursor.pos)
	cursor.pos += 7
	return value
end

local function pushi8(cursor: WriteCursor, value: number)
	buffer.writei8(RESERVED_BUFFER, cursor.pos, value)
	cursor.pos += 1
end

local function pushi16(cursor: WriteCursor, value: number)
	buffer.writei16(RESERVED_BUFFER, cursor.pos, value)
	cursor.pos += 2
end

local function pushi24(cursor: WriteCursor, value: number)
	writei24(RESERVED_BUFFER, cursor.pos, value)
	cursor.pos += 3
end

local function pushi32(cursor: WriteCursor, value: number)
	buffer.writei32(RESERVED_BUFFER, cursor.pos, value)
	cursor.pos += 4
end

local function pushi53(cursor: WriteCursor, value: number)
	writei53(RESERVED_BUFFER, cursor.pos, value)
	cursor.pos += 7
end

local function popi8(cursor: ReadCursor): number
	local value = buffer.readi8(cursor.buff, cursor.pos)
	cursor.pos += 1
	return value
end

local function popi16(cursor: ReadCursor): number
	local value = buffer.readi16(cursor.buff, cursor.pos)
	cursor.pos += 2
	return value
end

local function popi24(cursor: ReadCursor): number
	local value = readi24(cursor.buff, cursor.pos)
	cursor.pos += 3
	return value
end

local function popi32(cursor: ReadCursor): number
	local value = buffer.readi32(cursor.buff, cursor.pos)
	cursor.pos += 4
	return value
end

local function popi53(cursor: ReadCursor): number
	local value = readi53(cursor.buff, cursor.pos)
	cursor.pos += 7
	return value
end

local function pushf16(cursor: WriteCursor, value: number)
	writef16(RESERVED_BUFFER, cursor.pos, value)
	cursor.pos += 2
end

local function pushf32(cursor: WriteCursor, value: number)
	buffer.writef32(RESERVED_BUFFER, cursor.pos, value)
	cursor.pos += 4
end

local function pushf64(cursor: WriteCursor, value: number)
	buffer.writef64(RESERVED_BUFFER, cursor.pos, value)
	cursor.pos += 8
end

local function popf16(cursor: ReadCursor): number
	local value = readf16(cursor.buff, cursor.pos)
	cursor.pos += 2
	return value
end

local function popf32(cursor: ReadCursor): number
	local value = buffer.readf32(cursor.buff, cursor.pos)
	cursor.pos += 4
	return value
end

local function popf64(cursor: ReadCursor): number
	local value = buffer.readf64(cursor.buff, cursor.pos)
	cursor.pos += 8
	return value
end

local function pushvlq(cursor: WriteCursor, value: number)
	repeat
		local byte = bit32.band(value, 0x7F) 
		value = bit32.rshift(value, 7)
		if value > 0 then
			byte = bit32.bor(byte, 0x80)
		end
		buffer.writeu8(RESERVED_BUFFER, cursor.pos, byte)
		cursor.pos += 1
	until value == 0
end

local function popvlq(cursor: ReadCursor): number
	local result = 0
	local shift = 0
	local byte

	repeat
		byte = buffer.readu8(cursor.buff, cursor.pos)
		cursor.pos += 1
		result = bit32.bor(result, bit32.lshift(bit32.band(byte, 0x7F), shift))
		shift += 7
	until bit32.band(byte, 0x80) == 0

	return result
end

local function pushbool(cursor: WriteCursor, a: boolean, b: boolean?, c: boolean?, d: boolean?, e: boolean?, f: boolean?, g: boolean?, h: boolean?)
	pushu8(cursor,
		(a and 1 or 0) +
		(b and 2 or 0) +
		(c and 4 or 0) +
		(d and 8 or 0) +
		(e and 16 or 0) +
		(f and 32 or 0) +
		(g and 64 or 0) +
		(h and 128 or 0)
	)
end

local function popbool(cursor: ReadCursor): (boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean)
	local value = popu8(cursor)
	return
		bit32.band(value, 1) ~= 0,
		bit32.band(value, 2) ~= 0,
		bit32.band(value, 4) ~= 0,
		bit32.band(value, 8) ~= 0,
		bit32.band(value, 16) ~= 0,
		bit32.band(value, 32) ~= 0,
		bit32.band(value, 64) ~= 0,
		bit32.band(value, 128) ~= 0
end

local function pushvectorf32(cursor: WriteCursor, value: vector)
	local starting_pos = cursor.pos
	buffer.writef32(RESERVED_BUFFER, starting_pos, value.x)
	buffer.writef32(RESERVED_BUFFER, starting_pos + 4, value.y)
	buffer.writef32(RESERVED_BUFFER, starting_pos + 8, value.z)
	cursor.pos += 12
end

local function popvectorf32(cursor: ReadCursor): vector
	local starting_pos = cursor.pos
	local value = vector.create(
		buffer.readf32(cursor.buff, starting_pos),
		buffer.readf32(cursor.buff, starting_pos + 4),
		buffer.readf32(cursor.buff, starting_pos + 8)
	)
	cursor.pos += 12
	return value
end

local function pushstring(cursor: WriteCursor, value: string)
	local len = string.len(value)
	pushvlq(cursor, len)
	buffer.writestring(RESERVED_BUFFER, cursor.pos, value)
	cursor.pos += len
end

local function popstring(cursor: ReadCursor): string
	local len = popvlq(cursor)
	local value = buffer.readstring(cursor.buff, cursor.pos, len)
	cursor.pos += len
	return value
end

local function inverse_copy<T>(tbl: {T}): {[T]: number}
	local inverse = {}
	for i, v in tbl do
		inverse[v] = i
	end
	return inverse
end

local function create_enum_table<T>(tbl: {T}): EnumContainer<T>
	return {
		map = tbl,
		inverse = inverse_copy(tbl)
	}
end

local function create_enum_vararg<T>(...: T): EnumContainer<T>
	return create_enum_table({...})
end

local function pushenum<T>(cursor: WriteCursor, value: T, enums: EnumContainer<T>)
	local index = enums.inverse[value]
	pushu8(cursor, index - 1)
end

local function popenum<T>(cursor: ReadCursor, enums: EnumContainer<T>): T
	local index = popu8(cursor)
	return enums.map[index + 1]
end

local function pushopt<T>(cursor: WriteCursor, push_method: (cursor: WriteCursor, value: T) -> (), value: T?)
	if value == nil then
		pushu8(cursor, 0)
	else
		pushu8(cursor, 1)
		push_method(cursor, value)
	end
end

local function popopt<T>(cursor: ReadCursor, pop_method: (cursor: ReadCursor) -> T): T?
	local present = popu8(cursor)
	if present == 1 then
		return pop_method(cursor)
	else
		return nil
	end
end

local function pushopt_enum<T>(cursor: WriteCursor, value: T?, enums: EnumContainer<T>)
	pushopt(cursor, function(c, v: T)
		pushenum(c, v, enums)
	end, value)
end

local function popopt_enum<T>(cursor: ReadCursor, enums: EnumContainer<T>): T?
	return popopt(cursor, function(c)
		return popenum(c, enums)
	end)
end

return {
	write_cursor = write_cursor,
	read_cursor = read_cursor,
	finalize = finalize,
	
	pushu8 = pushu8,
	pushu16 = pushu16,
	pushu24 = pushu24,
	pushu32 = pushu32,
	pushu53 = pushu53,
	popu8 = popu8,
	popu16 = popu16,
	popu24 = popu24,
	popu32 = popu32,
	popu53 = popu53,
	
	pushi8 = pushi8,
	pushi16 = pushi16,
	pushi24 = pushi24,
	pushi32 = pushi32,
	pushi53 = pushi53,
	popi8 = popi8,
	popi16 = popi16,
	popi24 = popi24,
	popi32 = popi32,
	popi53 = popi53,
	
	pushf16 = pushf16,
	pushf32 = pushf32,
	pushf64 = pushf64,
	popf16 = popf16,
	popf32 = popf32,
	popf64 = popf64,
	
	pushvlq = pushvlq,
	popvlq = popvlq,
	
	pushbool = pushbool,
	popbool = popbool,
	
	pushvectorf32 = pushvectorf32,
	popvectorf32 = popvectorf32,
	
	pushstring = pushstring,
	popstring = popstring,
	
	create_enum_vararg = create_enum_vararg,
	create_enum_table = create_enum_table,
	
	pushenum = pushenum,
	popenum = popenum,
	
	pushopt = pushopt,
	popopt = popopt,
	
	pushopt_enum = pushopt_enum,
	popopt_enum = popopt_enum
}
