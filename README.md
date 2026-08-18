# Gena — a day planner

A day planner that lives in **one HTML file**. No accounts, no backend, no build step, no tracking — open it and plan your day. Works offline, and your data never leaves your own storage.

**Try it:** https://skabone.github.io/gena/

> **Gena** (ገና) is the everyday Amharic word for *not yet* — which is also what Carol Dweck's
> growth-mindset research is about. An unfinished list isn't failure; it's a comma, not a period.
> The mark is a meskel flower: three petals open, one still a bud.

*Previously called Daybook / Pencil Me In. The old address redirects here.*

## Features

- **Today view** — a focused daily page: top priorities, a master task list, Morning / Afternoon / Evening blocks, an Anytime list, Someday parking lot, habits, and daily notes. Every section is collapsible with its own progress bar.
- **Week view** — the next seven days as lists; drag tasks between days or add straight into one.
- **⌘K command palette & keyboard shortcuts** — every action, view, profile, and task from one fuzzy box; `g`+key navigation; `?` shows the cheat sheet.
- **Natural-language capture with autocomplete** — type `Call the bank tomorrow @errands @3pm` and it lands on the right day, block, time, and project; `@` opens suggestions in every input.
- **Subtasks, rich notes & nesting** — checklists with progress pills, formatted notes (bold/italic/underline, bullet & numbered lists) on daily notes, projects, people, jobs, and tasks; drag a task onto another to nest it.
- **Bulk edit** — select many tasks and complete / move / retag / delete them at once.
- **Drag & drop everywhere** — reorder lists, or drop a task on the dock to move it to a block, date, Someday, or another project.
- **Profiles & filters** — Outlook-style contexts (All / Favorites / Work / School…) plus multi-select project filters, scoped across every view.
- **Day-by-day history** — flip back through any day, with a completed log and a carried-over panel for anything that slipped.
- **Task rollover** — unfinished tasks follow you to today automatically, marked with how long they've been carried.
- **Weekly review** — a guided two-minute ritual: celebrate wins, clear carried tasks, pick what's next.
- **Insights** — 14-day completion chart, streaks, power block, and per-project progress. All computed locally.
- **Reminders & focus timer** — browser notifications at each task's clock time (while open) and a built-in 25-minute focus timer.
- **Projects, milestones & phases** — kanban-style project cards, a color-coded calendar (month / week / work-week / 3-day / year), and a zoomable timeline (months / weeks / days).
- **Recurring tasks** — daily, weekly by weekday, or every N days, with an optional **end date**. Editing one occurrence asks the Outlook question: just this one, this and all future, or the whole series. Repeats stay on their own dates and never carry forward.
- **Date ranges** — set an end date on a one-off and it spreads across those days as separate tasks.
- **Day-start review** — first open of a new day lists everything still open, showing where each thing lived, so you can tick off what got done and pull the rest forward.
- **Edit in place** — clicking a task turns the row itself into a two-column editor; the list never disappears underneath you. Subtasks collapse, and reorder by drag or by arrows.
- **Journal & `[[wikilinks]]`** — every day you wrote something, newest first. Type `[[a project, person, or task]]` and it becomes a link; bare URLs link themselves.
- **Focus-session log** — completed focus blocks are recorded with a daily total.
- **People / follow-ups** — lightweight CRM for staying in touch on a cadence.
- **Habits & streaks** — daily habit dots with streak tracking.
- **Smart suggestions** — local, explainable nudges from your own patterns. No AI calls, nothing sent anywhere.
- **Calendar import & export** — subscribe to iCal/webcal feeds, import `.ics`, export your plan as `.ics` or CSV.
- **Make it yours** — six colour schemes including **Habesha** (deep green / gold / red), a full colour picker for the app accent and for every project and person, emoji on projects and profiles, three densities and four typefaces. Light/dark throughout, a print-friendly layout, and an archive to stay fast over the years.
- **Accessible** — skip-to-content, visible focus rings for keyboard users, and reduced-motion support.

## Install it

**As an app (any browser):** open https://skabone.github.io/gena/ and use your browser's *Install* / *Add to
Dock* option. It gets its own window and icon, and still syncs.

**As a native macOS app:** `cd native && ./build.sh` builds `Gena.app` with Swift + WKWebView — no Electron,
no dependencies, nothing to pay for. Drag it to `/Applications`. See [`native/README.md`](native/README.md).

**As a plain file:** download `index.html` and open it. That's the whole app; it works with no server at all.

## Where your data lives

Everything is stored in your browser's `localStorage`. The site itself stores nothing and has no server. Three ways to move or protect your data:

1. **Export / Import** — one-click JSON backup.
2. **Sync file** — auto-save to a local file (Chrome/Edge), handy with a synced drive folder.
3. **Cloud sync (optional)** — connect a GitHub personal access token (gist scope only) and Gena auto-saves to a secret gist on *your* account, so you can pick up on any browser or computer. The token never leaves your browser and is never included in exports.

## Install it as an app

Gena runs fine in a browser tab, but you can also give it its own window and Dock/Home-screen icon:

- **Desktop (Brave / Chrome / Edge):** open the site, then menu → **Install Gena…** (or the install icon in the address bar). It opens in its own window, works offline, and lives in Launchpad / the Start menu.
- **iPhone / iPad (Safari):** Share → **Add to Home Screen**.
- **Android (Chrome):** menu → **Add to Home screen / Install app**.
- **Native macOS app (no Electron, free):** build a real Swift + WKWebView app — see [`native/`](native/). `cd native && ./build.sh`, then move `Gena.app` to Applications.

## Run it yourself

Download `index.html` and double-click it — that's the whole install. Or fork this repo and enable GitHub Pages to host your own copy.

## License

**Free for personal & noncommercial use · created by Mintay Misgano · commercial use by permission.**

Gena is licensed under the [PolyForm Noncommercial License 1.0.0](LICENSE):

- ✅ Use it, change it, and share it freely for any **noncommercial** purpose.
- 🏷️ Keep the credit — every shared copy or derivative must retain the notice
  `Required Notice: Copyright (c) 2026 Mintay Misgano (https://github.com/skabone)`.
- 💼 **Commercial use** (selling it, paid products/services built on it, etc.) requires written permission — [open an issue](https://github.com/skabone/gena/issues) to ask.
- 💌 Building something on top of it? A heads-up is appreciated.
