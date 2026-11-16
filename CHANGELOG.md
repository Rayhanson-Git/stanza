# Changelog

Each release's notes. `scripts/release.sh` copies the section for the version it builds into the GitHub release and into the update window.

## 0.3.5

- **Move Lyrics**, in the menu bar menu: a card appears where the lyrics sit; drag it anywhere and click Done (or choose Move Lyrics again). The spot is kept on every display and on the lock screen. **Reset Lyrics Position** puts them back in the middle.
- When the music has been paused for 10 seconds, the lyrics fade away instead of staying on the paused line. They come back the moment it plays again.
- A click anywhere else in the Stanza window now closes an open panel, as well as doing what it would anyway.
- The menu's size slider is now called **Size**, since it scales the whole style, not just the words. It is drawn in colour and no longer stutters while you drag it.

## 0.3.4

- **About Stanza**, at the foot of Settings: the version, who made Stanza, and links to the portfolio at rayhanson.tech, the source on GitHub and what's new.
- A small "Made by Rayhanson" credit at the bottom right of the window, linking to rayhanson.tech.

## 0.3.3

- A Settings panel behind the gear at the top right of the window, in the same glass as the other panels. It holds the new **Open at login** switch, **Install updates automatically**, the version and **Check Now**.
- The update strip at the bottom of the window is gone; everything it held is in Settings.

## 0.3.2

- Stanza is now signed with its own fixed certificate, so macOS remembers that you allowed it to read Spotify and Music. After this update it may ask one last time; after that, updates no longer bring the question back.

## 0.3.1

- The menu bar icon is a little smaller and lighter, closer in weight to the system icons beside it.

## 0.3.0

- Stanza now keeps itself up to date. It looks for a new version once a day, downloads it quietly and installs it the next time Stanza restarts.
- When an update is waiting, the menu bar menu and the Stanza window offer to restart into it straight away.
- Check for updates any time from the menu bar menu, or at the bottom of the Stanza window, where automatic installs can also be switched off.
- Stanza now comes as a disk image (DMG) on the Releases page: open it and drag Stanza into Applications. No Terminal needed.
