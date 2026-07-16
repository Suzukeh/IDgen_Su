-- IDgen_Su ID generation module
-- returns {"id_type_name", generate(rand, ctx)}
--   rand:  { byte(offset), float(offset) }
--   ctx:   { time, frame, framerate, seed, eid, state }

local UUID_NAMES = {
    "UUIDv4", "NanoID", "ULID", "CUID", "UUIDv7", "ShortID", "KSUID", "Snowflake"
}

local function gen_uuid(rand, ctx)
    local b = {}
    for i = 1, 16 do b[i] = rand.byte(i) end
    b[7] = AND(b[7], 0x0F) + 0x40
    b[9] = AND(b[9], 0x3F) + 0x80
    return string.format(
        "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
        b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8],
        b[9], b[10], b[11], b[12], b[13], b[14], b[15], b[16]
    )
end

local function gen_nanoid(rand, ctx)
    local a = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"
    local r = {}
    for i = 1, 21 do
        local n = math.floor(rand.float(100 + i) * 64) + 1
        r[i] = a:sub(n, n)
    end
    return table.concat(r)
end

local function gen_ulid(rand, ctx)
    local a = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
    local ts = math.floor(ctx.time * 1000) + math.floor(ctx.frame * 1000 / ctx.framerate)
    ts = ts % 281474976710656

    local ts_chars = {}
    for i = 1, 10 do
        ts_chars[11 - i] = a:sub((ts % 32) + 1, (ts % 32) + 1)
        ts = math.floor(ts / 32)
    end

    local rand_chars = {}
    for i = 1, 16 do
        local n = math.floor(rand.float(200 + i) * 32) + 1
        rand_chars[i] = a:sub(n, n)
    end
    return table.concat(ts_chars) .. table.concat(rand_chars)
end

local function gen_cuid(rand, ctx)
    local a = "0123456789abcdefghijklmnopqrstuvwxyz"

    local function enc(num, len)
        local r = {}
        for i = 1, len do
            r[len - i + 1] = a:sub((num % 36) + 1, (num % 36) + 1)
            num = math.floor(num / 36)
        end
        return table.concat(r)
    end

    local ts = math.floor(ctx.time * 1000) + math.floor(ctx.frame * 1000 / ctx.framerate)
    local ts_str = enc(ts, 8)

    ctx.state.cuid_counter = (ctx.state.cuid_counter or 0) + 1
    local counter_str = enc(ctx.state.cuid_counter, 4)

    local fp = ctx.seed
    local fp_str = enc(fp, 4)

    local rand_str = {}
    for i = 1, 8 do
        local n = math.floor(rand.float(300 + i) * 36) + 1
        rand_str[i] = a:sub(n, n)
    end
    return "c" .. ts_str .. counter_str .. fp_str .. table.concat(rand_str)
end

local function gen_uuid7(rand, ctx)
    local ts = math.floor(ctx.time * 1000) + math.floor(ctx.frame * 1000 / ctx.framerate)
    ts = ts % 281474976710656
    local b = {}
    for i = 1, 6 do
        b[7 - i] = ts % 256
        ts = math.floor(ts / 256)
    end
    for i = 7, 16 do
        b[i] = rand.byte(1000 + i)
    end
    b[7] = AND(b[7], 0x0F) + 0x70
    b[9] = AND(b[9], 0x3F) + 0x80
    return string.format(
        "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
        b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8],
        b[9], b[10], b[11], b[12], b[13], b[14], b[15], b[16]
    )
end

local function gen_shortid(rand, ctx)
    local a = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"
    local r = {}
    for i = 1, 11 do
        local n = math.floor(rand.float(500 + i) * 64) + 1
        r[i] = a:sub(n, n)
    end
    return table.concat(r)
end

local function gen_ksuid(rand, ctx)
    local EPOCH = 1400000000
    local a = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

    local bytes = {}
    local ts = math.floor(ctx.time) + math.floor(ctx.frame / ctx.framerate)
    ts = ts - EPOCH
    if ts < 0 then ts = 0 end
    ts = ts % 4294967296
    for i = 1, 4 do
        bytes[5 - i] = ts % 256
        ts = math.floor(ts / 256)
    end
    for i = 1, 16 do
        bytes[4 + i] = rand.byte(6000 + i)
    end

    local parts = {}
    for w = 1, 5 do
        local o = (w - 1) * 4
        parts[w] = bytes[o+1] * 16777216 + bytes[o+2] * 65536 + bytes[o+3] * 256 + bytes[o+4]
    end

    local result = {}
    local bp = 5
    while bp > 0 do
        local q = {}
        local qlen = 0
        local rem = 0
        for i = 1, bp do
            local v = parts[i] + rem * 4294967296
            local d = math.floor(v / 62)
            rem = v % 62
            if qlen > 0 or d ~= 0 then
                qlen = qlen + 1
                q[qlen] = d
            end
        end
        table.insert(result, 1, a:sub(rem + 1, rem + 1))
        parts = q
        bp = qlen
    end

    local s = table.concat(result)
    while #s < 27 do
        s = "0" .. s
    end
    return s
end

local function gen_snowflake(rand, ctx)
    local EPOCH = 1577836800000
    local ts = math.floor(ctx.time * 1000) + math.floor(ctx.frame * 1000 / ctx.framerate)
    ts = ts - EPOCH
    if ts < 0 then ts = 0 end
    ts = ts % 4398046511104
    local r = math.floor(rand.float(800) * 1024)
    return tostring(ts * 1024 + r)
end

local generators = { gen_uuid, gen_nanoid, gen_ulid, gen_cuid, gen_uuid7, gen_shortid, gen_ksuid, gen_snowflake }

return {
    names = UUID_NAMES,
    generate = function(rand, ctx)
        local fn = generators[ctx.id_type + 1] or generators[1]
        return fn(rand, ctx)
    end,
}
