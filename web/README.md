# Amber legal pages

Static Privacy Policy and Terms of Use for the Amber iOS app, ready to host on Vercel.

## Files
- `index.html` — landing page linking to both policies
- `privacy.html` — served at `/privacy`
- `terms.html` — served at `/terms`
- `style.css` — shared styling
- `vercel.json` — enables clean URLs (`/privacy`, `/terms` with no `.html`)

## Live deployment

Deployed to the **amber-ai** project under the kpuchkov1@gmail.com account. Live at:

- https://amber-ai-kpuchkov1-3058s-projects.vercel.app/privacy
- https://amber-ai-kpuchkov1-3058s-projects.vercel.app/terms

These are the URLs the app's Settings links point to (see
`AmberAI/AmberAI/SettingsView.swift`). The bare `amber-ai.vercel.app` subdomain is
owned by another Vercel team, so the project uses its account-scoped domain instead.
To use a nicer domain, attach a custom domain to the `amber-ai` project in the Vercel
dashboard and update the two `Link` URLs in `SettingsView.swift` to match.

## Redeploying

Re-run the deploy after editing any file here. Either drag this folder into the Vercel
dashboard for the `amber-ai` project, or from a machine with the CLI:

```bash
npm i -g vercel        # once, if not installed
vercel login           # once
vercel --prod          # from this web/ folder
```
