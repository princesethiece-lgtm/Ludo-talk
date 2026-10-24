# AN Ludo (iPhone)

Ludo game for iPhone by Audio Nation. Play against the computer or with 2–4 friends on one phone.

## What is in this repository

| Path | What it is |
|---|---|
| `web/index.html` | The whole game: board, tokens, dice, rules, computer players, sounds |
| `App/AppDelegate.swift` | iPhone app shell that shows the game full screen and adds real vibration |
| `App/Assets.xcassets` | App icon and launch colour |
| `project.yml` | Xcode project description (XcodeGen) |
| `.github/workflows/build-ipa.yml` | Builds `AN-Ludo.ipa` on GitHub's free Mac on every push |

## Getting the .ipa

Every push to `main` builds the app. Open **Releases** on the right side of the GitHub page and download `AN-Ludo.ipa` from the newest build. You can also start a build by hand: **Actions → Build iPhone app (.ipa) → Run workflow**.

## Installing on iPhone from a Windows laptop (Sideloadly)

1. Install **iTunes** and **iCloud** from apple.com (the website versions, not the Microsoft Store ones).
2. Install **Sideloadly** from sideloadly.io.
3. Connect the iPhone with a cable, unlock it and tap **Trust**.
4. Open Sideloadly, drag `AN-Ludo.ipa` into it, type your Apple ID and press **Start**. Enter your Apple ID password and the code if asked.
5. On the iPhone: **Settings → Privacy & Security → Developer Mode → On**, then restart.
6. On the iPhone: **Settings → General → VPN & Device Management → your Apple ID → Trust**.

A free Apple ID signs the app for **7 days**. After that, open Sideloadly and install the same `.ipa` again. Your saved game stays.

## Changing the game

Edit `web/index.html` and push. GitHub builds a new `.ipa` in about 5 minutes.
