#===============================================================================
# Mod pictures, sounds and fonts, looked up in place (Cody, 2026-10-20).
#
# A mod's Graphics/, Audio/ and Fonts/ folders stay inside the mod
# (Mods/<mod>/Graphics/...). When the game asks for "Graphics/Pictures/x",
# KIF looks in every mod that loaded first, then in the game's own folders.
# Nothing is copied into the game, so a hand-dropped mod works the same as a
# downloaded one, and uninstalling a mod is deleting its folder.
# Two mods with the same file: the one that loads later wins (the same rule
# as for code: a later mod's alias wraps an earlier one's).
#
# Hooked: RTP.eachPathFor (pbResolveBitmap, RTP.exists? / getPath and
# everything built on them), Bitmap.new (RPG::Cache and direct loads) and
# Audio.bgm/bgs/me/se_play.
# shortcut: fonts aren't looked up (mkxp-z reads Fonts/ once at start-up and
# has no call to add one later); no catalog mod ships fonts (2026-10-20).
#===============================================================================
module KIF
  module ModAssets
    DIRS = %w[Graphics Audio Fonts]
    EXT  = /\.(png|gif|dat|jpe?g|bmp|ogg|mp3|wav|wma|mid|midi|ttf|otf)\z/i
    @files = {}    # "graphics/pictures/x" => "Mods/Mod/Graphics/Pictures/x.png"
    @memo = {}

    def self.any?; return !@files.empty?; end
    def self.files; return @files; end

    # "Graphics\\Pictures/X.png", "./Graphics/..." => "graphics/pictures/x"
    def self.key_for(path)
      k = path.to_s.tr("\\", "/").sub(%r{\A\./}, "")
      return nil unless k =~ %r{\A(graphics|audio|fonts)/}i
      return k.sub(EXT, "").downcase
    end

    # the mod's file for a game path, or nil
    def self.file_for(path)
      return nil if @files.empty? || !path.is_a?(String)
      return @memo[path] if @memo.has_key?(path)
      k = key_for(path)
      return @memo[path] = (k && @files[k])
    end

    # dirs: the mod folders that loaded, in load order (a later one wins)
    def self.build(dirs)
      files = {}
      dirs.each do |dir|
        DIRS.each do |sub|
          base = File.join(dir, sub)
          next unless File.directory?(base)
          Dir.glob(File.join(base, "**", "*")).each do |f|
            next unless File.file?(f)
            rel = f[(dir.length + 1)..-1]
            k = key_for(rel)
            files[k] = f.sub(%r{\A\./}, "") if k
          end
        end
      end
      @files = files
      @memo = {}
      KIF.log("Mod files: #{files.length} pictures and sounds from #{dirs.length} mods") if !files.empty? && defined?(KIF.log)
      return files.length
    end
  end
end

module RTP
  class << self
    alias kif_ma_eachPathFor eachPathFor unless method_defined?(:kif_ma_eachPathFor)
    def eachPathFor(filename, &block)
      f = KIF::ModAssets.file_for(filename)
      yield f.sub(KIF::ModAssets::EXT, "") if f && block   # callers add the extension
      return kif_ma_eachPathFor(filename, &block)
    end
  end
end

class Bitmap
  class << self
    alias kif_ma_new new unless method_defined?(:kif_ma_new)
    def new(*args, &block)
      if args.length == 1 && (f = KIF::ModAssets.file_for(args[0]))
        args = [f]
      end
      return kif_ma_new(*args, &block)
    end
  end
end

module Audio
  class << self
    [:bgm_play, :bgs_play, :me_play, :se_play].each do |m|
      next unless method_defined?(m) || private_method_defined?(m)
      orig = :"kif_ma_#{m}"
      alias_method orig, m unless method_defined?(orig) || private_method_defined?(orig)
      define_method(m) do |name, *rest|
        f = KIF::ModAssets.file_for(name)
        return send(orig, f || name, *rest)
      end
    end
  end
end
