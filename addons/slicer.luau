--!strict
--!native

local HEADER_SIZE = 4
local CALL_ID = 0
local GENERATION = 0

local map = {}
local generations = {}

local function get_slices(buf: buffer, size: number): {buffer}
	if size <= HEADER_SIZE then
		error("slices must at least be larger than", HEADER_SIZE)
	end

	size -= HEADER_SIZE

	local len = buffer.len(buf)
	local steps = math.ceil(len / size)
	local slices = table.create(steps) :: {buffer}

	local pos = 0
	while pos < len do
		local chunk = math.min(size, len - pos)
		local slice = buffer.create(chunk + HEADER_SIZE)

		local index = #slices + 1
		buffer.writeu8(slice, 0, CALL_ID)
		buffer.writeu8(slice, 1, GENERATION)
		buffer.writeu8(slice, 2, index)
		buffer.writeu8(slice, 3, steps)
		buffer.copy(slice, HEADER_SIZE, buf, pos, chunk)

		slices[index] = slice
		pos += chunk
	end

	CALL_ID = (CALL_ID + 1) % 2^8
	GENERATION = (GENERATION + 1) % 2^8

	return slices
end

local function process(buf: buffer): buffer?
	local id = buffer.readu8(buf, 0)
	local generation = buffer.readu8(buf, 1)
	local index = buffer.readu8(buf, 2)
	local count = buffer.readu8(buf, 3)
	
	if map[id] and generations[id] ~= generation then
		map[id] = nil
		generations[id] = nil
	end
	
	local slices = map[id]
	if not slices then
		slices = {[index] = buf}
		map[id] = slices
		generations[id] = generation
	else
		slices[index] = buf
	end

	if #slices == count then
		local total = 0
		for _, slice in slices do
			total += buffer.len(slice) - HEADER_SIZE
		end

		local out = buffer.create(total)
		local pos = 0

		for i = 1, count do
			local slice = slices[i]
			local payload = buffer.len(slice) - HEADER_SIZE
			buffer.copy(out, pos, slice, HEADER_SIZE, payload)
			pos += payload
		end
		
		map[id] = nil
		generations[id] = nil

		return out
	end

	return nil
end

return {
	get_slices = get_slices,
	process = process
}
