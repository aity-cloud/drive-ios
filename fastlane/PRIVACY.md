# App Privacy - what the store label declares, and why

`app_privacy_details.json` beside this file IS the App Privacy declaration of
Aity Drive on App Store Connect, in the format fastlane's
`upload_app_privacy_details_to_app_store` consumes (one entry per data type,
Apple's category ids). Raul entered the same answers by hand on 2026-09-16
for the first review; the file is the record of what was declared. There is
no CI path for it on purpose: App Privacy has no App Store Connect API, and
fastlane's action drives the private web API with an Apple ID login, which
the runner does not have. A change is made by hand in App Store Connect and
recorded here in the same commit.

## What is declared

Every type is collected for APP FUNCTIONALITY only, LINKED to the user, and
NOT used for tracking.

| Data type | Why it is collected |
|---|---|
| Contact Info - Email Address | the sign-in identity (Keycloak account) |
| Contact Info - Name | the account's display name, sent to and shown by the server |
| Identifiers - User ID | the account id the server assigns |
| User Content - Photos or Videos | manual and automatic photo upload |
| User Content - Other User Content | the user's files and documents in the Drive |

## What is deliberately NOT declared, and the condition that keeps it so

- **Location**: the app can use location changes on the device as a trigger
  for background photo upload; the location never leaves the phone.
- **Diagnostics - Crash Data**: crash reporting is opt-in ("Enable
  diagnostics") and the report is sent by the user themselves through Mail;
  that meets Apple's optional-disclosure exemption (optional, infrequent,
  not primary functionality).
- **Search History**: searches run on the server and no history is kept.
- **Usage Data, Advertising Data, Device ID, tracking**: there is no
  analytics, no advertising SDK and no third-party data sharing in the app.

## When this file MUST change

Apple's definition of "collected" is "transmitted off the device in a way
that is more than transient", and the label must match the binary that is
in review. Answer the questions again in App Store Connect and update
`app_privacy_details.json` in the same change if any of these lands:

- product analytics or behaviour tracking (app launches, taps, screens):
  add PRODUCT_INTERACTION / OTHER_USAGE_DATA with purpose ANALYTICS;
- crash or performance reporting that uploads automatically: add
  CRASH_DATA / PERFORMANCE_DATA;
- an advertising or attribution SDK: add ADVERTISING_DATA and DEVICE_ID with
  purpose THIRD_PARTY_ADVERTISING or DEVELOPER_ADVERTISING, add
  DATA_USED_TO_TRACK_YOU to the affected types, and adopt App Tracking
  Transparency in the app - the permission prompt is mandatory then;
- uploading the device's location (not just using it as a trigger): add
  PRECISE_LOCATION or COARSE_LOCATION;
- any SDK that phones home on its own, even for "diagnostics".

A label that understates collection is a Guideline 5.1.2 rejection and a
GDPR problem; a label that overstates it only costs a moment of the
reviewer's attention. When in doubt, declare.
