#############################
#
# HTTP utility functions
#
#############################

def pbPostData(url, postdata, filename=nil, depth=0)
  return "" unless url =~ /^https?:\/\/([^\/]+)(.*)$/
  host = $1
  path = $2
  path = "/" if path.empty?

  userAgent = "Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.9.0.14) Gecko/2009082707 Firefox/3.0.14"

  # Serialize as JSON
  body = serialize_json(postdata)

  ret = HTTPLite.post_body(
    url,
    body,
    "application/json",
    {
      "Host" => host,
      "Proxy-Connection" => "Close",
      "Content-Length" => body.bytesize.to_s,
      "Pragma" => "no-cache",
      "User-Agent" => userAgent
    }
  ) rescue ""

  return "" if !ret.is_a?(Hash)
  return "" if ret[:status] != 200
  if filename
    File.open(filename, "wb") { |f| f.write(ret[:body]) }
    return ""
  end
  ret[:body]
end



def pbDownloadData(url, filename = nil, authorization = nil, depth = 0, &block)
  return nil if !downloadAllowed?()
  echoln "downloading data from #{url}"
  headers = {
    "Proxy-Connection" => "Close",
    "Pragma" => "no-cache",
    "User-Agent" => "Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.9.0.14) Gecko/2009082707 Firefox/3.0.14"
  }
  headers["authorization"] = authorization if authorization
  ret = HTTPLite.get(url, headers) rescue ""
  return ret if !ret.is_a?(Hash)
  return "" if ret[:status] != 200
  return ret[:body] if !filename
  File.open(filename, "wb") { |f| f.write(ret[:body]) }
  return ""
end

def pbDownloadToString(url)
  begin
    data = pbDownloadData(url)
    return data if data
    return ""
  rescue
    return ""
  end
end

def pbDownloadToFile(url, file)
  begin
    pbDownloadData(url,file)
  rescue
  end
end

def pbPostToString(url, postdata, timeout = 30)
  safe_postdata = postdata.transform_values(&:to_s)
  begin
    data = pbPostData(url, safe_postdata)
    return data || ""
  rescue MKXPError => e
    echoln("[Remote AI] Exception: #{e.message}")
    return ""
  end
end





def pbPostToFile(url, postdata, file)
  begin
    pbPostData(url, postdata,file)
  rescue
  end
end

def serialize_value_legacy(value)
  if value.is_a?(Hash)
    serialize_json(value)
  elsif value.is_a?(String)
    escaped_value = value.gsub(/\\/, '\\\\\\').gsub(/"/, '\\"').gsub(/\n/, '\\n').gsub(/\r/, '\\r')
    "\"#{escaped_value}\""
  else
    value.to_s
  end
end


def serialize_json(data)
  if data.is_a?(Hash)
    parts = ["{"]
    data.each_with_index do |(key, value), index|
      parts << "\"#{key}\":#{serialize_value(value)}"
      parts << "," unless index == data.size - 1
    end
    parts << "}"
    return parts.join
  else
    return serialize_value(data)
  end
end

def serialize_value(value)
  case value
  when String
    "\"#{escape_json_string(value)}\""
  when Numeric
    value.to_s
  when TrueClass, FalseClass
    value.to_s
  when NilClass
    "null"
  when Array
    "[" + value.map { |v| serialize_value(v) }.join(",") + "]"
  when Hash
    serialize_json(value)
  else
    raise "Unsupported type: #{value.class}"
  end
end

def escape_json_string(str)
  # Minimal escape handling
  str.gsub(/["\\]/) { |m| "\\#{m}" }
    .gsub("\n", "\\n")
    .gsub("\t", "\\t")
    .gsub("\r", "\\r")
end



def downloadAllowed?()
  return $PokemonSystem.download_sprites==0
end

def clean_json_string(str)
  #echoln str
  #return str if $PokemonSystem.on_mobile
  # Remove non-UTF-8 characters and unexpected control characters
  #cleaned_str = str.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '')
  cleaned_str = str
  # Remove literal \n, \r, \t, etc.
  cleaned_str = cleaned_str.gsub(/\\n|\\r|\\t/, '')

  # Remove actual newlines and carriage returns
  cleaned_str = cleaned_str.gsub(/[\n\r]/, '')

  # Remove leading and trailing quotes
  cleaned_str = cleaned_str.gsub(/\A"|"\Z/, '')

  # Replace Unicode escape sequences with corresponding characters
  cleaned_str = cleaned_str.gsub(/\\u([\da-fA-F]{4})/) { |match|
    [$1.to_i(16)].pack("U")
  }
  return cleaned_str
end


# json.rb - lightweight JSON parser for MKXP/RGSS XP

# Lightweight JSON for MKXP/RGSS XP
module JSON
  module_function

  # Convert Ruby object (hash/array/etc) into JSON string
  def generate(obj)
    case obj
    when Hash
      "{" + obj.map { |k, v| "\"#{k}\":#{generate(v)}" }.join(",") + "}"
    when Array
      "[" + obj.map { |v| generate(v) }.join(",") + "]"
    when String, Symbol
      "\"#{obj.to_s}\""
    when TrueClass, FalseClass
      obj.to_s
    when NilClass
      "null"
    when Numeric
      obj.to_s
    else
      raise "Unsupported type #{obj.class}"
    end
  end

  # Simple parser (not full JSON) — optional
  def parse(str)
    return nil if str.nil? || str.strip.empty?
    eval(str)
  end
end











