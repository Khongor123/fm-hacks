# F&MHacks 2026

The F&MHacks website includes event information, email/password registration, 50 participant places with a waitlist, a signed-in dashboard, teams by code, a private organizer roster, event-day dashboard, check-in, and project submissions.

## Run locally

1. For a new Supabase project, run [`supabase/schema.sql`](supabase/schema.sql) in its SQL Editor, followed by [`supabase/migrations/20261011_event_submissions.sql`](supabase/migrations/20261011_event_submissions.sql). For an existing project, apply any missing historical migrations in order: [`remove_email_confirmation`](supabase/migrations/20261011_remove_email_confirmation.sql), [`dashboard_teams`](supabase/migrations/20261011_dashboard_teams.sql), and [`event_submissions`](supabase/migrations/20261011_event_submissions.sql). Then apply [`limit_registration_to_50`](supabase/migrations/20261023_limit_registration_to_50.sql) and [`six_character_team_codes`](supabase/migrations/20261023_six_character_team_codes.sql). Finally apply [`organizer_invitations`](supabase/migrations/20261027_organizer_invitations.sql), then [`organizer_invitations_allow_delete`](supabase/migrations/20261027_organizer_invitations_allow_delete.sql) and [`organizer_roster_team_names`](supabase/migrations/20261027_organizer_roster_team_names.sql), on both new and existing projects.
2. In **Supabase → Authentication → Sign In / Providers → Email**, keep email/password signup enabled and turn **Confirm Email** off. Set the minimum password length to 8. Apply the migration in step 1 **before** turning off Confirm Email on an existing project.
3. Create `.env.local` with `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`, and `NEXT_PUBLIC_SITE_URL=http://localhost:3000`. The last variable is used for password reset links.
4. Run `npm install`, then `npm run dev`.

On a disposable Supabase project, run [`supabase/tests/organizer_invitations.sql`](supabase/tests/organizer_invitations.sql) before the public registration cutoff to exercise the invitation and seat restoration rules. The script rolls back its fixture data. Concurrent signup and promotion should also be exercised with two database sessions against that disposable project.

The public Supabase key is safe in the browser because the `profiles` table has row-level security. Never add the Supabase secret or service role key to a `NEXT_PUBLIC_` variable.

## Organizer accounts

Establish the first trusted organizer directly in Supabase: verify the person's identity, then set their `profiles.admin` to `true` and `registration_status` to `organizer`. Apply the invitation migration before deploying the invitation pages. The migration normalizes existing `admin = true` profiles to `organizer`, fills open places from the waitlist in `assigned_at` order, and reports any pre-existing confirmed count above 50 for manual review. It preserves all existing confirmed participants.

After that, organizers create seven-day, single-use invitations for specific F&M addresses at `/admin/invitations`. They copy the private link and share it directly with the intended person after verifying their identity. The site does not send invitation emails. An unused invitation can be revoked from the same page. A new invitee creates an organizer account directly, even after public registration closes; an existing participant signs in and accepts. A confirmed participant's freed place is offered automatically to the earliest waitlisted non-organizer, including after registration closes. The organizer must contact that student separately; the site does not send waitlist emails.

To return an organizer to participant status, change `admin` and `registration_status` together in one SQL update, then call `assign_registration` under the registration assignment lock. Changing only the `admin` cell violates the profile constraint. The new status is `confirmed` if a place is open, otherwise `waitlisted`. The follow-up invitation migration lets Supabase Auth delete an account without invitation references blocking its profile deletion.

## Deploy

Run the database migrations **before** deploying the updated website. Connect this repository to Vercel as a Next.js project. Set the three environment variables above, using the production origin for `NEXT_PUBLIC_SITE_URL`. Set Supabase's Site URL to the production origin. Confirmation callbacks are no longer needed.

Public registration closes **November 3, 2026 at 11:59 p.m. Eastern**. The server action and database trigger reject late participant signups; valid organizer invitations remain usable until their own expiry. Students are assigned confirmed or waitlisted status under a database lock so simultaneous signups cannot exceed 50 seats. Existing confirmed registrations are preserved when the new capacity migration runs; if more than 50 students are already confirmed, organizers must review those registrations. The home-page countdown targets the **November 7, 2026 at 9:00 a.m. Eastern** kickoff.

Confirmed participants can create or join one team of up to four people using a 6-character code. Members can leave before the registration deadline. If the creator leaves, the earliest remaining member becomes creator; an empty team is deleted. Database functions enforce the team limit and deadline even if requests bypass the website. Team names and member names are visible only to members of that team through `get_my_team()`. Applying the six-character-code migration gives existing teams new codes; members must share their new code with anyone joining afterward.

## Email and account limits

Repeating an email catches typing mistakes; it does not prove that a student owns the address or attends F&M. Someone could register with another student's address and prevent its real owner from using it. Organizers should verify student identity separately before relying on the roster or admitting someone to the event.

The **Forgot password** flow still sends a reset email. For that feature to reach arbitrary student addresses, configure custom SMTP in Supabase Auth. Add the production `/auth/callback?next=/reset-password` URL to Supabase's redirect allowlist. Without working SMTP, students who forget their passwords may need organizer help to regain access.

Supabase Auth manages passwords and sessions; passwords are never stored in `profiles`. Every profile is private to its owner and organizers. Organizer access changes only through the database-checked invitation flow or by a trusted Supabase project owner.

## Event day and submissions

At **9:00 a.m. Eastern on November 7, 2026**, the signed-in dashboard switches to event information. Submissions open at **10:00 a.m. Eastern** and close at **10:00 a.m. Eastern on November 8**. The page refreshes at these boundaries, and the database uses its own clock for every write. The event-day migration must be applied before the updated site is deployed.

Organizers verify student identity in person and mark confirmed participants as arrived on `/admin`. A checked-in team member can save a shared draft, upload slides, and submit or resubmit on behalf of the team. A checked-in student without a team can submit alone. Entries become read only at the deadline except for the GitHub repository URL, which participants may correct afterward. Organizers review entries by track at `/admin/submissions` and verify that the affirmed public GitHub links actually open.

Slides live in the private `submission-slides` Supabase Storage bucket created by the migration. Only the submitting team or solo student and organizers can download them. Files are limited to 10 MiB and `.pptx`, `.key`, or `.pdf`; Keynote packages must be exported to PDF. Uploads over 6 MiB use the TUS resumable endpoint. Replacing a slide updates the submission first, then removes the previous object. If removal fails, an organizer may need to remove the unused file in Supabase Storage.

The event migration has not been applied to a remote Supabase project by this repository alone. Apply it in Supabase SQL Editor before deploying.

To rehearse the event safely before November 7, follow the [event preview guide](docs/event-preview.md) on the `event-preview` branch with a separate Supabase project.

## Organizer account guide

### Set up and sign in

1. A trusted Supabase project owner establishes the first organizer as described above. Existing `admin = true` accounts are normalized by the invitation migration; the normal website signup cannot create an organizer.
2. A signed-in organizer opens **Organizer invitations** from `/admin` or `/account`, enters the invitee's F&M email, and creates a link. Copy it immediately; the link is shown only once. Verify the invitee's identity and share it directly. The link is single-use and expires after seven days.
3. The invitee opens the link. A new invitee creates an organizer account with their invited email, name, and password. Someone with an existing account signs in through the invitation page to accept. The email must match exactly. Invite signup remains available after participant registration closes.
4. To cancel an unused invitation, open `/admin/invitations` and select **Revoke**. Used and expired invitations cannot be revoked or reused.
5. If an existing confirmed participant accepts, the system promotes the earliest waitlisted non-organizer in the same transaction. The organizer roster shows their new status. Contact the promoted student directly; no email is sent automatically. A waitlisted participant who accepts becomes an organizer without opening an extra place.

### Before the event: review registrations

- Open `/admin` to see the confirmed count out of 50, waitlisted count, total student accounts, and the roster. Each row shows the student's name, email, class year, T-shirt size, team name (or **Solo**), registration status, and arrival control. The roster is ordered by `assigned_at`.
- Verify a student's identity separately before treating a roster entry as theirs. Registration does not verify ownership of the F&M address. When an invited confirmed participant becomes an organizer, the earliest waitlisted student is promoted automatically. Contact that student directly. Other manual seat changes still require a trusted project owner to update Supabase and contact the student.
- If a participant cannot sign in, direct them to **Forgot password**. Reset mail to arbitrary student addresses requires the Supabase custom SMTP and redirect configuration described above. Passwords are managed by Supabase Auth and cannot be read from the roster.
- Team creation, joining by code, and leaving are participant actions on the signed-in dashboard. Only confirmed non-organizer accounts can use them, and team changes close November 3 at 11:59 p.m. Eastern. The organizer roster does not edit teams.

### Event day: check participants in

1. At Stager Auditorium, ask the student for their student ID and match their identity to the roster before recording arrival.
2. On `/admin`, find their **confirmed** row and select **Mark arrived**. The page then shows the check-in time in Eastern Time and the organizer who recorded it. Waitlisted students and organizer accounts cannot be checked in.
3. If the wrong person was marked or a check-in must be reversed, select **Arrived ✓ · Undo** on that row. Recheck the student's identity before marking them arrived again.
4. Explain that check-in is required before a confirmed student can save a project draft, upload slides, submit, or correct a repository link after the deadline. A checked-in team member can act for the shared team submission; a checked-in student without a team can submit solo.

### Review projects and slides

- Open **Review submissions** from `/admin`, or visit `/admin/submissions`. Entries are grouped under **AI**, **Social good**, **Creative build**, and **No track selected**. The page includes saved drafts as well as submitted projects, so check each entry's **draft** or **submitted** badge before judging.
- For each team or solo entry, review the title, description, member check-in states, GitHub URL and public-link affirmation, AI-use level and disclosure, slides, and last update time. Open the GitHub URL yourself to confirm that the repository is publicly accessible; the participant's affirmation does not verify it.
- Use **Download slides** on an entry to retrieve its file from the private `submission-slides` bucket. The participant upload limit is 10 MiB and accepted formats are `.pptx`, `.key`, and `.pdf`. Share downloaded files only with people who need them for event review.
- Submissions open November 7 at 10:00 a.m. Eastern and close November 8 at 10:00 a.m. Eastern. Until closing, checked-in participants can revise and resubmit. After closing, their submission is view only except that a checked-in participant can correct the GitHub URL on an existing entry. Refresh the organizer submissions page to see a correction. The organizer view does not edit or submit projects on a participant's behalf.
- If replacing slides leaves an unused old file because cleanup failed, a trusted project owner may remove that unreferenced object in Supabase Storage after confirming it is not the current `slide_path`. The organizer website has no storage cleanup control.
