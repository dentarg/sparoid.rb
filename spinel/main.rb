# frozen_string_literal: true

# The sparoid executable as Spinel compiles it: sparoid's CLI between the
# compatibility layers (spinel/README.md)
require_relative "compat"
require_relative "../lib/sparoid/cli"
require_relative "compat_post"

Sparoid::CLI.run
