# Brief: multi-language (do this AFTER the responsive + playtest work is green)

Languages (Roblox's biggest audiences): en (default), es, pt (Brazil), fr, de, id, tr, ru, ja, ko, th, vi.

1. `src/shared/Locale.luau` (plus one module per language under `src/shared/Locales/<code>.luau` returning a flat
   `{ [key] = "text with {name} placeholders" }`). API:
   - `Locale.t(lang: string, key: string, args: {[string]: any}?) -> string` — falls back to `en`, then to the key itself.
   - `Locale.resolve(localeId: string) -> string` — maps Roblox LocaleId ("es-es", "es-mx", "pt-br", "zh-cn"…) to a supported code, default "en".
   - Number/cash formatting stays language-neutral (Format module).
2. Client: language = saved preference (profile field `lang`, set via a Request action `SetLanguage`) or else
   `Locale.resolve(Players.LocalPlayer.LocaleId)`. EVERY user-visible string in the UI goes through `t()` — panel titles, buttons,
   descriptions, tutorial, toasts built client-side, item/seed/pet/stage/theme names and descriptions from Config (add keys
   like `seed.carrot.name`), rarity names, weather names/descriptions, etc. Add a language picker (flag emoji + native name) in
   an existing settings/menu panel; switching re-renders the UI live without rejoining.
3. Server: never send English sentences to clients. Send `Notify(key, args, kind)` (and messages returned by Request as
   `{key=..., args=...}` or a translated string using that player's language — pick one approach and apply it everywhere,
   keeping the client toast code working). Server-wide broadcasts ("X hatched a Legendary…") must be translated per recipient.
   World text on SurfaceGuis/BillboardGuis (shop signs, plot signs, leaderboard titles, stage signs) should be localized on the
   client (client-side labels or client re-writes the text) — or kept as universally readable emoji+short English if impossible.
4. Translations: write them yourself, natural and short (gaming tone, kids/teens audience), keep placeholders intact,
   make sure strings fit buttons (German/Russian run long → TextScaled or UITextSizeConstraint). Japanese/Korean/Thai need a
   font that renders them: use `Font.new("rbxasset://fonts/families/...")` only if it exists, otherwise Roblox falls back
   automatically for missing glyphs — VERIFY in the playtest screenshots that ja/ko/th text is not rendered as boxes.
5. Also keep Roblox automatic translation compatible (don't set AutoLocalize=false except on dynamic numbers).
6. Tests: a pure-Luau test (luau.exe) that every key in `en` exists in all languages and every placeholder in `en` appears in each
   translation; and in the Studio playtest, force each language via SetLanguage and screenshot/audit at 920x505 (the UI audit
   flags text overflow) at least for de, ru, ja, pt. 0 analyzer errors, commit, rebuild the .rbxlx deliverable.
