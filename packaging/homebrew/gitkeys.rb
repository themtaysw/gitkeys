# Homebrew cask for GitKeys.
# Lives in the tap repo: github.com/themtaysw/homebrew-gitkeys (Casks/gitkeys.rb).
# The release pipeline replaces SHA256_PLACEHOLDER with the checksum of GitKeys.zip.
cask 'gitkeys' do
  version '0.2.0'
  sha256 'SHA256_PLACEHOLDER'

  url "https://github.com/themtaysw/gitkeys/releases/download/v#{version}/GitKeys.zip"
  name 'GitKeys'
  desc 'Native macOS GUI for SSH config, SSH/GPG keys, and Git host setup'
  homepage 'https://github.com/themtaysw/gitkeys'

  depends_on macos: '>= :ventura'

  app 'GitKeys.app'

  caveats <<~EOS
    GitKeys is open source but not notarized by Apple, so macOS Gatekeeper
    will warn on first launch. Either:

      * Right-click GitKeys.app -> Open -> Open (needed once), or
      * install with: brew install --cask --no-quarantine gitkeys
  EOS
end
