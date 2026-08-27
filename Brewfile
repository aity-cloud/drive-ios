# Host tooling the Mac runner installs at job time (mac-runner.md: only
# Xcode, ruby/bundler and the Android SDK live on the host; everything
# else comes from the Factory). `brew bundle` in the CI job scripts.
brew "xcodegen"   # generates smoke/AityDriveSmoke.xcodeproj from project.yml
brew "xcbeautify"  # gym pipes xcodebuild through it; a Homebrew binary is on PATH
                   # for the plain `sh` gym shells out to, which a bundled gem is not
