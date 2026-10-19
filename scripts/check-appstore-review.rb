#!/usr/bin/env ruby
# The App Review lanes (prepare:appstore-review, submit:appstore-review)
# against a fake App Store Connect: the real fastlane/Fastfile is loaded under
# a stdlib-only DSL shim and Spaceship is replaced by the models below, so
# every write a lane makes is recorded and nothing reaches Apple. The lint
# image has ruby and no gems, hence no fastlane, no json.
#
# What it cannot see: Apple's real state transitions, Spaceship's HTTP layer
# and timing. The first run against Apple is prepare's read-only preflight.

require "digest"
require "fileutils"
require "tmpdir"

REPO = File.expand_path("..", __dir__)
NOTES = File.read(File.join(REPO, "fastlane", "review", "notes.txt"))
TARGET_BUILD = "afe4e712-8825-45ce-8714-48fcc59d66e9"
OLD_BUILD = "old-build-60"
SUBMISSION = "4877e3a4-d90c-4eee-ada0-c5bee79727f6"

class UserError < StandardError; end

module UI
  def self.log = ($log ||= [])
  def self.user_error!(message) = raise(UserError, message)
  %i[message success important error header verbose].each do |level|
    define_singleton_method(level) { |text| log << text.to_s }
  end
end

class AppleError < StandardError; end

# A fake App Store Connect. Every write is appended to `writes`; reads return
# the live objects, so a lane re-reading sees what its writes did.
class World
  attr_accessor :app, :builds, :versions, :detail, :submissions, :items, :writes, :sleeps,
                :refuse_submit, :stuck, :deliver_calls

  def initialize
    @writes = []
    @sleeps = []
    @deliver_calls = []
    @app = Fake.new(id: "app-1", bundle_id: "tech.aity.drive")
    target = Fake.new(id: TARGET_BUILD, version: "80", processing_state: "VALID", expired: false,
                      uses_non_exempt_encryption: false, app: @app,
                      pre_release_version: Fake.new(version: "12.7.1", platform: "IOS"))
    @builds = { TARGET_BUILD => target, OLD_BUILD => Fake.new(id: OLD_BUILD, version: "60") }
    @versions = [Fake.new(id: "version-1", version_string: "1.0", app_version_state: "REJECTED",
                          release_type: "AFTER_APPROVAL", earliest_release_date: nil, build: @builds[OLD_BUILD])]
    @detail = Fake.new(id: "detail-1", notes: "the 1.0 (60) notes", demo_account_required: true,
                       demo_account_name: "demo@aity.tech", demo_account_password: "secret",
                       contact_first_name: "Raul", contact_last_name: "Bag",
                       contact_email: "office@aity.ro", contact_phone: "+40000000000",
                       app_store_review_attachments: [Fake.new(id: "att-1", file_name: "background-audio.mov")])
    @submissions = [Fake.new(id: SUBMISSION, state: "UNRESOLVED_ISSUES", platform: "IOS", submitted_date: nil)]
    @items = { SUBMISSION => [Fake.new(id: "item-1", state: "REJECTED", app_store_version: version)] }
  end

  def version = @versions.first
  def submission = @submissions.first
end

class Fake
  def initialize(**attributes)
    @attributes = attributes
  end

  def method_missing(name, *args)
    key = name.to_s.delete_suffix("=").to_sym
    return @attributes[key] = args.first if name.to_s.end_with?("=")
    return @attributes[key] if @attributes.key?(key)

    super
  end

  def respond_to_missing?(name, include_private = false)
    name.to_s.end_with?("=") || @attributes.key?(name) || super
  end

  # AppStoreVersion
  def select_build(build_id:)
    $world.writes << [:select_build, build_id]
    self.build = $world.builds.fetch(build_id)
  end

  def update(attributes:)
    $world.writes << [@attributes.key?(:version_string) ? :update_version : :update_detail, attributes]
    attributes.each { |key, value| @attributes[key] = value }
  end

  def fetch_app_store_review_detail(**) = $world.detail

  # AppStoreReviewAttachment
  def delete!
    $world.writes << [:delete_attachment, file_name]
    $world.detail.app_store_review_attachments.delete(self)
  end

  # App
  def get_app_store_versions(filter:, **)
    $world.versions.select { |v| v.version_string == filter[:versionString] }
  end

  def get_review_submissions(filter:, **)
    states = filter[:state].split(",")
    $world.submissions.select { |s| s.platform == filter[:platform] && states.include?(s.state) }
  end

  def create_review_submission(platform:)
    created = Fake.new(id: "submission-new", state: "READY_FOR_REVIEW", platform: platform, submitted_date: nil)
    $world.writes << [:create_submission, platform]
    $world.submissions << created
    $world.items[created.id] = []
    created
  end

  # ReviewSubmission
  def add_app_store_version_to_review_items(app_store_version_id:)
    $world.writes << [:add_item, id, app_store_version_id]
    $world.items[id] << Fake.new(id: "item-new", state: "READY_FOR_REVIEW", app_store_version: $world.version)
    $world.version.app_version_state = "READY_FOR_REVIEW"
  end

  def submit_for_review
    $world.writes << [:submit, id]
    if $world.refuse_submit
      raise AppleError, "The request cannot be fulfilled because of the state of another resource. - " \
                        "associatedErrors: App Privacy answers are missing"
    end
    return if $world.stuck

    self.state = "WAITING_FOR_REVIEW"
    self.submitted_date = "2026-10-19T12:00:00Z"
    $world.version.app_version_state = "WAITING_FOR_REVIEW"
  end
end

class RequestClient
  def patch(path, body)
    $world.writes << [:patch, path, body]
    item = $world.items.values.flatten.find { |i| path == "v1/reviewSubmissionItems/#{i.id}" }
    item.state = "READY_FOR_REVIEW"
    $world.version.app_version_state = "READY_FOR_REVIEW"
  end
end

module Spaceship
  class ConnectAPI
    class << self
      attr_accessor :token
    end

    def self.client = Struct.new(:tunes_request_client).new(RequestClient.new)

    class Token
      def self.create(**) = :token
    end

    class App
      def self.find(bundle_id) = ($world.app if $world.app.bundle_id == bundle_id)
    end

    class Build
      def self.get(build_id:, **) = $world.builds[build_id]
    end

    class AppStoreVersion
      def self.get(app_store_version_id:, **) = $world.versions.find { |v| v.id == app_store_version_id }
    end

    class ReviewSubmission
      def self.get(review_submission_id:, **) = $world.submissions.find { |s| s.id == review_submission_id }
    end

    class ReviewSubmissionItem
      def self.all(review_submission_id:, **) = $world.items.fetch(review_submission_id)
    end
  end
end

# The fastlane DSL, as far as loading the Fastfile and running a lane needs.
class Runner
  attr_reader :lanes

  def initialize
    @lanes = {}
  end

  def default_platform(_) = nil
  def platform(_) = yield
  def desc(_) = nil
  def lane(name, &block) = (@lanes[name] = block)

  def private_lane(name, &block)
    define_singleton_method(name) { |options = {}| instance_exec(options, &block) }
  end

  def deliver(**options) = $world.deliver_calls << options
  def sleep(seconds) = $world.sleeps << seconds

  def run(name)
    lane = @lanes[name] or raise KeyError, "lane #{name} does not exist"
    instance_exec({}, &lane)
  end
end

# The Fastfile runs from build/upstream/fastlane of a materialised tree and
# reads fastlane/review from the factory root above it.
TMP = Dir.mktmpdir("check-appstore-review")
at_exit { FileUtils.rm_rf(TMP) }
TREE = File.join(TMP, "build", "upstream")
FileUtils.mkdir_p(File.join(TREE, "fastlane"))
File.symlink(File.join(REPO, "fastlane"), File.join(TMP, "fastlane"))
FASTFILE = File.join(TREE, "fastlane", "Fastfile")
FileUtils.cp(File.join(REPO, "fastlane", "Fastfile"), FASTFILE)
RUNNER = Runner.new
RUNNER.instance_eval(File.read(FASTFILE), FASTFILE)

BASE_ENV = {
  "ASC_KEY_ID" => "KEY", "ASC_ISSUER_ID" => "ISSUER", "ASC_KEY_P8" => "/dev/null",
  "AITY_REVIEW_VERSION" => "1.0", "AITY_REVIEW_BUILD_NUMBER" => "80", "AITY_REVIEW_BUILD_ID" => TARGET_BUILD
}.freeze

# Runs one lane in the world; returns [error message or nil, log lines].
def play(lane, env: {}, environment: "production")
  File.write(File.join(TREE, ".aity-environment"), environment)
  saved = ENV.to_h
  %w[VERBOSE SPACESHIP_DEBUG].each { |var| ENV.delete(var) }
  BASE_ENV.merge(env).each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  $log = []
  error = nil
  begin
    RUNNER.run(lane)
  rescue UserError, AppleError => e
    error = e.message
  ensure
    ENV.replace(saved)
  end
  [error, $log.dup]
end

def fresh(&setup)
  $world = World.new
  setup&.call($world)
  $world
end

def receipt(log, tag) = log.grep(/\A#{tag} /)

$failures = []
$cases = 0

def check(name)
  $cases += 1
  yield
  puts "  ok   #{name}"
rescue StandardError => e
  $failures << name
  puts "  FAIL #{name}: #{e.message}"
end

def expect(condition, message)
  raise message unless condition
end

PREPARE = :aity_prepare_appstore_review
SUBMIT = :aity_submit_appstore_review
EXPECTED_PREPARE_WRITES = [
  [:select_build, TARGET_BUILD],
  [:update_version, { release_type: "MANUAL", earliest_release_date: nil }],
  [:update_detail, { notes: NOTES }],
  [:delete_attachment, "background-audio.mov"]
].freeze
RESOLVE = [:patch, "v1/reviewSubmissionItems/item-1",
           { data: { type: "reviewSubmissionItems", id: "item-1", attributes: { resolved: true } } }].freeze

puts "check-appstore-review: the App Review lanes against a fake App Store Connect"

check "prepare selects the exact build, MANUAL with no date, notes from the file, deletes attachments" do
  world = fresh
  error, log = play(PREPARE)
  expect(error.nil?, "prepare failed: #{error}")
  expect(world.writes == EXPECTED_PREPARE_WRITES, "writes were #{world.writes.inspect}")
  ready = receipt(log, "AITY_REVIEW_READY")
  expect(ready.length == 1, "want one AITY_REVIEW_READY line, got #{ready.inspect}")
  %W[build=80 build_id=#{TARGET_BUILD} marketing=12.7.1 release=MANUAL release_date=none
     notes_sha256=#{Digest::SHA256.hexdigest(NOTES)} attachments=0 demo=present contact=present
     version=1.0 version_id=version-1 path=resubmit:#{SUBMISSION}].each do |field|
    expect(ready.first.split.include?(field), "READY line lacks #{field}: #{ready.first}")
  end
  expect(receipt(log, "AITY_REVIEW_WRITE").length == 4, "want four AITY_REVIEW_WRITE lines")
end

check "prepare leaves demo account and contact alone and never prints them" do
  world = fresh
  _, log = play(PREPARE)
  expect(world.detail.demo_account_name == "demo@aity.tech" && world.detail.demo_account_required == true,
         "demo account changed")
  expect(world.detail.contact_email == "office@aity.ro", "contact changed")
  expect(log.none? { |line| line.include?("secret") || line.include?("demo@aity.tech") || line.include?("+40000000000") },
         "a review detail value was printed")
end

check "prepare is idempotent: a prepared record gets no write" do
  world = fresh
  play(PREPARE)
  world.writes.clear
  error, log = play(PREPARE)
  expect(error.nil? && world.writes.empty?, "second prepare: #{error.inspect} #{world.writes.inspect}")
  expect(receipt(log, "AITY_REVIEW_READY").length == 1, "no READY line on the second run")
end

check "the listing lane keeps submit_for_review: false" do
  fresh
  File.write(File.join(TREE, ".aity-environment"), "production")
  RUNNER.aity_deliver_listing(api_key: :key)
  calls = $world.deliver_calls
  expect(calls.length == 1 && calls.first[:submit_for_review] == false, "deliver got #{calls.map { |c| c[:submit_for_review] }.inspect}")
end

# Every refusal of the preflight and of the path table, for both lanes, with
# nothing written.
REFUSALS = {
  "VERBOSE set" => [{ "VERBOSE" => "1" }, nil],
  "SPACESHIP_DEBUG set" => [{ "SPACESHIP_DEBUG" => "1" }, nil],
  "staging tree" => [{ environment: "staging" }, nil],
  "ASC key missing" => [{ "ASC_KEY_P8" => nil }, nil],
  "build id missing" => [{ "AITY_REVIEW_BUILD_ID" => nil }, nil],
  "build number latest" => [{ "AITY_REVIEW_BUILD_NUMBER" => "latest" }, nil],
  "build number blank" => [{ "AITY_REVIEW_BUILD_NUMBER" => " " }, nil],
  "build number not the build's" => [{ "AITY_REVIEW_BUILD_NUMBER" => "81" }, nil],
  "build id unknown" => [{ "AITY_REVIEW_BUILD_ID" => "nope" }, nil],
  "build of another app" => [{}, ->(w) { w.builds[TARGET_BUILD].app = Fake.new(id: "app-2", bundle_id: "tech.aity.drive.staging") }],
  "build not IOS" => [{}, ->(w) { w.builds[TARGET_BUILD].pre_release_version.platform = "MAC_OS" }],
  "build processing" => [{}, ->(w) { w.builds[TARGET_BUILD].processing_state = "PROCESSING" }],
  "build expired" => [{}, ->(w) { w.builds[TARGET_BUILD].expired = true }],
  "encryption unanswered" => [{}, ->(w) { w.builds[TARGET_BUILD].uses_non_exempt_encryption = nil }],
  "non-exempt encryption" => [{}, ->(w) { w.builds[TARGET_BUILD].uses_non_exempt_encryption = true }],
  "no version 1.0" => [{ "AITY_REVIEW_VERSION" => "1.1" }, nil],
  "no review detail" => [{}, ->(w) { w.detail = nil }],
  "demo account not required" => [{}, ->(w) { w.detail.demo_account_required = false }],
  "demo account name missing" => [{}, ->(w) { w.detail.demo_account_name = "" }],
  "contact phone missing" => [{}, ->(w) { w.detail.contact_phone = nil }],
  "contact email missing" => [{}, ->(w) { w.detail.contact_email = " " }],
  "foreign item" => [{}, ->(w) { w.items[SUBMISSION] << Fake.new(id: "item-x", state: "READY_FOR_REVIEW", app_store_version: nil) }],
  "item for another version" => [{}, ->(w) { w.items[SUBMISSION].first.app_store_version = Fake.new(id: "version-0") }],
  "two open submissions" => [{}, lambda { |w|
    w.submissions << Fake.new(id: "other", state: "READY_FOR_REVIEW", platform: "IOS")
    w.items["other"] = []
  }],
  "submission CANCELING" => [{}, ->(w) { w.submission.state = "CANCELING" }],
  "submission COMPLETING" => [{}, ->(w) { w.submission.state = "COMPLETING" }],
  "rejected version without its submission" => [{}, ->(w) { w.submissions.clear }],
  "rejected version in a draft submission" => [{}, ->(w) { w.submission.state = "READY_FOR_REVIEW" }],
  "version READY_FOR_SALE" => [{}, ->(w) { w.version.app_version_state = "READY_FOR_SALE" }],
  "new version under an unresolved submission" => [{}, ->(w) { w.version.app_version_state = "PREPARE_FOR_SUBMISSION" }],
  "in review with another build" => [{}, lambda { |w|
    w.version.app_version_state = "WAITING_FOR_REVIEW"
    w.version.release_type = "MANUAL"
    w.submission.state = "WAITING_FOR_REVIEW"
  }],
  "approved but released automatically" => [{}, lambda { |w|
    w.version.app_version_state = "PENDING_DEVELOPER_RELEASE"
    w.version.build = w.builds[TARGET_BUILD]
    w.submissions.clear
  }]
}.freeze

REFUSALS.each do |name, (env, setup)|
  [PREPARE, SUBMIT].each do |lane|
    check "#{lane == PREPARE ? 'prepare' : 'submit'} refuses before any write: #{name}" do
      world = fresh(&setup)
      environment = env.fetch(:environment, "production")
      error, log = play(lane, env: env.except(:environment), environment: environment)
      expect(error, "the lane did not stop")
      expect(world.writes.empty?, "it wrote #{world.writes.inspect}")
      expect(receipt(log, "AITY_REVIEW_READY").empty? && receipt(log, "AITY_REVIEW_SUBMITTED").empty?, "it printed a receipt")
    end
  end
end

check "prepare refuses a resolved item: the version is submit's after a resolve" do
  world = fresh do |w|
    w.version.app_version_state = "READY_FOR_REVIEW"
    w.items[SUBMISSION].first.state = "READY_FOR_REVIEW"
  end
  error, = play(PREPARE)
  expect(error && world.writes.empty?, "#{error.inspect} #{world.writes.inspect}")
end

check "the path table refusal names the state it found" do
  fresh { |w| w.submission.state = "CANCELING" }
  error, = play(PREPARE)
  expect(error.to_s.include?("CANCELING") && error.include?(SUBMISSION), "message was: #{error}")
end

check "submit refuses an unprepared record: play prepare:appstore-review first" do
  world = fresh
  error, = play(SUBMIT)
  expect(error.to_s.include?("play prepare:appstore-review first"), "message was: #{error.inspect}")
  expect(world.writes.empty?, "it wrote #{world.writes.inspect}")
end

check "submit refuses a record whose notes changed after prepare" do
  world = fresh
  play(PREPARE)
  world.detail.notes = "edited by hand"
  world.writes.clear
  error, = play(SUBMIT)
  expect(error.to_s.include?("play prepare:appstore-review first") && world.writes.empty?, "#{error.inspect} #{world.writes.inspect}")
end

check "resubmit: resolve the rejected item, then submit that same submission" do
  world = fresh
  play(PREPARE)
  world.writes.clear
  error, log = play(SUBMIT)
  expect(error.nil?, "submit failed: #{error}")
  expect(world.writes == [RESOLVE, [:submit, SUBMISSION]], "writes were #{world.writes.inspect}")
  submitted = receipt(log, "AITY_REVIEW_SUBMITTED")
  expect(submitted.length == 1, "want one AITY_REVIEW_SUBMITTED line, got #{submitted.inspect}")
  %W[submission=#{SUBMISSION} state=WAITING_FOR_REVIEW version_state=WAITING_FOR_REVIEW
     build_id=#{TARGET_BUILD} release=MANUAL release_date=none submitted=2026-10-19T12:00:00Z].each do |field|
    expect(submitted.first.split.include?(field), "SUBMITTED line lacks #{field}: #{submitted.first}")
  end
end

check "a refused submit is not retried; the replay finds the item resolved and only submits" do
  world = fresh
  play(PREPARE)
  world.writes.clear
  world.refuse_submit = true
  error, log = play(SUBMIT)
  expect(error, "a refused submit did not fail the lane")
  expect(world.writes == [RESOLVE, [:submit, SUBMISSION]], "writes were #{world.writes.inspect}")
  expect(log.any? { |line| line.include?("App Privacy answers are missing") }, "Apple's error body was not printed")
  world.writes.clear
  world.refuse_submit = false
  error, = play(SUBMIT)
  expect(error.nil?, "replay failed: #{error}")
  expect(world.writes == [[:submit, SUBMISSION]], "replay writes were #{world.writes.inspect}")
end

check "new: create a review submission, add version 1.0, submit" do
  world = fresh do |w|
    w.version.app_version_state = "PREPARE_FOR_SUBMISSION"
    w.submissions.clear
  end
  error, log = play(PREPARE)
  expect(error.nil? && receipt(log, "AITY_REVIEW_READY").first.to_s.split.include?("path=new"), "prepare: #{error.inspect} #{log.last}")
  world.writes.clear
  error, = play(SUBMIT)
  expect(error.nil?, "submit failed: #{error}")
  expect(world.writes == [[:create_submission, "IOS"], [:add_item, "submission-new", "version-1"], [:submit, "submission-new"]],
         "writes were #{world.writes.inspect}")
end

check "draft: an empty READY_FOR_REVIEW submission gets version 1.0 and is submitted" do
  world = fresh do |w|
    w.version.app_version_state = "DEVELOPER_REJECTED"
    w.submission.state = "READY_FOR_REVIEW"
    w.items[SUBMISSION] = []
  end
  error, log = play(PREPARE)
  expect(error.nil? && receipt(log, "AITY_REVIEW_READY").first.to_s.split.include?("path=draft:#{SUBMISSION}"), "prepare: #{error.inspect}")
  world.writes.clear
  error, = play(SUBMIT)
  expect(error.nil?, "submit failed: #{error}")
  expect(world.writes == [[:add_item, SUBMISSION, "version-1"], [:submit, SUBMISSION]], "writes were #{world.writes.inspect}")
end

check "draft holding version 1.0 already: submit only" do
  world = fresh do |w|
    w.version.app_version_state = "READY_FOR_REVIEW"
    w.submission.state = "READY_FOR_REVIEW"
    w.items[SUBMISSION].first.state = "READY_FOR_REVIEW"
  end
  play(PREPARE)
  world.writes.clear
  error, = play(SUBMIT)
  expect(error.nil? && world.writes == [[:submit, SUBMISSION]], "#{error.inspect} #{world.writes.inspect}")
end

check "already submitted: verified, nothing written, by both lanes" do
  [PREPARE, SUBMIT].each do |lane|
    world = fresh do |w|
      w.version.app_version_state = "IN_REVIEW"
      w.version.release_type = "MANUAL"
      w.version.build = w.builds[TARGET_BUILD]
      w.submission.state = "IN_REVIEW"
    end
    error, log = play(lane)
    expect(error.nil? && world.writes.empty?, "#{lane}: #{error.inspect} #{world.writes.inspect}")
    expect(receipt(log, "AITY_REVIEW_ALREADY_SUBMITTED").length == 1, "#{lane}: no AITY_REVIEW_ALREADY_SUBMITTED line")
  end
end

check "approved: verified, nothing written, by both lanes" do
  [PREPARE, SUBMIT].each do |lane|
    world = fresh do |w|
      w.version.app_version_state = "PENDING_DEVELOPER_RELEASE"
      w.version.release_type = "MANUAL"
      w.version.build = w.builds[TARGET_BUILD]
      w.submissions.clear
    end
    error, log = play(lane)
    expect(error.nil? && world.writes.empty?, "#{lane}: #{error.inspect} #{world.writes.inspect}")
    expect(receipt(log, "AITY_REVIEW_APPROVED").length == 1, "#{lane}: no AITY_REVIEW_APPROVED line")
  end
end

check "a read-back that never reaches WAITING_FOR_REVIEW exits non-zero after ten minutes, no further write" do
  world = fresh
  play(PREPARE)
  world.writes.clear
  world.sleeps.clear
  world.stuck = true
  error, log = play(SUBMIT)
  expect(error, "the lane did not fail")
  expect(world.writes == [RESOLVE, [:submit, SUBMISSION]], "writes were #{world.writes.inspect}")
  expect(world.sleeps.count(30) * 30 >= 600 && world.sleeps.count(30) * 30 <= 630, "read-back slept #{world.sleeps.inspect}")
  expect(receipt(log, "AITY_REVIEW_SUBMITTED").empty?, "it printed AITY_REVIEW_SUBMITTED")
  expect(error.include?("UNRESOLVED_ISSUES"), "the last state is not in the message: #{error}")
end

puts
if $failures.empty?
  puts "check-appstore-review: OK - #{$cases} cases"
  exit 0
end
missing = [PREPARE, SUBMIT].reject { |lane| RUNNER.lanes.key?(lane) }
warn "check-appstore-review: FAIL - #{$failures.length} of #{$cases} cases"
warn "missing lanes: #{missing.join(', ')}" unless missing.empty?
exit 1
