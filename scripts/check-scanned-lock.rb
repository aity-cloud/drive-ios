#!/usr/bin/env ruby
require "fileutils"
require "json"
require "tmpdir"
require "yaml"

module UI
  def self.user_error!(message)
    raise message
  end
end

root = File.expand_path("..", __dir__)
source = File.read(File.join(root, "fastlane/Fastfile"))
eval(source[/^def aity_restore_scanned_lock.*?^end$/m], TOPLEVEL_BINDING)
Dir.mktmpdir do |directory|
  begin
    aity_restore_scanned_lock(directory)
    raise "Missing inventory was accepted"
  rescue RuntimeError => error
    raise unless error.message.start_with?("Missing scanned Swift lock")
  end
  relative = "build/upstream/ownCloud.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
  scanned = File.join(directory, "vulnerability-source", relative)
  FileUtils.mkdir_p(File.dirname(scanned))
  contents = JSON.generate({"pins" => [{"identity" => "down", "state" => {"revision" => "a" * 40}}]})
  File.binwrite(scanned, contents)
  path, expected = aity_restore_scanned_lock(directory)
  raise "Lock was not restored byte-for-byte" unless File.binread(path) == contents && expected == contents
end
config = YAML.load_file(File.join(root, ".gitlab-ci.yml"), aliases: true)
%w[publish:staging-testflight publish:preprod-testflight promote:production-appstore].each do |job|
  raise "Missing inventory need: #{job}" unless config.fetch(job).fetch("needs").include?("dependency-inventory")
end
%w[skip_package_dependencies_resolution disable_package_automatic_updates].each do |flag|
  raise "Missing Xcode lock enforcement" unless source.include?("#{flag}: true")
end
raise "Missing post-build lock guard" unless source.include?("File.binread(swift_lock) == scanned_swift_lock")
puts "check-scanned-lock: missing inventory refused, exact lock restored, all shipping lanes bound"
