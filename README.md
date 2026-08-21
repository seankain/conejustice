# Cone Justice

Some people park like the rules are for other people. You have a truck full of traffic cones.

**Cone Justice** is a physics-based throwing game about dispensing curbside justice. Scan the
street for cars parked where they shouldn't be — blocking hydrants, straddling two spots, parked
across the sidewalk — then lob a traffic cone at the offender. Cones are rigid bodies, so every
throw bounces, rolls, and topples for real. Land one on the roof for maximum justice; miss and
you'll watch your cone clatter off into the gutter.

## Gameplay

- Aim and throw traffic cones from a first-person view.
- Pick your targets: only illegally parked vehicles count.
- Ragdoll-ish, fully simulated cone physics — no two throws land the same way.
- Short, arcade-style levels set in a low-poly neighborhood street.

## Tech

- **Engine:** Godot 4.7
- **Language:** GDScript
- **Renderer:** GL Compatibility (for broad browser support)
- **Physics:** Jolt Physics (3D)
- **Target:** Web (HTML5), playable in the browser

## Project layout

```
Scenes/       Game scenes — Main (game root), level, Cone, SUV, Tree1
Scripts/      GDScript — Autoload/ (GameState, EventBus), Camera/, Gameplay/, UI/
ThirdParty/   Third-party models and textures (cars, building, trees, skybox)
docs/         Design and implementation notes
project.godot Godot project configuration
export_presets.cfg  Web export preset
```

`Scenes/Main.tscn` is the main scene: it composes the level, the camera rig, the
gameplay nodes and the HUD. `Scenes/level.tscn` is scenery and targets only.

## Running locally

1. Install [Godot 4.7](https://godotengine.org/download) or newer.
2. Clone this repo and open the folder with the Godot project manager (`Import` → select
   `project.godot`).
3. Press **F5** to run the main scene.

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

## Status

Early prototype. The scenes, models, and web export pipeline are in place; gameplay scripting
(throwing, scoring, target validation) is still being built out.

## Credits

Models, textures, and the skybox under `ThirdParty/` belong to their respective authors.
