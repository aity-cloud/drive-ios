# App Review - what Apple asked, what we changed, what we answer

The App Review record of Aity Drive (`tech.aity.drive`), the same way
`PRIVACY.md` records the App Privacy answers. The App Review notes are
`fastlane/review/notes.txt`, set on the version by `prepare:appstore-review`.
The demo account and the contact stay only in App Store Connect and are never
written here (spec decision 17); the lanes check they are present and never
print or change them.

## 1.0 (60) - rejected 2026-10-01, submission 4877e3a4-d90c-4eee-ada0-c5bee79727f6

Answered in the Resolution Center on 2026-10-08 (text in `aa26078`): the
4.8 business-app exemption and a device recording of background audio. That
position was dropped on 2026-10-13 for the resubmission below.

Build 60 is pipeline #60 (`2848074753`), job `publish:preprod-testflight`
16492159632, main `ecff830`, Pin `owncloud/ios-app` v12.7.0 (`3fac7ea`),
ios-sdk `275bad5`. Reviewed on an iPhone 17 Pro Max. Its compiled
`Info.plist` declared `UIBackgroundModes = [audio, fetch, location]` and all
three location usage strings, because `build.flags` did not carry upstream's
`DISABLE_BACKGROUND_LOCATION`.

### 4.8 Login Services

Apple saw "Continue with Google / Microsoft / GitHub" on the sign-in page.
That page is Aity's own Keycloak (`auth.aity.tech`, client `drive-ios`,
public PKCE). Verified on 2026-10-08:

- the app has no sign-up: Keycloak refuses registration for `drive-ios`
  (`/registrations` answers 403 on `auth.aity.tech` and `auth.aity.works`)
  and the page shows no "Create an account" link;
- the listing says so: "Aity Drive needs an Aity workspace account. It is
  not a standalone storage service and there is no sign-up in the app."

NOT verified: that a Google/Microsoft/GitHub identity with no existing
account is refused for `drive-ios`. The guard exists
(`aity-broker-create-user-if-allowed`, infra/keycloak `5cdfc39`), but its
e2e (`aity-broker-registration`) is red on keycloak main and the production
flow binding was not read back. The resubmission hides the providers for
`drive-ios` instead (below).

No change to the app on 2026-10-08. Answer: the business-app exemption of
4.8. Not added, by decision (Raul, 2026-10-08): Sign in with Apple, consumer
registration.

### 2.5.4 - UIBackgroundModes `location`

Upstream's only location use is an opt-in "Background uploads (Lab
Version) > Use background location updates" switch: it asks for Always
authorization and uses visit monitoring purely to wake the app for photo
upload. It is not a location feature, and Apple's own 5.1.5 wants location
only where it is directly relevant. Removed with upstream's own build flag
`DISABLE_BACKGROUND_LOCATION` (Branding, no patch): the switch, the
CoreLocation code, the three `NSLocation*` strings and the `location` mode
are gone. Automatic photo upload stays, on background refresh.

### 2.5.4 - UIBackgroundModes `audio`

Kept on 2026-10-08 as a real feature: opening an audio or video file plays
it with `AVPlayer` under the `.playback` session, publishes Now Playing info
and handles the lock-screen / Control Center transport commands
(`MediaDisplayViewController`); playback continued after Home. Apple wanted
a recording from a PHYSICAL device showing exactly that. Removed for the
resubmission instead (below).

### Found on the way, fixed in the same change

`scripts/debrand-strings.py` rewrote "ownCloud" inside identifiers, so build
60 shipped `com.Aity Drive.background-refresh-task` (background refresh was
never scheduled: the code registers `com.owncloud.background-refresh-task`),
`com.Aity Drive.FileProviderUI.Share` (the Files app "Share" action matched
nothing) and `com.Aity Drive.captureRestoreActivityType` (window state
restoration). Identifiers are now left alone; `lint` fails if one is touched.

## 1.0 (80) - resubmission, decided 2026-10-13

Raul decided not to wait for App Review's answer and to remove what it
flagged instead of arguing for it (decision 19 of
`drive/meta/specs/aity-drive-v1.md`). Version 1.0 is resubmitted with build
80, set to "Manually release this version", so the release to the public
listing stays Promote.

- **4.8.** The sign-in page shows no identity-provider buttons for client
  `drive-ios`: email and password only (the `aity` login theme in
  `keycloak`; every other client is unchanged). With no third-party login
  offered, 4.8 does not apply. No Sign in with Apple: Keycloak has no
  supported Apple provider, and a reviewer without a workspace account
  could not complete it anyway.
- **2.5.4 `audio`.** Removed. Upstream declares it with no flag, so
  `aity_apply_identity` deletes the entry and fails the build when a Pin
  moves it; both build lanes then fail unless the compiled `Info.plist`
  says `UIBackgroundModes = [fetch]` with no `NSLocation*` key. Audio and
  video still play in the foreground; leaving the app ends playback. The
  smoke stage and the demo WAV that proved background audio are gone, and
  no App Review attachment is sent.
- **2.5.4 `location`.** Removed by the 1.0 (60) fix above; this build is the
  first compiled binary that carries it.

Before submitting, read the IPA of `publish:preprod-testflight` back:

```sh
plutil -extract UIBackgroundModes json -o - Payload/*.app/Info.plist   # ["fetch"]
plutil -p Payload/*.app/Info.plist | grep -c NSLocation               # 0
```

### Build 80

Pipeline #80 (`2960401594`), job `publish:preprod-testflight` 17265858376,
main `a951ee9`, Pin `owncloud/ios-app` v12.7.1 (`dd72d0d`), ios-sdk
`7648ca8`. Uploaded to TestFlight internal only. App Store Connect build id
`afe4e712-8825-45ce-8714-48fcc59d66e9`, marketing version 12.7.1; the App
Store version record stays `1.0`, as build 60 (12.7.0) was reviewed as
1.0 (60).

Read back from the job artifact on 2026-10-19:

- `aity-drive-production-80.ipa`, sha256
  `c3265a975d6d64d70e7b0f19780d8a2ae0b4ca4f30ca5bf7cdeaac5ce00bc8b1`;
- `Payload/ownCloud.app/Info.plist`: `tech.aity.drive`, 12.7.1, 80,
  `UIBackgroundModes = ["fetch"]`, no `NSLocation*` key.

### Submitting it

The target is reviewed source: `AITY_REVIEW_VERSION`,
`AITY_REVIEW_BUILD_NUMBER` and `AITY_REVIEW_BUILD_ID` in `.gitlab-ci.yml`,
and the notes file. The next submission changes them in a merge request;
the jobs are never played with job variables.

1. Play `prepare:appstore-review` on the main pipeline. It reads the build,
   the version, the open review submissions and the review details first and
   stops before any write on anything unexpected. Then it attaches build 80,
   sets "Manually release this version" with no date, sets the notes from
   the file and deletes any App Review attachment. Read its
   `AITY_REVIEW_READY` line; expected `path=resubmit:4877e3a4-d90c-4eee-ada0-c5bee79727f6`.
2. Raul's go, then play `submit:appstore-review`. It refuses a record that
   prepare did not leave ready, resolves the rejected item of submission
   4877e3a4 and resubmits that same submission, so the Resolution Center
   thread stays on it. Read its `AITY_REVIEW_SUBMITTED` line.
3. Raul pastes the reply below in the Resolution Center and presses Release
   after approval.

Neither job cancels or removes a submission, changes the build after
submitting, releases, or retries a submission Apple refused.

## App Review Information - Notes

The notes are `fastlane/review/notes.txt`, the single source of their text;
`prepare:appstore-review` sets them on the version and prints their sha256.

## Resolution Center reply (4877e3a4)

Raul pastes it; there is no API for the Resolution Center.

```
Hello,

Thank you for the review. Instead of the screen recording we offered earlier, we changed the app and submitted build 80.

Guideline 4.8 - Login Services
The sign-in page no longer offers any third-party or social login. Aity Drive signs in only with the user's Aity workspace account, by email and password, on Aity's own identity service (auth.aity.tech, operated by AITY CLOUD SRL). Accounts are created by the customer organisation's administrator; there is no account creation in the app.

Guideline 2.5.4 - audio
The audio background mode is removed in build 80. Audio and video files play while the app is in the foreground.

Guideline 2.5.4 - location
The location background mode is removed in build 80. The app no longer uses location at all: the background-upload trigger that needed it and all location permission strings are gone.

Kind regards,
Raul Bag
AITY CLOUD SRL
```
