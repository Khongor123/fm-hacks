# F&MHacks 2026

The first release of the F&MHacks website includes event information, email/password registration, a 75-place waitlist, and a private organizer roster. Team codes and project submissions are planned for later releases.

## Run locally

1. Create a Supabase project. In its SQL Editor, run [`supabase/schema.sql`](supabase/schema.sql). For a project that already used the earlier schema, run [`supabase/migrations/20261011_remove_email_confirmation.sql`](supabase/migrations/20261011_remove_email_confirmation.sql) instead.
2. In **Supabase → Authentication → Sign In / Providers → Email**, keep email/password signup enabled and turn **Confirm Email** off. Set the minimum password length to 12. Apply the migration in step 1 **before** turning off Confirm Email on an existing project.
3. Create `.env.local` with `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`, and `NEXT_PUBLIC_SITE_URL=http://localhost:3000`. The last variable is used for password reset links.
4. Run `npm install`, then `npm run dev`.

The public Supabase key is safe in the browser because the `profiles` table has row-level security. Never add the Supabase secret or service role key to a `NEXT_PUBLIC_` variable.

## Organizer accounts

An email address is **not proof of ownership** when confirmation is off. Registration never grants `admin` based on the address entered. Register your organizer account, then set its `profiles.admin` field to `true` and `registration_status` to `organizer` manually in the Supabase Table Editor. Check the account's identity in person before granting access. The password previously shared in chat is not stored in this project; use a new password.

If that account held one of the 75 participant places, promote the earliest waitlisted profile to `confirmed` as part of the organizer change. Only trusted project owners should have Supabase dashboard access.

## Deploy

Connect this repository to Vercel as a Next.js project. Set the three environment variables above, using the production origin for `NEXT_PUBLIC_SITE_URL`. Set Supabase's Site URL to the production origin. Confirmation callbacks are no longer needed.

Registration closes **November 4, 2026 at 11:59 p.m. Eastern**. The server action and database trigger reject late signups. Students are assigned confirmed or waitlisted status under a database lock so simultaneous signups cannot exceed 75 seats. The home-page countdown targets the **November 7, 2026 at 9:00 a.m. Eastern** kickoff.

## Email and account limits

Repeating an email catches typing mistakes; it does not prove that a student owns the address or attends F&M. Someone could register with another student's address and prevent its real owner from using it. Organizers should verify student identity separately before relying on the roster or admitting someone to the event.

The **Forgot password** flow still sends a reset email. For that feature to reach arbitrary student addresses, configure custom SMTP in Supabase Auth. Add the production `/auth/callback?next=/reset-password` URL to Supabase's redirect allowlist. Without working SMTP, students who forget their passwords may need organizer help to regain access.

Supabase Auth manages passwords and sessions; passwords are never stored in `profiles`. Every profile is private to its owner and organizers. Admin status cannot be changed from the website.
