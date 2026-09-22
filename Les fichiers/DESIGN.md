---
name: Synthetix Neon
colors:
  surface: '#10141a'
  surface-dim: '#10141a'
  surface-bright: '#353940'
  surface-container-lowest: '#0a0e14'
  surface-container-low: '#181c22'
  surface-container: '#1c2026'
  surface-container-high: '#262a31'
  surface-container-highest: '#31353c'
  on-surface: '#dfe2eb'
  on-surface-variant: '#cbc3d7'
  inverse-surface: '#dfe2eb'
  inverse-on-surface: '#2d3137'
  outline: '#958ea0'
  outline-variant: '#494454'
  surface-tint: '#d0bcff'
  primary: '#d0bcff'
  on-primary: '#3c0091'
  primary-container: '#a078ff'
  on-primary-container: '#340080'
  inverse-primary: '#6d3bd7'
  secondary: '#4cd7f6'
  on-secondary: '#003640'
  secondary-container: '#03b5d3'
  on-secondary-container: '#00424e'
  tertiary: '#4edea3'
  on-tertiary: '#003824'
  tertiary-container: '#00a572'
  on-tertiary-container: '#00311f'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#e9ddff'
  primary-fixed-dim: '#d0bcff'
  on-primary-fixed: '#23005c'
  on-primary-fixed-variant: '#5516be'
  secondary-fixed: '#acedff'
  secondary-fixed-dim: '#4cd7f6'
  on-secondary-fixed: '#001f26'
  on-secondary-fixed-variant: '#004e5c'
  tertiary-fixed: '#6ffbbe'
  tertiary-fixed-dim: '#4edea3'
  on-tertiary-fixed: '#002113'
  on-tertiary-fixed-variant: '#005236'
  background: '#10141a'
  on-background: '#dfe2eb'
  surface-variant: '#31353c'
typography:
  headline-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 48px
    fontWeight: '800'
    lineHeight: '1.1'
    letterSpacing: -0.02em
  headline-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 32px
    fontWeight: '700'
    lineHeight: '1.2'
    letterSpacing: -0.01em
  headline-sm:
    fontFamily: Plus Jakarta Sans
    fontSize: 24px
    fontWeight: '600'
    lineHeight: '1.3'
  body-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 18px
    fontWeight: '400'
    lineHeight: '1.6'
  body-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 16px
    fontWeight: '400'
    lineHeight: '1.6'
  label-md:
    fontFamily: JetBrains Mono
    fontSize: 14px
    fontWeight: '500'
    lineHeight: '1.2'
    letterSpacing: 0.05em
  label-sm:
    fontFamily: JetBrains Mono
    fontSize: 12px
    fontWeight: '500'
    lineHeight: '1.2'
    letterSpacing: 0.05em
  headline-lg-mobile:
    fontFamily: Plus Jakarta Sans
    fontSize: 32px
    fontWeight: '800'
    lineHeight: '1.1'
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  unit: 4px
  gutter: 24px
  margin-mobile: 16px
  margin-desktop: 48px
  container-max: 1440px
---

## Brand & Style

The design system is engineered for a high-end, developer-centric music streaming experience. It merges **Glassmorphism** with a **Tech-Brutalist** edge, emphasizing precision, performance, and creative energy. The target audience values the intersection of high-fidelity audio and modern development environments.

The UI should evoke a "command center" feel—highly functional yet visually immersive. By utilizing vibrant neon accents against deep, dark surfaces, the interface creates a focused atmosphere suitable for deep work and high-energy listening. Layouts are structured through a "Bento Box" philosophy, organizing content into modular, high-density compartments that remain intuitive and fluid.

## Colors

The palette is rooted in a **Midnight Blue (#0D1117)** base to maximize contrast and reduce eye strain in low-light environments. 

- **Primary (Electric Violet):** Used for primary actions, active navigation states, and brand signatures.
- **Secondary (Cyan/Aqua):** Used for technical metadata, secondary interactive elements, and information visualization.
- **Tertiary (Neon Green):** Reserved exclusively for "Play" states, success indicators, and positive growth trends in listener stats.
- **Surfaces:** Utilize a glassmorphic effect with `#161E2E` at 80% opacity and a `20px` background blur to create layered depth without losing the sense of a unified space.

## Typography

This design system uses a dual-font strategy to balance readability with a technical aesthetic.

- **Plus Jakarta Sans** handles all editorial and narrative content. Large headlines should use heavy weights (700-800) with tight letter spacing to feel impactful and modern.
- **JetBrains Mono** is utilized for technical data, timecodes, badges, and metadata. This font should always be used in uppercase when applied to small badges to enhance its "code-like" feel.
- **Alignment:** For music stats and tracklists, ensure monospaced numbers from JetBrains Mono are used to maintain vertical alignment in lists.

## Layout & Spacing

The layout follows a **Bento Box** philosophy: content is grouped into distinct, rounded rectangles that fit together in a tight, logical grid.

- **Grid:** Use a 12-column fluid grid for desktop with 24px gutters. On mobile, transition to a 2-column or single-column stack with 16px gutters.
- **Bento Modules:** Every section (New Releases, Personal Stats, Visualizer) should be housed in its own card container. Modules should span varying column widths (e.g., a 2x2, 4x2, or 1x1 configuration) to create a dynamic visual hierarchy.
- **Consistency:** Use an 8px base spacing system for internal element padding to maintain a clean, rhythmic structure.

## Elevation & Depth

Depth is conveyed through **Glassmorphism** and **Light Translucency** rather than traditional drop shadows.

- **Z-Axis Hierarchy:**
    1. **Base:** Deep Midnight Blue (#0D1117).
    2. **Middle (Content Cards):** Semi-transparent glass (#161E2E at 80%) with a subtle `1px` white border at 10% opacity.
    3. **Top (Hover/Active):** Elements should exhibit a subtle outer glow using the Primary or Secondary accent color (e.g., `box-shadow: 0 0 15px rgba(139, 92, 246, 0.3)`).
- **Background Blurs:** Apply a `backdrop-filter: blur(20px)` to all glass containers to ensure readability over moving background gradients or album art.

## Shapes

The shape language is "Rounded-Tech." It avoids the softness of mobile apps in favor of a more structured, professional feel.

- **Standard Radius:** Use `0.5rem` (8px) for cards and inputs.
- **Interactive Elements:** Use `rounded-lg` (1rem) for buttons to make them feel more "clickable" and distinct from the structural grid.
- **Album Art:** Album covers should use a 3D transform on hover (rotateY/rotateX) to mimic physical media, accompanied by a slight lift.

## Components

- **Buttons:** High-contrast, vibrant fills. Use first-person, action-oriented labels like "J'écoute maintenant" or "Ma Bibliothèque". Apply a subtle glow on hover.
- **Persistent Mini-Player:** A glassmorphic bar anchored at the bottom. Use JetBrains Mono for the track time and technical bit-rate info. The "Play" button should always be Neon Green.
- **Cards (3D Effect):** Bento-style cards for albums. On hover, apply a `1.05x` scale and a slight 3D tilt.
- **Chips/Badges:** Use JetBrains Mono in all-caps with a `1px` border matching the accent color. For example, a "FLAC" badge should have a Cyan border.
- **Input Fields:** Dark backgrounds with a `1px` white border (10%). Focus state changes the border to Electric Violet with a subtle inner glow.
- **Lists:** Tracklists should use a subtle highlight on hover. Icons (Like, Add, Share) appear only on row hover to reduce visual clutter.