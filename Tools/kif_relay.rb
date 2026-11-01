# KIF relay: passes messages between two KIF games that can't reach each
# other directly (for example when both internet providers share one address).
#
#   ruby kif_relay.rb [port]        default port 52413 (open it on this PC's router)
#
# Needs only a normal Ruby (2.7 or newer). Players type this PC's address in
# Multiplayer > Use a relay. Each game sends one short line saying which room
# it's in and whether it hosts or joins; when both sides of a room are there,
# the relay passes bytes along and nothing else. It never gets the game's
# secret, so it can't read the join code's key, forge or change messages; it
# can see them (they aren't encrypted) and it can cut the line.
require "socket"

class KIFRelay
  HELLO_MAX  = 256          # bytes in the first frame
  HELLO_WAIT = 10           # seconds to send it
  WAIT_MAX   = 30 * 60      # seconds a room waits for its second player
  MAX_ROOMS  = 200
  HELLO = /\A\{"t":"relay","room":"([0-9a-f]{16})","role":"(host|join)"\}\z/

  attr_reader :port

  def initialize(port = 52413, bind = "0.0.0.0", log: $stdout)
    @port = port
    @bind = bind
    @log = log
    @rooms = {}   # room => { "host" => [sock, time], "join" => [sock, time] }
    @lock = Mutex.new
  end

  def start
    @server = TCPServer.new(@bind, @port)
    @port = @server.addr[1]
    @thread = Thread.new do
      loop do
        c = @server.accept
        Thread.new(c) { |s| handle(s) }
      end
    rescue IOError, SystemCallError
      nil
    end
    say("relay listening on port #{@port}")
    return self
  end

  def stop
    (@server.close rescue nil)
    @lock.synchronize { @rooms.each_value { |r| r.each_value { |s, _| (s.close rescue nil) } }; @rooms.clear }
  end

  def run
    start
    @thread.join
  end

  private

  def say(text); @log&.puts("#{Time.now.strftime('%H:%M:%S')} #{text}"); end

  def frame(text); [text.bytesize].pack("N") + text; end

  def read_exact(sock, n, stop)
    buf = "".b
    while buf.bytesize < n
      left = stop - Time.now
      return nil if left <= 0 || !IO.select([sock], nil, nil, left)
      buf << sock.readpartial(n - buf.bytesize)
    end
    buf
  end

  def handle(sock)
    stop = Time.now + HELLO_WAIT
    len = read_exact(sock, 4, stop)&.unpack1("N")
    text = len && len <= HELLO_MAX ? read_exact(sock, len, stop) : nil
    m = text && text.force_encoding("UTF-8").match(HELLO)
    return refuse(sock, "bad") unless m
    room, role = m[1], m[2]
    other = nil
    why = @lock.synchronize do
      now = Time.now
      @rooms.delete_if { |_, r| r.values.all? { |_, t| now - t > WAIT_MAX } && r.each_value { |s, _| (s.close rescue nil) } }
      r = @rooms[room]
      if r && r[role] then "taken"
      elsif !r && @rooms.length >= MAX_ROOMS then "full"
      else
        r ||= (@rooms[room] = {})
        r[role] = [sock, now]
        other = r[role == "host" ? "join" : "host"]
        @rooms.delete(room) if other
        nil
      end
    end
    return refuse(sock, why) if why
    return say("room #{room[0, 4]}...: #{role} waiting") unless other
    say("room #{room[0, 4]}...: paired")
    a, b = sock, other[0]
    [a, b].each { |s| s.write(frame('{"t":"relay_ok"}')) }
    t = Thread.new { pump(b, a) }
    pump(a, b)
    t.join
  rescue IOError, SystemCallError
    (sock.close rescue nil)
  end

  def refuse(sock, why)
    (sock.write(frame(%({"t":"relay_no","why":"#{why}"}))) rescue nil)
    (sock.close rescue nil)
  end

  def pump(from, to)
    loop { to.write(from.readpartial(16_384)) }
  rescue IOError, SystemCallError
    nil
  ensure
    (from.close rescue nil)
    (to.close rescue nil)
  end
end

KIFRelay.new((ARGV[0] || 52413).to_i).run if $PROGRAM_NAME == __FILE__
