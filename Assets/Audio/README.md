# Placeholder audio

Every `.wav` here was **synthesised by `Tools/generate_placeholder_audio.py`**, not
recorded or downloaded. They are not third-party assets and carry no external licence:
they belong to this project the same way the code does, which is why they live under
`Assets/` rather than `ThirdParty/`.

They exist so the audio wiring in `Scripts/Audio/SfxPlayer.gd` can be exercised end to
end. They are functional, not good — thin, synthetic, and obviously placeholder.

## Replacing them

Drop real files in with the same names and nothing in the game changes:

| File | Cue | Trigger |
|---|---|---|
| `throw_whoosh.wav` | `THROW` | a cone leaves the hand |
| `cone_car.wav` | `CONE_CAR` | cone strikes a target car, scaled by impact speed |
| `cone_ground.wav` | `CONE_GROUND` | cone strikes anything else, quieter |
| `cone_settled.wav` | `SETTLED` | a cone is counted; pitched up for a roof landing |
| `car_coned.wav` | `CAR_CONED` | a car reaches its required cone count |
| `reload_rustle.wav` | `RELOAD` | reload starts; repitched to the real lockout |
| `empty_click.wav` | `EMPTY` | a throw refused for an empty magazine |
| `low_time_beep.wav` | `BEEP` | once a second under the low-time threshold |
| `section_clear.wav` | `CLEAR` | a section is cleared |
| `time_up.wav` | `TIMEOUT` | the clock runs out |

`SfxPlayer` loads these at runtime rather than preloading them, so a missing file
warns and goes silent instead of breaking the autoload.

If you replace these with anything sourced from elsewhere, move it to `ThirdParty/`
and record the licence there with the other third-party credits.

## Regenerating

```sh
python3 Tools/generate_placeholder_audio.py Assets/Audio
```

Seeded per file, so regenerating produces identical output.
