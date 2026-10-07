# frozen_string_literal: true

# main.rb for the statically linked Linux build: Ubuntu's libcrypto.a needs
# jitterentropy, zlib and zstd, linked after libcrypto
require_relative "compat"
require_relative "../lib/sparoid/cli"
require_relative "compat_post"

# The libraries libcrypto.a refers to
module StaticLinkLibcrypto
  ffi_lib "jitterentropy"
  ffi_lib "z"
  ffi_lib "zstd"
end

Sparoid::CLI.run
