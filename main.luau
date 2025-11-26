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

export type Descriptor<T> = {
	push: (cursor: WriteCursor, value: T) -> (),
	pop: (cursor: ReadCursor) -> T
}

export type TupleDescriptor<T...> = {
	push: (cursor: WriteCursor, T...) -> (),
	pop: (cursor: ReadCursor) -> T...
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

local function inverse_table<T>(tbl: {T}): {[T]: number}
	local inverse = {}
	for i, v in tbl do
		inverse[v] = i
	end
	return inverse
end

local function matches(arg1: any, arg2: any): boolean
	if not (arg1 and arg2) then
		return false
	end

	local type1, type2 = typeof(arg1), typeof(arg2)
	if type1 ~= type2 then
		return false
	end

	if type1 == "table" then
		for key, value in arg1 do
			if not matches(arg2[key], value) then
				return false
			end
		end
		for key, value in arg2 do
			if not matches(arg1[key], value) then
				return false
			end
		end
	else
		return arg1 == arg2
	end

	return false
end

local function write_cursor(global_offset: number?): WriteCursor
	return {
		pos = global_offset or 0
	}
end

local function finalize(cursor: WriteCursor): buffer
	local buff = buffer.create(cursor.pos)
	buffer.copy(buff, 0, RESERVED_BUFFER, 0, cursor.pos)
	return buff
end

local function read_cursor(buff: buffer, global_offset: number?): ReadCursor
	return {
		pos = global_offset or 0,
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

local function pushbool_simple(cursor: WriteCursor, value: boolean)
	pushu8(cursor, value and 1 or 0)
end

local function popboool_simple(cursor: ReadCursor): boolean
	return popu8(cursor) == 1
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

local literal_descriptor_cache = {}
local function literal_descriptor<T>(literals: {T}): Descriptor<T>
	if literal_descriptor_cache[literals] then
		return literal_descriptor_cache[literals]
	end
	
	local inverse_literals = inverse_table(literals)
	
	local descriptor: Descriptor<T> = {
		push = function(cursor, value: T)
			local index = inverse_literals[value]
			pushu8(cursor, index - 1)
		end,
		pop = function(cursor)
			local index = popu8(cursor)
			return literals[index + 1]
		end,
	}
	
	literal_descriptor_cache[literals] = descriptor
	
	return descriptor
end

local vector_descriptor_cache = {}
local function vector_descriptor<number>(inner: Descriptor<number>): Descriptor<vector>
	if vector_descriptor_cache[inner] then
		return vector_descriptor_cache[inner]
	end
	
	local push, pop = inner.push, inner.pop
	
	local descriptor: Descriptor<vector> = {
		push = function(cursor, value: vector)
			push(cursor, value.x)
			push(cursor, value.y)
			push(cursor, value.z)
		end,
		pop = function(cursor)
			return vector.create(
				pop(cursor),
				pop(cursor),
				pop(cursor)
			)
		end,
	}
	
	vector_descriptor_cache[inner] = descriptor
	
	return descriptor
end

local opt_descriptor_cache = {}
local function opt_descriptor<T>(inner: Descriptor<T>): Descriptor<T?>
	if opt_descriptor_cache[inner] then
		return opt_descriptor_cache[inner]
	end
	
	local push, pop = inner.push, inner.pop
	
	--inline for slightly better speed yknow
	local descriptor: Descriptor<T?> = {
		push = function(cursor, value: T?)
			if value == nil then
				pushu8(cursor, 0)
			else
				pushu8(cursor, 1)
				push(cursor, value)
			end
		end,
		pop = function(cursor)
			local present = popu8(cursor)
			if present == 1 then
				return pop(cursor)
			else
				return nil
			end
		end,
	}
	
	opt_descriptor_cache[inner] = descriptor
	
	return descriptor
end

local struct_descriptor_cache = {}
local function struct_descriptor<T>(struct: T): Descriptor<T>
	if struct_descriptor_cache[struct] then
		return struct_descriptor_cache[struct]
	end
	
	local descriptor: Descriptor<T> = {
		push = function(cursor, value)
			for field, inner in struct :: {[string]: Descriptor<any>} do
				inner.push(cursor, value[field])
			end
		end,
		pop = function(cursor)
			local result = {}
			for field, inner in struct :: {[string]: Descriptor<any>} do
				result[field] = inner.pop(cursor)
			end
			return result
		end,
	}
	
	struct_descriptor_cache[struct] = descriptor
	
	return descriptor
end

local array_descriptor_cache = {}
local function array_descriptor<T>(inner: Descriptor<T>): Descriptor<{T}>
	if array_descriptor_cache[inner] then
		return array_descriptor_cache[inner]
	end
	
	local push, pop = inner.push, inner.pop
	
	local descriptor: Descriptor<{T}> = {
		push = function(cursor, value: {T})
			pushvlq(cursor, #value)
			for _, entry in value do
				push(cursor, entry)
			end
		end,
		pop = function(cursor)
			local len = popvlq(cursor)
			local result = table.create(len)
			for i = 1, len do
				table.insert(result, pop(cursor))
			end
			return result
		end,
	}
	
	array_descriptor_cache[inner] = descriptor
	
	return descriptor
end

local map_descriptor_cache = {}
local function map_descriptor<K, V>(inner_key: Descriptor<K>, inner_value: Descriptor<V>): Descriptor<{[K]: V}>
	if map_descriptor_cache[inner_key] and map_descriptor_cache[inner_key][inner_value] then
		return map_descriptor_cache[inner_key][inner_value]
	end
	
	local key_push, key_pop = inner_key.push, inner_key.pop
	local value_push, value_pop = inner_value.push, inner_value.pop
	
	local descriptor: Descriptor<{[K]: V}> = {
		push = function(cursor, value: {[K]: V})
			local len = 0
			for key, entry in value do
				len += 1
			end
			
			pushvlq(cursor, len)
			
			for key, entry in value do
				key_push(cursor, key)
				value_push(cursor, entry)
			end
		end,
		pop = function(cursor)
			local len = popvlq(cursor)
			local map = {}
			
			for i = 1, len do
				map[key_pop(cursor)] = value_pop(cursor)
			end
			
			return map
		end,
	}
	
	map_descriptor_cache[inner_key] = {[inner_value] = descriptor}
	
	return descriptor
end

local function T<T>(value: Descriptor<T>): T
	return value
end

local u8_descriptor: Descriptor<number> = {
	push = pushu8,
	pop = popu8,
}

local u16_descriptor: Descriptor<number> = {
	push = pushu16,
	pop = popu16,
}

local u24_descriptor: Descriptor<number> = {
	push = pushu24,
	pop = popu24,
}

local u32_descriptor: Descriptor<number> = {
	push = pushu32,
	pop = popu32,
}

local u53_descriptor: Descriptor<number> = {
	push = pushu53,
	pop = popu53,
}

local i8_descriptor: Descriptor<number> = {
	push = pushi8,
	pop = popi8,
}

local i16_descriptor: Descriptor<number> = {
	push = pushi16,
	pop = popi16,
}

local i24_descriptor: Descriptor<number> = {
	push = pushi24,
	pop = popi24,
}

local i32_descriptor: Descriptor<number> = {
	push = pushi32,
	pop = popi32,
}

local i53_descriptor: Descriptor<number> = {
	push = pushi53,
	pop = popi53,
}

local f16_descriptor: Descriptor<number> = {
	push = pushf16,
	pop = popf16,
}

local f32_descriptor: Descriptor<number> = {
	push = pushf32,
	pop = popf32,
}

local f64_descriptor: Descriptor<number> = {
	push = pushf64,
	pop = popf64,
}

local vlq_descriptor: Descriptor<number> = {
	push = pushvlq,
	pop = popvlq,
}

local string_descriptor: Descriptor<string> = {
	push = pushstring,
	pop = popstring,
}

local bool_descriptor: TupleDescriptor<...boolean> = {
	push = pushbool,
	pop = popbool
}

local bool_simple_descriptor: Descriptor<boolean> = {
	push = pushbool_simple,
	pop = popboool_simple
}

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
	
	pushstring = pushstring,
	popstring = popstring,
	
	pushopt = pushopt,
	popopt = popopt,
	
	u8 = u8_descriptor,
	u16 = u16_descriptor,
	u24 = u24_descriptor,
	u32 = u32_descriptor,
	u53 = u53_descriptor,
	
	i8 = i8_descriptor,
	i16 = i16_descriptor,
	i24 = i24_descriptor,
	i32 = i32_descriptor,
	i53 = i53_descriptor,
	
	f16 = f16_descriptor,
	f32 = f32_descriptor,
	f64 = f64_descriptor,
	
	vlq = vlq_descriptor,
	
	bool = bool_descriptor,
	bool_simple = bool_simple_descriptor,
	
	string = string_descriptor,
	
	literal = literal_descriptor,
	vector = vector_descriptor,
	opt = opt_descriptor,
	struct = struct_descriptor,
	array = array_descriptor,
	map = map_descriptor
}
