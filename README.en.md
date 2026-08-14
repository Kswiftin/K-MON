<div align="center">

<img src="assets/icon.png" width="128" alt="K-MON icon">

# Pokédoro

**An idle Pokémon companion that grows in your macOS menu bar — then battles your friends over LAN.**

[![macOS](https://img.shields.io/badge/macOS-14%2B-0969da)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6-f05138)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-3fb950)](LICENSE)

**English** · [한국어](README.md) · [日本語](README.ja.md)

</div>

K-MON lives in your macOS menu bar and grows a **Pokémon companion** on its own — just keep the app running. Pick your first partner, watch it evolve through its real evolution line, name it, graduate it into your Pokédex, and start again. When a friend on the same network is running K-MON too, challenge them to a live turn-based **Brawl**. Races for several trainers at once are their own event — the **Pokéathlon**.

> Built on top of [PokeTokenBar](https://github.com/chattymin/PokeTokenBar). Unofficial, non-commercial Pokémon fan project — see [License & disclaimer](#license--disclaimer).

## How it works

1. 🎒 **Choose your starter.** On first launch you enter a **trainer name** and pick one of **three Gen-1 starters** drawn just for you. The three are locked to your Mac — reinstalling won't re-roll them (no starter fishing).
2. ⏳ **It grows while the app runs.** Your companion earns **✨ Stardust** every second the app is open — no tokens required. Stardust incubates the egg, evolves your Pokémon through its real evolution tree, and graduates it into the Pokédex. The more species you've collected, the faster it grows (**+2% per species**).
3. 🐣 **Hatch, evolve, name.** Eggs and starters hatch into Pokémon with real evolution lines from [PokéAPI](https://pokeapi.co/). Every hatch rolls one of 25 natures, and once in a rare while — **✨ Shiny**. Give any Pokémon a **nickname** with the ✏️ button.
4. 🎓 **Graduate & collect.** Final form + threshold permanently archives it in your **Pokédex**, and a fresh egg arrives. From then on, eggs hatch a variety of Pokémon (weighted by capture rate — legendaries are rare).
5. 🍬 **Daily treat.** Every day you open the app, you get a **Rare Candy** — spend it from the **Bag** to instantly grow your current Pokémon.
6. 🛒 **Spend at the Shop.** Your Stardust is spendable currency — buy **Rare Candy**, a **Mint** to re-roll nature, a **Shiny Charm** for permanently better shiny odds, or an egg to send off your current companion and start over.
7. 💗 **Care when it calls.** Build affection and growth through favorite treats and petting, then manage messes, hygiene, illness, training, and sleep as its needs change.
8. ⏱️ **Grow only through focus adventures.** Stardust comes exclusively from completed 25, 50, or 90-minute sessions. Longer focus pays more per minute and improves the Mystery Egg chance. Work mode uses a neutral timer and hides the floating pet.

## ⚔️ Battle a friend over LAN

When two Macs on the same network are both running K-MON, they discover each other automatically (Bonjour + AWDL). No IP typing — but a manual `IP:port` fallback is there for locked-down networks.

- **Brawl** — a turn-based battle. Pick from four moves; type advantage, STAB, crits and misses all matter. Deterministic engine — both peers compute the same result, so nothing can be forged over the wire.
- **Auto-accept** — flip it on and challenges are accepted the moment they arrive, so a battle happens even while you're away from the keyboard.
- **Notifications & a pinned window** — a challenge raises a system notification even while you're working; when a battle starts, the window pins itself open (it won't close when you click away) so you can play while you work.
- **Names everywhere** — your trainer name and your Pokémon's nickname show up on the challenge, the arena, and the notification.

## Tour

<table>
<tr>
<td width="45%" align="center"><img src="assets/floating-pet.gif" width="340" alt="Floating desktop pet with a hover callout and right-click menu"></td>
<td width="55%" valign="middle">
<h3>🐾 Let it live on your desktop</h3>
Move your companion out of the menu bar and onto the desktop, at any size from 48 to 192px. Hover it for today's stats, click to open the popover, right-click for a menu, drag it wherever you like.
</td>
</tr>
<tr>
<td width="55%" valign="middle">
<h3>In your menu bar</h3>
An animated Gen-V sprite lives next to <b>today's time together</b>. It updates every minute the app is open.
</td>
<td width="45%" align="center"><img src="assets/menubar.gif" width="240" alt="Menu bar"></td>
</tr>
<tr>
<td width="45%" align="center"><img src="assets/shiny-banner.gif" width="340" alt="Normal vs shiny"></td>
<td width="55%" valign="middle">
<h3>✨ Once in a rare while — Shiny</h3>
Shiny hatches keep their distinct colors through every evolution — menu bar, home card, evolution line. In the Pokédex a ✨ sits next to the dex number. A dedicated notification makes sure you don't miss the moment.
</td>
</tr>
<tr>
<td width="55%" valign="middle">
<h3>A Pokédex worth filling</h3>
The <b>Pokédex</b> folds every species you've owned into one cell — in dex-number order, with a ✨ on the ones you own shiny. The <b>Catch log</b> keeps the individuals: newest first, each with its full evolution line, rarity, nature, and capture date. Every species you collect speeds up your Stardust.
</td>
<td width="45%" align="center"><img src="assets/screenshot-collection-pokedex.png" width="300" alt="Pokédex — one cell per species"><br><br><img src="assets/screenshot-collection-catchlog.png" width="300" alt="Catch log — one row per Pokémon raised"></td>
</tr>
<tr>
<td width="45%" align="center"><img src="assets/screenshot-shop.png" width="300" alt="Shop — Rare Candy, Mint, Shiny Charm, eggs"></td>
<td width="55%" valign="middle">
<h3>🛒 A shop that runs on Stardust</h3>
The Stardust you collect over time is your currency. Spend it on <b>Rare Candy</b> to grow your current Pokémon, a <b>Mint</b> to re-roll its nature, a <b>Shiny Charm</b> that permanently raises your shiny hatch odds, or an egg to send off your companion and start over. Eggs come in three grades — plain, Uncommon-or-better, and Rare-or-better.
</td>
</tr>
<tr>
<td width="55%" valign="middle">
<h3>Tune it your way</h3>
Menu-bar items, refresh interval, launch at login, companion event notifications, and battle auto-accept. Full <b>KO / EN / JA</b> UI and Pokémon names.
</td>
<td width="45%" align="center"><img src="assets/settings.png" width="300" alt="Settings"></td>
</tr>
</table>

> Screenshots may lag the latest UI — the app has moved from a token counter to a time-based idle game.

## Install

### Requirements

macOS 14+ (Apple Silicon or Intel).

### Download

Grab `PokeTokenBar.zip` from the [releases](https://github.com/2giduck/K-MON/releases), unzip it, and drag `PokeTokenBar.app` into `/Applications`.

Because the app is ad-hoc/self-signed (not notarized under an Apple Developer account), Gatekeeper shows an "unidentified developer" warning on first launch. Clear it once:

- **Finder:** right-click (or Control-click) `PokeTokenBar.app` → **Open** → **Open** again in the dialog.
- **Terminal:** `xattr -dr com.apple.quarantine /Applications/PokeTokenBar.app`

On first launch, **allow the notification prompt** (for battle challenges) and, when you first open the Battle tab, **allow Local Network access** (for auto-discovery) in System Settings → Privacy.

### Build from source

```bash
swift build                  # debug
./scripts/build-app.sh       # release → PokeTokenBar.app → /Applications
```

> Running the full test suite (`swift test`) requires Xcode (for XCTest); Command Line Tools alone build the app but not the tests.

## Fair play

- **Starters are device-locked.** Your three starter choices are derived from a stable hardware identifier — deleting the app and reinstalling gives you the same three, so there's no re-rolling for a legendary. (Legendaries never appear as starters anyway.)
- **Save integrity.** The save file is signed with a device-keyed checksum. Hand-editing `companion-state.json` to inflate currency or hand yourself items is detected on the next launch and resets the tampered progress.
- **Deterministic battles.** Both peers compute the same battle result from a shared seed; results are never sent over the wire, so they can't be forged.

## Privacy & permissions

- **Local network.** Battle discovery uses Bonjour/AWDL on your LAN only. Battles connect peer-to-peer; nothing goes to a server.
- **Outbound requests.** The app talks to [PokéAPI](https://pokeapi.co/) (`pokeapi.co`, `graphql.pokeapi.co`) and `raw.githubusercontent.com` for species/evolution data and sprites, and uses the GitHub API to check for app updates.
- **Pokémon assets** are fetched at runtime from PokéAPI and cached only under `~/Library/Application Support/PokeTokenBar/`. The app binary bundles no Pokémon assets.

## License & disclaimer

**MIT** — see [LICENSE](LICENSE). The MIT license covers this project's original source code only; it grants no rights to any third-party trademarks, artwork, or data accessed through the app. K-MON is based on the MIT-licensed [PokeTokenBar](https://github.com/chattymin/PokeTokenBar).

K-MON is an **unofficial, non-commercial fan project**. It is **not affiliated with, endorsed, sponsored, or approved by Nintendo, Game Freak, Creatures Inc., or The Pokémon Company.** "Pokémon" and all related names, characters, and imagery are trademarks and copyrights of their respective owners. This project claims no ownership of, and asserts no rights over, any Pokémon intellectual property.

- **The app binary and its release artifacts bundle no Pokémon assets.** Species data and sprites are fetched **at runtime** from the public [PokéAPI](https://pokeapi.co) and cached locally on the user's own device.
- Any Pokémon imagery in this repository's documentation (screenshots/GIFs) is shown solely to illustrate the app's functionality.
- The app is provided free of charge for **personal, non-commercial use only.**

*Provided "as is", without warranty of any kind. This notice is not legal advice.*
