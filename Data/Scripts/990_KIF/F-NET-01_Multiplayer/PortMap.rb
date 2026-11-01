#===============================================================================
# F-NET-01 – Multiplayer: opening the router's port while hosting
# 1. UPnP IGD: SSDP search (UDP multicast 239.255.255.250:1900), the
#    router's description over HTTP, then SOAP GetExternalIPAddress,
#    AddPortMapping (TCP, 2-hour lease, renewed hourly), DeletePortMapping.
# 2. NAT-PMP: UDP to the router on 5351 (external address, map, unmap).
# The external address tells the screens apart: in 100.64.0.0/10 or a
# private range = the provider shares one address (CGNAT, or a second
# router), so opening this router can't help.
# Plain Ruby on the engine's socket library, short timeouts, run in a
# background thread (KIF::Net.start_hosting). Every address can be passed
# in, so the kit tests it against fake routers on localhost.
#
# Any device on the network can answer a search, so who is believed:
# - only a device in this PC's own /24 network (or a program on this PC);
#   the router at x.x.x.1 is waited for and, once it answered, it is asked
#   first; one answer per device; a plain, short LOCATION path
# - NAT-PMP only to that router, never to whoever answered the search
# - a 2-hour lease, never a permanent mapping, on a random external port
#   (the port the game listens on, 52411-52415, stays inside the router);
#   a router that wants equal ports (UPnP 724) or has that port taken (718) gets
#   one more try with the listening port, so it still opens
# - at most 4 services per device and 10 s for the whole opening; replies are
#   cut at 64 KB (description) and 32 KB (SOAP) and read without backtracking
# - Net.stop ends it early: it sets Thread[:kif_stop] on the opening thread
#===============================================================================
module KIF
  module Net
    module PortMap
      SSDP = ["239.255.255.250", 1900]
      NATPMP_PORT = 5351
      LEASE = 7200
      OPEN_TIME = 10.0       # seconds the whole opening may take (after the search)
      MAX_DEVICES = 8        # devices that answered the search and are kept
      MAX_SERVICES = 4       # WAN services tried on one device
      MAX_DESC = 65_536      # bytes of a description
      MAX_SOAP = 32_768      # bytes of a SOAP answer
      PLAIN_PATH = %r{\A/[\w.\-/~]*(?:\?[\w.\-=&%]*)?\z}
      DESC = "KIF"
      TARGETS = ["urn:schemas-upnp-org:device:InternetGatewayDevice:1",
                 "urn:schemas-upnp-org:service:WANIPConnection:1",
                 "urn:schemas-upnp-org:service:WANPPPConnection:1"]

      module_function

      # Result hash: status :open (via :upnp/:natpmp/:none), :shared, :closed;
      # external_ip, external_port, local_ip, gateway, mapping (for close)
      def open(port, ssdp: SSDP, natpmp_port: NATPMP_PORT, gateways: nil, wait: 2.0, local: nil)
        local ||= local_ip
        res = { status: :closed, local_ip: local, internal_port: port, external_port: port }
        if local && ip_kind(local) == :public   # no router in the way
          return res.merge(status: :open, via: :none, external_ip: local)
        end
        ext_port = external_port_for(port)
        gw = gateway_guess(local)
        shared = nil   # a private or CGNAT address a device named (kept; the router's own word ends the search)
        found = discover(ssdp, wait, local, gw)
        Thread.current[:pm_deadline] = Net.now + OPEN_TIME
        found.each do |location, from|
          break if over?
          services(location).each do |svc|
            break if over?
            ans = soap(svc, "GetExternalIPAddress")
            break if ans[:status] == 0   # this device doesn't answer: its other services won't either
            ext = ans["NewExternalIPAddress"]
            next if ip_kind(ext) == :invalid   # none, "" or 0.0.0.0 (WAN down, IPv6-only): no address for a code
            res[:external_ip] ||= ext
            if shared?(ext)
              return res.merge(status: :shared, external_ip: ext, via: :upnp) if from == gw
              shared ||= [ext, :upnp]
              next
            end
            if (used = add_upnp(svc, port, ext_port, svc[:local] || local))   # the port the router took
              return res.merge(status: :open, via: :upnp, external_ip: ext, external_port: used, gateway: from,
                               mapping: [:upnp, svc, used, port])
            end
          end
        end
        (gateways || [gw]).compact.uniq.each do |g|
          break if over?
          ext = natpmp_external(g, natpmp_port)
          next if ip_kind(ext) == :invalid
          res[:external_ip] ||= ext
          return res.merge(status: :shared, external_ip: ext, via: :natpmp) if shared?(ext)
          eport = natpmp_map(g, natpmp_port, port, ext_port, LEASE) or next
          return res.merge(status: :open, via: :natpmp, external_ip: ext, external_port: eport, gateway: g,
                           mapping: [:natpmp, g, natpmp_port, port, eport])
        end
        return res.merge(status: :shared, external_ip: shared[0], via: shared[1]) if shared
        return res
      rescue StandardError => e
        Net.log("port opening stopped: #{e.class}: #{e.message}")
        return res || { status: :closed }
      ensure
        Thread.current[:pm_deadline] = nil
      end

      # the mapping again (lease renewal); never a longer lease than LEASE
      def renew(mapping)
        case mapping[0]
        when :upnp then add_upnp(mapping[1], mapping[3], mapping[2], mapping[1][:local], false)   # no other port: the code names this one
        when :natpmp
          eport = natpmp_map(mapping[1], mapping[2], mapping[3], mapping[4], LEASE)
          mapping[4] = eport if eport && eport > 0   # the router may give another port: the next renewal asks for that one
          eport
        end
      rescue StandardError
        nil
      end

      def close(mapping)
        case mapping[0]
        when :upnp
          soap(mapping[1], "DeletePortMapping", "NewRemoteHost" => "", "NewExternalPort" => mapping[2],
                                                "NewProtocol" => "TCP")
        when :natpmp then natpmp_map(mapping[1], mapping[2], mapping[3], 0, 0)
        end
      rescue StandardError
        nil
      end

      # The port the router listens on for this game. The listening port is one
      # of five that a scan of the internet looks for, so those get a random
      # port in 49152-65535; any other port is its own.
      def external_port_for(port)
        known = (Net::PORT...Net::PORT + Net::PORT_TRIES).to_a
        known += known.map { |x| x - 10_000 }
        return port unless known.include?(port)
        loop do
          p = 49_152 + Crypto.random(2).unpack1("n") % 16_384
          return p unless known.include?(p)
        end
      end

      def ip_kind(ip)
        a = ip.to_s.split(".")
        return :invalid unless a.length == 4 && a.all? { |x| x =~ /\A\d{1,3}\z/ && x.to_i < 256 }
        a = a.map(&:to_i)
        return :invalid if a[0] == 0 || a[0] >= 224
        return :cgnat if a[0] == 100 && a[1].between?(64, 127)
        return :private if a[0] == 10 || a[0] == 127 || (a[0] == 172 && a[1].between?(16, 31)) ||
                           (a[0] == 192 && a[1] == 168) || (a[0] == 169 && a[1] == 254)
        return :public
      end

      def shared?(ip); [:cgnat, :private].include?(ip_kind(ip)); end

      # a public IPv4 or a global IPv6 address (2000::/3), as the player types it
      def public_ip?(ip)
        return true if ip_kind(ip) == :public
        return false unless ip.to_s =~ /\A[23][0-9a-f]{3}:[0-9a-f:]{2,35}\z/i
        return (Addrinfo.ip(ip).ipv6? rescue false)
      end

      # this PC's address on the network (a UDP "connect" sends nothing)
      def local_ip(toward = "192.0.2.1")
        u = UDPSocket.new
        u.connect(toward, 9)
        return u.local_address.ip_address
      rescue StandardError
        return nil
      ensure
        u&.close
      end

      def gateway_guess(local)
        return nil unless local && ip_kind(local) == :private
        return local.sub(/\.\d+\z/, ".1")
      end

      # a global IPv6 address of this PC (2000::/3), or nil
      def global_ipv6
        a = Socket.ip_address_list.find { |x| x.ipv6? && x.ip_address =~ /\A[23][0-9a-f]{3}:/i }
        return a && a.ip_address.sub(/%.*\z/, "")
      rescue StandardError
        return nil
      end

      # the same /24 network (a UDP source can be forged, so this only narrows who is asked)
      def same_net?(a, b)
        return false unless ip_kind(a) != :invalid && ip_kind(b) != :invalid
        return a.split(".")[0, 3] == b.split(".")[0, 3]
      end

      # a device whose answer to the search is believed: on this PC's network, or a
      # program on this PC (a router is never 127.x; shortcut: loopback is trusted
      # unless this PC's own address is loopback too, which only the kit uses)
      def trusted_device?(ip, local)
        return true if local && same_net?(ip, local)
        return ip.to_s.start_with?("127.") && !local.to_s.start_with?("127.")
      end

      # http://host[:port]/short/plain/path (no "..", no odd characters)
      def plain_url?(url)
        path = url.to_s[%r{\Ahttp://[^/]+(/.*)?\z}i, 1] || "/"
        return path.length <= 128 && path =~ PLAIN_PATH && !path.include?("..") ? true : false
      end

      # the stop flag Net.stop sets, or the opening's time is up
      def over?
        return true if Thread.current[:kif_stop]
        d = Thread.current[:pm_deadline]
        return d ? Net.now > d : false
      end

      #-------------------------------------------------------------------------
      # UPnP
      #-------------------------------------------------------------------------
      # [[location, responder address], ...], the router (gw) first. A LOCATION
      # must be on the device that answered; the first answer of a device counts;
      # the search ends when the router answered (or after wait seconds), so
      # a device that answers four times first can't push the router out.
      def discover(ssdp, wait, local = nil, gw = nil)
        found = {}
        u = UDPSocket.new
        TARGETS.each do |st|
          msg = "M-SEARCH * HTTP/1.1\r\nHOST: #{SSDP.join(':')}\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: #{st}\r\n\r\n"
          u.send(msg, 0, ssdp[0], ssdp[1])
        end
        stop = Net.now + wait
        while (left = stop - Net.now) > 0 && !over?
          next unless IO.select([u], nil, nil, [left, 0.2].min)
          data, from = (u.recvfrom(2048) rescue nil)
          next unless data
          ip = from[3]
          loc = data[/^location:\s*(\S+)/i, 1]
          next unless loc && url_host(loc) == ip && plain_url?(loc) && trusted_device?(ip, local)
          next if found.key?(ip) || (found.length >= MAX_DEVICES && ip != gw)
          found[ip] = loc
          break if ip == gw
        end
        list = found.map { |ip, loc| [loc, ip] }
        return list.select { |_, ip| ip == gw } + list.reject { |_, ip| ip == gw }
      ensure
        u&.close
      end

      # WANIPConnection / WANPPPConnection services in a description (at most
      # MAX_SERVICES; plain string searches, nothing that can backtrack)
      def services(location)
        st, body, = http(location)
        return [] unless st == 200
        base = tag_text(body, "URLBase") || location
        list = []
        each_tag(body, "service", 32) do |svc|
          type = tag_text(svc, "serviceType").to_s
          ctl = tag_text(svc, "controlURL")
          next unless type =~ /\Aurn:schemas-upnp-org:service:WAN(IP|PPP)Connection:\d\z/ && ctl
          url = join_url(base, ctl)
          next unless url && url_host(url) == url_host(location) && plain_url?(url)
          list << { type: type, control: url }
        end
        return list.sort_by.with_index { |s, i| [s[:type].include?("WANIP") ? 0 : 1, i] }.first(MAX_SERVICES)
      end

      # the text inside the first <name>...</name>, stripped, or nil
      def tag_text(text, name)
        a = text.index("<#{name}>") or return nil
        a += name.length + 2
        b = text.index("</#{name}>", a) or return nil
        return text[a...b].strip
      end

      # yields the inside of each <name>...</name> (at most max of them)
      def each_tag(text, name, max)
        i = 0
        max.times do
          a = text.index("<#{name}>", i) or break
          a += name.length + 2
          b = text.index("</#{name}>", a) or break
          yield text[a...b]
          i = b + name.length + 3
        end
      end

      # The external port the router took, or nil. A router that only takes permanent mappings
      # (error 725) is left alone. One that wants the same port on both sides (724) or has the
      # random one taken (718) gets one more try with the listening port, unless Stop came meanwhile
      # (a request that was sent is waited for, so a late one would leave a mapping behind).
      # shortcut: for such a router the fixed KIF port is on the internet again; a router that
      # can't do more would otherwise not open at all, and the player can open it by hand anyway.
      def add_upnp(svc, port, ext_port, client, fallback = true)
        r = add_once(svc, port, ext_port, client)
        return ext_port if r[:status] == 200
        if fallback && ext_port != port && %w[718 724].include?(r["errorCode"]) && !over?
          return port if add_once(svc, port, port, client)[:status] == 200
        end
        return nil
      end

      def add_once(svc, port, ext_port, client)
        return soap(svc, "AddPortMapping",
                    "NewRemoteHost" => "", "NewExternalPort" => ext_port, "NewProtocol" => "TCP",
                    "NewInternalPort" => port, "NewInternalClient" => client, "NewEnabled" => 1,
                    "NewPortMappingDescription" => DESC, "NewLeaseDuration" => LEASE)
      end

      # {status:, "NewX" => value, "errorCode" => ...}; remembers this PC's
      # address as the router sees it (svc[:local])
      def soap(svc, action, args = {})
        xml = args.map { |k, v| "<#{k}>#{v.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')}</#{k}>" }.join
        body = %(<?xml version="1.0"?>\r\n<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" ) +
               %(s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>) +
               %(<u:#{action} xmlns:u="#{svc[:type]}">#{xml}</u:#{action}></s:Body></s:Envelope>\r\n)
        st, res, local = http(svc[:control], body, { "Content-Type" => 'text/xml; charset="utf-8"',
                                                   "SOAPAction" => %("#{svc[:type]}##{action}") })
        svc[:local] ||= local
        out = { status: st }
        # [^<]*+ never gives text back, so a tag that never closes costs one pass
        res.to_s.scan(%r{<(New\w+|errorCode)>([^<]*+)</\1>}) { |k, v| out[k] = v.strip }
        return out
      end

      def url_host(url); url.to_s[%r{\Ahttp://\[?([^/\]]+?)\]?(?::\d+)?(?:/|\z)}i, 1]; end

      def join_url(base, path)
        return path if path =~ %r{\Ahttp://}i
        origin = base[%r{\Ahttp://[^/]+}i] or return nil
        return origin + (path.start_with?("/") ? path : "/" + path)
      end

      # [status, body, this PC's address] or [0, "", nil]. Stops with the opening
      # (Thread[:kif_stop], PortMap.open's deadline) unless it is an AddPortMapping
      # (one that was sent is waited for, so its mapping can be removed). The
      # answer is cut at MAX_SOAP bytes for a POST, MAX_DESC for a GET.
      def http(url, body = nil, headers = {}, timeout: 3.0)
        max = body ? MAX_SOAP : MAX_DESC
        abortable = !body.to_s.include?("<u:AddPortMapping")
        m = url.to_s.match(%r{\Ahttp://(\[[0-9a-fA-F:.]+\]|[^/:]+)(?::(\d+))?(/\S*)?\z}i) or return [0, "", nil]
        if (d = Thread.current[:pm_deadline])
          timeout = [timeout, d - Net.now].min
          return [0, "", nil] if timeout <= 0
        end
        return [0, "", nil] if abortable && Thread.current[:kif_stop]
        host = m[1].delete("[]")
        sock = TCPSocket.new(host, (m[2] || 80).to_i, connect_timeout: timeout)
        req = +"#{body ? 'POST' : 'GET'} #{m[3] || '/'} HTTP/1.0\r\nHost: #{m[1]}#{m[2] ? ":#{m[2]}" : ''}\r\nConnection: close\r\n"
        headers.each { |k, v| req << "#{k}: #{v}\r\n" }
        req << "Content-Length: #{body.bytesize}\r\n" if body
        sock.write(req + "\r\n" + body.to_s)
        data = +"".b
        stop = Net.now + timeout
        while (left = stop - Net.now) > 0 && data.bytesize < max && !(abortable && Thread.current[:kif_stop])
          next unless IO.select([sock], nil, nil, [left, 0.2].min)
          chunk = (sock.readpartial(16_384) rescue nil) or break
          data << chunk
        end
        data = data.byteslice(0, max + 1_024)   # the head and the first max bytes of the body
        head, rest = data.split("\r\n\r\n", 2)
        status = head.to_s[%r{\AHTTP/\d\.\d (\d+)}, 1].to_i
        rest = dechunk(rest.to_s) if head.to_s =~ /^transfer-encoding:\s*chunked/i
        return [status, rest.to_s.byteslice(0, max).to_s.force_encoding("UTF-8").scrub, (sock.local_address.ip_address rescue nil)]
      rescue StandardError
        return [0, "", nil]
      ensure
        sock&.close
      end

      def dechunk(s)
        out = +"".b
        i = 0
        while (eol = s.index("\r\n", i))
          n = s[i...eol].to_i(16)
          break if n <= 0
          out << s.byteslice(eol + 2, n).to_s
          i = eol + 2 + n + 2
        end
        return out
      end

      #-------------------------------------------------------------------------
      # NAT-PMP (RFC 6886)
      #-------------------------------------------------------------------------
      def natpmp(gw, port, req, size)
        u = UDPSocket.new
        u.connect(gw, port)
        [0.25, 0.5, 1.0].each do |t|
          break if over?
          u.send(req, 0)
          next unless IO.select([u], nil, nil, t)
          data = (u.recv(64) rescue nil)
          return data if data && data.bytesize >= size && data.getbyte(0) == 0 && data.getbyte(1) == req.getbyte(1) + 128 &&
                         data.unpack1("@2n") == 0
        end
        return nil
      rescue StandardError
        return nil
      ensure
        u&.close
      end

      def natpmp_external(gw, port)
        d = natpmp(gw, port, [0, 0].pack("CC"), 12)
        return d && d.byteslice(8, 4).unpack("C4").join(".")
      end

      # the external port the router gave (0 for a removed mapping), or nil when
      # the answer isn't for this request: the reply must name our internal port,
      # a port 1-65535 and a lifetime above 0 (a map) or 0 (lifetime 0 removes it)
      def natpmp_map(gw, port, internal, external, life)
        d = natpmp(gw, port, [0, 2, 0, internal, external, life].pack("CCnnnN"), 16)
        return nil unless d && d.unpack1("@8n") == internal
        got, lifetime = d.unpack("@10nN")
        return life == 0 ? (lifetime == 0 ? 0 : nil) : (got.between?(1, 65_535) && lifetime > 0 ? got : nil)
      end
    end
  end
end
