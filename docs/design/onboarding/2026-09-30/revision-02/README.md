<!-- Hallmark pre-emit critique: P4 H4 E3 S3 R4 V3. Subjective visual assessment, not accessibility validation. -->

# Bagdar onboarding — revision 02

Generated with the built-in image_gen tool on 2026-09-30.
The user rejected the initial boards for template-like composition, visual style,
oversized elements, and not resembling a real mobile application.

This revision narrows the design target to one language-selection screen.
The initial boards were attached to each generation as negative references.
No application code was changed.

The three choices below correspond to the three newly displayed images in this revision,
not to the earlier rejected boards.

| Visible choice | Image | Prompt |
| --- | --- | --- |
| 1 | [01-graphite-language.png](01-graphite-language.png) | [prompt](01-graphite-language.prompt.md) |
| 2 | [02-language-form.png](02-language-form.png) | [prompt](02-language-form.prompt.md) |
| 3 | [03-language-sheet.png](03-language-sheet.png) | [prompt](03-language-sheet.prompt.md) |

Status: the user selected **visible choice 2** on 2026-09-30.
`02-language-form.png` is the implementation reference for native Flutter onboarding v2.
The native form and the contextual bottom sheet are alternative interaction designs,
not extra mandatory onboarding steps.

Remaining limits: image generation adds subtle shading despite the flat-color prompts.
Exact glyphs, text metrics, tap targets, TalkBack behavior, focus, and large-text layouts
must be implemented and checked independently in native Flutter widgets.

