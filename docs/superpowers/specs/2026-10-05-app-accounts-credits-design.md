# Accounts and credits in the app — design

**Date:** 2026-10-05
**Status:** awaiting the owner's review
**Server contract:** `slimshot_server/docs/app-credits-api.md` on `feat/accounts-credits`
(commit `e8c81aa`). Everything this app sends or reads is defined there; this spec does not
restate request and response shapes, only how the app uses them.
**Product design:** `2026-10-04-credits-server-brief.md` (beside this file), as built by the
server with the changes in §2.

## 1. What this builds

The app stays free and works fully signed out. Auto captions becomes the first paid feature:

- Tapping it signed out opens a **sign-in sheet**: Google, or email with a one-time code.
- A new account then **claims** its free credits by choosing a username.
- Each run is **priced before it starts**, silently; only a shortfall is shown (§4.4).
- A user short of credits can **watch a rewarded ad** or **invite a friend**.
- The balance sits **top right on the home screen**.
- **Settings** gains an account section with sign out and delete account.

## 2. What the server changed from the brief

These are settled on the server; the app follows them.

- **No Android ID.** Google Play's data policy forbids tying it to an account, so the server's
  per-device rule is **per app install** (the device token from `POST /devices`). The app sends
  only the device token.
- **The bonus amount is unknown before sign-in.** `/me` and the claim response carry real
  amounts; nothing tells a signed-out app what the bonus is. See §4.1.
- **Captions need a signed-in user.** The server now refuses the install token for
  `/captions` (`401 SIGN_IN_REQUIRED`). **The app on `main` can no longer caption against this
  server branch** until this work lands.
- **Pricing is by duration, measured by the server from the WAV.** The server session is
  currently adding a per-second mode. The app is unaffected: it asks for a quote and shows
  the credits the server returns.

## 3. Decisions in this spec — please check these

| # | Question | Recommendation |
|---|---|---|
| A | When is the price shown? | **After the audio is rendered, before it is uploaded.** The price depends on the WAV's length, which exists only after rendering. The progress sheet stops at a price step: "6 credits · You have 94" with Generate. Rendering is local and costs nothing. |
| B | When does sign-in appear? | **When Auto captions is tapped**, before its options sheet, as you described. After signing in (and claiming), the options sheet opens as if nothing interrupted. |
| C | Signed-out home button copy | **"Free credits"**, with no number. The amount is set in admin and the app cannot know it before sign-in. A hard-coded "100" would be wrong the day it changes, and wrong for anyone whose email or phone already claimed. After the claim the app shows the real amount: "+100 credits". The number could be shown up front if the server adds a small public "offers" endpoint; that is a server change, so not by default. |
| D | Which AdMob unit pays credits? | **Its own unit, "earn credits" (`…/2451324896`)**, with server-side verification turned on in the AdMob console and its ID given to the server. *Revised 2026-10-07:* this first said the existing rewarded unit (`…/3806842044`); verification was set on the new unit instead, and ads from the old one paid nothing. The old unit stays with the Pro-unlock ads (off). |
| E | Ads switch | **Credit ads get their own switch**, on. `AdService.enabled` stays false, so interstitials and the Pro-unlock ads stay off, as agreed. The ads SDK starts when either switch is on. |
| F | Where tokens live | **`flutter_secure_storage`** for the access token, the refresh token and the install token. The install token moves there from `shared_preferences` once, as its comment promised. |
| G | Google sign-in | **`google_sign_in` 7** (Credential Manager underneath: the account picker, no browser). The Web client ID comes from `--dart-define=SLIMSHOT_GOOGLE_CLIENT_ID=…`. Without it the Google button is hidden and email still works: not offered before it works. |
| H | Username change, history | Both in this work. The server has them and each is small: a username field in Settings, and a credit history list on the Credits screen. |
| I | Suspended accounts | One line where spending is refused: "This account is suspended." **The app has no support address anywhere**; give me one and the line links to it. |

## 4. Screens and sheets

**The sheet frame.** Every sheet here is a `showEditorSheet`-style bottom sheet. Each is capped
at 480 px wide and centred, so on a tablet it reads as a card, not a band across the screen. Colours come from `AppColors`, there are no echo titles,
and toasts are pills. The one heading a sheet carries says **why** it opened, never which tool
opened it.

### 4.1 Home

- **Top right, beside the logo row:** a pill.
- **Signed in:** a coin glyph and the balance. Tap it to open the Credits screen.
- **Signed out:** "Free credits". Tap it to open the sign-in sheet, then the claim sheet, then
  the Credits screen.
- **Signed in but not yet claimed:** also "Free credits", opening the claim sheet.
- The balance shown is the last one known (cached), refreshed on launch, on resume and after
  anything that spends or earns.

### 4.2 Sign-in sheet

- **Heading:** the reason it opened, for example "Sign in to use Auto captions" (from captions)
  or "Sign in to get free credits" (from home or Settings).
- **Continue with Google**, then "or", then an email field and **Continue**.
- **Code step:** the same sheet changes to a 6-digit field showing "Sent to ann@example.com".
  Resend counts down from `resendAfterSeconds`. A wrong code shows "Wrong code · 3 tries left".
  An expired code, or too many tries, shows Send a new code.
- **Errors** are one line under the field they concern, never a dialog (§6).
- **On success:** if `needsClaim`, the claim sheet follows; otherwise the sheet closes and the
  caller continues.

### 4.3 Claim sheet

- **Heading:** "Choose a username to claim your free credits".
- **Username field** with live availability: 300 ms debounce, a tick, or the reason in one line
  ("Taken", "3–20 letters, numbers or _", "Not available").
- **Invite code:** a "Have an invite code?" link reveals an optional field.
- **Claim:**
  - Credits granted: a success sheet, "+100 credits", plus any referral credits as their own
    line.
  - Bonus not granted: the account is still made, and one honest line says why
    (`BONUS_ALREADY_CLAIMED`: "This email or phone has already had its free credits").
  - `REFERRAL_CODE_INVALID`: the code field shows the error and nothing is saved.
- Closing the sheet without claiming leaves the user signed in, with `needsClaim` still true.
  The next paid action, or the home pill, asks again.

### 4.4 The price step (inside the caption progress sheet)

**Revised by the owner on 2026-10-06, after seeing it on the device:** the price is checked
silently while the sheet says "Preparing audio" — no "Checking price" stage and no confirm.

- **Enough credits:** generates straight away. (Was: "6 credits · You have 94" with Generate.)
- **Not enough:** "Needs 6 credits · You have 2", with **Watch an ad · +5** (hidden at the daily
  cap) and **Invite a friend**, beside Close. When an ad lands, the step re-quotes and the
  run goes on by itself once the balance is enough.
- The upload's `charged.balance` updates the home pill straight away.
- **A failed job is refunded by the server.** The app re-reads `/me` and says "Captioning failed.
  Your credits were returned."
- A free job (`credits: 0`) skips the step: there is nothing to confirm.

### 4.5 Credits screen

- **Balance**, large.
- **Watch an ad · +5**, with "N left today". At the cap it reads "Back tomorrow".
- **Invite a friend:** the user's code and a Share button. The share text holds the code and
  the Play Store link.
- **History:** paged, newest first. Each row has its type in plain words, the amount and the
  date.

### 4.6 Settings

An **Account** section at the top of Settings.

- **Signed out:** one row, Sign in.
- **Signed in:**
  - Username, which opens an edit sheet with the same availability check.
  - Email.
  - Credits, which opens the Credits screen.
  - Sign out.
  - Delete account, in the error colour.
- **Delete account** opens a confirm sheet: "Your credits will be lost. This can't be undone."
  with a destructive Delete. It sends `DELETE /me` with `{"confirm":"DELETE"}`, clears the
  tokens and toasts "Account deleted".

### 4.7 Rewarded ad flow

1. `POST /rewards/ads/session` returns a nonce.
2. Load the ad and set `ServerSideVerificationOptions(userId: ssvUserId, customData: nonce)`
   **before** showing it. Use a new session for every ad.
3. Show the ad. When it closes, rewarded or not, poll the session about once a second, for up to
   30 s.
4. The result:
   - `granted`: "+5 credits" and the new balance.
   - `capped`: "That's today's last reward".
   - `rejected`: "No reward this time".
   - Still `pending` after 30 s: "Your reward is on its way", and `/me` is re-read later.
5. The app never adds credits itself.

## 5. How it fits together

| Unit | Responsibility |
|---|---|
| `SecureTokenStore` | Access, refresh and install tokens in `flutter_secure_storage`; the one-time move of the install token from prefs. |
| `SlimshotApi` (extended) | Install token as before. **Signed-in requests** carry the access token. On `401 UNAUTHENTICATED` it refreshes **once**, single-flight: concurrent 401s wait on the one refresh in progress, because a refresh token works once and a second use ends the session. `SIGN_IN_REQUIRED` or a failed refresh clears the tokens and reports signed out. A sign-in answered `DEVICE_NOT_REGISTERED` re-registers and retries once. |
| `AccountService` | One method per endpoint: Google, email start and verify, refresh, logout, `/me`, username availability and change, claim, delete, quote, history, ad session and poll. Pure request and response, no UI. |
| `AccountNotifier` | App-wide Riverpod state, **not** autoDispose: `signedOut` or `signedIn(me)`. Restores from stored tokens on launch, showing the cached `/me` at once and refreshing it in the background. |
| `requireAccount(context, reason)` | The one door: sign-in sheet, then claim sheet if needed. Returns whether the user ended signed in and claimed. `CaptionAccess.ensureAllowed` becomes this. |
| `CaptionPipeline` (extended) | A `confirmPrice(durationSeconds)` step between render and upload. Declining deletes the audio and spends no key. |
| `CreditAdService` | The rewarded ad with SSV options, its own switch, and the poll. Fakeable for tests. |
| Widgets | Sign-in sheet, claim sheet, price step, earn-credits block (shared by the price step and the Credits screen), Credits screen, Settings account section, home pill. |

**The Google sign-in plugin and the ads plugin sit behind small interfaces**, so the flows are
tested without a device. That is the same pattern `CaptionPipeline` already uses for its steps.

## 6. Errors the user can see

Branch on `error.code`, never on the message. Every one is a single line, no title.

| Code | Shown |
|---|---|
| `NETWORK` (local) | "No connection" |
| `GOOGLE_TOKEN_INVALID` | "Google sign-in didn't work. Try again." |
| `GOOGLE_EMAIL_UNVERIFIED`, `SIGN_IN_METHOD_UNAVAILABLE` | "Use your email instead" (focuses the email field) |
| `ACCOUNT_LINK_CONFLICT` | "This email uses a different Google account" |
| `EMAIL_DOMAIN_NOT_ALLOWED` | "Use a regular email address" |
| `OTP_INVALID` | "Wrong code · N tries left" |
| `OTP_EXPIRED`, `OTP_ATTEMPTS_EXCEEDED` | "Code expired" with Send a new code |
| `OTP_RESEND_TOO_SOON`, `RATE_LIMITED` | the countdown from `retryAfterSeconds` |
| `USERNAME_INVALID` / `USERNAME_TAKEN` | the rule / "Taken" |
| `REFERRAL_CODE_INVALID` | "That invite code doesn't work" |
| `ACCOUNT_SUSPENDED` | "This account is suspended" (§3 I) |
| `INSUFFICIENT_CREDITS` | the earn-credits block (§4.4) |
| `CAPTIONS_UNAVAILABLE` | "Auto captions is unavailable right now" |
| `AD_DAILY_CAP_REACHED` | "Back tomorrow" on the ad button |
| `IDEMPOTENCY_KEY_REUSED` | not shown: the pipeline takes a new key and uploads once more |

## 7. Testing

**Test-first, as always.**

**Unit tests:**
- **Single-flight refresh:** two concurrent 401s make one refresh call and both requests retry.
- **Session loss:** a refresh that fails leaves the app signed out.
- **Token store:** the move from prefs happens once.
- **Pipeline:** the price step runs between render and upload; declining uploads nothing and
  keeps no key; `IDEMPOTENCY_KEY_REUSED` takes one fresh key.
- **Ad flow** against a fake ad and a fake clock: `pending`, then `granted`, the 30 s give-up,
  and `capped`.
- **Account notifier:** restore, sign out on `SIGN_IN_REQUIRED`, and the balance updated from
  `charged`.

**Widget tests:**
- the sign-in steps and every error line in §6;
- the availability debounce: one request after typing stops;
- the claim outcomes;
- the price step in both states;
- the home pill in both states;
- the Settings section in both states;
- delete sends `{"confirm":"DELETE"}`.

The existing caption pipeline and toolbar tests must stay green. `flutter analyze` stays at 48.

## 8. Built in three stages

Each stage is device-tested before the next, as the server was.

1. **Accounts:** secure tokens, signed-in requests, the sign-in and claim sheets, the home pill,
   and the Settings account section with username, sign out and delete. Auto captions asks for
   sign-in.
2. **Paid captions:** the price step, the not-enough state (without ads yet), charge and refund
   reflected in the balance.
3. **Earning:** rewarded ads with SSV, invite and share, the Credits screen with history.

## 9. What you set up outside the code

- **Google Cloud:** an **Android** OAuth client (package `com.techfamz.slimshotai`, with the
  debug **and** Play signing SHA-1s) and a **Web** client. The Web client ID goes to the app
  (`--dart-define=SLIMSHOT_GOOGLE_CLIENT_ID=…`) and to the server (`GOOGLE_CLIENT_IDS`).
- **AdMob:** turn on server-side verification on the rewarded unit, with the callback
  `https://<server>/api/app/v1/rewards/admob/ssv`, and put the unit ID in the server's
  `ADMOB_AD_UNIT_IDS`.
- **A public server for ad testing.** AdMob calls the server from the internet, so the LAN
  server (`192.168.1.x`) **cannot receive the reward callback**. Ads can be tested end to end
  only against a public HTTPS address: the deployed server, or a tunnel to the local one. Add the
  test phone as a test device in AdMob, because Google's sample ad units never call your server.
- **Email:** `EMAIL_SENDER=log` on the server prints the codes in its console for local
  testing; SMTP for real mail.
- **Play Console:** the account deletion URL is `https://<server>/account-deletion`.

## 10. Not in this work

- Payments.
- A public username or profile.
- Play Integrity device checks (the server lists them as later hardening).
- iOS.
