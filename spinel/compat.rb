# frozen_string_literal: true

# The CRuby stdlib surface sparoid.rb uses that Spinel lacks, built on what
# Spinel has. Required before sparoid in the Spinel build only.
require "socket"
require "securerandom"
require "openssl"

module OpenSSL
  # OpenSSL::Random.random_bytes, Spinel's openssl package has no Random
  module Random
    def self.random_bytes(count)
      SecureRandom.random_bytes(count)
    end
  end
end

# The part of Resolv sparoid uses: parsing an IP address string and its
# network-order bytes. Spinel has no resolv library.
module Resolv
  # An IPv4 address
  class IPv4
    # Written out: Spinel's case/when doesn't match an interpolated Regexp
    Regex = /\A(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\.(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\.(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\.(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\z/

    def self.create(str)
      raise ArgumentError, "cannot interpret as IPv4 address: #{str}" unless Regex.match?(str)

      new(str.split(".").map(&:to_i).pack("C4"))
    end

    attr_reader :address

    def initialize(address)
      @address = address
    end

    def to_s
      @address.unpack("C4").join(".")
    end
  end

  # An IPv6 address, in full or :: shortened hex form
  class IPv6
    Regex = /\A[0-9A-Fa-f]{0,4}(?::[0-9A-Fa-f]{0,4}){2,7}\z/

    def self.create(str)
      raise ArgumentError, "cannot interpret as IPv6 address: #{str}" unless Regex.match?(str)

      head, tail = str.split("::", 2)
      groups = head.to_s.split(":")
      unless tail.nil?
        rest = tail.split(":")
        groups += Array.new(8 - groups.size - rest.size, "0") + rest
      end
      raise ArgumentError, "cannot interpret as IPv6 address: #{str}" unless groups.size == 8

      new(groups.map(&:hex).pack("n8"))
    end

    attr_reader :address

    def initialize(address)
      @address = address
    end

    def to_s
      @address.unpack("n8").map { |g| g.to_s(16) }.join(":")
    end
  end
end

# AES-256-CBC through libcrypto: Spinel's OpenSSL::Cipher has only the GCM
# ciphers, and sparoid's packet format is AES-256-CBC
module SpinelAES256CBC
  ffi_lib "crypto"
  ffi_source <<~C
    #include <openssl/evp.h>
    static __thread unsigned char spinel_aes_out[1024];
    const char *spinel_aes256cbc_encrypt(const char *key, const char *iv, const char *data, long len) {
      int n1 = 0, n2 = 0, ok = 0;
      if (len < 0 || len > (long)sizeof spinel_aes_out - 16) return NULL;
      EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
      if (!ctx) return NULL;
      ok = EVP_EncryptInit_ex(ctx, EVP_aes_256_cbc(), NULL, (const unsigned char *)key, (const unsigned char *)iv) == 1 &&
           EVP_EncryptUpdate(ctx, spinel_aes_out, &n1, (const unsigned char *)data, (int)len) == 1 &&
           EVP_EncryptFinal_ex(ctx, spinel_aes_out + n1, &n2) == 1;
      EVP_CIPHER_CTX_free(ctx);
      if (!ok) return NULL;
      sp_ffi_bin_len = n1 + n2;
      return (const char *)spinel_aes_out;
    }
  C
  ffi_func :spinel_aes256cbc_encrypt, [:str, :str, :str, :long], :binstr

  # Encrypt with a 32 byte key and a 16 byte IV, answers the ciphertext
  def self.encrypt(key, iv, data)
    raise ArgumentError, "key must be 32 bytes" unless key.bytesize == 32
    raise ArgumentError, "iv must be 16 bytes" unless iv.bytesize == 16

    out = SpinelAES256CBC.spinel_aes256cbc_encrypt(key, iv, data, data.bytesize)
    raise OpenSSL::OpenSSLError, "AES-256-CBC encryption failed" if out.nil?

    out
  end
end

# UDPSocket#sendmsg and #nonblock=, which Spinel's sockets lack
class UDPSocket
  def sendmsg(data, flags, addr)
    send(data, flags, addr.ip_address, addr.ip_port)
  end

  # Spinel's sockets block, a non-blocking call sets O_NONBLOCK for itself
  def nonblock=(_value); end
end

# Passing a file descriptor over a Unix socket (SCM_RIGHTS), what
# `Socket.for_fd(1).sendmsg "\0", 0, nil, Socket::AncillaryData.unix_rights(s)`
# does in CRuby
module SpinelFdpass
  ffi_source <<~C
    #include <string.h>
    #include <sys/socket.h>
    long spinel_fdpass_send(long sock, long fd) {
      char data = 0;
      struct iovec iov = { &data, 1 };
      union { struct cmsghdr align; char buf[CMSG_SPACE(sizeof(int))]; } control;
      memset(&control, 0, sizeof control);
      struct msghdr msg;
      memset(&msg, 0, sizeof msg);
      msg.msg_iov = &iov;
      msg.msg_iovlen = 1;
      msg.msg_control = control.buf;
      msg.msg_controllen = sizeof control.buf;
      struct cmsghdr *cmsg = CMSG_FIRSTHDR(&msg);
      cmsg->cmsg_level = SOL_SOCKET;
      cmsg->cmsg_type = SCM_RIGHTS;
      cmsg->cmsg_len = CMSG_LEN(sizeof(int));
      int f = (int)fd;
      memcpy(CMSG_DATA(cmsg), &f, sizeof f);
      return sendmsg((int)sock, &msg, 0);
    }
    /* SO_ERROR of a socket: 0 once a non-blocking connect succeeded */
    long spinel_socket_error(long fd) {
      int err = 0;
      socklen_t len = sizeof err;
      if (getsockopt((int)fd, SOL_SOCKET, SO_ERROR, &err, &len) != 0) return -1;
      return err;
    }
  C
  ffi_func :spinel_fdpass_send, [:long, :long], :long
  ffi_func :spinel_socket_error, [:long], :long

  # The fd to pass, Socket::AncillaryData.unix_rights(io)
  class Rights
    attr_reader :fd

    def initialize(fd)
      @fd = fd
    end
  end

  # A socket known by its descriptor, Socket.for_fd(fd)
  class FdSocket
    def initialize(fd)
      @fd = fd
    end

    def sendmsg(_data, _flags, _dest, rights)
      raise IOError, "sendmsg failed passing fd #{rights.fd}" if SpinelFdpass.spinel_fdpass_send(@fd, rights.fd).negative?
    end
  end
end

class Socket
  def self.for_fd(fd)
    SpinelFdpass::FdSocket.new(fd)
  end

  # Socket::AncillaryData.unix_rights
  module AncillaryData
    def self.unix_rights(io)
      SpinelFdpass::Rights.new(io.fileno)
    end
  end
end
