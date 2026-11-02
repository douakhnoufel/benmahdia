# Clinic branding

Every logo in the patient app and the doctor dashboard comes from the files in
this folder. They are the clinic's own files; nothing here is drawn or generated.

| File | Size | Used for |
| --- | --- | --- |
| `logo.png` | 1024 × 1024, transparent | App header (`AppMark`), in-app splash, dashboard sidebar, dashboard login, dashboard favicon (`apps/dashboard/public/clinic-logo.png`) |
| `logo_source.jpg` | 2048 × 2048 | Launcher icon, Android and iOS (`flutter_launcher_icons`) |
| `logo_padded.png` | 1024 × 1024 | Android adaptive icon foreground, native splash before Android 12 and on iOS (`flutter_native_splash`) |
| `logo_android12.png` | 1152 × 1152 | Android 12+ native splash |
| `logo_green.jpg` | 2048 × 2048 | Green splash variant (`life_quality_splash_screen.dart`) |

The mobile app reads its copies from `apps/mobile/assets/brand/` (Flutter assets
must live inside the package). Keep both folders identical when the clinic sends
a new logo, then run `dart run flutter_launcher_icons` and
`dart run flutter_native_splash:create` in `apps/mobile`.

## Missing variants (ask the clinic)

- **Notification icon**: the logo as a white shape on a transparent background,
  24, 36, 48, 72 and 96 px (Android mdpi to xxxhdpi). Until it arrives, local
  notifications keep `@mipmap/ic_launcher`.
- **Web sizes**: favicon (16 / 32 / 48 px `.ico`), 180 px apple-touch icon and a
  256 px sidebar logo. Until they arrive, the dashboard uses `logo.png` as is.
