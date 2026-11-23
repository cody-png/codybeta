#===============================================================================
# KIF.safe_marshal_load: reads a Marshal file that holds only plain data (nil,
# true, false, numbers, strings, symbols, arrays, hashes, also with a default
# value) and refuses anything
# else. Marshal.load itself builds whatever class a file names, so a file a mod
# can write must not go through it. Files written by Marshal.dump read the same.
#===============================================================================
module KIF
  class SafeMarshal
    class Bad < StandardError; end
    MAX_DEPTH = 64

    def self.load(data); return new(data.to_s.b).read_all; end

    def initialize(data)
      @s = data
      @i = 0
      @syms = []
      @objs = []
    end

    def read_all
      raise Bad, "not Marshal 4.8 data" unless @s.getbyte(0) == 4 && @s.getbyte(1) == 8
      @i = 2
      v = value(0)
      raise Bad, "text after the data" if @i != @s.bytesize
      return v
    end

    def byte
      b = @s.getbyte(@i)
      raise Bad, "data ends early" unless b
      @i += 1
      return b
    end

    def long
      c = byte
      c -= 256 if c > 127
      return 0 if c == 0
      if c > 0
        return c - 5 if c > 4
        x = 0
        c.times { |k| x |= byte << (8 * k) }
        return x
      end
      return c + 5 if c < -4
      x = -1
      (-c).times { |k| x &= ~(0xff << (8 * k)); x |= byte << (8 * k) }
      return x
    end

    def bytes
      n = long
      raise Bad, "bad length" if n < 0 || @i + n > @s.bytesize
      r = @s.byteslice(@i, n)
      @i += n
      return r
    end

    def symbol
      case byte
      when 58 then s = bytes.force_encoding(Encoding::UTF_8).to_sym; @syms << s; return s
      when 59 then s = @syms[long]; raise Bad, "bad symbol link" unless s; return s
      end
      raise Bad, "symbol expected"
    end

    def value(depth)
      raise Bad, "nested too deep" if depth > MAX_DEPTH
      t = byte
      case t
      when 48 then return nil
      when 84 then return true
      when 70 then return false
      when 105 then return long
      when 58 then @i -= 1; return symbol
      when 59 then @i -= 1; return symbol
      when 64 then o = @objs[long]; raise Bad, "bad link" unless @objs.length > 0 && o; return o[0]
      when 34 then return keep(bytes)
      when 102
        s = bytes
        return keep(s == "inf" ? Float::INFINITY : s == "-inf" ? -Float::INFINITY : s == "nan" ? Float::NAN : Float(s))
      when 108
        sign = byte
        n = long
        raise Bad, "bad length" if n < 0 || @i + 2 * n > @s.bytesize
        x = 0
        (2 * n).times { |k| x |= byte << (8 * k) }
        return keep(sign == 45 ? -x : x)
      when 91
        n = long
        raise Bad, "bad length" if n < 0 || n > @s.bytesize - @i
        a = keep([])
        n.times { a << value(depth + 1) }
        return a
      when 123 then return value_hash(depth)
      when 125   # a hash with a default value (Hash.new(0))
        h = value_hash(depth)
        h.default = value(depth + 1)
        return h
      when 73   # a string or symbol with its encoding
        if @s.getbyte(@i) == 58   # a non-ASCII symbol: its slot in the symbol table comes first
          @i += 1
          raw = bytes
          slot = @syms.length
          @syms << nil
          utf8 = false
          long.times { k = symbol; v = value(depth + 1); utf8 = true if k == :E && v == true }
          return @syms[slot] = (utf8 ? raw.force_encoding(Encoding::UTF_8) : raw).to_sym
        end
        raise Bad, "only strings and symbols carry that" unless @s.getbyte(@i) == 34
        @i += 1
        str = keep(bytes)
        long.times do
          k = symbol
          v = value(depth + 1)
          str.force_encoding(Encoding::UTF_8) if k == :E && v == true
        end
        return str
      end
      raise Bad, "type #{t.chr.inspect} is not plain data"
    end

    def value_hash(depth)
      n = long
      raise Bad, "bad length" if n < 0 || 2 * n > @s.bytesize - @i
      h = keep({})
      n.times { k = value(depth + 1); h[k] = value(depth + 1) }
      return h
    end

    # every object but nil, true, false, integers and symbols can be named again by a link
    def keep(v); @objs << [v]; return v; end
  end

  def self.safe_marshal_load(data); return SafeMarshal.load(data); end
end
