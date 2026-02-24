# Safety Database Maintenance Guide

**Version:** 1.0
**Last Updated:** 2026-02-24
**Maintainer:** DevDash Development Team

## Table of Contents

1. [Overview](#overview)
2. [Current Safelist Sources](#current-safelist-sources)
3. [Curation Process](#curation-process)
4. [Maintenance Schedule](#maintenance-schedule)
5. [Guidelines & Best Practices](#guidelines--best-practices)
6. [What to Do / What NOT to Do](#what-to-do--what-not-to-do)
7. [Verification Checklist](#verification-checklist)
8. [Research Resources](#research-resources)
9. [Testing Protocol](#testing-protocol)
10. [Emergency Response](#emergency-response)

---

## Overview

The SafetyDatabase (`SafetyDatabase.swift`) is DevDash's **safelist-based protection system** that prevents accidental deletion of critical user data. It uses a **safelist approach**: if a path is not explicitly approved, it will NEVER be scanned or deleted.

### Core Principle

**"When in doubt, protect it."**

Better to miss cleaning some safe files than to delete one critical file.

---

## Current Safelist Sources

The current safelist was curated from the following verified sources on 2026-02-24:

### 1. CleanMyMac Safety Database Research

**Primary Source:** CleanMyMac by MacPaw (14+ years of safety rules)

- **Safety Database Overview**: https://macpaw.com/support/cleanmymac-x/knowledgebase/safety-database
  - Contains detailed rules and exceptions for macOS versions and apps
  - Continuously updated since 2008
  - Aggregates 14+ years of Mac cleaning experience

- **What CleanMyMac NEVER touches**:
  - `/Library` (system-level)
  - `/System/Library` (macOS system files)
  - `~/Library/Application Support` (app data, licenses, configs)
  - `~/Library/Preferences` (app settings, registrations)
  - Source: https://macpaw.com/how-to/clear-cache-on-mac

- **What CleanMyMac cleans by default**:
  - Only "automatically generated system or app-related data"
  - No personal files unless user explicitly selects them
  - Source: https://macpaw.com/cleanmymac-x/mac-cleanup

### 2. macOS Cache Safety Research

**Source:** Multiple verified tech support sites (2025 data)

- **Safe cache directories** (regenerable):
  - `~/Library/Caches` - *ONLY specific subdirectories* (see safeCachePaths)
  - `/private/tmp` - temporary files
  - `/private/var/tmp` - system temp files
  - Source: https://macpaw.com/how-to/clear-cache-on-mac

- **Important warnings**:
  - "Never delete the main Application Support folder — it contains support files for apps still on your Mac"
  - "Deleting Library Preferences could result in loss of default preferences and customized settings"
  - Source: https://iboysoft.com/wiki/library-preferences-mac.html

### 3. Browser-Specific Research

**Chrome on macOS:**
- **User Data Location**: `~/Library/Application Support/Google/Chrome/`
- **Profile Structure**: Each profile stored in `Default/` or `Profile [N]/` subdirectories
- **Cache Location**: Derived from profile directory, stored in `~/Library/Caches/Google/Chrome/`
- **CRITICAL**: Profile folders contain sessions, passwords, bookmarks - NEVER delete
- **Safe to delete**: Cache folders (NOT Default/Profile folders)
- Source: https://chromium.googlesource.com/chromium/src/+/master/docs/user_data_dir.md

**Firefox on macOS:**
- **Profile Location**: `~/Library/Application Support/Firefox/Profiles/`
- **Cache Location**: `~/Library/Caches/Firefox/Profiles/`
- **Separation**: Firefox separates profile data from cache
- **Safe to delete**: Cache directory only
- Source: https://support.mozilla.org/en-US/kb/profiles-where-firefox-stores-user-data

**Safari on macOS:**
- **Sessions/Profiles**: Stored in `~/Library/Safari/`
- **Cache**: `~/Library/Caches/com.apple.Safari/`
- **CRITICAL**: Safari folder contains bookmarks, history, passwords
- Source: macOS system documentation

### 4. macOS Preferences Safety

**Research findings:**
- **Never delete entire Preferences folder** - holds config files for all apps
- **Individual .plist files**: Can be deleted for troubleshooting, but may lose licenses/registrations
- **Best practice**: Move to temp folder first, test, then delete
- **What happens**: Preferences regenerate with defaults, losing customizations
- Source: https://echoone.com/tips/how-to-delete-preferences

### 5. Developer Tool Caches

**Xcode (verified safe to delete):**
- `~/Library/Developer/Xcode/DerivedData` - Build artifacts (regenerates)
- `~/Library/Developer/Xcode/Archives` - Old archives (safe to remove)
- `~/Library/Developer/Xcode/iOS DeviceSupport` - Device symbols (re-downloads)
- **Source**: Official Xcode documentation, developer community consensus

**Package Managers (verified safe to delete):**
- Homebrew: `~/Library/Caches/Homebrew` - Downloaded packages (re-downloads)
- npm: `~/.npm` - Package cache (regenerates)
- pip: `~/Library/Caches/pip` - Python packages (re-downloads)
- cargo: `~/.cargo/registry`, `~/.cargo/git` - Rust packages (re-downloads)
- **Source**: Package manager documentation

### 6. macOS System Paths Research

**Apple File System Programming Guide:**
- https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/
- Documents standard macOS directory structure
- Explains purpose of each system directory

**Protected system directories** (based on Apple docs):
- `/System` - macOS system files
- `/Library` - System-wide resources
- `/Applications` - System applications
- `/usr`, `/bin`, `/sbin` - Unix system binaries
- `/private/var` - System variable data (except `/private/tmp`)
- `/private/etc` - System configuration

---

## Curation Process

### How the Current Safelist Was Built

1. **Research Phase** (3 hours)
   - Reviewed CleanMyMac safety documentation
   - Read 20+ tech support articles on macOS cache cleanup
   - Studied browser data storage documentation
   - Reviewed Apple developer documentation

2. **Categorization Phase**
   - Separated paths into 3 categories:
     - **Protected** (NEVER delete)
     - **Safe** (regenerable, can delete)
     - **User Data** (requires review)

3. **Validation Phase**
   - Cross-referenced with CleanMyMac's known-safe list
   - Verified browser cache vs profile separation
   - Tested on development machine

4. **Conservative Filtering**
   - When multiple sources conflicted, chose protection
   - Entire directories blocked if any subdirectory is critical
   - Example: Block all of `~/Library/Application Support` instead of trying to whitelist safe subdirectories

---

## Maintenance Schedule

### After macOS Major Updates (Required)

**Timeline:** Within 1 week of new macOS release

**Actions:**
1. Read official macOS release notes
2. Check for new system directories
3. Review File System changes
4. Update `protectedPaths` if new critical directories added
5. Test on non-production machine first

**Resources:**
- Apple Developer Release Notes: https://developer.apple.com/documentation/macos-release-notes
- What's New in macOS: https://www.apple.com/macos/

### Quarterly Review (Recommended)

**Timeline:** Every 3 months

**Actions:**
1. Search: "macOS cache cleanup safety [current year]"
2. Check CleanMyMac release notes for new rules
3. Review any user-reported issues
4. Update documentation

**Resources:**
- CleanMyMac Blog: https://macpaw.com/cleanmymac/blog
- MacRumors Forums: https://forums.macrumors.com/forums/macos.172/
- Reddit r/MacOS: https://reddit.com/r/MacOS

### After User Reports (Immediate)

**Timeline:** Within 24 hours

**Actions:**
1. Reproduce the issue
2. Identify what was deleted
3. Add path to `protectedPaths` immediately
4. Document in code comments
5. Release hotfix
6. Update this guide

### When Adding New Cleanup Categories

**Timeline:** Before implementation

**Actions:**
1. Research target directories thoroughly
2. Verify with multiple sources
3. Test on development machine
4. Monitor for 1 week before production release

---

## Guidelines & Best Practices

### Adding to `protectedPaths` (Always Safe)

✅ **DO add when:**
- Contains user-created content (documents, photos, etc.)
- Contains app licenses or registration data
- Contains passwords or credentials
- Contains email, messages, or contacts
- Contains app settings or preferences
- Deleting it breaks applications
- Multiple sources say "never delete"

✅ **Examples:**
```swift
"Library/Keychains",        // Passwords - CRITICAL
"Library/Mail",             // Email data - CRITICAL
"Library/Application Support", // App data - CRITICAL
"Library/Preferences",      // Settings - CRITICAL
```

❌ **DON'T remove unless:**
- You have 100% proof it's regenerable
- Multiple authoritative sources confirm it's safe
- You've tested deletion on multiple machines without issues

### Adding to `safeCachePaths` (Requires Verification)

✅ **DO add when:**
- Data regenerates automatically
- Deleting it doesn't break apps (just slower initial launch)
- Multiple sources confirm it's safe
- You've tested deletion yourself successfully

✅ **Verification process:**
1. Research the directory purpose
2. Check 3+ sources confirming it's safe
3. Delete on test machine
4. Restart affected app
5. Verify app works normally
6. Monitor for 48 hours

✅ **Examples:**
```swift
"Library/Caches/Homebrew",              // Re-downloads packages - SAFE
"Library/Developer/Xcode/DerivedData",  // Rebuilds - SAFE
".npm",                                 // Re-downloads - SAFE
```

❌ **DON'T add if:**
- Only one source says it's safe
- You haven't tested it yourself
- App shows ANY issues after deletion
- Purpose is unclear

### Browser Cache Rules (Special Handling)

**CRITICAL DISTINCTION:**
- **Cache** = Safe to delete (images, scripts, temp files)
- **Profile** = NEVER delete (sessions, passwords, bookmarks)

✅ **Safe (cache only):**
```swift
"Library/Caches/Google/Chrome/Cache",      // Image/script cache - SAFE
"Library/Caches/Google/Chrome/GPUCache",   // GPU cache - SAFE
"Library/Caches/Firefox/Profiles/*/cache2" // Firefox cache - SAFE
```

❌ **NEVER delete (profiles/sessions):**
```swift
"Library/Caches/Google/Chrome/Default",    // PROFILE - PROTECTED
"Library/Caches/Google/Chrome/Profile",    // PROFILE - PROTECTED
"Library/Application Support/Google/Chrome" // ALL PROFILES - PROTECTED
"Library/Safari",                          // BOOKMARKS/SESSIONS - PROTECTED
```

### App-Specific Cache Rules

**Research each app individually:**

1. Search: "[App Name] macOS cache safe to delete"
2. Check official documentation
3. Check support forums
4. Test deletion yourself

**Document in code:**
```swift
// Spotify cache - verified safe 2026-02-24
// Source: https://support.spotify.com/article/storage/
"Library/Caches/com.spotify.client",
```

---

## What to Do / What NOT to Do

### ✅ ALWAYS DO

1. **Research Before Adding**
   - Read at least 3 independent sources
   - Check official documentation if available
   - Search recent (last 2 years) articles

2. **Test on Your Own Machine First**
   - Delete the directory yourself
   - Restart the app
   - Use the app for 24-48 hours
   - Monitor for any issues

3. **Document Your Sources**
   ```swift
   // Homebrew cache - verified safe to delete
   // Source: https://docs.brew.sh/FAQ
   // Tested: 2026-02-24 - No issues after deletion
   "Library/Caches/Homebrew",
   ```

4. **Be Conservative**
   - When in doubt, protect it
   - Entire directories preferred over specific files
   - Example: Protect all of `Library/Application Support` instead of trying to whitelist safe subdirectories

5. **Version Control**
   - Comment when you added a path
   - Comment why it's safe/protected
   - Include macOS version if relevant

6. **User Communication**
   - Update category descriptions
   - Add warnings in UI for risky categories
   - Explain what each category cleans

### ❌ NEVER DO

1. **Don't Guess**
   - Never add to safelist based on assumptions
   - "It looks like a cache folder" is NOT enough
   - Always verify with documentation

2. **Don't Trust Single Sources**
   - One blog post is not enough
   - Need multiple independent confirmations
   - Official docs trump blog posts

3. **Don't Add Without Testing**
   - Always test deletion yourself first
   - Never trust "it should be fine"
   - Monitor for at least 24 hours

4. **Don't Remove Protections**
   - Never remove from `protectedPaths` without extensive research
   - If unsure, leave it protected
   - Better safe than sorry

5. **Don't Scan System Paths**
   - Never add `/System`, `/Library`, `/Applications` to safe paths
   - Never try to "smart scan" Application Support
   - These are ALWAYS protected

6. **Don't Trust User Requests Blindly**
   - If user says "please add X to cleanup", verify first
   - Users may not understand consequences
   - Test extensively before adding

7. **Don't Assume Regeneration**
   - "Cache" in name doesn't mean regenerable
   - Some "caches" contain critical data
   - Example: Chrome stores profiles in Cache directory

---

## Verification Checklist

Before adding ANY path to `safeCachePaths`, complete this checklist:

### Research Phase

- [ ] Found official documentation for this directory
- [ ] Read at least 3 independent sources confirming safety
- [ ] Sources are recent (within 2 years)
- [ ] No sources warn against deletion
- [ ] Understand what data is stored here

### Testing Phase

- [ ] Backed up test machine (Time Machine)
- [ ] Noted current directory size
- [ ] Deleted directory on test machine
- [ ] Restarted affected application(s)
- [ ] Verified app launches successfully
- [ ] Verified app functionality (not just launch)
- [ ] Checked for error messages or warnings
- [ ] Monitored for 24-48 hours
- [ ] No data loss detected
- [ ] No performance degradation (beyond initial cache rebuild)

### Documentation Phase

- [ ] Added source URLs in code comments
- [ ] Noted testing date
- [ ] Described what's stored in this directory
- [ ] Updated this guide with new information
- [ ] Added to category description if needed

### Code Review Phase

- [ ] Verified path string is correct (no typos)
- [ ] Checked path doesn't overlap with protected paths
- [ ] Added to correct category (cache vs temp vs user data)
- [ ] Verified pattern matching works correctly

**Sign-off:** Only add after ALL boxes checked.

---

## Research Resources

### Official Documentation

1. **Apple Developer Documentation**
   - File System Programming Guide: https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/
   - Foundation Framework: https://developer.apple.com/documentation/foundation/filemanager
   - macOS Release Notes: https://developer.apple.com/documentation/macos-release-notes

2. **Browser Documentation**
   - Chromium User Data Directory: https://chromium.googlesource.com/chromium/src/+/master/docs/user_data_dir.md
   - Firefox Profiles: https://support.mozilla.org/en-US/kb/profiles-where-firefox-stores-user-data
   - Safari Documentation: Part of macOS docs

3. **Package Manager Documentation**
   - Homebrew FAQ: https://docs.brew.sh/FAQ
   - npm Documentation: https://docs.npmjs.com/cli/v8/configuring-npm/folders
   - pip User Guide: https://pip.pypa.io/en/stable/user_guide/
   - Cargo Documentation: https://doc.rust-lang.org/cargo/

### Third-Party Safety Resources

1. **CleanMyMac Documentation** (Most Authoritative)
   - Safety Database: https://macpaw.com/support/cleanmymac-x/knowledgebase/safety-database
   - How to Clear Cache: https://macpaw.com/how-to/clear-cache-on-mac
   - macOS Cleanup Guide: https://macpaw.com/cleanmymac-x/mac-cleanup

2. **Tech Support Sites** (Verify Multiple Sources)
   - iBoysoft (macOS utilities): https://iboysoft.com/wiki/
   - MacPaw How-To: https://macpaw.com/how-to/
   - AppInstitute Guides: https://appinstitute.com/
   - MacKeeper Blog: https://mackeeper.com/blog/

3. **Community Forums** (Use with Caution)
   - Apple Support Communities: https://discussions.apple.com/
   - MacRumors Forums: https://forums.macrumors.com/
   - Reddit r/MacOS: https://reddit.com/r/MacOS
   - Stack Overflow: https://stackoverflow.com/questions/tagged/macos

   ⚠️ **Warning**: Community forums are helpful for research but NOT authoritative. Always verify with official docs.

### Search Strategies

**Effective search queries:**
```
"[directory name] macOS safe to delete"
"~/Library/Caches/[app] safe to remove"
"macOS [version] cache cleanup"
"[app name] cache location macOS"
"CleanMyMac [app name] safe"
```

**Red flags in search results:**
- "It should be fine" (not definitive)
- "Probably safe" (not certain)
- Old articles (pre-2020)
- Single anecdotal experience
- No explanation of consequences

**Green flags:**
```
- Official documentation
- CleanMyMac confirms it
- Multiple sources (3+) agree
- Explains what regenerates
- Recent article (within 2 years)
```

---

## Testing Protocol

### Phase 1: Development Machine Testing

**Setup:**
1. Full Time Machine backup
2. Note current state (screenshots, directory listings)
3. Document app versions being tested

**Test Steps:**
1. Run DevDash scan on test category
2. Review items found
3. Verify no protected paths appear in results
4. Select items and delete (move to trash first)
5. Restart affected applications
6. Test application functionality:
   - Launch successful?
   - Core features work?
   - Settings preserved?
   - User data intact?
7. Monitor for 48 hours
8. Empty trash only after confirming success

**Success Criteria:**
- All apps launch normally
- No error messages
- No data loss
- No performance issues (after initial cache rebuild)
- No user settings lost

### Phase 2: Secondary Machine Testing

**Setup:**
1. Test on different macOS version if possible
2. Different hardware (Intel vs Apple Silicon)
3. Different app versions

**Repeat Phase 1 test steps**

### Phase 3: Monitored Release

**Process:**
1. Release to beta testers first (if available)
2. Monitor for 1 week
3. Request feedback specifically about deleted items
4. Check for any reports of issues

**Only proceed to production if:**
- No issues reported in Phase 1
- No issues reported in Phase 2
- No issues from beta testers
- 100% confidence in safety

---

## Emergency Response

### If User Reports Data Loss

**Immediate Actions (Within 1 Hour):**

1. **Stop the Bleeding**
   ```swift
   // Immediately add to protectedPaths
   "Library/[reported-path]", // EMERGENCY: User reported data loss - [date]
   ```

2. **Release Hotfix**
   - Bump version
   - Build and test
   - Release immediately
   - Notify users to update

3. **User Support**
   - Apologize
   - Ask if they have Time Machine backup
   - Guide recovery process
   - Offer to help restore data

**Investigation (Within 24 Hours):**

1. **Reproduce**
   - Set up identical environment
   - Run same scan/delete operation
   - Verify what was deleted

2. **Root Cause Analysis**
   - Why was this path not protected?
   - Was it in a scanned category?
   - Did SafetyDatabase validation fail?
   - Was it a code bug or missing protection?

3. **Document**
   - Add to this guide
   - Update code comments
   - Create incident report

**Prevention (Within 1 Week):**

1. **Review Similar Paths**
   - Are there related paths that should be protected?
   - Update entire category if needed

2. **Add Tests**
   - Add unit test to verify protection
   - Add to testing protocol

3. **Update Documentation**
   - Update this guide
   - Add to "Never Do" section
   - Update SafetyDatabase comments

### False Positive (Path Incorrectly Protected)

**If user reports valid cleanup is being blocked:**

**Investigation Required:**

1. Research extensively (3+ sources)
2. Test deletion on multiple machines
3. Monitor for 1 week
4. Get confirmation from 2+ team members

**Only Remove Protection If:**
- 100% certain it's regenerable
- Tested on 3+ machines
- Monitored for 1+ week
- Multiple authoritative sources confirm
- No edge cases found

**Document Reasoning:**
```swift
// Removed from protectedPaths 2026-03-01
// Reason: Confirmed regenerable by [sources]
// Tested on: macOS 14, 15 (Intel & Apple Silicon)
// Monitoring: 1 week, no issues
```

---

## Version History

### Version 1.0 (2026-02-24)
- Initial safelist creation
- Based on CleanMyMac research
- Browser protection rules
- Conservative approach implemented
- Sources documented

### Future Versions

Document all changes here:

```
Version X.X (YYYY-MM-DD)
- Added: [path] to safeCachePaths
- Reason: [why]
- Sources: [URLs]
- Tested: [dates/machines]
```

---

## Contributing to This Guide

### When to Update This Guide

- After adding new paths to SafetyDatabase
- After macOS updates
- After discovering new research
- After user reports
- After any safety-related changes

### How to Update

1. Edit this file: `DevDash/Modules/StorageManager/SAFETY_DATABASE_GUIDE.md`
2. Document sources with URLs
3. Update version history
4. Commit with descriptive message
5. Tag safety-related commits: `[SAFETY]`

---

## Final Notes

### Philosophy

DevDash's storage cleanup is **deliberately conservative**. We would rather:
- Miss cleaning some safe files
- Than delete one critical file

### Trust but Verify

- Trust authoritative sources (Apple, CleanMyMac)
- But always verify with testing
- Never trust single sources
- Never assume

### User First

- User data is sacred
- When in doubt, protect
- Transparency over cleaning efficiency
- Safety over features

---

**Last Updated:** 2026-02-24
**Next Review:** 2026-05-24 (Quarterly)
**Contact:** DevDash Development Team

---

## Quick Reference

### Safe to Clean (High Confidence)
- Xcode DerivedData
- Homebrew cache
- npm cache
- pip cache
- cargo cache
- /private/tmp

### NEVER Clean (Protected)
- ~/Library/Application Support
- ~/Library/Preferences
- ~/Library/Keychains
- ~/Library/Mail
- ~/Library/Messages
- ~/Library/Safari
- Browser Profiles (Chrome Default, Firefox Profiles)

### Research First (Uncertain)
- App-specific caches
- New app directories
- Unfamiliar paths
- Anything not documented here
