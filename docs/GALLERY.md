# Gallery: albums and sharing with Android

Albums are plain folders under `~/Pictures` (`Camera` is the default one and the timeline); "add to album" makes a hard
link, "move" leaves the file only in the album, and `phonegallery-albums` (user level, `--selfcheck` for its tests)
does all file work. Waydroid's shared storage belongs to another user, so the one privileged step is
`/usr/local/bin/phonegallery-android` (root-owned, mode 755), run through sudo by this line in
`/etc/sudoers.d/phonegallery-android` (mode 440, written by `make install`, check it with `visudo -cf`):

    %wheel ALL=(root) NOPASSWD: /usr/local/bin/phonegallery-android

The helper takes only fixed subcommands (`send [--strip] FILE...`, `clear`, `expose-none`, `expose-albums NAME...`,
`expose-all`). Sources must be regular files without links directly inside a folder of the user's Pictures, album names
come from a strict character set, the destination is always `Pictures/PhoneGallery` in Waydroid's media folder and the
read-only bind mount always goes to `Pictures/PhoneGalleryView`. `clear` removes only the files in its own manifest
(`/var/lib/phonegallery-android/sent`). The gallery keeps the choice (`mode=send|album|all`, `albums=A,B`, `strip=1|0`)
in `~/.config/phonegluewc/gallery-android.conf` and puts the mount back when it starts, since a reboot drops it.

`phonegallery-android-apply` reads that file and calls the helper; the user unit `phonegallery-android.service` runs it at
login, so the exposure follows the setting after a reboot. The gallery also applies it when it starts.

Waydroid only sees bind mounts that existed when its container started, so after a container start the mounts are made
again. `phonegallery-android refresh` reads the saved choice (`gallery-android.conf`, album names validated like any other
argument), mounts what is missing, unmounts what should not be there and mounts again when the container's cgroup stamp
changed since the mounts were made. The user timer `phonegallery-android-refresh.timer` runs it once a minute and the
login unit runs it once at login. Both UIs apply a change at once through the helper and show its error if it fails.
