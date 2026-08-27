#!/usr/bin/env ruby
# Guards against a Ruby trap that faked a green smoke on 2026-08-27.
#
# In Ruby, a `#` comment on the line after a backslash line-continuation does
# not continue the expression - it ENDS it, and every following string literal
# is parsed as a separate, discarded expression. `ruby -c` is happy; the value
# is simply truncated. In the smoke lane that turned
#
#     "set -o pipefail; " \
#       # a helpful explanation
#       "xcodebuild test ... > log 2>&1"
#
# into `set -o pipefail; VAR=x VAR=y` - an assignment-only shell line that
# exits 0 without running anything - so the lane reported 1/1 green having
# never launched a test.
#
# Comments belong ABOVE the assignment, or the command belongs in an array.
src = File.read(File.expand_path("../fastlane/Fastfile", __dir__))
offenders = []
src.each_line.with_index(1) do |line, number|
  offenders << number if line.rstrip.end_with?("\\")
end
offenders.select! do |number|
  next_line = src.lines[number] # zero-based: the line AFTER the continuation
  next_line && next_line.strip.start_with?("#")
end

if offenders.empty?
  puts "check-fastfile: OK - no backslash continuation is followed by a comment"
  exit 0
end

warn "check-fastfile: FAIL - a backslash line-continuation is followed by a comment"
warn "This silently truncates the expression (see the header of this script)."
offenders.each { |number| warn "  fastlane/Fastfile:#{number}" }
exit 1
