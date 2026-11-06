# Mythica Studio

A Mac app for writing your life story one month at a time, with your photos and videos linked right where they already live. Made for gathering stories for the **Into the Mythica** website.

## What it does

- **A timeline of years and months.** Each month shows how many photos you took then, the moments you've already written, and suggestions from your albums and big photo days. Click a suggestion to turn it into a moment.
- **Moments.** Each one has dates, kind (journey, show, gathering, teaching, release, ceremony, home, family, love), place, who was there, a song or show, tags, and three writing spaces: **the story**, **why it mattered**, and **synchronicities & lore**. Mark each one Seed → Drafted → ✦ Told.
- **Threads.** Link moments across the years that echo each other.
- **Photos and videos are linked, never copied.** Apple Photos items (including ones only in iCloud) and files on your disk or external drives. A drive's photos show while it's plugged in.
- **✦ Next blank** jumps to the next month that has photos but no story. **✓ Quiet** marks a month that doesn't need telling.
- **Exports:** chapters (Markdown, one per year, ready for the Into the Mythica writer), website story cards (HTML + cover photo), and the whole story as JSON.

## Install

1. Double-click `build-mythica-studio-mac-app.command`. The first time, macOS may ask to install Apple's free Command Line Tools. Install them, then double-click again.
   If macOS says it can't open the file: right-click it › Open › Open.
2. Mythica Studio opens and lands in Applications. Drag it to your Dock.
3. In the app: pick the year your story begins, then **Connect Apple Photos** (top right) and allow access.
4. Optional: **🗂 Folders › Link a folder** for photos and videos on a drive or in Finder.

Needs macOS 12.3 or newer.

## Where your story is saved

`Documents › Mythica Studio › mythica-studio-data.json`. The app saves as you type and keeps a dated copy in `backups/` each day. Exports go to `exports/`. None of this goes into this repository.

You can also open `app/mythica-studio.html` in a browser to write without the app. Photos and folders won't show there, and the story is kept in that browser only (use ⇪ Export › Story data to save a copy).

## Keys

`←` `→` change year · `N` next blank · `Esc` close

## Files

| Path | What |
|---|---|
| `app/mythica-studio.html` | The whole interface (no internet needed) |
| `app/mythica-studio-seed.js` | Optional starting story (empty) |
| `mac/mythica-studio-mac-main.swift` | The Mac app window |
| `mac/mythica-studio-mac-bridge.swift` | Apple Photos, files, saving and exports |
| `build-mythica-studio-mac-app.command` | One-click build and install |
