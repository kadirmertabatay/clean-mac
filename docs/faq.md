# FAQ and Troubleshooting

## Installing and launching

### "CleanMac can't be opened because the developer cannot be verified"

Releases are ad-hoc signed; they are not signed with an Apple Developer ID and not notarized. To open the app:

- **macOS 14:** in Finder, right-click the app › **Open** › **Open**.
- **macOS 15 and later:** try opening the app once, then click **Open Anyway** for CleanMac under **System Settings › Privacy & Security**.

If you'd rather not trust a binary, build from source: `./build-app.sh`.

### Permissions are requested again after rebuilding

The ad-hoc signature changes with every build, and macOS ties permissions to the signature. Remove the old CleanMac entry from **System Settings › Privacy & Security › Full Disk Access** and add the new one.

### There's a menu bar item but no window

While the menu bar item is enabled, closing the main window doesn't quit the app. Click the item and choose **Open CleanMac**, or click the Dock icon. If you want the app to quit when the window closes, turn off **Settings › Menu bar**.

### How do I switch the language?

Open **Settings (⌘,) › Language**, choose **English**, **Türkçe** or **System Default**, and click **Restart Now**. English is the default.

## Scanning

### Some folders show "No access"

macOS only opens some locations (Mail, Messages, Safari, the Trash, iPhone backups…) to apps with **Full Disk Access**. Add CleanMac under **System Settings › Privacy & Security › Full Disk Access** and restart the app. Without it, these locations are shown as "No access", never as "All clean". The app never reports an empty result as "clean" by mistake.

### The scanned total is less than the disk's "used" space

That's expected. The space the scan can't see may consist of:

- the macOS system volume and the Preboot / Recovery volumes,
- local Time Machine snapshots,
- space macOS keeps as "purgeable",
- folders without permission,
- virtual memory files.

The **Storage Breakdown** screen explains the difference volume by volume. For the full picture, set the scope to **Entire Mac (/)**.

### The Entire Mac scan doesn't include my external disk

That's intentional. `/Volumes` is skipped so external disks don't mix into the totals and aren't touched unintentionally. To scan an external disk, choose **Other Folder…** from the scope menu and select the disk.

### Scanning is slow

The first scan takes longer while the file system cache is cold. The scanner uses every core; on an SSD a home folder usually finishes in seconds and the whole disk within a minute or two. Network disks and folders with lots of small files (e.g. `node_modules`) take longer.

### The "last used" date looks wrong

The date comes from the access date macOS keeps and from Spotlight. Some apps read files without "opening" them, or Spotlight may not be indexing a folder. Check a file that looks old with **Quick Look** before deleting it.

## Cleaning up

### I deleted something by mistake

If the item was moved to the Trash, click **Restore** on the **Cleanup History** screen and it goes back to where it was. If the Trash has been emptied or permanent deletion was chosen, it can't be restored by CleanMac; you can restore it from a Time Machine backup.

### Some items say "skipped"

Every item is checked again right before removal. An item is skipped when:

- it changed after the scan,
- it no longer exists,
- it is in the exclusions,
- for duplicates, the copy to keep has disappeared.

The reason is shown in the notification. Scan again to refresh the list.

### I cleaned caches but free space didn't change

- If the items are in the Trash, the space stays in use until the Trash is emptied.
- Running apps may recreate their caches right away.
- macOS can take a few minutes to update free space (especially when APFS snapshots exist).

### Is deleting caches safe?

Categories labeled "Safe" are data that apps recreate when needed. After they're deleted, the app may be a little slower on its next launch or download some content again; no data is lost. If you never want an app's cache touched, protect it in **Smart Cleanup**.

### I never want a folder to be suggested

Right-click it in a list › **Exclude**. Excluded items never appear in any list, never go into any automated flow, and are skipped at the final check during removal.

## Privacy

### Does CleanMac connect to the internet?

No. The app makes no network requests and sends no analytics or crash reports. Some features run system tools (`brew`, `docker`, `xcrun simctl`, `tmutil`, `diskutil`); those tools behave according to their own settings.

### What data does it store?

The cleanup history, scan summaries (folder sizes and the paths of large files) and settings, only on your Mac. See [safety.md](safety.md#stored-data) for details and a command that deletes all of it.

## Other

### Which languages are available?

English and Turkish. Translations are welcome; see [development.md](development.md#adding-a-language) and [CONTRIBUTING.md](../CONTRIBUTING.md).

### Does it work on Intel Macs?

Yes. Releases are universal binaries (Apple silicon and Intel), and building from source works on any Mac running macOS 14.
