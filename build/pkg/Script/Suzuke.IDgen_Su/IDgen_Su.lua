--[[
IDgen_Su — AviUtl2用ユニークID生成モジュール

    使い方はファイル末尾のコメントを参照。
]]

local AND = AND  -- AviUtl2グローバル: ビットAND

local ALPHABETS = {
    URL64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-",
    CROCKFORD32 = "0123456789ABCDEFGHJKMNPQRSTVWXYZ",
    BASE36 = "0123456789abcdefghijklmnopqrstuvwxyz",
    BASE62 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz",
}

-- helpers

local function encode_base(num, alphabet, len)
    local base = #alphabet
    local r = {}
    for i = 1, len do
        r[len - i + 1] = alphabet:sub((num % base) + 1, (num % base) + 1)
        num = math.floor(num / base)
    end
    return table.concat(r)
end

local function random_chars(rand, alphabet, offset, count)
    local base = #alphabet
    local r = {}
    for i = 1, count do
        local n = math.floor(rand.float(offset + i) * base) + 1
        r[i] = alphabet:sub(n, n)
    end
    return table.concat(r)
end

local function pack_uint32_be(bytes, offset)
    return bytes[offset+1] * 16777216 + bytes[offset+2] * 65536 + bytes[offset+3] * 256 + bytes[offset+4]
end

local function format_uuid(b, version)
    b[7] = AND(b[7], 0x0F) + version * 0x10
    b[9] = AND(b[9], 0x3F) + 0x80
    return string.format(
        "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
        b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8],
        b[9], b[10], b[11], b[12], b[13], b[14], b[15], b[16]
    )
end

-- timestamp helper: ctx → 経過ミリ秒
local function ms(ctx)
    return math.floor(ctx.time * 1000) + math.floor(ctx.frame * 1000 / ctx.framerate)
end
local function sec(ctx)
    return math.floor(ctx.time) + math.floor(ctx.frame / ctx.framerate)
end

-- generators

local function gen_uuid(rand)
    local b = {}
    for i = 1, 16 do b[i] = rand.byte(i) end
    return format_uuid(b, 4)
end

local function gen_nanoid(rand)
    return random_chars(rand, ALPHABETS.URL64, 100, 21)
end

local function gen_ulid(rand, ctx)
    local a = ALPHABETS.CROCKFORD32
    return encode_base(ms(ctx) % 281474976710656, a, 10) .. random_chars(rand, a, 200, 16)
end

local function gen_cuid(rand, ctx)
    local a = ALPHABETS.BASE36
    local ts_str = encode_base(ms(ctx), a, 8)
    ctx.state.cuid_counter = (ctx.state.cuid_counter or 0) + 1
    local ctr_str = encode_base(ctx.state.cuid_counter, a, 4)
    local fp_str = encode_base(ctx.seed, a, 4)
    local rand_str = random_chars(rand, a, 300, 8)
    return "c" .. ts_str .. ctr_str .. fp_str .. rand_str
end

local function gen_uuid7(rand, ctx)
    local ts = ms(ctx) % 281474976710656
    local b = {}
    for i = 1, 6 do
        b[7 - i] = ts % 256
        ts = math.floor(ts / 256)
    end
    for i = 7, 16 do b[i] = rand.byte(1000 + i) end
    return format_uuid(b, 7)
end

local function gen_shortid(rand)
    return random_chars(rand, ALPHABETS.URL64, 500, 11)
end

local function gen_ksuid(rand, ctx)
    local EPOCH = 1400000000
    local a = ALPHABETS.BASE62

    local ts = sec(ctx) - EPOCH
    if ts < 0 then ts = 0 end
    ts = ts % 4294967296

    local bytes = {}
    for i = 1, 4 do bytes[5 - i] = ts % 256; ts = math.floor(ts / 256) end
    for i = 1, 16 do bytes[4 + i] = rand.byte(6000 + i) end

    local parts = {}
    for w = 0, 4 do parts[w + 1] = pack_uint32_be(bytes, w * 4) end

    local result = {}
    while #parts > 0 do
        local q, r = {}, 0
        for _, p in ipairs(parts) do
            local v = p + r * 4294967296
            local d = math.floor(v / 62)
            r = v % 62
            if d ~= 0 or #q > 0 then table.insert(q, d) end
        end
        table.insert(result, 1, a:sub(r + 1, r + 1))
        parts = q
    end

    local s = table.concat(result)
    while #s < 27 do s = "0" .. s end
    return s
end

local function gen_snowflake(rand, ctx)
    local EPOCH = 1577836800000
    local ts = ms(ctx) - EPOCH
    if ts < 0 then ts = 0 end
    ts = ts % 4398046511104
    return tostring(ts * 1024 + math.floor(rand.float(800) * 1024))
end

-- exports

local GENERATORS = {
    gen_uuid, gen_nanoid, gen_ulid, gen_cuid,
    gen_uuid7, gen_shortid, gen_ksuid, gen_snowflake,
}

return {
    names = { "UUIDv4", "NanoID", "ULID", "CUID", "UUIDv7", "ShortID", "KSUID", "Snowflake" },
    generate = function(rand, ctx)
        local fn = GENERATORS[ctx.id_type + 1] or GENERATORS[1]
        return fn(rand, ctx)
    end,
}

--[[
--------------------------------------------------------------------------------
使用例

  -- rand テーブル（呼び出し側で実装）
  local rand = {}
  function rand.float(offset)
      return obj.rand1(offset)  -- 0.0〜1.0
  end
  function rand.byte(offset)
      return math.floor(rand.float(offset) * 256)
  end

  -- ctx テーブル
  local ctx = {
      id_type   = 0,             -- 0=UUIDv4 … 7=Snowflake
      time      = obj.time,
      frame     = obj.frame,
      framerate = obj.framerate,
      seed      = 0,
      eid       = obj.effect_id or 0,
      state     = {},            -- 永続化するテーブル（CUIDのカウンター保持）
  }

  local ID = require("Suzuke.IDgen_Su.IDgen_Su")

  -- ID種別一覧: ID.names[n]  例: ID.names[0] == "UUIDv4"
  -- ID生成: ID.generate(rand, ctx) → 文字列

## 依存

  - AviUtl2 の AND() グローバル関数
  - Lua 標準ライブラリ: string, math, table

## 注意

  - タイムスタンプは ctx.time/frame/framerate から算出（Unix時間ではない）
  - Snowflake は Lua の53bit整数精度制限により52bitに短縮
  - CUID を使う場合は ctx.state をフレーム間で永続化すること（グローバル変数推奨）
]]
