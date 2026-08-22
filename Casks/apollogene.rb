cask "apollogene" do
  version "201b2"
  sha256 "ebd04d65cef41e71672a5fc0f35658f5f6aba6ec43bcdb653cc2d7b2306fa0be"

  url "https://github.com/dtseto/Hermes-master/releases/download/v#{version}/ApolloGene.zip"
  name "ApolloGene"
  desc "Pandora client for Intel and Apple Silicon Macs"
  homepage "https://github.com/dtseto/Hermes-master"

  depends_on macos: :big_sur

  app "ApolloGene.app"

  zap trash: [
    "~/Library/Preferences/com.davidseto.ApolloGene.plist",
    "~/Library/Preferences/com.dtseto.ApolloGene.plist",
    "~/Library/Saved Application State/com.davidseto.ApolloGene.savedState",
    "~/Library/Saved Application State/com.dtseto.ApolloGene.savedState",
  ]
end
