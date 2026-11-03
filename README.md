# ONYE ISI — African hair professionals in Germany

A marketplace where customers find and book African hair professionals, and stylists manage their own profiles.

**Stack:** plain HTML/CSS/JavaScript, Supabase (PostgreSQL, Auth, Storage, row-level security), Netlify (hosting + serverless functions), Groq (chat guide), Gemini / FLUX (AI hair try-on).

## Features
- Stylist discovery with filters by specialty and city, profile pages with services and photos
- Email and Google sign-in for customers and vendors, each with a profile
- Booking requests saved to the database; stylists confirm or decline in their dashboard
- Admin page (`/admin.html`) to approve stylist profiles
- AI chat guide and AI hair try-on, with API keys kept server-side in Netlify Functions
- Password reset and account deletion (personal data removed)

## Project structure
```
public/index.html            main app
public/admin.html            stylist approvals (admins only)
netlify/functions/chat.mjs   AI chat proxy (holds the Groq key)
netlify/functions/tryon.mjs  AI try-on proxy (holds Gemini / FLUX keys)
netlify.toml                 Netlify config
supabase/setup_all.sql       complete database setup (run once)
```

## Setup
1. **Supabase:** open the SQL Editor and run `supabase/setup_all.sql`. Under Authentication → URL Configuration set the Site URL to your Netlify address. Optional: enable the Google provider.
2. **Admin user:** create an account, then run
   `insert into public.admins (user_id) values ('<your user id>');`
3. **Netlify:** import this repo (build command empty, publish directory `public`), then add environment variables:
   - `GROQ_API_KEY` for the chat guide
   - `GEMINI_API_KEY` and/or `BFL_API_KEY` for the try-on (optional `TRYON_PROVIDER`, `GEMINI_MODEL`, `BFL_PATH`)
   - `ALLOWED_ORIGIN` set to your site address (recommended)
4. Redeploy after changing environment variables.

## Security notes
- The Supabase publishable key in the page is public by design; data is protected by row-level security.
- Never commit the Supabase service role key or any AI provider key. Keys live only in Netlify environment variables.
- Photos sent to the try-on are processed by a third-party AI provider; users must consent, and nothing is stored by this app.

*Onye Isi* means "head person" in Igbo.
