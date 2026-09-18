# Parkade

**Parkade** (Park + Arcade) is a small arcade of browser games about parking badly and the
consequences of it. The main menu lists the cabinets; picking one loads it, and **Escape** brings
you back out to the menu from anywhere.

| Cabinet | State |
| --- | --- |
| **Cone Justice** — throw traffic cones at cars parked where they shouldn't be | playable |
| **Parking Game** — beat the clock, find a space, park it straight | playable |

## Cone Justice

Some people park like the rules are for other people. You have a truck full of traffic cones.

**Cone Justice** is a physics-based throwing game about dispensing curbside justice. Scan the
street for cars parked where they shouldn't be — slewed across the lines, straddling two bays,
nose hanging out into the road — then lob a traffic cone at the offender. Cones are rigid bodies,
so every throw bounces, rolls, and topples for real. Land one on the roof for maximum justice;
miss and you'll watch your cone clatter off into the gutter.

Not every car deserves it. Most of the street is parked perfectly legally, and coning an innocent
car costs you points. Look at the painted bay before you throw.

### Gameplay

- Aim and throw traffic cones from a first-person view.
- Pick your targets: cone the badly parked, leave the law-abiding alone.
- The street is dealt fresh every run, so which cars are in the wrong changes each time.
- Ragdoll-ish, fully simulated cone physics — no two throws land the same way.
- Short, arcade-style levels set in a low-poly neighborhood street.

## Parking Game

A GDScript port of [ParkingThings](https://github.com/seankain/parkingthings/tree/main/ParkingThings),
which is the same engine but written in C# — and a .NET build does not run on the web at all. Drive
a car around a lot against a countdown and park it between the lines; the round is graded A to F on
your angle, how centred you are, whether you crossed a line and what you hit on the way in.

It drives Cone Justice's cars: the source's placeholder is a box, and the SUV and minivan meshes
are already in this repo, so both cabinets share one set of vehicles. Picking the cabinet lands you
on vehicle select first — a carousel of cars turning on plates, in the San Francisco Rush shape —
and confirming one starts the round in it. Adding a car to the carousel is a resource, not code.

The lot does not hold still while you park in it. A parked car can back out and drive off, opening
a space that was not there a moment ago; a rival can come in off the road and take one, as often as
not the one you were lining up for. People get out of their cars and walk to the building, and
geese cross the aisle in a gaggle because it is there — hit one and it goes over, and it costs you
a grade. All of it gets likelier every level, so a later lot is a busier one rather than the same
one with less time on the clock.

[docs/parking-game.md](docs/parking-game.md) documents the game: the round, the grade table and
where to tune it. [docs/parking-game-port.md](docs/parking-game-port.md) is the plan the port
followed — what the source contained, which of its defects were fixed on the way across rather
than carried, and what is still outstanding.

**The people and the geese are a capsule and a box.** The source's pedestrian mesh is a free
Sketchfab download under the Sketchfab Standard licence rather than one of the Creative Commons
grants the other models carry, so bringing it across means crediting the author and checking that
licence about committing the mesh itself to a public repository — see
[docs/parking-game-port.md](docs/parking-game-port.md). What shipped instead is the behaviour with
a primitive standing in for the model: walking a navigation path, worth a full grade to hit, and
going over when a car reaches it. A real model swaps the mesh in and brings an animator and a
proper ragdoll with it; nothing around it changes. `ParkingRound.pedestrians_enabled` empties the
lot of them, which is what the tests use.

## The shell

`Scenes/Parkade/MainMenu.tscn` is the project's main scene. It builds its list of cabinets from
`Parkade.games` in `Scripts/Autoload/Parkade.gd`, so adding a game is one `ArcadeGame` entry there
and no change to the menu scene; a game whose `available` is false is listed greyed rather than
hidden.

`Parkade` is an autoload and owns every scene change: it unpauses the tree and restores the mouse
cursor on the way through, so nothing a game did to either can leak into the next one. It also
handles **Escape** as *unhandled* input, which means a game that wants Escape for its own pause
menu simply consumes it first.

The `GameState` and `EventBus` autoloads are Cone Justice's alone — a second game gets its own
state rather than widening those. `SfxPlayer` and `MusicPlayer` are shared, and the music keeps
playing across cabinets.

## Tech

- **Engine:** Godot 4.7
- **Language:** GDScript
- **Renderer:** GL Compatibility (for broad browser support)
- **Physics:** Jolt Physics (3D)
- **Target:** Web (HTML5), playable in the browser

## Project layout

```
Scenes/Parkade/  The arcade menu — MainMenu, the project's main scene
Scenes/          Cone Justice scenes — Main (its root), level, Cone, SUV, Tree1, UI/
Scenes/ParkingGame/  Parking game scenes — Main (its root)
Scenes/Vehicles/ Drivable chassis, shared by whichever cabinet wants to drive one
Scripts/         GDScript — Autoload/, Parkade/, Audio/, Camera/, Gameplay/, ParkingGame/, UI/
Assets/          First-party assets (vehicle and pedestrian catalogs, generated placeholder audio)
ThirdParty/      Third-party models and textures (cars, building, trees, skybox)
Tools/           Asset generation scripts
docs/            Design and implementation notes
project.godot    Godot project configuration
export_presets.cfg  Web export preset
```

Cone Justice's scenes and scripts sit at the top of `Scenes/` and `Scripts/` rather than under a
folder of their own; it was here first, and moving it would touch every scene in the repo for no
gain. The parking game goes in `Scenes/ParkingGame/` and `Scripts/ParkingGame/`.

`Scenes/Main.tscn` is Cone Justice's root: it composes the level, the camera rig, the
gameplay nodes and the HUD. `Scenes/level.tscn` is scenery, the camera rail and the
parking bays; the cars are spawned into those bays when a run starts. See
[docs/parking-bays.md](docs/parking-bays.md) for how a car ends up innocent or guilty, and
[docs/vehicle-variety.md](docs/vehicle-variety.md) for adding a vehicle to the pool the
bays are filled from.

## Running locally

1. Install [Godot 4.7](https://godotengine.org/download) or newer.
2. Clone this repo and open the folder with the Godot project manager (`Import` → select
   `project.godot`).
3. Press **F5** to run the main scene — the Parkade menu. **F6** runs whichever scene is open, so
   `Scenes/Main.tscn` still launches straight into Cone Justice while you work on it.

## Web export

A `Web` export preset is already configured, targeting `Export/export/WebProject.html`.

From the editor: **Project → Export… → Web → Export Project**.

Or from the command line:

```sh
godot --headless --export-release "Web" Export/export/WebProject.html
```

Web builds must be served over HTTP — opening the `.html` file directly from disk won't work:

```sh
python3 -m http.server --directory Export/export 8000
```

Then visit <http://localhost:8000/WebProject.html>.

## Deployment

Every push to `main` is exported and published to GitHub Pages by
[`.github/workflows/deploy-pages.yml`](.github/workflows/deploy-pages.yml):

<https://seankain.github.io/conejustice/>

The workflow installs the pinned Godot editor and its export templates (checking both downloads
against the SHA-512 checksums published with that release), imports the project, runs the `Web`
preset into `build/web/index.html`, verifies the export actually produced `index.html`,
`index.js`, `index.wasm` and `index.pck`, and uploads that directory as the Pages artifact. Pull
requests against `main` run the same build as a check, but only `main` is ever deployed.

### Blender import is off

`filesystem/import/blender/enabled=false` in `project.godot`. Godot's `.blend` importer shells out
to Blender, and on a runner without it the importer fails during the filesystem scan and takes the
**entire** reimport pass down with it — every texture and every sound is then packed as an empty
entry, so the build loads and plays with white models and no audio while the workflow still reports
success. Nothing loads the `.blend` at runtime: `ThirdParty/LowPolyTrees/LowPolyTrees.blend` was
imported once with its meshes and materials saved next to it as `.res`/`.tres`, and
`Scenes/Tree1.tscn` references those. The `.blend` and its `.import` stay in the repo for
provenance and for the import settings; turn the setting back on locally (and install Blender) if
you need to re-import the trees.

Two guards keep that failure mode from reaching the site again: the build fails if
`godot --headless --import` produces no imported resources at all, and it fails if the export logs
an error naming `res://.godot/imported`, which is the only signal that a resource was packed empty.

One-time repository setup: **Settings → Pages → Build and deployment → Source: GitHub Actions**.
Until that is set there is no Actions-based Pages source to publish to, and the deploy job fails.

The `Web` preset exports without thread support, so the build needs no `Cross-Origin-Opener-Policy`
or `Cross-Origin-Embedder-Policy` headers. That is what makes it hostable on GitHub Pages, which
does not let you configure response headers; turning on **Thread Support** or **Extension Support**
in the preset would require those headers and break the deployment.

To change engine version, update `GODOT_VERSION` in the workflow together with both checksums,
which are published in `releases/godot-<version>.json` in
[godotengine/godot-builds](https://github.com/godotengine/godot-builds).

## Status

Early prototype, with two cabinets playing. Cone Justice's core loop — throwing, scoring, target
validation and the randomised street — plays end to end. The parking game plays its own loop end
to end too: vehicle select, a graded round in a lot filling with parked cars, cars leaving and
rivals arriving while you park, people and geese crossing in front of you, and levels that get
shorter, fuller and busier. An end to the run, and the licensed meshes to replace the placeholder
pedestrians, are what the port left open.

## Credits

Models, textures, and the skybox under `ThirdParty/` belong to their respective authors.

Two of them are CC-BY-4.0 and require attribution, so their `license.txt` sits beside the model and
the required credit is reproduced here:

- This work is based on ["Auzrea Parking Final"](https://sketchfab.com/3d-models/auzrea-parking-final-f8cc7c78aa1e40fb832d05ec6733aa73)
  by [MML0385](https://sketchfab.com/MML0385) licensed under
  [CC-BY-4.0](http://creativecommons.org/licenses/by/4.0/) — `ThirdParty/Models/ParkingLot/`.
- This work is based on ["Low rise wall to wall office building"](https://sketchfab.com/3d-models/low-rise-wall-to-wall-office-building-6488ad5edd1d454884b3fe030f5f04b1)
  by [aitortilla01](https://sketchfab.com/aitortilla01) licensed under
  [CC-BY-4.0](http://creativecommons.org/licenses/by/4.0/) — `ThirdParty/Models/OfficeBuilding/`.

Sound effects under `Assets/Audio/` are placeholders generated by
`Tools/generate_placeholder_audio.py` — first-party, no external licence. See
`Assets/Audio/README.md` before replacing them.

The three `music_track*.mp3` files under `Assets/Audio/` were added separately and are not
generated. If they came from elsewhere, their licence belongs in `ThirdParty/` with the other
third-party credits.
