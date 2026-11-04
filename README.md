<div align="center">

# AIO

**A Windows-style window switcher and a Dynamic Island-style notch for macOS.**

![macOS](https://img.shields.io/badge/macOS-000000?style=flat-square&logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI%20%2B%20AppKit-0A84FF?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-lightgrey?style=flat-square)

</div>

A small menu bar app that bundles the Mac tweaks I wanted into one place (all-in-one): a Cmd+Tab that
switches between **windows** instead of apps, and a notch that shows what's playing, what's next and more.

## Features

- **Window switcher**: Cmd+Tab shows every window, most recently used first, like Alt+Tab on Windows
- **Now Playing in the notch**: track, artwork and progress from any player
- **Agenda**: your next calendar events at a glance
- **File shelf**: drop files on the notch to hold them for later
- **Volume and brightness HUD** drawn in the notch
- **Battery** status and charging flash
- **Keep Awake** for 1 h, 3 h or until turned off
- **Launch at login** from the menu bar

## Install

Needs macOS 27 and Xcode command line tools.

```sh
./build.sh --install     # builds, signs and copies AIO.app to /Applications
```

On first launch, grant **Accessibility** access (System Settings → Privacy & Security) so the switcher can
see windows and catch Cmd+Tab.

## Usage

- **Cmd+Tab** to switch windows; keep Cmd held and press Tab to move, release to switch
- Hover the notch to open it; drag files onto it to add them to the shelf
- Click the menu bar icon for Keep Awake, Launch at Login and Quit

## How it works

The switcher intercepts the system Cmd+Tab with an event tap and builds a window list from the Accessibility
API, including windows on other Spaces. The notch is a borderless SwiftUI panel drawn around the hardware
notch.

<details>
<summary><b>More details</b></summary>

- **Private APIs** (window focusing, symbolic hotkeys, DisplayServices brightness) are all looked up with
  `dlsym` at runtime, so a missing symbol disables one feature instead of crashing the app.
- **Now Playing**: MediaRemote refuses non-Apple callers, so a tiny helper library is loaded through the
  system Perl, which Apple signs, and reports back to the app.
- **Window list**: kept in most-recently-used order and updated from Accessibility notifications, so the
  switcher opens instantly.
- **Signing**: `build.sh` uses an Apple Development identity if you have one, then a local self-signed
  identity, then ad-hoc.
- **Personal hub** (optional): the notch can also show calendar and fitness stats from a self-hosted
  dashboard that serves `{"events": [...], "fit": {...}}`. It's off unless both are set:

  ```sh
  defaults write ca.felix.aio hubURL https://hub.example.com/api/glance
  security add-generic-password -s aio-hub -a glance -w <token>
  ```

```
Sources/AIO/App.swift          menu bar item, Keep Awake, launch at login
Sources/AIO/EventTap.swift     global key event tap
Sources/AIO/Switcher/          window list, switcher panel, private APIs
Sources/AIO/Notch/             notch window, Now Playing, agenda, shelf, battery, media keys
Helper/                        Now Playing helper
```

</details>

## Development

```sh
swift build              # debug build
./build.sh               # release build → build/AIO.app
```

## License

[MIT](LICENSE) © Felix Wang
