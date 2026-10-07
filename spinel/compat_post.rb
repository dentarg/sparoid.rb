# frozen_string_literal: true

# Loaded after sparoid in the Spinel build: replaces what calls Addrinfo
# methods Spinel's builtin Addrinfo doesn't have.
module Sparoid
  # sparoid's fdpass, with the socket assigned outside the rescue: there `s` could
  # be nil, which made it a poly value without connect_nonblock in Spinel
  def fdpass(addrs, port, connect_timeout: 10) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
    viable_addrs = []
    sockets = []
    addrs.each do |addr|
      sock = Socket.new(addr.afamily, Socket::SOCK_STREAM)
      begin
        sock.connect_nonblock(Socket.sockaddr_in(port, addr.ip_address), exception: false)
        viable_addrs << addr
        sockets << sock
      rescue Errno::EHOSTUNREACH, Errno::ENETUNREACH, Errno::ECONNREFUSED => e
        warn "Sparoid: skip #{addr.ip_address}: #{e.message}"
        sock.close
      end
    end
    until sockets.empty?
      _, writeable, errors = IO.select(nil, sockets, nil, connect_timeout) || break
      errors.each { |err| sockets.delete(err) }
      writeable.each do |ready|
        idx = sockets.index(ready)
        conn = sockets.delete_at(idx)
        viable_addrs.delete_at(idx)
        # check for errors: a Socket read out of an Array has no connect_nonblock
        # (or getsockopt) in Spinel, read SO_ERROR off its descriptor instead
        next unless SpinelFdpass.spinel_socket_error(conn.fileno).zero?

        Socket.for_fd(1).sendmsg "\0", 0, nil, Socket::AncillaryData.unix_rights(conn)
        exit 0
      end
    end
    exit 1
  end

  # Spinel's OpenSSL::Cipher has no AES-256-CBC, the key is just 32 random bytes
  def keygen
    puts "key = #{SecureRandom.random_bytes(32).unpack1("H*")}"
    puts "hmac-key = #{SecureRandom.random_bytes(32).unpack1("H*")}"
  end

  private

  # sparoid's encrypt, with the AES-256-CBC of spinel/compat.rb
  def encrypt(key, data)
    key = [key].pack("H*") # hexstring to bytes
    raise ArgumentError, "Key must be 32 bytes hex encoded" if key.bytesize != 32

    iv = SecureRandom.random_bytes(16)
    iv + SpinelAES256CBC.encrypt(key, iv, data)
  end

  # Spinel's Addrinfo has no getaddrinfo, and a program can't add one (a
  # `class Addrinfo` body clashes with the builtin), go through
  # Socket.getaddrinfo and keep the datagram addresses, as sparoid does
  def resolve_ip_addresses(host, port)
    # Spinel's Socket.getaddrinfo ignores the socktype argument, filter the rows
    rows = Socket.getaddrinfo(host, port).select { |row| row[5] == Socket::SOCK_DGRAM }
    raise(ResolvError, "Sparoid failed to resolv #{host}") if rows.empty?

    rows.map { |row| Addrinfo.udp(row[3], row[1]) }
  rescue SocketError
    raise(ResolvError, "Sparoid failed to resolv #{host}")
  end

  # Addrinfo has no ipv6_* predicates in Spinel, work on the address bytes
  def global_ipv6?(addr)
    ip = addr.ip_address.split("%", 2).first
    return false unless Resolv::IPv6::Regex.match?(ip)

    b = Resolv::IPv6.create(ip).address
    loopback = b == "#{"\0" * 15}\u0001".b
    unspecified = b == ("\0" * 16).b
    linklocal = b.getbyte(0) == 0xfe && (b.getbyte(1) & 0xc0) == 0x80
    sitelocal = b.getbyte(0) == 0xfe && (b.getbyte(1) & 0xc0) == 0xc0
    multicast = b.getbyte(0) == 0xff
    v4mapped = (0..9).all? { |i| b.getbyte(i).zero? } && b.getbyte(10) == 0xff && b.getbyte(11) == 0xff
    !(loopback || linklocal || unspecified || sitelocal || multicast || v4mapped || ip.start_with?("fd", "fc"))
  end
end

module Sparoid
  # CLI
  module CLI
    # Spinel's File.readlines doesn't raise Errno::ENOENT for a missing file
    def self.parse_ini(path)
      path = File.expand_path(path)
      unless File.exist?(path)
        return {
          "key" => ENV.fetch("SPAROID_KEY", nil),
          "hmac-key" => ENV.fetch("SPAROID_HMAC_KEY", nil)
        }
      end
      File.readlines(path).to_h { |line| line.split("=", 2).map(&:strip) }
    end
    private_class_method :parse_ini
  end
end
