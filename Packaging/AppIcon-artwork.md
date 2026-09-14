# LidRipple icon refinement

## Current refined material variant

The current `AppIcon.png` uses a pearl emblem with restrained relief on graphite.
Created with the built-in image editor. Previous dark version is preserved as
`AppIcon-dark-flat.png`; the light version is `AppIcon-light.png`.

Final prompt:

Use case: style-transfer. Edit the supplied LidRipple macOS icon into a refined premium native macOS app icon. Preserve identity: tilted open laptop outline, two concentric elliptical ripple arcs with central oval, curved laptop base, dark rounded-square tile. Refine rather than replace the mark. Reduce the overly heavy outline weight by about 15%, precisely smooth all curves, balance spacing, optically center emblem, keep the silhouette bold enough at 32px. Use a deep near-black graphite tile, satin finish, an extremely restrained top-left soft highlight and finely defined continuous rounded edges. Emblem should be luminous pearl-white ceramic with only a tiny hint of physical relief: fine bevel highlights and soft close contact shadows, mostly flat frontal faces; no shiny chrome, no chunky extrusion. Refined industrial design, restrained tactile material, exceptionally clean anti-aliased edges. Keep monochrome. No Apple logo, no text, no neon, no sparkle, no decorative border, no dramatic gradients, no realistic laptop photograph, no background scene. Entire composition front-on, square canvas, tile inset 6%, actual transparent alpha outside tile, production app icon. Maintain the reference logo's basic perspective and proportions; do not add extra ripple rings.

## Current dark variant

Built-in image editor used for the current `AppIcon.png`. Light variant preserved
as `AppIcon-light.png`. The menu-bar template icon is unchanged.

Final dark-variant prompt:

Use case: precise-object-edit. Edit target: supplied LidRipple macOS app icon. Change only the color scheme: rounded tile becomes near-black graphite (#111318) with a restrained satin gradient, slightly lighter upper edge; the entire laptop outline, curved base and concentric ripple emblem become soft silver-white (#E8EBEF), high contrast with subtle satin shading, no chrome reflections. Preserve the exact shapes, layout, scale, perspective, proportions, and generous readable strokes from input. Maintain existing rounded-square tile silhouette and transparent alpha outside it. Keep the interior screen area the same near-black as the tile. No text, no extra details, no neon glow, no colored accents, no mockup background. Elegant restrained production app icon, square output.

Edited with the built-in image generation tool from the owner's `Downloads/lidrip.png`.
Selected artwork: `AppIcon.png`. Packaged asset: `AppIcon.icns`.
Run `bash scripts/build-icon.sh` to regenerate the macOS icon sizes.
The original Downloads file is unchanged.

## Final editing prompt

Edit target: supplied LidRipple app icon. Preserve the exact dark laptop silhouette, perspective and concentric ripple emblem design. Enlarge the complete emblem to occupy about 72% of the square canvas width (currently about 51%), centered optically. Replace the full-bleed off-white background with an elegant off-white rounded-square macOS app tile, inset about 5% from canvas edges, continuous smooth corners with radius about 20% of tile width. Very subtle soft edge and shadow only, no dramatic 3D bevel. Outside the rounded tile must be actual transparent alpha, not white or a checkerboard. Output square 1024x1024 production app icon, no text, no additional objects, no mockup scene. Keep emblem dark charcoal, crisp and faithful to original. This is only a scale and tile refinement, not a logo redesign.
