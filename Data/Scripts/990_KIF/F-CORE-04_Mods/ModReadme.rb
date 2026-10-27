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
    # characters the game's fonts may not have
    FOLD = { "–" => "-", "—" => "-", "‘" => "'", "’" => "'", "“" => '"',
             "”" => '"', "…" => "...", "×" => "x", " " => " ", "→" => "->",
             "•" => "-", "\t" => "  " }
    ENTITIES = { "&amp;" => "&", "&lt;" => "<", "&gt;" => ">", "&quot;" => '"', "&#39;" => "'", "&nbsp;" => " " }

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
    # when the catalog didn't answer
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
      return text ? [n, text] : :offline
    end

    # what the reader shows
    def lines_for(found, desc)
      desc = fold(desc.to_s).gsub(/\s+/, " ").strip
      desc = _INTL("This mod has no description.") if desc.empty?
      return [_INTL("Couldn't reach the mod catalog to read the full description. Check the internet connection and try again."), "", desc] if found == :offline
      return [desc] unless found
      lines = plain(found[1], found[0] !~ /\.txt\z/i)
      return lines.empty? ? [desc] : lines
    end

    def show(title, found, desc)
      KIF::Updater.show_text(KIF::PixelFont.utf8(title.to_s), lines_for(found, desc), false)
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
      s = KIF::PixelFont.utf8(s.to_s)
      return s.gsub(/[–—‘’“”…× →•\t]/) { |c| FOLD[c] }
              .gsub(/[\x00-\x08\x0B-\x1F\x7F]/, "")
    end

    # the reader's lines: Markdown (md) as plain text, a .txt as it is;
    # more than MAX bytes is cut and says so
    def plain(text, md = true)
      t = text.to_s.b
      cut = t.bytesize > MAX
      t = t.byteslice(0, MAX) if cut
      t = fold(t.force_encoding("UTF-8").scrub("").sub(/\A﻿/, "").gsub(/\r\n?/, "\n"))
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
      text.gsub(/<!--.*?-->/m, "").split("\n").each do |l|
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
          out[-1] += " " + inline(s)
        else
          t = inline(s)
          next if t.empty?   # an html line (<p align="center">)
          para = para ? "#{para} #{t}" : t
        end
      end
      flush.call
      return out
    end

    # one line's text: pictures as [picture], links as their text, no
    # emphasis, code or html marks
    def inline(s)
      keep = proc { |t| t.gsub(/[!-\/:-@\[-`{-~]/) { |c| (0xE000 + c.ord).chr(Encoding::UTF_8) } }
      s = s.gsub(/\\([!-\/:-@\[-`{-~])/) { keep.call($1) }   # \* stays a *
      s = s.gsub(/(`+)(.+?)\1/) { keep.call($2.strip) }     # code: its text, as it is
      s = s.gsub(/<img\b[^>]*>/i, "[picture]").gsub(/!\[[^\]]*\](\([^)]*\)|\[[^\]]*\])/, "[picture]")
      s = s.gsub(/\[((?:[^\[\]]|\[[^\]]*\])*)\](\([^)]*\)|\[[^\]]*\])/, '\1')
      s = s.gsub(/<((?:https?|mailto):[^>\s]+)>/, '\1').gsub(/<\/?[A-Za-z][^>]*>/, "")
      s = s.gsub(/(\*\*|__)(?=\S)(.+?)(?<=\S)\1/, '\2').gsub(/~~(.+?)~~/, '\1')
      s = s.gsub(/(?<![\w*])\*(?=\S)(.+?)(?<=\S)\*(?![\w*])/, '\1').gsub(/(?<!\w)_(?=\S)(.+?)(?<=\S)_(?!\w)/, '\1')
      s = s.gsub(/&(amp|lt|gt|quot|#39|nbsp);/) { |e| ENTITIES[e] }
      return s.gsub(/[\u{E021}-\u{E07E}]/) { |c| (c.ord - 0xE000).chr }.strip
    end
  end
end
