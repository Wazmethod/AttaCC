-- Pure Lua SHA-256 for CraftOS (bit32); no undocumented ROM hashing API.
local bit=bit32
local MOD=4294967296
local constants={0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2}
local initial={0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19}
local function word(raw,i)
    local a,b,c,d=raw:byte(i,i+3)
    return a*16777216+b*65536+c*256+d
end
local function digest(data)
    assert(type(data)=="string","sha256 input must be a string")
    local bits=#data*8
    data=data.."\128"
    local pad=(56-(#data%64))%64
    data=data..string.rep("\0",pad)
    local hi=math.floor(bits/MOD)
    local lo=bits%MOD
    local function bytes(x)
        return string.char(bit.band(bit.rshift(x,24),255),bit.band(bit.rshift(x,16),255),
            bit.band(bit.rshift(x,8),255),bit.band(x,255))
    end
    data=data..bytes(hi)..bytes(lo)
    local h={table.unpack(initial)}
    for offset=1,#data,64 do
        local w={}
        for t=1,16 do w[t]=word(data,offset+(t-1)*4) end
        for t=17,64 do
            local x,y=w[t-15],w[t-2]
            local s0=bit.bxor(bit.rrotate(x,7),bit.rrotate(x,18),bit.rshift(x,3))
            local s1=bit.bxor(bit.rrotate(y,17),bit.rrotate(y,19),bit.rshift(y,10))
            w[t]=(w[t-16]+s0+w[t-7]+s1)%MOD
        end
        local a,b,c,d,e,f,g,z=table.unpack(h)
        for t=1,64 do
            local s1=bit.bxor(bit.rrotate(e,6),bit.rrotate(e,11),bit.rrotate(e,25))
            local ch=bit.bxor(bit.band(e,f),bit.band(bit.bnot(e),g))
            local tmp1=(z+s1+ch+constants[t]+w[t])%MOD
            local s0=bit.bxor(bit.rrotate(a,2),bit.rrotate(a,13),bit.rrotate(a,22))
            local maj=bit.bxor(bit.band(a,b),bit.band(a,c),bit.band(b,c))
            local tmp2=(s0+maj)%MOD
            z,g,f,e,d,c,b,a=g,f,e,(d+tmp1)%MOD,c,b,a,(tmp1+tmp2)%MOD
        end
        for t,v in ipairs({a,b,c,d,e,f,g,z}) do h[t]=(h[t]+v)%MOD end
    end
    local parts={}
    for i,v in ipairs(h) do parts[i]=string.format("%08x",v) end
    return table.concat(parts)
end
return {digest=digest}
