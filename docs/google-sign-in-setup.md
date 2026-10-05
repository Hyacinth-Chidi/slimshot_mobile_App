# Google sign-in: getting the keys

What you set up once in Google Cloud so "Continue with Google" works, where each value goes,
and how to check it. About 20 minutes.

## What you end up with

| Value | Where it goes | Secret? |
|---|---|---|
| **Web client ID** (`1234…-abc.apps.googleusercontent.com`) | The server's `.env` as `GOOGLE_CLIENT_IDS`, **and** the app's run or build command as `SLIMSHOT_GOOGLE_CLIENT_ID` | No. It ends up inside the app anyway. |
| **Android client(s)** | Nowhere. They only have to exist. Google recognises the app by its package name and signing fingerprint. | No |
| Web client **secret** | **Nowhere.** Neither the app nor the server uses it. Don't paste it into `.env`, the app or a chat. | Yes |

Both values that matter are the **same Web client ID**. If the app and the server hold different
IDs, every Google sign-in fails with `GOOGLE_TOKEN_INVALID`.

## Before you start

- A Google account to own the project. Use the one that owns the Play Console app, so it all
  lives together.
- The app's package name: **`com.techfamz.slimshotai`**.
- The SHA-1 fingerprints of the keys that sign the app (Step 3 shows how to get them).

## Step 1 — A Google Cloud project

1. Open <https://console.cloud.google.com/>.
2. In the project picker at the top, choose **New project**. Name it `SlimShot` and click
   **Create**. If a project already exists for the app (Firebase or AdMob may have made one), use
   it.
3. Make sure that project is selected in the picker for every step below. **All the clients
   must be in the same project.**

## Step 2 — The sign-in screen (Google Auth Platform)

1. Go to the menu, then **APIs & Services**, then **OAuth consent screen**. On new consoles this
   opens **Google Auth Platform**.
2. If asked to get started, fill in:
   - **App name:** `SlimShot AI`
   - **User support email:** your email
   - **Audience:** **External**
   - **Contact information:** your email
   - Agree, then click **Create**.
3. Under **Branding**, add the privacy policy link `https://slimshotai.vercel.app/privacy` and
   save. Leave the logo empty: adding one starts a brand review that can take days.
4. Under **Audience**:
   - While it says **Testing**, only the accounts listed under **Test users** can sign in. Add
     the Google accounts you test with.
   - When you are ready for everyone, click **Publish app**. Sign-in asks only for name, email
     and profile picture, so publishing needs no Google review.
5. **Data access:** leave it as it is. The app asks only for the basic scopes (`openid`,
   `email`, `profile`).

## Step 3 — Your SHA-1 fingerprints

Every key that signs an installed copy of the app needs its own Android client. There are
up to three.

### a. Debug key (`flutter run` on your PC)

In PowerShell, from the app's folder:

```powershell
cd android
.\gradlew signingReport
```

Find `Variant: debug` and copy its **SHA1** line (`AB:CD:…`, 20 pairs).

If Gradle won't run, use keytool (it ships with Android Studio):

```powershell
& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -list -v `
  -keystore "$env:USERPROFILE\.android\debug.keystore" `
  -alias androiddebugkey -storepass android -keypass android
```

Each PC has its own debug key. If you build on another computer, repeat this there and add
that SHA-1 too.

### b. Your upload/release key (APKs you build and sideload)

Your release key is the one named in `android/key.properties` (`storeFile`, `keyAlias`). Run:

```powershell
& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -list -v `
  -keystore "<path from storeFile>" -alias <keyAlias>
```

Enter the store password when asked, and copy the **SHA1**. `.\gradlew signingReport` shows it
too, under `Variant: release`.

### c. Google Play's app signing key (copies installed from the Play Store)

Google re-signs what it delivers from the Play Store with **its own** key. Get it from Play
Console: open the app, then **Test and release**, then **Setup**, then **App signing**. Copy
**App signing key certificate**, then **SHA-1 certificate fingerprint**.

**Miss this one** and Google sign-in works in every build you test yourself, then fails for
everyone who installs from the Play Store.

## Step 4 — The Web client (the one ID you use)

1. In **Google Auth Platform**, open **Clients**, then **Create client** (on older consoles:
   **Credentials**, then **Create credentials**, then **OAuth client ID**).
2. **Application type:** **Web application**.
3. **Name:** `SlimShot server`.
4. Leave **Authorised JavaScript origins** and **Authorised redirect URIs** empty. Nothing
   redirects; the server only checks tokens.
5. Click **Create** and copy the **Client ID**. Ignore the client secret.

## Step 5 — The Android clients (one per SHA-1)

For **each** SHA-1 from Step 3:

1. Go to **Clients**, then **Create client**.
2. **Application type:** **Android**.
3. **Name:** for example `SlimShot Android (debug)`, `(release)` or `(Play)`.
4. **Package name:** `com.techfamz.slimshotai`.
5. **SHA-1 certificate fingerprint:** paste it.
6. Click **Create**. You don't need to copy anything from these.

Allow a few minutes (sometimes up to an hour) for new clients to take effect before
concluding that something is wrong.

## Step 6 — Put the Web client ID on the server

In `slimshot_server/.env` (and in the VPS's `.env` later):

```env
GOOGLE_CLIENT_IDS=1234567890-abcdefg.apps.googleusercontent.com
```

- One ID, or several separated by commas. Don't add quotes or spaces.
- Restart the server so it re-reads `.env` (`npm run start:dev` locally, your process manager on
  the VPS).
- Left empty, the server answers Google sign-in with `SIGN_IN_METHOD_UNAVAILABLE`. The app then
  says "Use your email instead".

## Step 7 — Put the same ID in the app's command

The app reads it at build time, so it goes on the command line, beside the server address you
already pass.

**Testing on your phone:**

```powershell
flutter run `
  --dart-define=SLIMSHOT_API_URL=http://192.168.1.158:2700 `
  --dart-define=SLIMSHOT_GOOGLE_CLIENT_ID=1234567890-abcdefg.apps.googleusercontent.com
```

**Release for the Play Store** (once the VPS has HTTPS):

```powershell
flutter build appbundle `
  --dart-define=SLIMSHOT_API_URL=https://api.your-domain.com `
  --dart-define=SLIMSHOT_GOOGLE_CLIENT_ID=1234567890-abcdefg.apps.googleusercontent.com
```

Without `SLIMSHOT_GOOGLE_CLIENT_ID` the app simply shows no Google button, and email sign-in still
works.

**To save typing:** put both values in a file such as `dart_defines.json` in the app's folder:

```json
{
  "SLIMSHOT_API_URL": "http://192.168.1.158:2700",
  "SLIMSHOT_GOOGLE_CLIENT_ID": "1234567890-abcdefg.apps.googleusercontent.com"
}
```

Then run `flutter run --dart-define-from-file=dart_defines.json`.

## Step 8 — Check it

1. Run the app with the command from Step 7 on a phone with Google Play services.
2. Tap Auto captions, or the "Free credits" pill. The sheet should show **Continue with
   Google**.
3. Tap it. The phone's Google accounts slide up, with no browser. Pick one.
4. A new account goes on to the username step; an existing one is signed in.

## If it doesn't work

| What you see | Usual cause |
|---|---|
| No Google button | The app was not run with `--dart-define=SLIMSHOT_GOOGLE_CLIENT_ID=…`. |
| The account list never appears, or closes at once | No Android client matches this build's SHA-1 and package name, or the clients are in a different project from the Web client. Check Step 3 for the key this build was signed with, and wait a few minutes after creating clients. On an emulator, use an image **with Google Play**. |
| "Google sign-in didn't work. Try again." | The server answered `GOOGLE_TOKEN_INVALID`. The ID in the app and in `GOOGLE_CLIENT_IDS` differ, or the server's clock is wrong. |
| "Use your email instead." | `GOOGLE_CLIENT_IDS` is empty or the server wasn't restarted, or that Google account has no verified email. |
| "Access blocked" or "app is being tested" | The consent screen is in **Testing** and this account isn't a test user (Step 2.4). |
| Works on your builds, fails from the Play Store | The Play app signing SHA-1 (Step 3c) has no Android client. |
