import Foundation

enum DiagramCraftSkill {
    static let instructions = """
---
name: diagram-craft
description: Create clear SVG diagrams, charts, and interactive visuals in a Tailwind + shadcn/ui codebase without relying on a diagram runtime. Use this skill for flowcharts, architecture diagrams, illustrative explainers, data charts, schemas, comparison visuals, and interactive widgets. Also use it when a request says “show,” “diagram,” “visualize,” “draw,” “chart,” or “illustrate.” Start by deciding whether a visual is useful, then choose the right visual form, apply the project’s design tokens, calculate the layout, and run the final quality checks.
---

# Diagram craft

Use this skill when you need to create a visual directly with SVG, HTML, Tailwind, and shadcn/ui.

Choose the artefact kind before designing. Use `inlineWeb` for a focused visual embedded in chat.
Use `web` for an immersive experience such as a game, simulation, editor, map, or interactive demo
that needs its own scene, navigation, persistent controls, or a fullscreen-sized canvas. The strict
seamless-host rules below apply to `inlineWeb` and host-facing UI. A `web` scene may own its visual
background, physical materials, lighting, and internal scrolling, while keeping controls, labels,
focus states, network access, and accessibility within Ginny’s injected boundaries.

## Governing principle: make the widget seamless

The user should not be able to tell where the chat response ends and the widget begins. Treat the widget as a visual extension of the response, not as a separate mini-application or document.

This principle controls the presentation rules:

- Keep the widget background transparent. Do not add a page, panel, or full-canvas background.
- Do not wrap the widget in a `Card` or another outer container. The host already provides the surface, spacing, and boundary.
- Do not place a visible title, subtitle, caption, instructions, or explanatory prose inside the widget. Chat typography does not automatically carry into widget internals, so duplicated text will look disconnected.
- Put all explanation, framing, and interpretation in the surrounding response.
- Keep only the visual, its direct labels, its controls, and necessary value readouts inside the widget.

Accessibility-only metadata such as SVG `<title>` and `<desc>` is allowed because it is not visible layout content. It does not replace the explanation in the response.

The main challenge is not writing SVG. It is choosing the right visual, sizing it correctly, keeping it readable in light and dark mode, and avoiding layout mistakes without breaking the seamless host presentation.

Follow this order:

1. Decide whether a visual is needed.
2. Choose the visual form.
3. Plan the content and layout.
4. Apply the project’s existing tokens.
5. Fit the visual into the host without adding a second surface.
6. Write the SVG or widget.
7. Run the pre-flight checks.

Do not start with colors or markup. A technically correct diagram can still fail if the form or layout is wrong.

---

## Hard constraints: three tiers

These rules are intentionally strict for inlineWeb. Ginny injects Tailwind CSS, shadcn-compatible utilities,
and the project’s theme variables into every web and inlineWeb preview. The artefact is a guest
inside the host conversation, not a standalone design exercise.

Do not slop the visual. Do not manufacture a dashboard, poster, card grid, decorative hero,
or mini design system when a focused diagram will do. Every shape, color, label, and control must
earn its place by explaining the mechanism or supporting the interaction.

### Tier 1 — breaks

These are non-negotiable and must be checked before returning the artefact:

- Ginny injects Tailwind CSS and the theme colors. Do not include Tailwind, a CDN stylesheet,
  a CSS reset, a second palette, or replacement theme variables.
- Do not put literal colors in inlineWeb or host-facing UI. No hex, `rgb()`, `hsl()`, `oklch()`,
  named colors, inline SVG colors, or invented color variables. Use the injected semantic and chart
  tokens. A full web scene may use physical colors only when they describe the depicted object or
  lighting, never as a replacement for injected control or host UI tokens.
- Keep an inlineWeb root transparent. Do not add a full-canvas background, outer border, host card,
  visible title, subtitle, caption, instructions, or explanatory prose. A full web scene may own a
  background and scene shell when those are the experience itself.
- In SVG, use `fill-*` for `<text>`, never only `text-*`; use `fill-none` on every connector path.
- Use literal Tailwind class names. Never interpolate class names such as ``fill-chart-${i}``.
- Give every SVG marker and clip-path a diagram-unique ID. IDs are global across the page.
- Keep inlineWeb content in normal flow. Never use `position: fixed` or a full-device canvas in an
  inlineWeb artefact. A web artefact may use a fullscreen-sized scene when its interaction requires it.
- Keep state in memory or the provided artefact API. Never use `localStorage` or `sessionStorage`
  in a sandboxed preview.
- Format every displayed number with rounding or a formatter. Floating-point noise is a rendering
  failure, not a cosmetic detail.
- Do not use `role="img"` on an SVG that contains focusable controls.

### Tier 2 — reads as broken

These choices render, but make the visual feel like a bug or a low-quality generated widget:

- Use one fixed `viewBox` width, preferably `680`, across related diagrams. Do not let a narrow
  diagram magnify its text relative to the rest of the set.
- Prefer three or four major nodes. Split before seven. Do not hand-place dense ERDs or class
  diagrams; use Mermaid for schema layout.
- Do not draw cycles as rings, rotate text, draw backward arrows through a linear flow, or let
  connectors pass through shapes and rely on fills to hide them.
- Do not solve label collisions with opaque rectangles behind text. Move, shorten, simplify, or
  split the diagram.
- Do not use black or neutral text on a colored fill. Use a readable same-hue token.
- Do not assign colors by sequence. Color encodes category, magnitude, polarity, status, or
  emphasis, never “step one is blue.” Never use role-loaded status colors as arbitrary categories.
- Never let color be the only encoding. Add line style, shape, marker, or another cue.
- Do not add more hues to rescue an overcrowded chart. Fold minor series into “other,” use small
  multiples, or switch to a table.
- Never invent geographic coordinates or topology. Fetch real data or do not draw a map.
- Strip every label as a test. If the remaining shapes do not convey a mechanism or relationship,
  the visual is decoration and should become prose.

### Tier 3 — design-system opinions

These are defaults, not physics. Break them only for a clear reason and keep the surrounding
system coherent:

- Use two font sizes: 14px for primary labels and 12px for secondary labels.
- Use weights 400 and 500. Avoid 600/700 unless the host system requires them.
- Use `0.5` for hairline boundaries and `1.5` for connectors.
- Use an 8px corner radius and 12px internal box padding unless the injected theme suggests otherwise.
- Keep animation loops under two seconds and animate only `transform` or `opacity`.

### Hard numbers

| Constraint | Default | Ceiling or rule |
|---|---:|---|
| Related SVG `viewBox` width | `680` | keep fixed across the set |
| Primary / secondary text sizes | `14px` / `12px` | two sizes only |
| Hairline / connector stroke | `0.5` / `1.5` | do not make structure heavier to solve layout |
| Major nodes | `3–4` | split at `7` |
| Category hues | `2–3` | `5` is the hard maximum |
| Chart series | `5` | fold minor series past `7` |
| Bottom padding | `40px` | add descender allowance first |

---

## 1. Decide whether a visual is useful

Use a visual only when it communicates something that prose cannot show as clearly.

A visual is usually justified when the request involves:

- spatial or containment relationships
- system structure
- a branching sequence
- a trend, distribution, magnitude, or outlier
- an interactive control or changing state

If none of these apply, answer with prose instead.

### Avoid decorative diagrams

A row of boxes labeled `input → process → output` is not automatically useful.

Use this test:

> Remove the labels. Does the arrangement still show a meaningful mechanism or relationship?

If the answer is no, the diagram is probably decoration.

### Avoid arbitrary metaphors

A metaphor should explain the mechanism, not merely decorate the subject.

For example:

- a call stack can be shown as frames that grow and shrink
- a hash function can be shown as items moving through a funnel into buckets
- gradient descent can be shown as a ball moving across a contoured surface
- attention can be shown as one token connected to other tokens with different weights

Do not draw a cloud just because the topic is cloud computing, or houses just because the topic is microservices.

---

## 2. Choose the visual form from the user’s intent

Choose the form based on what the user wants to understand or do, not just the subject they named.

| User intent | Recommended form |
|---|---|
| “How does X work?” / “Give me intuition for X” | Illustrative explainer |
| “Walk me through the steps” | Flowchart |
| “What is the architecture?” / “Where does X live?” | Structural or nested diagram |
| “Compare X and Y” / “Help me choose” | Card grid or plain table |
| Show trend, distribution, or magnitude | Chart |
| “Let me change X and see the result” | Interactive widget |
| Schema, ERD, or class diagram | Mermaid layout engine |

### Default rules

- For an unqualified “How does X work?”, prefer an illustrative explainer.
- When the real system has a meaningful control, consider making the visual interactive.
- Do not combine several visual families in one drawing.

If both intuition and reference are useful, present them separately:

1. show the intuitive visual
2. explain it in prose
3. show the structural or reference visual

---

## 3. Plan the content before drawing

List the important concepts, components, or states before placing anything.

### Keep each visual focused

A single diagram should usually contain no more than three or four major nodes or concepts.

If the request names six or more components, split the result into:

- one simplified overview
- one smaller visual for each important sub-flow

This reduces overlapping boxes, crossed arrows, and unreadable labels.

### Choose a consistent coordinate system

Use one fixed `viewBox` width for every related diagram.

For example, use a width of `680` for every diagram in a set, even when one diagram contains less content. Center narrow content inside the same coordinate space.

Do not change the `viewBox` width from diagram to diagram. With a responsive width, a smaller `viewBox` makes text and strokes appear larger and breaks layout consistency.

---

## 4. Use the project’s existing design tokens

A shadcn/ui project already provides theme-aware colors. Use those tokens instead of inventing a separate diagram palette.

The widget root must remain transparent. Tokens such as `--card` and `--muted` may be used for meaningful internal nodes, regions, controls, or plotted areas, but never to paint an outer widget background or recreate the host card.

Do not place literal hex values in inlineWeb or host-facing UI. A full web scene may use physical
colors for depicted materials and lighting when tokens would misrepresent the subject.

Dark mode should normally come from the ancestor `.dark` class. Avoid adding individual `dark:` variants unless they are genuinely needed.

### Neutral tokens

| Purpose | Token | Tailwind utility |
|---|---|---|
| Node or card fill | `--card` | `fill-card`, `bg-card` |
| Recessed or page fill | `--muted` | `fill-muted`, `bg-muted` |
| Main text | `--foreground` | `fill-foreground`, `text-foreground` |
| Secondary text | `--muted-foreground` | `fill-muted-foreground` |
| Borders and gridlines | `--border` | `stroke-border`, `border-border` |
| Focus or emphasis edge | `--ring` | `stroke-ring` |

### Do not use semantic UI colors as arbitrary categories

Do not use `--primary`, `--secondary`, `--accent`, or `--destructive` simply to distinguish categories.

These colors have interface meaning. For example, `--destructive` implies an error or dangerous action. Use semantic colors only for their intended meaning.

### Use chart tokens for categories

Use the chart tokens when categories need different colors:

```text
--chart-1 through --chart-5
```

They are available as utilities such as:

```text
fill-chart-1
stroke-chart-2
bg-chart-3
```

Use two or three category colors in most diagrams. Treat five as a hard maximum, not a target.

### Colored nodes need fill, border, and text treatment

A chart token provides one solid color, but a diagram node often needs:

- a light fill
- a stronger border
- readable text from the same color family

Use the injected tokens directly. If a node needs a softer fill, prefer an opacity modifier.

#### Option A: use opacity modifiers

This is the simplest option and works automatically in light and dark mode.

```html
<rect class="fill-chart-1/15 stroke-chart-1 [stroke-width:0.5]" rx="8" />
<text class="fill-chart-1 text-sm font-medium">Auth service</text>
```

Do not add a second palette for inlineWeb or host-facing UI. If the injected tokens do not provide
a suitable variant, use a neutral token or simplify the visual. A full web scene may use physical
colors for its depicted materials, but must still use injected tokens for controls, labels, focus
states, and host-facing UI.

For colored nodes, use same-hue text rather than black, `--foreground`, or neutral gray. The text
should belong to the same injected color ramp as the fill and border.

---

## 5. Start static SVGs with this template

Tailwind utilities work on SVG elements, so a separate `<style>` block is usually unnecessary.

The root stays transparent. Do not add a full-size background rectangle, outer border, card shell, visible heading, caption, or paragraph. The host supplies the surrounding surface, and the response supplies the explanation.

The arrow marker must be defined in `<defs>` because Tailwind does not provide a marker utility.

```svg
<svg viewBox="0 0 680 H" class="block w-full bg-transparent" role="img"
     xmlns="http://www.w3.org/2000/svg">
  <!-- Accessibility metadata only; these are not visible widget copy. -->
  <title>One sentence naming what this shows</title>
  <desc>A longer description for screen readers.</desc>
  <defs>
    <marker id="arrow-diagram-name" viewBox="0 0 10 10" refX="8" refY="5"
            markerWidth="6" markerHeight="6" orient="auto-start-reverse">
      <path d="M2 1L8 5L2 9" fill="none" stroke="context-stroke"
            stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" />
    </marker>
  </defs>
  <!-- diagram content -->
</svg>
```

Use a unique marker ID for each diagram. SVG IDs are global to the document, so repeated IDs can collide when multiple diagrams appear on one page.

### Recommended utility combinations

| Element | Utilities |
|---|---|
| Node box | `fill-card stroke-border [stroke-width:0.5]` |
| Node title | `fill-foreground text-sm font-medium` |
| Node subtitle | `fill-muted-foreground text-xs` |
| Connector | `stroke-border [stroke-width:1.5] fill-none` plus `marker-end` |
| Leader line | `stroke-muted-foreground [stroke-width:0.5] [stroke-dasharray:3_3]` |

If the same utility string appears repeatedly, move it into an `@utility` definition or component class.

---

## 6. Avoid common SVG mistakes

### Use `fill-*` for SVG text color

Tailwind’s `text-*` utilities set the CSS `color` property. SVG `<text>` elements paint with `fill`.

Incorrect:

```html
<text class="text-foreground">Label</text>
```

Correct:

```html
<text class="fill-foreground text-sm font-medium">Label</text>
```

The sizing utility still works because SVG respects `font-size`.

### Add `fill-none` to connector paths

SVG paths are filled by default. A connector path without `fill-none` can render as a large black shape.

```html
<path class="fill-none stroke-border [stroke-width:1.5]" d="..." />
```

### Use explicit hairline stroke widths

Diagram borders often need a `0.5` stroke width.

Use:

```text
[stroke-width:0.5]
```

A one- or two-pixel border often appears too heavy at diagram scale.

### Do not construct Tailwind classes dynamically

This may be removed by Tailwind’s source scanner:

```ts
`fill-chart-${i}`
```

Map to complete literal class names instead:

```ts
const FILL = [
  'fill-chart-1',
  'fill-chart-2',
  'fill-chart-3',
  'fill-chart-4',
  'fill-chart-5',
];
```

### Keep accessibility elements first

For a static diagram, place `<title>` and `<desc>` as the first children of the SVG and use `role="img"`.

The arrow marker uses `stroke="context-stroke"` so the arrowhead inherits the line color.

---

## 7. Size text and boxes before placing them

SVG text does not wrap automatically. Calculate the required space before drawing the box.

### Use two text sizes

Use:

- `text-sm` for node titles and region labels
- `text-xs` for subtitles and annotations

More font sizes usually create unnecessary visual noise.

### Estimate label width

For a 14px Latin sans-serif font, use these starting estimates:

- medium-weight text: about 8px per character
- regular text: about 7px per character

Use this formula:

```text
box_width ≥ max(title_chars × 8, subtitle_chars × 7) + 2 × padding
```

Treat this as an estimate, not a guarantee.

Uppercase text, digits, CJK characters, subscripts, and mathematical symbols may need more space. Add roughly 30–50% for labels containing symbols such as `C₆H₁₂O₆`, `∑`, or `√`.

When exact sizing matters, measure the text:

```js
const context = document.createElement('canvas').getContext('2d');
context.font = '500 14px system-ui, sans-serif';
context.measureText('Authentication service').width;
```

### Calculate the full row width

Before placing a row of nodes, calculate whether it fits:

```text
row_width = (node_count × box_width) + ((node_count - 1) × gap)
```

If the row is wider than the safe area:

- shorten subtitles
- reduce box width carefully
- split the row
- split the diagram

Do not place elements first and hope they fit.

### Center text vertically

For text inside a box, use:

```html
dominant-baseline="central"
```

Set `y` to the center of the text slot. Otherwise SVG treats `y` as the baseline, which often makes labels sit too high.

---

## 8. Run these pre-flight checks

Run every check before returning the visual.

1. **ViewBox fit**  
   Find the lowest shape and text baseline. Add about 4px for descenders, then add bottom padding.

2. **No content outside the canvas**  
   Check for negative coordinates and labels that extend beyond the left or right edge. With `text-anchor="end"`, verify that the label width is smaller than the anchor’s x-coordinate.

3. **Connectors do not cross nodes**  
   Trace every connector. If it crosses a box, route it around the box with an L-shaped path:

   ```text
   M x1 y1 L x1 ymid L x2 ymid L x2 y2
   ```

4. **No accidental overlaps**  
   Acceptable overlaps are limited to:
   - a label inside its own box
   - an arrowhead touching its target
   - a highlight placed behind the item it highlights

5. **Labels have clear space**  
   Move a colliding label to an open area. Do not hide the problem by placing an opaque rectangle behind the text. If there is no open area, simplify or split the diagram.

6. **Dark mode works**  
   Confirm that all text, borders, and fills remain readable on a near-black background. Any literal color such as `fill="#333"` is a warning sign.

7. **Displayed numbers are formatted**  
   Use `Math.round`, `toFixed`, or `Intl.NumberFormat` before showing values. Do not expose floating-point artifacts such as `0.30000000000000004`.

---

## 9. Use these patterns for common difficult cases

### Cycles

Do not automatically place cycle stages around a ring. Circular layouts are difficult to size and often produce overlapping labels and unclear arrows.

Prefer a stepper:

- one panel per stage
- a current-position indicator
- a next action that wraps from the final stage to the first

A linear row with a curved return arrow is acceptable only when the cycle has one input, one output, and little per-stage detail.

### Schemas and class diagrams

Use Mermaid for ERDs, class diagrams, and similar schemas.

These visuals require text layout, cardinality markers, and connector routing. A layout engine handles them more reliably than hand-positioned SVG.

### Backward flow

Avoid drawing a large arrow backward across a left-to-right flow.

Instead:

- use a small return indicator with a short label
- move the return path outside the main flow
- restructure the visual

### Connector endpoints

Stop connectors at the boundary of a component.

Do not draw a line through a node and rely on the node fill to hide it. That couples the connector to the background and can break when the surface color changes.

### Maps

Never invent geographic coordinates or hand-draw country outlines.

Use real topology data or do not draw the map.

### Rotated text

Avoid rotated axis labels and vertical annotations.

Prefer one of these:

- shorten the label
- move the label
- change the layout
- angle the full visual instead of rotating individual text

---

## 10. Choose color after the layout is working

First decide what color is supposed to communicate.

Color can represent:

- category
- magnitude
- polarity around a baseline
- status
- emphasis

### Color rules

1. Assign color by category, not by sequence. Do not make step 1 blue, step 2 amber, and step 3 red unless those colors have real meaning.
2. Use two or three hues in most diagrams.
3. Keep structural, start, and end nodes neutral when possible.
4. Use one hue plus neutral gray when only one item needs emphasis.
5. Do not solve too many series by adding more hues. After roughly seven series, group minor items into “other,” use small multiples, or switch to a table.
6. Never rely on color alone. Add a second cue such as marker shape, line style, or hatching.
7. Use same-hue text on colored fills. Do not use arbitrary black or neutral gray.

For illustrative diagrams, color may represent intensity rather than category:

- warm colors for active, hot, or high-weight areas
- cool colors for dormant or low-intensity areas
- gray for inactive structure

Reserve green, amber, and red for real success, warning, and error states.

---

## 11. Build interactive visuals as seamless widgets

Use a widget when the user can change a parameter or move through states. The widget must still read as part of the response rather than as a separate application surface.

Common controls include:

- sliders
- toggles
- tabs
- steppers
- live readouts

Keep the drawing in inline SVG and place only the controls and necessary live values around it. Put instructions and interpretation in the response.

### Use existing shadcn/ui components

Prefer installed components such as `Slider`, `Toggle`, `Tabs`, `Badge`, and `Tooltip`.

Do not add an outer `Card`. The host already provides the card-like surface. Use existing components only for real controls or small interface elements inside that surface. They provide theming, keyboard support, and focus behavior without introducing a second visual container. The SVG should be custom; the controls should use the existing component system.

### Animation rules

- Animate `transform` and `opacity` when possible.
- Keep repeating animations under about two seconds.
- Use `motion-safe:` and `motion-reduce:` variants.
- Prefer `motion-safe:animate-*` so motion is opt-in.
- Animate behavior such as flow, rotation, settling, or convection. Do not add motion only for decoration.

---

## 12. Apply the correct accessibility model

Static diagrams and interactive widgets need different accessibility patterns.

### Static diagram

Use:

- `role="img"`
- `<title>`
- `<desc>`

Do not place focusable controls inside the SVG.

### Interactive widget

Do not use `role="img"` on an SVG that contains or represents interactive controls.

Instead:

- set the SVG drawing to `aria-hidden="true"`
- put semantics on the real controls
- label every control
- expose important values in visible text, a live region, or `aria-valuetext`

Nothing important may be communicated only by the picture.

### Clickable SVG nodes

A `<g>` element with `onClick` is not automatically accessible.

Add:

- `role="button"`
- `tabIndex={0}`
- an `aria-label`
- Enter and Space keyboard handling
- a visible focus style

### Embedded or streamed HTML

When output is streamed into a chat surface:

- put short styles before the content
- put scripts last
- prefer inline styles on controls that must render correctly during streaming
- avoid `display:none` sections that appear suddenly after streaming
- avoid gradients and shadows that may flash during DOM updates

When output renders in one complete pass, do not add these streaming-specific workarounds.

Also:

- load a library’s `<script src>` before code that uses its global
- avoid `position: fixed` inside an embedded frame that sizes to content height
- use a normal-flow wrapper with `min-height` and a dim background to simulate overlays

---

## 13. Keep all explanation in the response

The response explains; the widget shows. Keep that boundary strict.

Do not place a visible title, subtitle, caption, instructions, takeaway, legend paragraph, or explanatory body copy inside the widget. Direct visual labels, axis labels, control labels, and compact value readouts are allowed when the visual cannot function without them.

A diagram with explanatory paragraphs inside it is effectively a screenshot of a document, and it breaks the seamless transition from chat text to visual.

When presenting multiple visuals, place a short explanation between them. Explain what the next visual adds and how it connects to the previous one.

Do not stack several visuals without connective prose.

Only promise the number of visuals you actually provide. One complete diagram is better than three incomplete diagrams.

---

## Final checklist

Before returning the result, confirm all of the following:

- The visual communicates something that prose alone would not show as clearly.
- The visual form matches the user’s intent.
- The diagram is focused enough to read without crowding.
- Text and boxes were sized before placement.
- All content fits inside the `viewBox`.
- Connectors stop at node boundaries and do not cross labels or boxes.
- The widget root is transparent and contains no full-canvas background.
- The widget does not recreate the host surface with an outer card, border, or panel.
- The diagram uses project tokens and works in dark mode.
- Color has a specific communication purpose.
- The result does not rely on color alone.
- Static and interactive accessibility rules are applied correctly.
- Visible titles, instructions, captions, and explanatory prose remain in the response, outside the widget.
- Only the visual, direct labels, controls, and necessary value readouts remain inside the widget.
- Every promised visual is included.
"""
}
