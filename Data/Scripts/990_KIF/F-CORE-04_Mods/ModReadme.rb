#===============================================================================
# Mod descriptions (KIF 1.2.7, 2026-10-26): "Read description" in Options >
# Mods (USE on an installed mod, or on a mod in Browse). Shows the mod's
# README (README.md, readme.md or README.txt in its folder) in the Update
# history's reader. A catalog mod that isn't installed has it read from its
# catalog, the same way and through the same blob-sha cache as its
# mod.json. No README: the mod.json description, so every mod has something.
# Markdown is shown as plain text; the file is only ever read as text.
#===============================================================================
module KIF
  module ModReadme
    MAX     = 64 * 1024    # bytes shown; the rest is cut
    MAX_GET = 256 * 1024   # a bigger README in a catalog isn't downloaded
    LINE    = 2048         # a longer line gets only the cheap cleanup (its Markdown regexes could take seconds)
    # the game's fonts (Fonts/*.ttf) have ASCII, Latin-1 and the gender
    # signs; these become ASCII, anything else they lack (emoji, CJK,
    # zero-width spaces, the soft hyphen) is dropped, not drawn as a box
    FOLD = { "–" => "-", "—" => "-", "‐" => "-", "‑" => "-", "−" => "-", "‘" => "'", "’" => "'", "‚" => "'",
             "“" => '"', "”" => '"', "„" => '"', "…" => "...", "×" => "x", " " => " ", "→" => "->", "←" => "<-",
             "•" => "-", "\t" => "  ", "✓" => "OK", "✔" => "OK", "✅" => "OK", "☑" => "OK", "✗" => "x", "✘" => "x",
             "❌" => "x", "⚠" => "!", "€" => "EUR", "©" => "(c)", "®" => "(R)", "™" => "(TM)", "★" => "*" }
    FOLD_RE = Regexp.union(FOLD.keys)
    UNDRAWN = / ?[^\n\x20-\x7E¡-¬®-ÿ♀♂]+/   # with a space before it: no double space is left
    ENTITIES = { "amp" => "&", "lt" => "<", "gt" => ">", "quot" => '"', "apos" => "'", "nbsp" => " ", "copy" => "©",
                 "reg" => "®", "trade" => "™", "mdash" => "—", "ndash" => "–", "hellip" => "…", "laquo" => "«",
                 "raquo" => "»" }

    module_function

    # the README among a folder's file names: a .md first, then any case
    def pick(names)
      return names.select { |n| n =~ /\Areadme\.(md|txt)\z/i }.min_by { |n| [n =~ /\.md\z/i ? 0 : 1, n] }
    end

    # [name, first MAX + 1 bytes] of the README in dir, or nil
    def local_text(dir)
      return nil unless dir && File.directory?(dir)
      n = pick(Dir.children(dir).select { |c| File.file?(File.join(dir, c)) })
      return n ? [n, File.open(File.join(dir, n), "rb") { |f| f.read(MAX + 1) }.to_s] : nil
    rescue SystemCallError, IOError
      return nil
    end

    # [name, text] of a catalog mod's README, nil when it has none, :offline
    # when the catalog didn't answer, :failed when it answered without it (a
    # 404: the README moved since Browse read the catalog's file list)
    def catalog_text(item)
      cat = KIF::ModCatalog
      n = pick(item.files.keys.reject { |k| k.include?("/") })
      return nil unless n
      info = item.files[n]
      if info[1].to_i > MAX_GET
        cat.log("#{item.folder}/#{n}: #{info[1]} bytes, too big to read in game")
        return nil
      end
      cat.status(_INTL("Reading the description"), item.name)
      cat.begin_stats(1)
      begin
        text = cat.cached_text(item.catalog || cat.catalogs[0], info, KIF::Updater.url_for(item.base, "#{item.folder}/#{n}"))
      ensure
        cat.end_stats("description of #{item.folder}")
        KIF::Updater.hide_status
      end
      return [n, text] if text
      return KIF::Updater.instance_variable_get(:@last_status).to_i > 0 ? :failed : :offline
    end

    # what the reader shows
    def lines_for(found, desc)
      desc = fold(desc.to_s).gsub(/\s+/, " ").strip
      desc = _INTL("This mod has no description.") if desc.empty?
      return [_INTL("Couldn't reach the mod catalog to read the full description. Check the internet connection and try again."), "", desc] if found == :offline
      return [_INTL("This mod's description couldn't be loaded."), "", desc] if found == :failed
      return [desc] if !found || binary?(found[1])
      lines = plain(found[1], found[0] !~ /\.txt\z/i)
      return lines.empty? ? [desc] : lines
    end

    def show(title, found, desc)
      KIF::Updater.show_text(fold(title), lines_for(found, desc), false)
    end

    # a README that is really a picture or an archive: NUL bytes, or more
    # than a tenth of it control bytes or broken UTF-8
    def binary?(text)
      t = text.to_s.b
      return true if t.include?("\0")
      bad = t.count("\x01-\x08\x0B\x0E-\x1F\x7F") + t.bytesize - t.dup.force_encoding("UTF-8").scrub("").bytesize
      return bad * 10 > t.bytesize
    end

    # an installed mod (KIF::Mods::Entry); a loose .rb has no folder
    def show_installed(e)
      show(e.name, e.kind == :file ? nil : local_text(e.path), e.description)
    end

    # a catalog mod: the installed copy's README, else the catalog's
    def show_catalog(item)
      cat = KIF::ModCatalog
      found = cat.installed?(item) ? local_text(cat.folder_of(item)) : nil
      show(item.name, found || catalog_text(item), item.description)
    end

    #---------------------------------------------------------------------------
    # Text
    #---------------------------------------------------------------------------
    def fold(s)
      return KIF::PixelFont.utf8(s.to_s).gsub(FOLD_RE, FOLD).gsub(UNDRAWN, "")
    end

    # &copy; &#169; &#xA9; as what they stand for, folded; one pass, so
    # &amp;lt; is "&lt;"
    def entities(s)
      return s.gsub(/&(#\d{1,7}|#[xX]\h{1,6}|[A-Za-z]+);/) do
        e = $1
        c = ENTITIES[e] || (e.start_with?("#") ? ((e =~ /x/i ? e[2..-1].hex : e[1..-1].to_i).chr(Encoding::UTF_8) rescue "") : nil)
        c ? fold(c) : $&
      end
    end

    # the reader's lines: Markdown (md) as plain text, a .txt as it is;
    # more than MAX bytes is cut and says so
    def plain(text, md = true)
      t = text.to_s.b
      cut = t.bytesize > MAX
      t = t.byteslice(0, MAX) if cut
      t = fold(t.force_encoding("UTF-8").scrub("").gsub(/\r\n?/, "\n"))
      lines = md ? markdown(t) : t.split("\n").map(&:rstrip)
      lines += ["", "(cut)"] if cut
      out = []
      lines.each { |l| out << l unless l.empty? && (out.empty? || out.last.empty?) }
      out.pop while out.last == ""
      return out
    end

    def markdown(text)
      out = []
      para = nil
      fence = nil
      flush = proc { out << para if para; para = nil }
      # html: no comments, scripts or styles (unclosed: to the end, as a
      # browser does); a tag over several lines is put on one, then dropped
      text = text.gsub(/<!--.*?(?:-->|\z)/m, "").gsub(/<(script|style)\b.*?(?:<\/\1\s*>|\z)/mi, "")
      text.gsub(/<\/?[A-Za-z][^<>]*>/) { |tag| tag.tr("\n", " ") }.split("\n").each do |l|
        if fence   # code: its text, indented
          if l.strip.start_with?(fence)
            fence = nil
            out << ""
          else
            out << "  " + l.rstrip
          end
          next
        end
        s = l.strip.sub(/\A(>\s?)+/, "").strip   # a quote: its text
        item = l =~ /\A(\s*)([-*+]|\d{1,9}[.)])\s+(.*)\z/ ? [$1.length / 2, $2, $3] : nil
        if (m = s.match(/\A(```|~~~)/))
          flush.call
          out << ""
          fence = m[1]
        elsif s.empty?
          flush.call
          out << ""
        elsif s =~ /\A\#{1,6}\s+(.+?)(?:\s+#+)?\z/   # # heading
          flush.call
          out << "" << inline($1)
        elsif para && s =~ /\A(=+|-+)\z/                # heading underlined
          out << "" << para
          para = nil
        elsif s =~ /\A([-*_])( *\1){2,}\z/            # a line across
          flush.call
          out << ""
        elsif s.include?("|") && s.include?("-") && s =~ /\A[\s|:-]+\z/   # a table's |---|---|
          next
        elsif s.start_with?("|")                        # table row: a | b
          flush.call
          out << s.sub(/\A\|/, "").sub(/(?<!\\)\|\z/, "").split(/(?<!\\)\|/).map { |c| inline(c) }.join(" | ")
        elsif s =~ /\A\[[^\]]+\]:\s*\S/                 # [ref]: url
          next
        elsif item
          flush.call
          mark = item[1] =~ /\d/ ? item[1].sub(")", ".") : "-"
          out << "  " * [item[0], 3].min + "#{mark} " + inline(item[2])
        elsif !para && l =~ /\A\s+\S/ && out.last.to_s =~ /\A *(- |\d+\. )/   # a list line's next line
          out[-1] << " " << inline(s)   # << not +=: a long paragraph isn't copied for each line
        else
          t = inline(s)
          next if t.empty?   # an html line (<p align="center">)
          para = para ? para << " " << t : t
        end
      end
      flush.call
      return out
    end

    # one line's text: pictures as [picture], links as their text, no
    # emphasis, code or html marks
    def inline(s)
      # shortcut: a line over LINE keeps its Markdown marks (hostile or generated files only)
      return entities(s.gsub(/<\/?[A-Za-z][^<>]*>/, "")).strip if s.length > LINE
      keep = proc { |t| t.gsub(/[!-\/:-@\[-`{-~]/) { |c| (0xE000 + c.ord).chr(Encoding::UTF_8) } }
      s = s.gsub(/\\([!-\/:-@\[-`{-~])/) { keep.call($1) }   # \* stays a *
      s = s.gsub(/(`+)(.+?)\1/) { keep.call($2.strip) }     # code: its text, as it is
      s = s.gsub(/<img\b[^>]*>/i, "[picture]").gsub(/!\[[^\]]*\](\([^)]*\)|\[[^\]]*\])/, "[picture]")
      s = s.gsub(/\[((?:[^\[\]]|\[[^\]]*\])*)\](\([^)]*\)|\[[^\]]*\])/, '\1')
      s = s.gsub(/<((?:https?|mailto):[^>\s]+)>/, '\1').gsub(/<\/?[A-Za-z][^>]*>/, "")
      s = s.gsub(/(\*\*|__)(?=\S)((?:(?!\1).)+?)(?<=\S)\1/, '\2').gsub(/~~(.+?)~~/, '\1')   # bold not past the next **: linear time
      s = s.gsub(/(?<![\w*])\*(?=\S)(.+?)(?<=\S)\*(?![\w*])/, '\1').gsub(/(?<!\w)_(?=\S)(.+?)(?<=\S)_(?!\w)/, '\1')
      return entities(s).gsub(/[\u{E021}-\u{E07E}]/) { |c| (c.ord - 0xE000).chr }.strip
    end
  end
end
