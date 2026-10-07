# frozen_string_literal: true

require "test_helper"
require "sparoid/cli"

class CLITest < Minitest::Test
  def test_connect_passes_its_options_on
    config = Tempfile.new("sparoid.ini")
    config.write("key = k\nhmac-key = h\n")
    config.flush
    auth_args = fdpass_args = nil
    Sparoid.stub(:auth, ->(*a) { auth_args = a and [:ip] }) do
      Sparoid.stub(:fdpass, ->(*a) { fdpass_args = a }) do
        Sparoid::CLI.run(["connect", "-h", "example.com", "-p", "1234", "-P", "2222", "-c", config.path])
      end
    end

    assert_equal ["k", "h", "example.com", 1234], auth_args
    assert_equal [[:ip], 2222], fdpass_args
  end
end
