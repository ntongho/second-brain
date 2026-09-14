# Second Brain — DESIGN.md

Quiet product UI. Not a marketing landing page. Not indigo-violet “AI SaaS”.

Reference language: Linear / Cal.com / ChatGPT — one canvas, hairlines, one ink CTA.

## Do not

- Purple, indigo, electric violet, cyan glow chips
- 20px pill bubbles, gradient fills, colored left-bars on every message
- Huge display type on the login screen
- Colored circular avatars as brand

## Color (dark is default)

| Token | Hex | Use |
| --- | --- | --- |
| Canvas | `#0E0E0D` | Scaffold |
| Surface | `#161615` | Inputs, rail, cards |
| Hairline | `#2A2926` | 1px borders, dividers |
| Ink | `#F3F1EE` | Primary text, filled buttons on dark |
| Muted | `#8A8780` | Meta, hints |
| Accent | `#E8E6E3` | CTA fill (ink-on-dark inverse) |
| Danger | `#C45C52` | Errors only |
| Warn | `#B8956A` | Degraded / queued |

Light fallback: canvas `#F4F3F0`, surface `#FFFFFF`, ink `#1A1917`, hairline `#E4E2DC`.

## Type

System UI. No Google Fonts.

- Title 18 / 600 / -0.3
- Body 15 / 400 / 1.45 / -0.1
- Caption 12 / 400 / muted
- Buttons 14 / 500

## Shape & space

Radius 8 on inputs and cards. 12 on chat user chips. Not 20.

Space: 8 / 12 / 16 / 24. Hairline 1px, never drop shadows.

Tap targets ≥ 40px.

## Components

- **Primary button:** ink fill, dark label, radius 8, height 40–44. Not a purple slab.
- **Secondary:** hairline border, transparent fill.
- **Inputs:** surface fill, 1px hairline, focus = ink 1px (no glow).
- **User message:** surface + hairline, right-aligned. Not a brand-color blob.
- **Assistant message:** no bubble. Body text on canvas.
- **Citations:** muted text chips, hairline, not cyan.
- **Rail:** same canvas as chat, right hairline only.

## Auth

Wordmark 18px, not a hero headline. One column, max 400px. Quiet “or”.
