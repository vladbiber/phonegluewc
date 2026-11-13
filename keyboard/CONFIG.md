# phonekbd config

File: `$XDG_CONFIG_HOME/phonekbd/config`, or `~/.config/phonekbd/config`.

One `key = value` per line. `#` starts a comment. Unknown keys are ignored, an
invalid value means the default. On and off can also be written true and false. Write the file atomically (temporary file, then
rename). The keyboard reads it each time it is shown.

| Key | Values | Default |
|---|---|---|
| autocorrect | on, off | on |
| predict | on, off | on |
| learn | on, off | on |
| predict_languages | language codes separated by spaces | English and every installed pack |
| number_row | off, on | off |
| height | small (85), normal (100), large (115), or 70 to 140, with or without % | normal |
| key_height | the older name of height: 70 to 140; height wins if both are there | 100 |
| sound | off, on | off |
| vibrate | off, on | off |
| one_handed | off, left, right | off |
| theme | phone, dark, light, system, contrast, red (nothing means dark) | phone |
| accent | theme, red, orange, yellow, green, blue, purple | the phone's accent, else the theme's own |
| key_borders | on, off | on |
| corner_hints | on, off | on |
| key_preview | on, off: the bubble above a pressed letter | on |
| long_press | short (220 ms), normal (350 ms), long (600 ms) | normal |
| translate_from | language code, set by the Translate panel | first usable pair |
| translate_to | language code, set by the Translate panel | first usable pair |
| space_cursor | on, off | on |
| clipboard_history | on, off | on |
| emoji_history | on, off | on |
| autocap | on, off | on |
| double_space | on, off | on |

`theme = phone` follows `theme` in the shell's phone.conf (light or dark, missing is dark).
`theme = system` does the same, and without that key asks `gsettings` for `org.gnome.desktop.interface color-scheme` at
each show: `prefer-dark` is dark, `default` and `prefer-light` are light, and no
answer is dark. `height` changes the rows only: the 48 px top strip and the 26 px
strip under the keys stay as they are. A password field is never taller than
normal, so the lock screen keeps its room. `vibrate` uses a force feedback device
directly and does nothing when there is none.

`predict_languages` lists the languages words and corrections come from. A code with
no installed pack is skipped, except that `en` is always there. An empty value is
the same as `predict` and `autocorrect` off, and the letters on a long press stay.
`phonekbd-lang` adds a language to the list when it installs one and takes it out when
it removes one, but only if the line exists. A word of an installed language that is
not on the list is neither offered nor corrected into, and a typo that happens to be
such a word is left alone.

The top strip has a gear at its right end: it runs `phonesettings keyboard` and hides
the keyboard. A tap on the chevron beside the bar's pill hides it too; it comes back when a
field is focused anew or by the left edge swipe. Neither is there on a password or
sensitive field: on the lock screen a hidden keyboard would have no way back, and the
settings app must not open over it. The turned and laptop layouts have no top strip, so no gear.

`sound` follows the phone's ringer: with `ringer = vibrate` or `silent` in
`phonegluewc/phone.conf` the keys are quiet whatever `sound` says. It is read at each show.

After the chevron, a new tap in the same field does not bring it back: the field sends
nothing the keyboard could see. Focus another field and come back, or use the left edge swipe.

The keyboard itself rewrites `one_handed` and `theme` when they are changed from
its own buttons, and keeps every other line.

## Local data

In `$XDG_STATE_HOME/phonekbd`, or `~/.local/state/phonekbd`:

- `learned.tsv`, `bigrams.tsv`: learned words and word pairs
- `emoji-recent`: recently used emoji
- `layout`: normal or laptop

`phonekbd --clear-learned` deletes the first three and exits 0. It needs no
display, and a running keyboard does not write the old data back.

`emoji_history = off` deletes `emoji-recent` the next time the keyboard starts,
is shown or sees a copy, records nothing and hides the recent tab. Recording also
needs `learn` on. `phonekbd --clear-emoji-history` deletes the file at once
without changing the setting; run it when turning the switch off.

`clipboard_history = off` empties the list at the same moments, records nothing
and hides the list. Paste and the other edit keys keep working. `phonekbd
--clear-clipboard-history` asks a running keyboard to empty its list without
changing the setting, and it does so the next time it is shown or sees a copy.

`predict = off` shows no suggestions and `autocorrect = off` applies no corrections.
With both off the strip shows only its buttons, and no dictionary or learned data
is loaded. `learn` is its own switch.

Languages live in `$XDG_DATA_HOME/phonekbd` and `$XDG_DATA_HOME/phonegluewc/translate`,
or under `~/.local/share`. `phonekbd-lang list`, `install CODE`, and `remove CODE`
do what the Translate panel's Add list does; they use the network only for `list`
and `install`. `password-letters` there outlasts a removed language, so holding a key on a
password field still offers its letters and such a password can still be typed.

Clipboard history is kept in memory only, at most 20 items and 64 KB. Nothing is
kept or suggested in password or sensitive fields, nor on the lock and login
screens.
