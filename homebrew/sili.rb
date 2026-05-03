class Sili < Formula
  desc     "Codespace resource manager with auto-tunnel"
  homepage "https://github.com/osortega/sili"
  url      "https://github.com/osortega/sili/archive/refs/tags/v0.1.0.tar.gz"
  sha256   "REPLACE_WITH_SHA256_FROM_CURL"
  license  "MIT"

  depends_on "gh"

  def install
    libexec.install "bin", "lib"
    bin.install_symlink libexec/"bin/sili"
  end

  test do
    assert_match "sili", shell_output("#{bin}/sili help")
  end
end
