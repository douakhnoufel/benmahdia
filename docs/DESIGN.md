# BenMahdia — Design System (DESIGN.md)

Calm, trustworthy health app. Soft teal + warm sand, rounded cards, generous
white space, large readable type. Bilingual: Arabic (full RTL, default) + French.

Tokens are the single source of truth. They map 1:1 to a Flutter `ThemeData`
(`apps/mobile`) and a Tailwind `theme.extend` (`apps/dashboard`). Never hardcode
a color, size, radius, or shadow — reference a token.

---

## 1. Color

### Brand — Teal (primary)
| Token | Hex | Use |
|---|---|---|
| `teal.50`  | `#EAF7F5` | tint backgrounds, selected-chip fill |
| `teal.100` | `#CDEAE6` | subtle fills, progress track |
| `teal.200` | `#A6DBD4` | borders on teal surfaces |
| `teal.300` | `#6FC5BB` | disabled primary, illustration |
| `teal.400` | `#39AB9F` | hover tint |
| `teal.500` | `#0F9E92` | **primary** — buttons, active icons, ring |
| `teal.600` | `#0C8578` | primary pressed/hover |
| `teal.700` | `#0A6A60` | primary text on light |
| `teal.800` | `#084F48` | deep accents |
| `teal.900` | `#063A35` | darkest brand |

### Neutral — Sand (warm surfaces)
| Token | Hex | Use |
|---|---|---|
| `sand.50`  | `#FBF8F3` | **app background** (warm off-white) |
| `sand.100` | `#F4EDE1` | alt section background |
| `sand.200` | `#EADFCB` | hairline on sand, inactive track |
| `sand.300` | `#DFCFB2` | sand accents |
| `sand.400` | `#CDB68E` | milestone/badge fill (muted gold) |
| `sand.500` | `#B9995F` | deep sand accent, badge text |

### Ink & lines
| Token | Hex | Use |
|---|---|---|
| `surface`       | `#FFFFFF` | cards, sheets, inputs |
| `background`    | `#FBF8F3` | screen background (= sand.50) |
| `text.strong`   | `#10302C` | headings |
| `text.body`     | `#3A4B48` | body copy |
| `text.muted`    | `#6B7A77` | captions, placeholders |
| `border`        | `#E5E0D6` | card/field borders, dividers |
| `overlay`       | `rgba(16,48,44,0.45)` | modal scrim, camera dim |

### Semantic
| Token | Hex | Use |
|---|---|---|
| `success` | `#2E9E6B` | confirmed, taken dose, streak up |
| `warning` | `#D98A2B` | snooze, pending, missed-soon |
| `danger`  | `#D7524C` | relapse, errors, destructive |
| `info`    | `#0F9E92` | = teal.500 |
| `on.primary` | `#FFFFFF` | text/icon on teal.500 |
| `on.sand`    | `#10302C` | text on sand surfaces |

Status tints (bg for badges/snackbars) = semantic color at ~12% alpha.

---

## 2. Typography

Arabic UI font: **Cairo** (fallback: IBM Plex Sans Arabic).
Latin / French font: **Inter**.
Runtime picks family by locale; both share the scale below. RTL mirrors layout.

| Token | Size / Line | Weight | Use |
|---|---|---|---|
| `display` | 34 / 40 | 700 | hero numbers (day counter) |
| `h1` | 28 / 36 | 700 | screen title |
| `h2` | 22 / 30 | 600 | section title |
| `h3` | 18 / 26 | 600 | card title |
| `bodyLg` | 17 / 26 | 400 | primary reading text |
| `body` | 15 / 24 | 400 | default body |
| `label` | 14 / 20 | 500 | field labels, chips |
| `caption` | 13 / 18 | 400 | meta, helper text |
| `button` | 16 / 20 | 600 | button label |

Weights: regular 400, medium 500, semibold 600, bold 700.
Arabic never italic. Letter-spacing 0 (Arabic), -0.01em for Latin headings.

---

## 3. Spacing  (4 px grid)

| Token | px |
|---|---|
| `space.xs` | 4 |
| `space.sm` | 8 |
| `space.md` | 12 |
| `space.lg` | 16 |
| `space.xl` | 24 |
| `space.2xl` | 32 |
| `space.3xl` | 48 |

Screen padding: 20 horizontal. Card inner padding: 16–20. Gap between stacked
cards: 12. Section gap: 24.

---

## 4. Radius

| Token | px | Use |
|---|---|---|
| `radius.field` | 12 | inputs, chips, small tiles |
| `radius.button` | 14 | buttons |
| `radius.card` | 20 | cards, slot pills container |
| `radius.sheet` | 28 | bottom sheets, modals |
| `radius.pill` | 999 | pills, toggles, avatars |

---

## 5. Shadows  (soft, low, teal-tinted)

| Token | Value |
|---|---|
| `shadow.sm`   | `0 1px 2px rgba(16,48,44,0.04)` |
| `shadow.card` | `0 4px 16px rgba(16,48,44,0.06)` |
| `shadow.lg`   | `0 12px 32px rgba(16,48,44,0.10)` |

Cards rest on `shadow.card`. No hard/dark drop shadows.

---

## 6. Motion

| Token | Value |
|---|---|
| `motion.fast` | 180 ms |
| `motion.medium` | 320 ms |
| `motion.slow` | 600 ms |
| `motion.stagger` | 70 ms |
| `motion.curve` | easeOutCubic |
| `motion.pop` | easeOutBack (badges, check marks) |
| `motion.breath` | 4000 ms (splash logo, one breath) |
| `motion.ringFill` | 1200 ms (day ring fill + count-up) |
| `motion.scan` | 1800 ms (ID frame scan line, one pass) |
| `motion.pulse` | 1400 ms (selfie oval pulse) |
| `motion.splashMinimum` | 1600 ms (shortest splash) |

OS reduced-motion disables all transitions/animations.

---

## 7. Components

**Button**
- Primary: fill `teal.500`, text `on.primary`, radius `button`, height 52,
  pressed `teal.600`, disabled `teal.300`. Full-width in forms.
- Secondary (outline): 1.5px `teal.500` border, transparent fill, text `teal.700`.
- Text/ghost: no border, text `teal.700`.
- Destructive: fill `danger`.

**Input / LabeledField** — surface fill, 1px `border`, radius `field`, height 52,
label `label` above, placeholder `text.muted`, focus border `teal.500` + 2px ring
`teal.100`, error border `danger` + helper in `danger`. RTL-aware alignment.

**Card** — `surface`, radius `card`, padding 16–20, `shadow.card`, optional 1px
`border`.

**Chip**
- Choice (multi-select): unselected = `surface` + `border`; selected = `teal.50`
  fill + `teal.500` border + check icon.
- Filter: pill, selected = `teal.500` fill + `on.primary`.

**Segmented control** — `sand.100` track, selected segment = `surface` +
`shadow.sm`, radius `pill`.

**Sobriety ring** — circular progress, track `teal.100`, progress `teal.500`
(gradient to `teal.400`), center `display` number + `caption` label. Milestone
reached → ring tip badge in `sand.400`.

**Stat card** — small `surface` tile, big `h2` value `teal.700`, `caption` label,
grid of 4.

**Date strip** — horizontal scroll of day pills; today outlined, selected =
`teal.500` fill.

**Time slot** — pill grid; available = `surface`+`border`, selected = `teal.500`,
disabled = `sand.100` muted.

**List row (settings)** — 56 height, leading icon `teal.600`, title `body`,
trailing chevron `text.muted`, divider `border`.

**Chat bubble** — incoming = `surface`+`border` radius `card` (tail start);
outgoing = `teal.500`/`on.primary` (tail end). Quick-reply = outline chips.

**Bottom nav** — 5 tabs, `surface`, active icon+label `teal.500`, inactive
`text.muted`, top hairline `border`.

**Stepper (progress bar)** — top of multi-step forms, track `sand.200`, fill
`teal.500`, `caption` "step X / N".

**Capture frame** — ID/selfie: `overlay` dim, rounded cutout, corner marks
`teal.500`, selfie oval with pulse ring.

**Payment toggle** — segmented: Cash / CIB-card, selected `teal.500`.

**Badge** — milestone = `sand.400` fill + `sand.500`/`on.sand` text, pill radius.

**Snackbar** — `surface`, left accent bar in semantic color, `shadow.lg`.

---

## 8. Framework mapping

**Flutter `ThemeData`** (`apps/mobile/lib/theme/`)
- `colorScheme`: primary `teal.500`, onPrimary `on.primary`, surface `surface`,
  background `background`, error `danger`, secondary `sand.400`.
- `ColorScheme.brightness = light`. `scaffoldBackgroundColor = background`.
- `textTheme`: map scale above; `fontFamily` from locale (Cairo ↔ Inter).
- Reuse existing `AppColors / AppSpace / AppRadius / AppMotion` token classes;
  extend with sand + semantic + typography.

**Tailwind `theme.extend`** (`apps/dashboard`)
- `colors`: `teal.*`, `sand.*`, `surface`, `background`, `ink` (text.*),
  `border`, semantic.
- `borderRadius`: field/button/card/sheet + `full`.
- `boxShadow`: sm/card/lg.
- `fontFamily`: `sans: [Inter...]`, `ar: [Cairo, 'IBM Plex Sans Arabic'...]`.
- `fontSize`: scale with line-heights. RTL via `dir="rtl"` + logical properties.

---

## 9. RTL & bilingual rules
- Arabic default, full RTL (mirror layout, icons, slide direction).
- Use logical edges (start/end), never left/right hardcoded.
- Numbers: Arabic-Indic acceptable in input, display per locale.
- No text baked into images. Every string in l10n (AR + FR).
