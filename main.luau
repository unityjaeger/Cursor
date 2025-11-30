--!native
--!optimize 2
--!strict

local RESERVED_BUFFER_SIZE = 1e6
local RESERVED_BUFFER = buffer.create(RESERVED_BUFFER_SIZE)
local PI = math.pi

export type WriteCursor = {
	pos: number,
	global_offset: number
}

export type ReadCursor = {
	pos: number,
	buff: buffer
}

export type Codec<T> = {
	write: (cursor: WriteCursor, value: T) -> (),
	read: (cursor: ReadCursor) -> T,
	optional: boolean?
}

export type TupleCodec<T...> = {
	write: (cursor: WriteCursor, T...) -> (),
	read: (cursor: ReadCursor) -> T...
}

type StructField = Codec<any> & {
	name: string
}

type OptStructField = StructField & {
	bitmask: number
}

type function EitherOr(a: type, b: type)
	if a:is("unknown") then
		return b
	else
		return a
	end
end

export type function SetTransformer(t: type)
	local new = types.newtable()
	for _, v in t:components() do
		new:setproperty(v, types.optional(types.boolean))
	end
	return Codec(new :: any)
end

type function GetCodecType(t: type)
	if t.tag ~= "table" then
		return types.never
	end

	local des_fn = t:readproperty(types.singleton("read"))
	if not des_fn or not des_fn:is("function") then
		return types.never
	end

	local ret = des_fn:returns().head
	if not ret or not ret[1] then
		return types.never
	end

	return ret[1]
end

type function StructTransformer(t: type)
	if t.tag ~= "table" then
		return t
	end

	local tbl_props = t:properties()

	local phantom_data = GetCodecType(t)
	if phantom_data ~= types.never then
		return StructTransformer(phantom_data)
	end

	local indexer = t:indexer()
	if indexer then
		local new = types.newtable()
		new:setindexer(StructTransformer(indexer.index), StructTransformer(indexer.readresult))
		return new :: any
	end

	local new = types.newtable()
	for key, v in tbl_props do
		local value = v.read or v.write
		new:setproperty(key, StructTransformer(value))
	end
	return new :: any
end

type function VariantTransformer(t: type)
	local t_props = t:properties()

	local intersect

	for k, v in t_props do
		local new_t = types.newtable()
		new_t:setproperty(types.singleton("kind"), k)
		new_t:setproperty(types.singleton("value"), StructTransformer(v.read))

		if not intersect then
			intersect = new_t
		else
			intersect = types.unionof(intersect, new_t)
		end
	end

	return intersect :: any
end

local function write_cursor(global_offset: number?): WriteCursor
	return {
		pos = global_offset or 0,
		global_offset = global_offset or 0
	}
end

local function finalize(cursor: WriteCursor): buffer
	local global_offset, pos = cursor.global_offset, cursor.pos
	local buff = buffer.create(pos)
	local count = pos - global_offset
	buffer.copy(buff, 0, RESERVED_BUFFER, global_offset, count)
	cursor.pos = global_offset
	return buff
end

local function read_cursor(buff: buffer): ReadCursor
	local buffer_len = buffer.len(buff)
	if buffer_len > RESERVED_BUFFER_SIZE then
		error(string.format("input buffer size exceeds maximum size %d, got %d", RESERVED_BUFFER_SIZE, buffer_len))
	end

	return {
		pos = 0,
		buff = buff
	}
end

local function writeu8(cursor: WriteCursor, value: number)
	buffer.writeu8(RESERVED_BUFFER, cursor.pos, value)
	cursor.pos += 1
end

local function writeu16(cursor: WriteCursor, value: number)
	buffer.writeu16(RESERVED_BUFFER, cursor.pos, value)
	cursor.pos += 2
end

local function writeu24(cursor: WriteCursor, value: number)
	local pos = cursor.pos

	buffer.writeu16(RESERVED_BUFFER, pos, value / 2^8)
	pos += 2

	buffer.writeu8(RESERVED_BUFFER, pos, value)
	cursor.pos = pos + 1
end

local function writeu32(cursor: WriteCursor, value: number)
	buffer.writeu32(RESERVED_BUFFER, cursor.pos, value)
	cursor.pos += 4
end

local function writeu53(cursor: WriteCursor, value: number)
	local pos = cursor.pos

	buffer.writeu32(RESERVED_BUFFER, pos, value / 2^24)
	pos += 4

	buffer.writeu16(RESERVED_BUFFER, pos, value / 2^8)
	pos += 2

	buffer.writeu8(RESERVED_BUFFER, pos, value)
	cursor.pos = pos + 1
end

local function readu8(cursor: ReadCursor): number
	local value = buffer.readu8(cursor.buff, cursor.pos)
	cursor.pos += 1
	return value
end

local function readu16(cursor: ReadCursor): number
	local value = buffer.readu16(cursor.buff, cursor.pos)
	cursor.pos += 2
	return value
end

local function readu24(cursor: ReadCursor): number
	local buff, pos = cursor.buff, cursor.pos

	local value = 2^8 * buffer.readu16(buff, pos)
	pos += 2

	value += buffer.readu8(buff, pos)
	cursor.pos = pos + 1

	return value
end

local function readu32(cursor: ReadCursor): number
	local value = buffer.readu32(cursor.buff, cursor.pos)
	cursor.pos += 4
	return value
end

local function readu53(cursor: ReadCursor): number
	local buff, pos = cursor.buff, cursor.pos

	local value = 2^24 * buffer.readu32(buff, pos)
	pos += 4

	value += 2^8 * buffer.readu16(buff, pos)
	pos += 2

	value += buffer.readu8(buff, pos)
	cursor.pos = pos + 1

	return value
end

local function writei8(cursor: WriteCursor, value: number)
	buffer.writei8(RESERVED_BUFFER, cursor.pos, value)
	cursor.pos += 1
end

local function writei16(cursor: WriteCursor, value: number)
	buffer.writei16(RESERVED_BUFFER, cursor.pos, value)
	cursor.pos += 2
end

local function writei24(cursor: WriteCursor, value: number)
	if value < 0 then
		value += 2^24
	end

	local pos = cursor.pos

	buffer.writeu16(RESERVED_BUFFER, pos, value / 2^8)
	pos += 2

	buffer.writeu8(RESERVED_BUFFER, pos, value)
	cursor.pos = pos + 1
end

local function writei32(cursor: WriteCursor, value: number)
	buffer.writei32(RESERVED_BUFFER, cursor.pos, value)
	cursor.pos += 4
end

local function writei53(cursor: WriteCursor, value: number)
	if value < 0 then
		value += 2^53
	end

	local pos = cursor.pos

	buffer.writeu32(RESERVED_BUFFER, pos, value / 2^24)
	pos += 4

	buffer.writeu16(RESERVED_BUFFER, pos, value / 2^8)
	pos += 2

	buffer.writeu8(RESERVED_BUFFER, pos, value)
	cursor.pos = pos + 1
end

local function readi8(cursor: ReadCursor): number
	local value = buffer.readi8(cursor.buff, cursor.pos)
	cursor.pos += 1
	return value
end

local function readi16(cursor: ReadCursor): number
	local value = buffer.readi16(cursor.buff, cursor.pos)
	cursor.pos += 2
	return value
end

local function readi24(cursor: ReadCursor): number
	local buff, pos = cursor.buff, cursor.pos

	local value = 2^8 * buffer.readu16(buff, pos)
	pos += 2

	value += buffer.readu8(buff, pos)
	cursor.pos = pos + 1

	if value >= 2^23 then
		return value - 2^24
	end

	return value
end

local function readi32(cursor: ReadCursor): number
	local value = buffer.readi32(cursor.buff, cursor.pos)
	cursor.pos += 4
	return value
end

local function readi53(cursor: ReadCursor): number
	local buff, pos = cursor.buff, cursor.pos

	local value = 2^24 * buffer.readu32(buff, pos)
	pos += 4

	value += 2^8 * buffer.readu16(buff, pos)
	pos += 2

	value += buffer.readu8(buff, pos)
	cursor.pos = pos + 1

	if value >= 2^52 then
		return value - 2^53
	end

	return value
end

local function writef16(cursor: WriteCursor, value: number)
	if value ~= value then
		buffer.writeu16(RESERVED_BUFFER, cursor.pos, 0x7E01)
		cursor.pos += 2
		return
	elseif value == 0 then
		buffer.writeu16(RESERVED_BUFFER, cursor.pos, 0x0000)
		cursor.pos += 2
		return
	end

	local sign = 0
	if value < 0 then
		sign = 0x8000
		value = -value
	end

	if value > 65504 then
		buffer.writeu16(RESERVED_BUFFER, cursor.pos, bit32.bor(sign, 0x7C00))
		cursor.pos += 2
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

	buffer.writeu16(RESERVED_BUFFER, cursor.pos, bit32.bor(
		sign,
		bit32.lshift(exponent, 10),
		fraction * 1024
	))

	cursor.pos += 2
end

local function writef32(cursor: WriteCursor, value: number)
	buffer.writef32(RESERVED_BUFFER, cursor.pos, value)
	cursor.pos += 4
end

local function writef64(cursor: WriteCursor, value: number)
	buffer.writef64(RESERVED_BUFFER, cursor.pos, value)
	cursor.pos += 8
end

local f16_lut = {}
do
	for value = 0, 2 ^ 16 - 1 do
		local result
		
		local banded = bit32.band(value, 0x7C00)
		if value == 0 then
			result = (bit32.band(value, 0x8000) ~= 0) and -0 or 0
			continue
		elseif value == 0x7C00 then
			result = math.huge
			continue
		elseif value == 0xFC00 then
			result = -math.huge
			continue
		elseif (banded == 0x7C00) and (bit32.band(value, 0x03FF) ~= 0) then
			result = 0/0
			continue
		end

		local sign = bit32.band(value, 0x8000) == 0 and 1 or -1
		local exponent = bit32.rshift(banded, 10)
		local fraction = bit32.band(value, 0x03FF) / 1024

		if exponent == 0 then
			result = sign * math.ldexp(fraction, -14)
		else
			result = sign * math.ldexp(1 + fraction, exponent - 15)
		end

		f16_lut[value] = result
	end
end

local function readf16(cursor: ReadCursor): number
	local value = f16_lut[buffer.readu16(cursor.buff, cursor.pos)]
	cursor.pos += 2
	return value
end

local function readf32(cursor: ReadCursor): number
	local value = buffer.readf32(cursor.buff, cursor.pos)
	cursor.pos += 4
	return value
end

local function readf64(cursor: ReadCursor): number
	local value = buffer.readf64(cursor.buff, cursor.pos)
	cursor.pos += 8
	return value
end

local function writevlq(cursor: WriteCursor, value: number)
	local pos = cursor.pos

	repeat
		local byte = value % 2^7
		value = (value - byte) / 2^7

		if value > 0 then
			byte += 2^7
		end

		buffer.writeu8(RESERVED_BUFFER, pos, byte)
		pos += 1
	until value == 0

	cursor.pos = pos
end

local function readvlq(cursor: ReadCursor): number
	local buff, pos = cursor.buff, cursor.pos

	local result = 0
	local shift = 1

	repeat
		local byte = buffer.readu8(buff, pos)
		pos += 1

		local chunk = byte % 2^7

		result += chunk * shift
		shift *= 2^7
	until byte < 2^7

	cursor.pos = pos

	return result
end

local function writesvlq(cursor: WriteCursor, value: number)
	if value >= 0 then
		writevlq(cursor, value * 2)
	else
		writevlq(cursor, -value * 2 - 1)
	end
end

local function readsvlq(cursor: ReadCursor): number
	local value = readvlq(cursor)

	if value % 2 == 0 then
		return value / 2
	else
		return -(value + 1) / 2
	end
end

local function writebuffer(cursor: WriteCursor, value: buffer)
	local len = buffer.len(value)
	writevlq(cursor, len)
	buffer.copy(RESERVED_BUFFER, cursor.pos, value, 0)
	cursor.pos += len
end

local function readbuffer(cursor: ReadCursor): buffer
	local len = readvlq(cursor)
	local result = buffer.create(len)
	buffer.copy(result, 0, cursor.buff, cursor.pos, len)
	cursor.pos += len
	return result
end

local function writebool(cursor: WriteCursor, a: boolean, b: boolean?, c: boolean?, d: boolean?, e: boolean?, f: boolean?, g: boolean?, h: boolean?)
	buffer.writeu8(RESERVED_BUFFER, cursor.pos, 
		(a and 2^0 or 0) +
		(b and 2^1 or 0) +
		(c and 2^2 or 0) +
		(d and 2^3 or 0) +
		(e and 2^4 or 0) +
		(f and 2^5 or 0) +
		(g and 2^6 or 0) +
		(h and 2^7 or 0)
	)

	cursor.pos += 1
end

local function readbool(cursor: ReadCursor): (boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean)
	local value = buffer.readu8(cursor.buff, cursor.pos)
	cursor.pos += 1

	return
		bit32.band(value, 2^0) ~= 0,
		bit32.band(value, 2^1) ~= 0,
		bit32.band(value, 2^2) ~= 0,
		bit32.band(value, 2^3) ~= 0,
		bit32.band(value, 2^4) ~= 0,
		bit32.band(value, 2^5) ~= 0,
		bit32.band(value, 2^6) ~= 0,
		bit32.band(value, 2^7) ~= 0
end

local function writebool_simple(cursor: WriteCursor, value: boolean)
	buffer.writeu8(RESERVED_BUFFER, cursor.pos, value and 1 or 0)
	cursor.pos += 1
end

local function readboool_simple(cursor: ReadCursor): boolean
	local value = buffer.readu8(cursor.buff, cursor.pos)
	cursor.pos += 1
	return value == 1
end

local function writestring(cursor: WriteCursor, value: string)
	local len = string.len(value)
	writevlq(cursor, len)
	buffer.writestring(RESERVED_BUFFER, cursor.pos, value)
	cursor.pos += len
end

local function readstring(cursor: ReadCursor): string
	local len = readvlq(cursor)
	local value = buffer.readstring(cursor.buff, cursor.pos, len)
	cursor.pos += len
	return value
end

local function writecolor3(cursor: WriteCursor, value: Color3)
	local pos = cursor.pos

	buffer.writeu8(RESERVED_BUFFER, pos, value.R * 255)
	pos += 1

	buffer.writeu8(RESERVED_BUFFER, pos, value.G * 255)
	pos += 1

	buffer.writeu8(RESERVED_BUFFER, pos, value.B * 255)
	cursor.pos = pos + 1
end

local function readcolor3(cursor: ReadCursor): Color3
	local buff, pos = cursor.buff, cursor.pos

	local r = buffer.readu8(buff, pos)
	pos += 1

	local g = buffer.readu8(buff, pos)
	pos += 1

	local b = buffer.readu8(buff, pos)
	cursor.pos = pos + 1

	return Color3.fromRGB(r, g, b)
end

local function writeopt<T>(cursor: WriteCursor, write_method: (cursor: WriteCursor, value: T) -> (), value: T?)
	if value == nil then
		buffer.writeu8(RESERVED_BUFFER, cursor.pos, 0)
		cursor.pos += 1
	else
		buffer.writeu8(RESERVED_BUFFER, cursor.pos, 1)
		cursor.pos += 1

		write_method(cursor, value)
	end
end

local function readopt<T>(cursor: ReadCursor, read_method: (cursor: ReadCursor) -> T): T?
	local is_present = buffer.readu8(cursor.buff, cursor.pos)
	cursor.pos += 1

	if is_present == 1 then
		return read_method(cursor)
	else
		return nil
	end
end

local function mark_opt<T>(inner: Codec<T>): Codec<T?>
	local copy = table.clone(inner)
	copy.optional = true
	return copy
end

local u8_codec: Codec<number> = {
	write = writeu8,
	read = readu8,
}

local u16_codec: Codec<number> = {
	write = writeu16,
	read = readu16,
}

local u24_codec: Codec<number> = {
	write = writeu24,
	read = readu24,
}

local u32_codec: Codec<number> = {
	write = writeu32,
	read = readu32,
}

local u53_codec: Codec<number> = {
	write = writeu53,
	read = readu53,
}

local i8_codec: Codec<number> = {
	write = writei8,
	read = readi8,
}

local i16_codec: Codec<number> = {
	write = writei16,
	read = readi16,
}

local i24_codec: Codec<number> = {
	write = writei24,
	read = readi24,
}

local i32_codec: Codec<number> = {
	write = writei32,
	read = readi32,
}

local i53_codec: Codec<number> = {
	write = writei53,
	read = readi53,
}

local f16_codec: Codec<number> = {
	write = writef16,
	read = readf16,
}

local f32_codec: Codec<number> = {
	write = writef32,
	read = readf32,
}

local f64_codec: Codec<number> = {
	write = writef64,
	read = readf64,
}

local vlq_codec: Codec<number> = {
	write = writevlq,
	read = readvlq,
}

local svlq_codec: Codec<number> = {
	write = writesvlq,
	read = readsvlq
}

local buffer_codec: Codec<buffer> = {
	write = writebuffer,
	read = readbuffer
}

local string_codec: Codec<string> = {
	write = writestring,
	read = readstring,
}

local bool_codec: TupleCodec<...boolean> = {
	write = writebool,
	read = readbool
}

local bool_simple_codec: Codec<boolean> = {
	write = writebool_simple,
	read = readboool_simple
}

local color3_codec: Codec<Color3> = {
	write = writecolor3,
	read = readcolor3
}

local literal_codec_cache = {}
local function literal_codec<T>(literals: {T}): Codec<T>
	if literal_codec_cache[literals] then
		return literal_codec_cache[literals]
	end

	if #literals > 255 then
		error(string.format("cannot have more than 255 literals, got %d", #literals))
	end

	local inverse_literals = {}
	for i, v in literals do
		inverse_literals[v] = i
	end

	local codec: Codec<T> = {
		write = function(cursor, value: T)
			local index = inverse_literals[value]
			buffer.writeu8(RESERVED_BUFFER, cursor.pos, index - 1)
			cursor.pos += 1
		end,
		read = function(cursor)
			local index = buffer.readu8(cursor.buff, cursor.pos)
			cursor.pos += 1
			return literals[index + 1]
		end,
	}

	literal_codec_cache[literals] = codec

	return codec
end

local vector_codec_cache = {}
local function vector3_codec(number_codec: Codec<number>): Codec<Vector3>
	if vector_codec_cache[number_codec] then
		return vector_codec_cache[number_codec]
	end

	local write, read = number_codec.write, number_codec.read

	local codec: Codec<Vector3> = {
		write = function(cursor, value: Vector3)
			write(cursor, value.X)
			write(cursor, value.Y)
			write(cursor, value.Z)
		end,
		read = function(cursor)
			return Vector3.new(
				read(cursor),
				read(cursor),
				read(cursor)
			)
		end,
	}

	vector_codec_cache[number_codec] = codec

	return codec
end

local opt_codec_cache = {}
local function opt_codec<T>(inner: Codec<T>): Codec<T?>
	if opt_codec_cache[inner] then
		return opt_codec_cache[inner]
	end

	local write, read = inner.write, inner.read

	local codec: Codec<T?> = {
		write = function(cursor, value: T?)
			if value == nil then
				buffer.writeu8(RESERVED_BUFFER, cursor.pos, 0)
				cursor.pos += 1
			else
				buffer.writeu8(RESERVED_BUFFER, cursor.pos, 1)
				cursor.pos += 1

				write(cursor, value)
			end
		end,
		read = function(cursor)
			local is_present = buffer.readu8(cursor.buff, cursor.pos)
			cursor.pos += 1

			if is_present == 1 then
				return read(cursor)
			else
				return nil
			end
		end,
	}

	opt_codec_cache[inner] = codec

	return codec
end

local function simple_struct<T>(fields: {StructField}): Codec<T>
	return {
		write = function(cursor, value)
			for _, inner in fields do
				inner.write(cursor, value[inner.name])
			end
		end,
		read = function(cursor)
			local result = {}
			for _, inner in fields do
				result[inner.name] = inner.read(cursor)
			end
			return result
		end,
	}
end

local function optional_struct<T>(fields: {StructField}, opt_fields: {OptStructField}, byte_codec: Codec<number>): Codec<T>
	local write_byte, read_byte = byte_codec.write, byte_codec.read

	return {
		write = function(cursor, value)
			local byte = 0
			for _, inner in opt_fields do
				local field_value = value[inner.name]
				if field_value ~= nil then
					byte = bit32.bor(byte, inner.bitmask)
				end
			end

			write_byte(cursor, byte)

			for _, inner in opt_fields do
				local field_value = value[inner.name]
				if field_value ~= nil then
					inner.write(cursor, field_value)
				end
			end

			for _, inner in fields do
				inner.write(cursor, value[inner.name])
			end
		end,
		read = function(cursor)
			local result = {}
			local byte = read_byte(cursor)

			for _, inner in opt_fields do
				if bit32.band(byte, inner.bitmask) ~= 0 then
					result[inner.name] = inner.read(cursor)
				end
			end

			for _, inner in fields do
				result[inner.name] = inner.read(cursor)
			end

			return result
		end,
	}
end

local struct_codec_cache = {}
local function struct_codec_hidden<T>(struct: T): Codec<T>
	if struct_codec_cache[struct] then
		return struct_codec_cache[struct]
	end

	local fields: {StructField} = {}
	local opt_fields: {OptStructField} = {}
	local opt_count = 0	

	for name, inner in struct :: {[string]: Codec<any>} do
		if inner.optional then
			table.insert(opt_fields, {
				name = name,
				write = inner.write,
				read = inner.read,
				bitmask = bit32.lshift(1, opt_count)
			} :: OptStructField)

			opt_count += 1

			if opt_count > 32 then
				error(string.format("structs can not have more than 32 optional fields, got %d", opt_count))
			end
		else
			table.insert(fields, {
				name = name,
				write = inner.write,
				read = inner.read
			} :: StructField)
		end
	end

	table.sort(opt_fields, function(a: OptStructField, b: OptStructField) return a.name < b.name end)
	table.sort(fields, function(a: StructField, b: StructField) return a.name < b.name end)

	local byte_codec: Codec<number>
	if opt_count <= 8 then
		byte_codec = u8_codec
	elseif opt_count <= 16 then
		byte_codec = u16_codec
	elseif opt_count <= 24 then
		byte_codec = u24_codec
	else
		byte_codec = u32_codec
	end

	local codec: Codec<T>
	if opt_count == 0 then
		codec = simple_struct(fields)
	else
		codec = optional_struct(fields, opt_fields, byte_codec)
	end

	struct_codec_cache[struct] = codec

	return codec
end

local function struct_codec<T>(struct: T & {[string]: Codec<any>}): Codec<StructTransformer<T>>
	return struct_codec_hidden(struct)
end

local array_codec_cache = {}
local function array_codec<T>(element_codec: Codec<T>): Codec<{T}>
	if array_codec_cache[element_codec] then
		return array_codec_cache[element_codec]
	end

	local write, read = element_codec.write, element_codec.read

	local codec: Codec<{T}> = {
		write = function(cursor, value: {T})
			writevlq(cursor, #value)
			for _, entry in value do
				write(cursor, entry)
			end
		end,
		read = function(cursor)
			local len = readvlq(cursor)
			local result = table.create(len)
			for i = 1, len do
				table.insert(result, read(cursor))
			end
			return result
		end,
	}

	array_codec_cache[element_codec] = codec

	return codec
end

local map_codec_cache = {}
local function map_codec<K, V>(key_codec: Codec<K>, value_codec: Codec<V>): Codec<{[K]: V}>
	if map_codec_cache[key_codec] and map_codec_cache[key_codec][value_codec] then
		return map_codec_cache[key_codec][value_codec]
	end

	local key_write, key_read = key_codec.write, key_codec.read
	local value_write, value_read = value_codec.write, value_codec.read

	local codec: Codec<{[K]: V}> = {
		write = function(cursor, value: {[K]: V})
			local len = 0
			for key, entry in value do
				len += 1
			end

			writevlq(cursor, len)

			for key, entry in value do
				key_write(cursor, key)
				value_write(cursor, entry)
			end
		end,
		read = function(cursor)
			local len = readvlq(cursor)
			local map = {}

			for i = 1, len do
				map[key_read(cursor)] = value_read(cursor)
			end

			return map
		end,
	}

	map_codec_cache[key_codec] = {[value_codec] = codec}

	return codec
end

local id_to_rotation = {
	CFrame.Angles(0, 0, 0),
	CFrame.Angles(math.rad(90), 0, 0),
	CFrame.Angles(0, math.rad(180), math.rad(180)),
	CFrame.Angles(math.rad(-90), 0, 0),
	CFrame.Angles(0, math.rad(180), math.rad(90)),
	CFrame.Angles(0, math.rad(90), math.rad(90)),
	CFrame.Angles(0, 0, math.rad(90)),
	CFrame.Angles(0, math.rad(-90), math.rad(90)),
	CFrame.Angles(math.rad(-90), math.rad(-90), 0),
	CFrame.Angles(0, math.rad(-90), 0),
	CFrame.Angles(math.rad(90), math.rad(-90), 0),
	CFrame.Angles(0, math.rad(90), math.rad(180)),
	CFrame.Angles(0, math.rad(-90), math.rad(180)),
	CFrame.Angles(0, math.rad(180), 0),
	CFrame.Angles(math.rad(-90), math.rad(-180), 0),
	CFrame.Angles(0, 0, math.rad(180)),
	CFrame.Angles(math.rad(90), math.rad(180), 0),
	CFrame.Angles(0, 0, math.rad(-90)),
	CFrame.Angles(0, math.rad(-90), math.rad(-90)),
	CFrame.Angles(0, math.rad(-180), math.rad(-90)),
	CFrame.Angles(0, math.rad(90), math.rad(-90)),
	CFrame.Angles(math.rad(90), math.rad(90), 0),
	CFrame.Angles(0, math.rad(90), 0),
	CFrame.Angles(math.rad(-90), math.rad(90), 0),
}

local rotation_to_id: {[number]: {[number]: {[number]: number}}} = {}
do
	for id, cframe in id_to_rotation do
		local x, y, z = cframe:ToOrientation()

		rotation_to_id[x] = rotation_to_id[x] or {}
		rotation_to_id[x][y] = rotation_to_id[x][y] or {}
		rotation_to_id[x][y][z] = id
	end
end

local cframe_codec_cache = {}
local function cframe_codec(position_codec: Codec<number>, position_scale: number?): Codec<CFrame>
	if cframe_codec_cache[position_codec] then
		warn("cached cframe codecs may not have the same position_scale if a different position_scale was defined")
		return cframe_codec_cache[position_codec]
	end

	local position_write, position_read = position_codec.write, position_codec.read

	local scale = position_scale or 1

	local codec: Codec<CFrame> = {
		write = function(cursor, value: CFrame)
			local rot_x, rot_y, rot_z = value:ToOrientation()
			local id = rotation_to_id[rot_x] and rotation_to_id[rot_x][rot_y] and rotation_to_id[rot_x][rot_y][rot_z]

			if id then
				buffer.writeu8(RESERVED_BUFFER, cursor.pos, id)
				cursor.pos += 1
			else
				local pos = cursor.pos

				buffer.writeu8(RESERVED_BUFFER, pos, 0)
				pos += 1

				buffer.writeu16(RESERVED_BUFFER, pos, math.map(rot_x, -PI, PI, 0, 2^16 - 1))
				pos += 2

				buffer.writeu16(RESERVED_BUFFER, pos, math.map(rot_y, -PI, PI, 0, 2^16 - 1))
				pos += 2

				buffer.writeu16(RESERVED_BUFFER, pos, math.map(rot_z, -PI, PI, 0, 2^16 - 1))
				cursor.pos = pos + 2
			end

			position_write(cursor, value.X * scale)
			position_write(cursor, value.Y * scale)
			position_write(cursor, value.Z * scale)
		end,
		read = function(cursor)
			local id = buffer.readu8(cursor.buff, cursor.pos)
			cursor.pos += 1

			local angles = id_to_rotation[id]
			if angles then
				return CFrame.new(
					position_read(cursor) / scale,
					position_read(cursor) / scale,
					position_read(cursor) / scale
				) * angles
			else
				local buff, pos = cursor.buff, cursor.pos

				local q_x = math.map(buffer.readu16(buff, pos), 0, 2^16 - 1, -PI, PI)
				pos += 2

				local q_y = math.map(buffer.readu16(buff, pos), 0, 2^16 - 1, -PI, PI)
				pos += 2

				local q_z = math.map(buffer.readu16(buff, pos), 0, 2^16 - 1, -PI, PI)
				cursor.pos = pos + 2

				local w = math.sqrt(1 - math.clamp(q_x * q_x + q_y * q_y + q_z * q_z, 0, 1))

				return CFrame.new(
					position_read(cursor) / scale,
					position_read(cursor) / scale,
					position_read(cursor) / scale,
					q_x, q_y, q_z, w
				)
			end
		end,
	}

	cframe_codec_cache[position_codec] = codec

	return codec
end

local variant_codec_cache = {}
local function variant_codec_hidden<T>(variants: T): Codec<T>
	if variant_codec_cache[variants] then
		return variant_codec_cache[variants]
	end

	local literals: {string} = {}
	for kind in variants :: {[string]: Codec<any>} do
		table.insert(literals, kind)
	end

	local kind_codec = literal_codec(literals)
	local kind_write, kind_read = kind_codec.write, kind_codec.read

	local codec: Codec<{ kind: string, value: any }> = {
		write = function(cursor, value)
			local kind = value.kind
			local payload = value.value

			local inner = (variants :: {[string]: Codec<any>})[kind]
			kind_write(cursor, kind)
			inner.write(cursor, payload)
		end,

		read = function(cursor)
			local kind = kind_read(cursor)
			local inner = (variants :: {[string]: Codec<any>})[kind]
			local payload = inner.read(cursor)

			return {
				kind = kind,
				value = payload,
			}
		end
	}

	variant_codec_cache[variants] = codec

	return codec
end

local function variant_codec<T>(variants: T & {[string]: Codec<any>}): Codec<VariantTransformer<T>>
	return variant_codec_hidden(variants)
end

local bitarray_codec_cache = {}
local function bitarray_codec(byte_count: number): Codec<{boolean}>
	if bitarray_codec_cache[byte_count] then
		return bitarray_codec_cache[byte_count]
	end

	local codec: Codec<{boolean}> = {
		write = function(cursor, value: {boolean})
			for i = 0, byte_count - 1 do
				local j = i * 8
				writebool(cursor, value[j + 1], value[j + 2], value[j + 3], value[j + 4], value[j + 5], value[j + 6], value[j + 7], value[j + 8])
			end
		end,
		read = function(cursor)
			local result = table.create(byte_count * 8, false) :: {boolean}
			for i = 0, byte_count - 1 do
				local j = i * 8
				result[j + 1], result[j + 2], result[j + 3], result[j + 4], result[j + 5], result[j + 6], result[j + 7], result[j + 8] = readbool(cursor)
			end
			return result
		end,
	}

	bitarray_codec_cache[byte_count] = codec

	return codec
end

local set_codec_cache = {}
local function set_codec<T>(set: {string}): Codec<EitherOr<T, {[string]: boolean?}>>
	if set_codec_cache[set] then
		return set_codec_cache[set]
	end

	local name_to_index = {}
	for i, name in set :: {string} do
		name_to_index[name] = i
	end

	local len = #set
	local bitarray = bitarray_codec(math.ceil(len / 8))
	local bitarray_write, bitarray_read = bitarray.write, bitarray.read

	local codec: Codec<T> = {
		write = function(cursor, value: {[string]: boolean?})
			local bools = table.create(len, false)

			for name, bool in value do
				if bool == true then
					bools[name_to_index[name]] = true
				end
			end

			bitarray_write(cursor, bools :: {boolean})
		end,
		read = function(cursor)
			local bools = bitarray_read(cursor)
			local result = {}

			for i, name in set :: {string} do
				if bools[i] == true then
					result[name] = true
				end
			end

			return result
		end,
	}

	set_codec_cache[set] = codec

	return codec
end

local function get_reserved_buffer(): buffer
	return RESERVED_BUFFER
end

return {
	write_cursor = write_cursor,
	read_cursor = read_cursor,
	finalize = finalize,

	writeu8 = writeu8,
	writeu16 = writeu16,
	writeu24 = writeu24,
	writeu32 = writeu32,
	writeu53 = writeu53,
	readu8 = readu8,
	readu16 = readu16,
	readu24 = readu24,
	readu32 = readu32,
	readu53 = readu53,

	writei8 = writei8,
	writei16 = writei16,
	writei24 = writei24,
	writei32 = writei32,
	writei53 = writei53,
	readi8 = readi8,
	readi16 = readi16,
	readi24 = readi24,
	readi32 = readi32,
	readi53 = readi53,

	writef16 = writef16,
	writef32 = writef32,
	writef64 = writef64,
	readf16 = readf16,
	readf32 = readf32,
	readf64 = readf64,

	writevlq = writevlq,
	readvlq = readvlq,

	writebuffer = writebuffer,
	readbuffer = readbuffer,

	writebool = writebool,
	readbool = readbool,

	writestring = writestring,
	readstring = readstring,

	writecolor3 = writecolor3,
	readcolor3 = readcolor3,

	writeopt = writeopt,
	readopt = readopt,
	mark_opt = mark_opt,

	u8 = u8_codec,
	u16 = u16_codec,
	u24 = u24_codec,
	u32 = u32_codec,
	u53 = u53_codec,

	i8 = i8_codec,
	i16 = i16_codec,
	i24 = i24_codec,
	i32 = i32_codec,
	i53 = i53_codec,

	f16 = f16_codec,
	f32 = f32_codec,
	f64 = f64_codec,

	vlq = vlq_codec,
	svlq = svlq_codec,

	buffer = buffer_codec,

	bool = bool_codec,
	bool_simple = bool_simple_codec,

	string = string_codec,

	color3 = color3_codec,

	literal = literal_codec,
	vector3 = vector3_codec,
	opt = opt_codec,
	struct = struct_codec,
	array = array_codec,
	map = map_codec,
	cframe = cframe_codec,
	variant = variant_codec,
	bitarray = bitarray_codec,
	set = set_codec,

	get_reserved_buffer = get_reserved_buffer
}