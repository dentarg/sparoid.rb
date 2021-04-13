# frozen_string_literal: true

require_relative "sparoid/version"
require "socket"
require "openssl"
require "resolv"

# Single Packet Authorisation client
module Sparoid
  extend self

  # Send an authorization packet
  def auth(key, hmac_key, host, port)
    msg = message(public_ip)
    data = prefix_hmac(hmac_key, encrypt(key, msg))
    sendmsg(host, port, data)
  end

  # Generate new aes and hmac keys, print to stdout
  def keygen
    cipher = OpenSSL::Cipher.new("aes-256-cbc")
    key = cipher.random_key.unpack1("H*")
    hmac_key = OpenSSL::Random.random_bytes(32).unpack1("H*")
    puts "key = #{key}"
    puts "hmac-key = #{hmac_key}"
  end

  # Connect to a TCP server and pass the FD to the parent
  def fdpass(host, port, connect_timeout: 20)
    tcp = Socket.tcp host, port, connect_timeout: connect_timeout
    parent = Socket.for_fd(1)
    parent.sendmsg "\0", 0, nil, Socket::AncillaryData.unix_rights(tcp)
  end

  private

  def sendmsg(host, port, data)
    UDPSocket.open do |socket|
      socket.connect host, port
      socket.sendmsg data, 0
    end
  end

  def encrypt(key, data)
    key = [key].pack("H*") # hexstring to bytes
    raise ArgumentError, "Key must be 32 bytes hex encoded" if key.bytesize != 32

    cipher = OpenSSL::Cipher.new("aes-256-cbc")
    cipher.encrypt
    iv = cipher.random_iv
    cipher.key = key
    cipher.iv = iv
    output = iv
    output << cipher.update(data)
    output << cipher.final
  end

  def prefix_hmac(hmac_key, data)
    hmac_key = [hmac_key].pack("H*") # hexstring to bytes
    raise ArgumentError, "HMAC key must be 32 bytes hex encoded" if hmac_key.bytesize != 32

    hmac = OpenSSL::HMAC.digest("SHA256", hmac_key, data)
    hmac + data
  end

  def message(ip)
    version = 1
    ts = (Time.now.utc.to_f * 1000).floor
    nounce = OpenSSL::Random.random_bytes(16)
    [version, ts, nounce, ip.address].pack("Nq>a16a4")
  end

  def public_ip
    Resolv::DNS.open(nameserver: ["208.67.222.222", "208.67.220.220"]) do |dns|
      dns.getresource("myip.opendns.com", Resolv::DNS::Resource::IN::A).address
    end
  end

  class Error < StandardError; end

  # Instance of SPAroid that only resolved public_ip once
  class Instance
    include Sparoid

    private

    def public_ip
      @public_ip ||= super
    end
  end
end
