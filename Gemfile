# Copied over the Pin's Gemfile by scripts/materialize.sh - identical
# dependency set (fastlane + the Pin's Pluginfile: appicon, badge, json),
# ours only so the recipe is self-contained and reviewable in the Factory.
source "https://rubygems.org"

gem "fastlane"
# gym's default xcodebuild formatter. Without it gym still PIPES to it under
# pipefail, so its absence surfaces as a bogus "ARCHIVE FAILED" (exit 127).
gem "xcpretty"

plugins_path = File.join(File.dirname(__FILE__), "fastlane", "Pluginfile")
eval_gemfile(plugins_path) if File.exist?(plugins_path)
