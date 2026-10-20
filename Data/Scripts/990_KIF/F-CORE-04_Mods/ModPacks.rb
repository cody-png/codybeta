#===============================================================================
# Modpacks and share codes - the Modpacks and Share Code tabs in
# Options > KIF Settings > Mods (2026-10-20)
#
# Modpacks: a catalog's modpacks/<folder>/modpack.json, the layout Mod Manager
# 2.0 reads: {name, id, version, author, description, tags,
# mods: [{id, version}]}. A mod's version there is the lowest one the pack
# wants. Installing a pack installs the mods from it the player doesn't have
# (and what they need) and updates the ones older than the pack wants.
#
# Share codes: Mod Manager 2.0's format, so codes work in both.
#   "KIF-" + base62(zlib deflate level 9 of "id@version,id@version,...")
#   ids sorted; "KIFr-" + base62(the text itself) when zlib isn't there.
#   base62 digits 0-9A-Za-z; each leading zero byte is a leading "0".
# A code holds the mods that are On. Spaces and line breaks in a pasted code
# are ignored (the screen shows it in groups so it fits).
#===============================================================================
module KIF
  module ModPacks
    class Pack
      attr_reader :folder, :json, :catalog
      def initialize(folder, json, catalog = nil)
        @folder = folder
        @json = json || {}
        @catalog = catalog
      end
      def id;      return (@json["id"] || @folder).to_s; end
      def name;    return KIF::PixelFont.utf8((@json["name"] || @folder).to_s); end
      def version; return @json["version"].to_s; end
      def author;  return KIF::PixelFont.utf8(@json["author"].to_s); end
      def description
        d = @json["description"]
        d = d.join(" ") if d.is_a?(Array)
        return KIF::PixelFont.utf8(d.to_s)
      end
      # [[id, lowest version or ""], ...]
      def mods
        return Array(@json["mods"]).map { |m| m.is_a?(Hash) ? [m["id"].to_s, m["version"].to_s] : [m.to_s, ""] }
                                   .reject { |id, _| id.empty? }
      end
    end

    B62 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    MAX_CODE = 20_000   # characters; a longer paste isn't a share code

    module_function

    def b62_encode(bytes)
      return "" if bytes.empty?
      num = bytes.inject(0) { |n, b| n * 256 + (b & 0xFF) }
      out = ""
      while num > 0
        out = B62[num % 62, 1] + out
        num /= 62
      end
      zeros = bytes.take_while { |b| b == 0 }.length
      return ("0" * zeros) + out
    end

    def b62_decode(str)
      zeros = str[/\A0*/].length
      num = 0
      str.each_char do |c|
        i = B62.index(c)
        return nil unless i
        num = num * 62 + i
      end
      bytes = []
      while num > 0
        bytes.unshift(num & 0xFF)
        num >>= 8
      end
      return ([0] * zeros) + bytes
    end

    # [[id, version], ...] => "KIF-..."
    def encode(list)
      return nil if list.nil? || list.empty?
      text = list.sort_by { |id, _| id.to_s }.map { |id, v| "#{id}@#{v}" }.join(",")
      begin
        return "KIF-" + b62_encode(Zlib::Deflate.deflate(text, 9).bytes)
      rescue StandardError, NameError
        return "KIFr-" + b62_encode(text.bytes)
      end
    end

    # "KIF-..." => [[id, version], ...], or nil when it isn't a code
    def decode(code)
      code = code.to_s.gsub(/\s+/, "")
      return nil if code.length > MAX_CODE
      if code.start_with?("KIF-")
        bytes = b62_decode(code[4..-1])
        return nil unless bytes
        text = (Zlib::Inflate.inflate(bytes.pack("C*")) rescue nil)
      elsif code.start_with?("KIFr-")
        bytes = b62_decode(code[5..-1])
        text = bytes ? bytes.pack("C*") : nil
      end
      return nil unless text
      text = text.force_encoding("UTF-8")
      list = text.split(",").map { |p| p.split("@", 2) }.reject { |id, _| id.nil? || id.empty? }
                 .map { |id, v| [id, v.to_s] }
      return list.empty? ? nil : list
    end

    # groups of 20 so a long code wraps in a message
    def spaced(code)
      return code.to_s.scan(/.{1,20}/).join(" ")
    end

    # the mods that are On: [[id, version], ...]
    def mine
      return KIF::Mods.entries.select(&:enabled?).map { |e| [e.id.to_s, e.version.to_s] }.uniq(&:first)
    rescue StandardError
      return []
    end

    # What getting wanted ([[id, lowest version]]) takes:
    #   :list    catalog mods to install or update (what they need first)
    #   :have    already installed and new enough
    #   :off     installed but switched Off (names)
    #   :missing in no catalog and not installed (ids)
    #   :wont    won't start on this KIF (names)
    def plan(wanted)
      cat = KIF::ModCatalog
      up = KIF::Updater
      out = { list: [], have: [], off: [], missing: [], wont: [] }
      todo = []
      entries = (KIF::Mods.entries rescue [])
      wanted.each do |id, min|
        e = entries.find { |x| x.id.to_s == id }
        out[:off] << e.name.to_s if e && !e.enabled?
        it = cat.find(id)
        if it.nil?
          ((e || cat.installed_id?(id)) ? out[:have] : out[:missing]) << id
        elsif cat.installed?(it)
          old = !min.to_s.empty? && up.newer?(min, cat.installed_version(it))
          if old && cat.update?(it) then todo << it else out[:have] << id end
        elsif cat.kif_problem(it)
          out[:wont] << it.name
        else
          todo << it
        end
      end
      todo.each do |it|
        list, miss = cat.install_list(it)
        list.each { |x| out[:list] << x unless out[:list].include?(x) }
        miss.each { |d| out[:missing] << d unless out[:missing].include?(d) }
      end
      return out
    end
  end
end
