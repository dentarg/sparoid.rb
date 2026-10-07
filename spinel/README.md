# sparoid compiled with Spinel

[Spinel](https://github.com/matz/spinel) compiles Ruby ahead of time to C
and a native executable. This directory builds sparoid's CLI with it: one
executable that needs no Ruby.

| Platform | Linking |
|---|---|
| Linux x86_64, arm64 | static: runs on any distribution, glibc or musl |
| macOS x86_64, arm64 | OpenSSL linked in from Homebrew's `openssl@3`, the rest from the system |

The `Binaries` workflow builds all four on a `v*` tag and attaches
`sparoid-VERSION-OS-ARCH.tar.gz` and `SHA256SUMS` to the tag's GitHub
release. It also runs on pull requests that touch `lib/` or this
directory.

## Build

`spinel-version` pins the Spinel commit. On Linux, in an `ubuntu:26.04`
container (it installs the compiler and static libraries it needs):

    docker run --rm -v "$PWD:/src" -w /src ubuntu:26.04 bash spinel/build-in-ubuntu.sh

On macOS, with Xcode's command line tools and `brew install openssl@3`:

    bash spinel/install-spinel.sh   # Spinel into build/spinel
    bash spinel/build.sh

`build.sh` writes `build/sparoid` and the tarball in `dist/`. It fails
unless the executable is linked as above, prints the version, and
generates keys.

## Compatibility layer

Spinel compiles a subset of Ruby. `main.rb` loads sparoid's CLI between
two layers. `compat.rb` is loaded before sparoid and adds what Spinel
lacks. `compat_post.rb` is loaded after it and replaces sparoid methods
that need something Spinel doesn't have:

| Missing in Spinel | Replacement |
|---|---|
| `resolv` | `Resolv::IPv4` / `IPv6`: `Regex`, `create`, `#address`, `#to_s` |
| `OpenSSL::Cipher` AES-256-CBC (only the GCM ciphers) | libcrypto's EVP through `ffi_source`, in `encrypt` and `keygen` |
| `OpenSSL::Random.random_bytes` | `SecureRandom.random_bytes` |
| `UDPSocket#sendmsg`, `#nonblock=` | `#send(data, flags, host, port)`, a no-op |
| `Addrinfo.getaddrinfo`, the `ipv6_*` predicates | `Socket.getaddrinfo` in `resolve_ip_addresses`, `global_ipv6?` on the bytes |
| `Socket.for_fd(1).sendmsg` with `AncillaryData.unix_rights` | `sendmsg` with `SCM_RIGHTS` through `ffi_source` |

It also works around these Spinel bugs:

- `case`/`when` doesn't match a Regexp built with interpolation, so the
  IPv4 pattern is written out.
- `Socket.getaddrinfo` ignores its socktype argument, so the rows are
  filtered.
- `File.readlines` doesn't raise `Errno::ENOENT`, so `parse_ini` checks
  `File.exist?`.
- A Socket read out of an Array has no `connect_nonblock` or
  `getsockopt`, so `fdpass` reads `SO_ERROR` off `#fileno`.

rubocop skips this directory: its suggestions can use methods Spinel
lacks. The gem leaves it out.
