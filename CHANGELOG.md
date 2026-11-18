# Changelog

Each release's notes. `scripts/release.sh` copies the section for the version it builds into the GitHub release and into the update window.

## 0.4.8

- **What's New**: after each update, Stanza shows what changed, once, the first time you open its window. Opened at login, it waits until you open the window.
- New and fixed since 0.4.1:
  - **Keyboard shortcuts**: show or hide the lyrics, or move to the next style, from any app. None are on until you set them in Settings.
  - **A quiet start at login**: Stanza waits in the menu bar instead of opening its window while your Mac starts.
  - **Lyrics fade sooner**: 5 seconds into a pause, down from 10, and back the moment music plays.
  - **Favourites**: star the styles you like; the menu bar menu then lists only those.
  - **Songs in English letters**: Hindi, Urdu, Punjabi and Bengali lyrics show in English letters when a version exists.
  - **More songs found**, even when the lyrics database spells the artist a little differently.
  - **Departure Board and Receipt** stay on screen through pauses, and now draw Bengali, Hindi, Urdu and other joined scripts correctly.
  - **Sliders** move with the mouse wheel or a two-finger swipe, and Size now goes down to 25%.
  - **A cleaner window**: the lyric settings sit in a pill at the bottom, the players in a pill under the Settings gear, and the previews are bigger.

## 0.4.7

- Keyboard shortcuts, off until you set them. In Settings (the gear), record one to show or hide the lyrics and one to move to the next style, from any app. A shortcut uses two of ⌃ ⌥ ⌘ (⌃⌥L, say), so it never takes copy, paste and the like away from other apps. Show or hide uses the same switch as Show When Unlocked, so the lock screen keeps its lyrics; Next style goes through your Favourites, or every style when you have none.

## 0.4.6

- The lyrics now fade away 5 seconds after you pause the music, instead of 10. They still come back the moment it plays again.

## 0.4.5

- When Stanza opens at login, it now starts quietly in the menu bar: the window no longer pops up while your Mac is starting. Open it from the menu bar icon whenever you want it. Opening Stanza yourself still shows the window as before.

## 0.4.4

- The player pill now moves fluidly: the icons glide along one spring into place beside each other as the pill grows into its panel, instead of snapping, and the panel fades in just after.
- The style previews in the window are bigger: about 15% in the large preview and 10% on the tiles.

## 0.4.3

- The Size, Font, Lock Screen and Aesthetics buttons now sit in a slim pill floating at the bottom of the window, and each panel rolls up out of the button that opened it.
- Apple Music and Spotify sit in a slim vertical pill under the Settings gear. Point at it and it widens to show their names; click one and the whole pill grows into that player's panel, with both icons side by side across the top.
- The README is rebuilt, with an architecture guide (docs/ARCHITECTURE.md) and a guide to every style and why it is designed the way it is (docs/STYLES.md).

## 0.4.2

- Departure Board and Receipt now stay on screen through pauses in the song, dimming a little like Messages instead of disappearing, and come back to full strength just before the next line.
- Every slider (Size in the menu bar menu, on the Drag Position pill and in the window, and the Timing slider) now also moves with the mouse wheel or a two-finger swipe on a trackpad.
- Size now goes down to 25%.

## 0.4.1

- **Favourites** replace pins. Star a style in the window (on the big preview or a tile) and it joins a new Favourites row above all the styles. Once you have favourites, the menu bar menu lists only those, plus the style in use and **All Styles…**, so it stays short. Anything you had pinned is already a favourite.
- Hindi, Urdu, Punjabi and Bengali songs now show their lyrics in English letters whenever a version in English letters exists (for example "Mujhko itna bataaye koi"). If none does, the original script is shown as it is.
- Lyrics are found for more songs: when the lyrics database knows a song under a slightly different artist name (say "Maanu" for "Maanu, Annural Khalid"), Stanza still finds it. Songs looked up before are checked once more.
- Departure Board and Receipt now draw Bengali, Hindi, Urdu and other joined scripts correctly, keeping each word whole.

## 0.4.0

- Ten new styles, for 23 in all:
  - Kinetic type: **Stretch** (held notes stretch, "looove"), **Ransom Note** (each word a cut-out magazine scrap), **Ink** (words write themselves with a pen, then the ink soaks in) and **Liquid** (words ooze out of one another and melt away).
  - Motion scenes: **Departure Board** (a split-flap board), **Score** (words under notes on a scrolling staff), **Highlighter** (a marker swipes each word on a printed card) and **Receipt** (a till prints the song).
  - Phone screens: **Calendar** (a day planner, one event per line) and **Voice Memo** (each line a recording under a waveform).
- The Drag Position card is now one slim Liquid Glass pill: the move symbol, the Size slider with its percentage, a reset icon and a round Done button.
- Dragging is smooth: the lyrics now stay glued to the card instead of stuttering behind it, and they can go anywhere, even past the edge of the screen (Reset Position brings them back).

## 0.3.8

- The Drag Position card is now really in front of the lyrics. The lyrics live in a special layer of the screen above everything else (it is how they show over the lock screen), so 0.3.7's higher window level did not help; the card now joins that layer, one step above the lyrics.

## 0.3.7

- Every style is now the same size at the same Size setting. Each one was measured and balanced to fill about the same part of the screen, and Size now scales every style the same way. The Map in particular is much smaller and now shrinks and grows with Size (when it fills the whole display it stays full-screen). Because of this, a Size you set before may look different now.
- The Drag Position card always stays above the lyrics, however large they are.
- The menu bar menu has a **Position and Size** section with Drag Position, Reset Position and the Size slider, whose button now says **Reset Size**.

## 0.3.6

- **Move Lyrics** is now called **Drag Position**, and **Reset Lyrics Position** is **Reset Position**. The Drag Position card has a size slider, so you can size and place the lyrics in one go.
- The size slider in the menu bar menu is redrawn from scratch. A standard slider there was drawn greyed out and could ignore the first click whenever Stanza was not the active app, which is why it only worked sometimes.
- The previews in the Stanza window now follow the song you are playing: the big preview and the style under the pointer show its real lyrics, in time with the music, in whichever style you are looking at. While nothing plays, or for a song without lyrics, they play the built-in demo.

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
