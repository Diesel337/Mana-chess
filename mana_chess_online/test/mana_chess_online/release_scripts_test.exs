defmodule ManaChessOnline.ReleaseScriptsTest do
  use ExUnit.Case, async: true

  @scripts ~w(compare-persistence-reports migrate server verify-persistence)

  test "Unix release scripts use LF line endings" do
    scripts_dir = Path.expand("../../rel/overlays/bin", __DIR__)

    Enum.each(@scripts, fn script ->
      contents = File.read!(Path.join(scripts_dir, script))

      assert String.starts_with?(contents, "#!/bin/sh\n"),
             "#{script} must start with a POSIX shell shebang"

      refute String.contains?(contents, "\r"),
             "#{script} must use LF line endings so it runs in the Linux release image"
    end)
  end
end
