# F&MHacks 2026

The F&MHacks website includes event information, email/password registration, 50 participant places with a waitlist, a signed-in dashboard, teams by code, a private organizer roster, event-day dashboard, check-in, and project submissions.

## Run locally

1. Create a Supabase project. In its SQL Editor, run [`supabase/schema.sql`](supabase/schema.sql). For an existing project, run [`supabase/migrations/20261011_remove_email_confirmation.sql`](supabase/migrations/20261011_remove_email_confirmation.sql) if you have not applied it yet, then run [`supabase/migrations/20261011_dashboard_teams.sql`](supabase/migrations/20261011_dashboard_teams.sql), followed by [`supabase/migrations/20261011_event_submissions.sql`](supabase/migrations/20261011_event_submissions.sql) and [`supabase/migrations/20261023_limit_registration_to_50.sql`](supabase/migrations/20261023_limit_registration_to_50.sql). For a new project, run `schema.sql`, then the event submissions migration.
2. In **Supabase → Authentication → Sign In / Providers → Email**, keep email/password signup enabled and turn **Confirm Email** off. Set the minimum password length to 12. Apply the migration in step 1 **before** turning off Confirm Email on an existing project.
3. Create `.env.local` with `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`, and `NEXT_PUBLIC_SITE_URL=http://localhost:3000`. The last variable is used for password reset links.
4. Run `npm install`, then `npm run dev`.

The public Supabase key is safe in the browser because the `profiles` table has row-level security. Never add the Supabase secret or service role key to a `NEXT_PUBLIC_` variable.

## Organizer accounts

An email address is **not proof of ownership** when confirmation is off. Registration never grants `admin` based on the address entered. Register your organizer account, then set its `profiles.admin` field to `true` and `registration_status` to `organizer` manually in the Supabase Table Editor. Check the account's identity in person before granting access. The password previously shared in chat is not stored in this project; use a new password.

If that account held one of the 50 participant places, promote the earliest waitlisted profile to `confirmed` as part of the organizer change. Only trusted project owners should have Supabase dashboard access.

## Deploy

Run the database migrations **before** deploying the updated website. Connect this repository to Vercel as a Next.js project. Set the three environment variables above, using the production origin for `NEXT_PUBLIC_SITE_URL`. Set Supabase's Site URL to the production origin. Confirmation callbacks are no longer needed.

Registration closes **November 3, 2026 at 11:59 p.m. Eastern**. The server action and database trigger reject late signups. Students are assigned confirmed or waitlisted status under a database lock so simultaneous signups cannot exceed 50 seats. Existing confirmed registrations are preserved when the new capacity migration runs; if more than 50 students are already confirmed, organizers must review those registrations. The home-page countdown targets the **November 7, 2026 at 9:00 a.m. Eastern** kickoff.

Confirmed participants can create or join one team of up to four people using a 12-character code. Members can leave before the registration deadline. If the creator leaves, the earliest remaining member becomes creator; an empty team is deleted. Database functions enforce the team limit and deadline even if requests bypass the website. Team names and member names are visible only to members of that team through `get_my_team()`.

## Email and account limits

Repeating an email catches typing mistakes; it does not prove that a student owns the address or attends F&M. Someone could register with another student's address and prevent its real owner from using it. Organizers should verify student identity separately before relying on the roster or admitting someone to the event.

The **Forgot password** flow still sends a reset email. For that feature to reach arbitrary student addresses, configure custom SMTP in Supabase Auth. Add the production `/auth/callback?next=/reset-password` URL to Supabase's redirect allowlist. Without working SMTP, students who forget their passwords may need organizer help to regain access.

Supabase Auth manages passwords and sessions; passwords are never stored in `profiles`. Every profile is private to its owner and organizers. Admin status cannot be changed from the website.

## Event day and submissions

At **9:00 a.m. Eastern on November 7, 2026**, the signed-in dashboard switches to event information. Submissions open at **10:00 a.m. Eastern** and close at **10:00 a.m. Eastern on November 8**. The page refreshes at these boundaries, and the database uses its own clock for every write. The event-day migration must be applied before the updated site is deployed.

Organizers verify student identity in person and mark confirmed participants as arrived on `/admin`. A checked-in team member can save a shared draft, upload slides, and submit or resubmit on behalf of the team. A checked-in student without a team can submit alone. Entries become read only at the deadline except for the GitHub repository URL, which participants may correct afterward. Organizers review entries by track at `/admin/submissions` and verify that the affirmed public GitHub links actually open.

Slides live in the private `submission-slides` Supabase Storage bucket created by the migration. Only the submitting team or solo student and organizers can download them. Files are limited to 10 MiB and `.pptx`, `.key`, or `.pdf`; Keynote packages must be exported to PDF. Uploads over 6 MiB use the TUS resumable endpoint. Replacing a slide updates the submission first, then removes the previous object. If removal fails, an organizer may need to remove the unused file in Supabase Storage.

The event migration has not been applied to a remote Supabase project by this repository alone. Apply it in Supabase SQL Editor before deploying.

To rehearse the event safely before November 7, follow the [event preview guide](docs/event-preview.md) on the `event-preview` branch with a separate Supabase project.
