# Copied over the Pin's Gemfile by scripts/materialize.sh - identical
# dependency set (fastlane + the Pin's Pluginfile: appicon, badge, json),
# ours only so the recipe is self-contained and reviewable in the Factory.
source "https://rubygems.org"

gem "fastlane"

plugins_path = File.join(File.dirname(__FILE__), "fastlane", "Pluginfile")
eval_gemfile(plugins_path) if File.exist?(plugins_path)
