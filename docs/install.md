# Installing mujo

`install.sh` installs mujo for the user who runs it. It works on a fresh Arch
install and on a machine that already has its own dotfiles. Running it again
with the same answers changes nothing.

```sh
git clone <repo> ~/.local/share/mujo     # or run it from any checkout
cd ~/.local/share/mujo
./install.sh --dry-run    # the full plan, nothing changes
./install.sh              # questions, the plan, one confirmation, then unattended
```

| Flag | Effect |
| --- | --- |
| `--dry-run` | Print the plan and change nothing (no sudo needed) |
| `--yes`, `-y` | No questions: take every default. Defaults never remove packages and never retire an old `hyprland.conf` |
| `--skip-system` | Only `$HOME`: no sudo, no packages, no `/etc`, no services |
| `--retire-old-config` | With `--yes`: also retire `~/.config/hypr/hyprland.conf` |

Without a terminal and without `--yes`, the installer stops instead of
guessing. Every run is appended to `~/.local/state/mujo/install.log`.

## What it does, in order

1. **Preflight.** Arch Linux, not root, `jq`/`stow` present, 3 GiB free,
   network up, sudo works. A failed check stops the install.
2. **Questions.** Keyboard layout and variant, time zone, editor, browser
   package. Then the decisions that are expensive to undo: replacing the
   current login screen with greetd, switching the locale to `en_US.UTF-8`,
   removing packages mujo replaces (`packages/replaced.txt`), removing
   Vicinae, and retiring the old `hyprland.conf`. Defaults come from the last
   run (`~/.config/mujo/config.json`, key `install`), then from the system.
3. **The plan.** Every link, every file that will be backed up, every stow
   package that will be unfolded or unstowed (with the links it removes).
4. **Packages** from `packages/pacman.txt` (`pacman -S --needed`).
5. **Your home directory.**
   - Folded stow links that mujo needs to write into (for example
     `~/.local/bin` pointing into another stow tree) are unfolded: the
     package is restowed with `--no-folding`, so the same files stay reachable.
   - Everything that is about to be replaced is backed up first.
   - Conflicting stow packages are unstowed; plain files in the way are removed.
   - `stow --no-folding` links `config/*` into `$HOME`.
   - `~/.config/hypr/host.lua` and `~/.config/zsh/local.zsh` are written once.
   - `mujo theme build` generates the theme files.
   - GSettings: dark colour scheme and adw-gtk3 (when a session bus exists).
6. **`/etc`.** The greetd config and console palette (generated, staged in
   `~/.local/state/mujo/theme/system/`) and `mujo-vtrgb.service`. Each file
   is shown as a diff or in full before it is written; the previous version is
   backed up.
7. **Services.** NetworkManager, bluetooth, `mujo-vtrgb` (palette loads at
   once), greetd (from the next boot; the old login screen is disabled only if
   you agreed). It warns if iwd and NetworkManager would fight over Wi-Fi.
8. **Locale, time zone, login shell.** Time zones are compared by content, so
   `Canada/Mountain` and `America/Edmonton` count as the same.
9. **Removals** you agreed to (`pacman -Rns`). mujo cannot undo these.

**Fingerprint.** On a machine with a fingerprint reader the installer asks
whether `sudo` should accept a fingerprint (default: no). If you agree it
installs `fprintd`, lets you enroll a finger, and puts `pam_fprintd.so` first
in `/etc/pam.d/sudo`, with the password as the fallback; the old file is
backed up and `mujo uninstall` restores it. The lock screen uses an enrolled
finger by itself, without any of this.

Packages on mujo's list that were only installed as a dependency of something
else are marked as explicitly installed, so that removing that something does
not take them along.

## Backups

Each run that replaces something creates
`~/.local/state/mujo/backups/<time>/`:

| Path | Contents |
| --- | --- |
| `home/...` | Replaced files and symlinks, at their path under `$HOME` (symlinks stay symlinks) |
| `etc/...` | Replaced files from `/etc` |
| `stow-<name>.tar` | The whole stow directory, taken before mujo unfolds or unstows any of its packages |
| `manifest.json` | Every action: backed-up paths, unfolded and unstowed packages (with their links), `/etc` files and whether they existed, the old login screen, the old locale, removed packages |

## Uninstalling

```sh
mujo uninstall --dry-run   # the plan; changes nothing
mujo uninstall --yes       # asks for sudo for the /etc part
```

`mujo uninstall` reads every manifest, newest first, and reverses it: the
links from `config/` are removed, files are restored from `home/` and `etc/`,
dotfile packages that were unstowed are stowed again, directories that were
unfolded become the single link they were, and the previous login screen and
locale come back. What mujo itself generated or wrote (theme files,
`host.lua`, `local.zsh`, `~/.config/mujo`) is moved to
`~/.local/state/mujo/uninstalled/<time>/`, not deleted.

It does not remove packages, does not reinstall packages you let the
installer remove (it lists them), and leaves the login shell, the checkout,
the backups and the journal alone. A backup directory without a manifest
comes from an install that was interrupted; its files stay there and are
reported, not restored. `--skip-system` leaves `/etc` and services untouched.
Run `install.sh` again to bring mujo back.

## Coming from an existing Hyprland setup

**Hyprland 0.57 removed `hyprland.conf` support** (release notes: "config:
remove legacy config support"). With 0.57 installed, a `hyprland.conf` alone
is ignored, and Hyprland writes its example `hyprland.lua` instead.

The installer prints every line of the old file and where it went:

| Old setting | Goes to |
| --- | --- |
| App compatibility: `xwayland force_zero_scaling`, `ELECTRON_OZONE_PLATFORM_HINT`, `OZONE_PLATFORM`, cursor sizes, `gnome-keyring-daemon` | `compat.lua`, each with a comment saying what it fixes |
| `monitor =` lines, lid switch binds, `moveworkspacetomonitor` | `host.lua` (ported automatically) |
| Keyboard layout, variant, options, pointer sensitivity | `host.lua` (they are the defaults of the keyboard question) |
| Gaps, borders, rounding, animations | Replaced by the token-driven `look.lua` and `animations.lua` |
| Binds | `binds.lua`, same keys where they still make sense |
| waybar, hyprpaper, nm-applet, swaync | Replaced by the Quickshell UI (phase 3) |
| `xrdb -merge ~/.Xresources` | Dropped when the file does not exist |
| `dwindle:pseudotile` | Dropped: no longer a Hyprland option |

Retiring the old file is a question, never a default. If it comes from a stow
package, the whole package is unstowed (the question lists its links); the
files stay in your dotfiles directory and in the backup.

Once mujo's `~/.zshenv` is linked, zsh reads `~/.config/zsh` and no longer
reads `~/.zshrc`; the old file stays where it is. `local.zsh` sources your
`~/.aliases`, sets `EDITOR`, and hooks zoxide, direnv and mise if they are
installed. Copy anything else you want from the old file into `local.zsh`.

The installer does not reload the running Hyprland: the new configuration
starts with the next login, which is why it ends by asking for a reboot.

## Testing in a VM

Hyprland needs 3D acceleration. In virt-manager: Video **Virtio** with **3D
acceleration** on, Display **Spice** with **OpenGL** on. With QEMU directly:
`-device virtio-vga-gl -display gtk,gl=on`. A fresh archinstall "minimal"
profile with one sudo user and NetworkManager is enough; then clone and run
`./install.sh`.

What only real hardware can show: the lid switch, brightness keys, the
fractional scales on the laptop panel and the Dell, and how the console
palette looks on the real panel.
