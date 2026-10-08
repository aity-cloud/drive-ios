# App Review - what Apple asked, what we changed, what we answer

The App Review record of Aity Drive (`tech.aity.drive`). App Review
Information (demo account, notes, attachment) is entered in App Store Connect;
this file is the record of what was entered and why, the same way
`PRIVACY.md` records the App Privacy answers. The demo password is never
written here (spec decision 17: it lives only in App Store Connect).

## 1.0 (60) - rejected 2026-10-01, submission 4877e3a4-d90c-4eee-ada0-c5bee79727f6

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
flow binding was not read back. The reply below says only what is verified
or intended; prove the guard, or hide the providers for `drive-*` clients,
before sending it.

No change to the app. Answer: the business-app exemption of 4.8 (reply
below). Not added, by decision (Raul, 2026-10-08): Sign in with Apple,
consumer registration.

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

Kept: it is a real feature. Opening an audio or video file plays it with
`AVPlayer` under the `.playback` session, publishes Now Playing info and
handles the lock-screen / Control Center transport commands
(`MediaDisplayViewController`); playback continues after Home. Apple wants
a recording from a PHYSICAL device showing exactly that. The simulator
smoke (`AccountJourneySmokeTests`) proves the mechanism on every run but is
not that recording.

### Found on the way, fixed in the same change

`scripts/debrand-strings.py` rewrote "ownCloud" inside identifiers, so build
60 shipped `com.Aity Drive.background-refresh-task` (background refresh was
never scheduled: the code registers `com.owncloud.background-refresh-task`),
`com.Aity Drive.FileProviderUI.Share` (the Files app "Share" action matched
nothing) and `com.Aity Drive.captureRestoreActivityType` (window state
restoration). Identifiers are now left alone; `lint` fails if one is touched.

## The device recording (human, physical iPhone)

1. Install the newest production build from TestFlight (`publish:preprod-testflight`)
   on an iPhone.
2. Put `fastlane/review/aity-drive-audio-demo.wav` (our own tones, nothing licensed)
   into the review demo account's personal space - web upload at
   `drive.aity.tech` signed in as that account, or from the app.
3. Control Center > Screen Recording, microphone off. Start.
4. Aity Drive, signed in as the demo account > Personal >
   `aity-drive-audio-demo.wav`: the tones play.
5. Swipe up to the Home Screen and open another app: the tones go on.
   Open Control Center (or lock the phone): Now Playing shows the file;
   pause and resume from there.
6. Back in Aity Drive, stop the recording.
7. Commit it as `fastlane/review/background-audio-iphone.mov` (or `.mp4`)
   and play `publish:listing`: deliver uploads it as the App Review
   attachment. Anything attached by hand in App Store Connect is DELETED by
   the next listing push (MAINTAINING.md).

## App Review Information - Notes (paste into App Store Connect)

```
Aity Drive is the file client of the Aity business workspace (AITY CLOUD SRL, Romania). It is for existing members of an organisation's Aity workspace: accounts are created by the organisation's administrator, and there is no sign-up in the app or on the sign-in page. Use the demo account above.

Sign-in: the app opens Aity's own sign-in page (auth.aity.tech, our self-hosted Keycloak) in the system browser. Enter the demo account's email, then its password.

Background modes:
- audio: the app plays audio and video files from the user's Drive. Open Personal > aity-drive-audio-demo.wav, then go to the Home Screen: playback continues and is controllable from Control Center and the Lock Screen. A screen recording from a physical iPhone is attached.
- fetch: background refresh for automatic photo upload.
- location: removed in this build.
```

## Resolution Center reply (4877e3a4)

```
Hello,

Thank you for the review. We changed the build and want to explain each point.

Guideline 4.8 - Login Services
Aity Drive is a business app for the Aity workspace. Every account is created by the customer organisation's administrator; the app has no account creation, and our sign-in service refuses registration for this app. Sign-in happens on Aity's own identity service (auth.aity.tech, operated by AITY CLOUD SRL), not on a third-party login service. The Google, Microsoft and GitHub options on that page exist for workspace members whose organisation signs in with Google Workspace or Microsoft 365; they sign in to the same organisation-provisioned account. We believe the app qualifies for the exception "Your app is an education, enterprise, or business app that requires the user to sign in with an existing education or enterprise account." The App Store description states that an Aity workspace account is required and that there is no sign-up in the app.

Guideline 2.5.4 - location
The location background mode is removed in build <BUILD>. The app no longer uses location at all: the background-upload trigger that needed it and all location permission strings are gone.

Guideline 2.5.4 - audio
Aity Drive plays the audio and video files users keep in their Drive, and playback is meant to continue in the background like any media player. The attached screen recording, made on a physical iPhone with build <BUILD>, opens an audio file from the demo account, goes to the Home Screen while it keeps playing, and controls it from Control Center. The App Review notes describe the same steps.

Kind regards,
Raul Bag
AITY CLOUD SRL
```
