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
#===============================================================================
module KIF
  module Net
    module PortMap
      SSDP = ["239.255.255.250", 1900]
      NATPMP_PORT = 5351
      LEASE = 7200
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
        gws = []
        discover(ssdp, wait).each do |location, from|
          gws << from
          services(location).each do |svc|
            ext = soap(svc, "GetExternalIPAddress")["NewExternalIPAddress"]
            next unless ext
            res[:external_ip] ||= ext if ip_kind(ext) != :invalid
            return res.merge(status: :shared, external_ip: ext, via: :upnp) if shared?(ext)
            if add_upnp(svc, port, svc[:local] || local)
              return res.merge(status: :open, via: :upnp, external_ip: ext, gateway: from,
                               mapping: [:upnp, svc, port])
            end
          end
        end
        gws += gateways || [gateway_guess(local)]
        gws.compact.uniq.each do |gw|
          ext = natpmp_external(gw, natpmp_port) or next
          res[:external_ip] ||= ext if ip_kind(ext) != :invalid
          return res.merge(status: :shared, external_ip: ext, via: :natpmp) if shared?(ext)
          eport = natpmp_map(gw, natpmp_port, port, port, LEASE) or next
          return res.merge(status: :open, via: :natpmp, external_ip: ext, external_port: eport, gateway: gw,
                           mapping: [:natpmp, gw, natpmp_port, port])
        end
        return res
      rescue StandardError => e
        Net.log("port opening stopped: #{e.class}: #{e.message}")
        return res || { status: :closed }
      end

      # the mapping again (lease renewal)
      def renew(mapping)
        case mapping[0]
        when :upnp   then add_upnp(mapping[1], mapping[2], mapping[1][:local])
        when :natpmp then natpmp_map(mapping[1], mapping[2], mapping[3], mapping[3], LEASE)
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

      #-------------------------------------------------------------------------
      # UPnP
      #-------------------------------------------------------------------------
      # [[location, responder address], ...]; a LOCATION must be on the
      # device that answered
      def discover(ssdp, wait)
        found = []
        u = UDPSocket.new
        TARGETS.each do |st|
          msg = "M-SEARCH * HTTP/1.1\r\nHOST: #{SSDP.join(':')}\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: #{st}\r\n\r\n"
          u.send(msg, 0, ssdp[0], ssdp[1])
        end
        stop = Net.now + wait
        while (left = stop - Net.now) > 0
          next unless IO.select([u], nil, nil, left)
          data, from = (u.recvfrom(2048) rescue nil)
          next unless data
          loc = data[/^location:\s*(\S+)/i, 1]
          next unless loc && url_host(loc) == from[3]
          found << [loc, from[3]] unless found.any? { |l, _| l == loc }
          break if found.length >= 4
        end
        return found
      ensure
        u&.close
      end

      # WANIPConnection / WANPPPConnection services in a description
      def services(location)
        st, body, = http(location)
        return [] unless st == 200
        base = body[%r{<URLBase>\s*(.*?)\s*</URLBase>}m, 1] || location
        list = body.scan(%r{<service>(.*?)</service>}m).map do |(svc)|
          type = svc[%r{<serviceType>\s*(.*?)\s*</serviceType>}m, 1].to_s
          ctl = svc[%r{<controlURL>\s*(.*?)\s*</controlURL>}m, 1]
          next nil unless type =~ /\Aurn:schemas-upnp-org:service:WAN(IP|PPP)Connection:\d\z/ && ctl
          url = join_url(base, ctl)
          next nil unless url && url_host(url) == url_host(location)
          { type: type, control: url }
        end
        return list.compact.sort_by { |s| s[:type].include?("WANIP") ? 0 : 1 }
      end

      def add_upnp(svc, port, client)
        [LEASE, 0].each do |lease|   # 0: routers that only take permanent mappings (error 725)
          r = soap(svc, "AddPortMapping",
                   "NewRemoteHost" => "", "NewExternalPort" => port, "NewProtocol" => "TCP",
                   "NewInternalPort" => port, "NewInternalClient" => client, "NewEnabled" => 1,
                   "NewPortMappingDescription" => DESC, "NewLeaseDuration" => lease)
          return true if r[:status] == 200
          return false unless r["errorCode"] == "725"
        end
        return false
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
        res.to_s.scan(%r{<(New\w+|errorCode)>\s*([^<]*?)\s*</\1>}) { |k, v| out[k] = v }
        return out
      end

      def url_host(url); url.to_s[%r{\Ahttp://\[?([^/\]]+?)\]?(?::\d+)?(?:/|\z)}i, 1]; end

      def join_url(base, path)
        return path if path =~ %r{\Ahttp://}i
        origin = base[%r{\Ahttp://[^/]+}i] or return nil
        return origin + (path.start_with?("/") ? path : "/" + path)
      end

      # [status, body, this PC's address] or [0, "", nil]
      def http(url, body = nil, headers = {}, timeout: 3.0)
        m = url.to_s.match(%r{\Ahttp://(\[[0-9a-fA-F:.]+\]|[^/:]+)(?::(\d+))?(/\S*)?\z}i) or return [0, "", nil]
        host = m[1].delete("[]")
        sock = TCPSocket.new(host, (m[2] || 80).to_i, connect_timeout: timeout)
        req = +"#{body ? 'POST' : 'GET'} #{m[3] || '/'} HTTP/1.0\r\nHost: #{m[1]}#{m[2] ? ":#{m[2]}" : ''}\r\nConnection: close\r\n"
        headers.each { |k, v| req << "#{k}: #{v}\r\n" }
        req << "Content-Length: #{body.bytesize}\r\n" if body
        sock.write(req + "\r\n" + body.to_s)
        data = +"".b
        stop = Net.now + timeout
        while (left = stop - Net.now) > 0 && data.bytesize < 262_144
          break unless IO.select([sock], nil, nil, left)
          chunk = (sock.readpartial(16_384) rescue nil) or break
          data << chunk
        end
        head, rest = data.split("\r\n\r\n", 2)
        status = head.to_s[%r{\AHTTP/\d\.\d (\d+)}, 1].to_i
        rest = dechunk(rest.to_s) if head.to_s =~ /^transfer-encoding:\s*chunked/i
        return [status, rest.to_s.force_encoding("UTF-8").scrub, (sock.local_address.ip_address rescue nil)]
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
          u.send(req, 0)
          next unless IO.select([u], nil, nil, t)
          data = (u.recv(64) rescue nil)
          return data if data && data.bytesize >= size && data.getbyte(1) == req.getbyte(1) + 128 &&
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

      # the external port, or nil; lifetime 0 removes it
      def natpmp_map(gw, port, internal, external, life)
        d = natpmp(gw, port, [0, 2, 0, internal, external, life].pack("CCnnnN"), 16)
        return d && d.unpack1("@10n")
      end
    end
  end
end
