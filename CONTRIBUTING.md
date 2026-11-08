# Contributing to Simple Snip

Thanks for helping. Simple Snip aims to stay small, fast and private, so a good change usually does one thing well.

## Reporting a bug

[Open an issue](https://github.com/Pavloff207/simple-snip/issues/new/choose) and include:
- your macOS version
- your Mac (Apple silicon or Intel) and how many displays you use
- the steps that cause the problem, and what you expected to happen

## Suggesting a feature

Open an issue first, so we can agree on the idea before you spend time on code. Some things are left out on purpose: screen recording, OCR/text extraction and timed snips. That keeps the app focused.

## Pull requests

- Build with Xcode 26 or later. There are no third-party dependencies, and new ones need a strong reason.
- Match the surrounding style: Swift 5 mode, SwiftUI for views, AppKit where SwiftUI can't do the job.
- Keep each pull request to one change, and describe how you tested it.
- Don't add network access or analytics. "Nothing leaves your Mac" is a promise to users.

If your change alters how the app looks, regenerate the README images with `Tools/demo/make_demo.sh`.
