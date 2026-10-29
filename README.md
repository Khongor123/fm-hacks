# F&MHacks 2026

The F&MHacks website includes event information, email/password registration, 50 participant places with a waitlist, a signed-in dashboard, teams by code, a private organizer roster, event-day dashboard, check-in, and project submissions.

## Run locally

1. Supabase GitHub integration applies the files in [`supabase/migrations`](supabase/migrations) in order. The `20261011_dashboard_teams.sql` file is a compatibility marker for the version already recorded on production; [`20261012000000_baseline.sql`](supabase/migrations/20261012000000_baseline.sql) creates the complete schema on a fresh preview and skips schema creation on an existing project. The later migrations add [self-service deletion](supabase/migrations/20261028000000_self_delete_account.sql), the [student directory](supabase/migrations/20261029000000_participant_directory.sql), and the [50-place repair](supabase/migrations/20261029000001_enforce_capacity_50.sql). Earlier scripts that were run manually are preserved in [`supabase/manual_history`](supabase/manual_history) and are not replayed by the integration.
2. In **Supabase → Authentication → Sign In / Providers → Email**, keep email/password signup enabled and turn **Confirm Email** off. Set the minimum password length to 8. Apply the migration in step 1 **before** turning off Confirm Email on an existing project.
3. Create `.env.local` with `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`, and `NEXT_PUBLIC_SITE_URL=http://localhost:3000`. Use the same Supabase project as the deployed site when signing in with an existing production account; a separate test project's accounts are independent. The last variable is used for password reset links.
4. Run `npm install`, then `npm run dev`.

On a disposable Supabase project, run [`supabase/tests/organizer_invitations.sql`](supabase/tests/organizer_invitations.sql), [`supabase/tests/self_delete_account.sql`](supabase/tests/self_delete_account.sql), and [`supabase/tests/participant_directory.sql`](supabase/tests/participant_directory.sql) before the public registration cutoff to exercise invitation, deletion, seat restoration, and directory permissions. The scripts roll back their fixture data. Run [`supabase/tests/submitted_projects_only.sql`](supabase/tests/submitted_projects_only.sql) there to check draft privacy; it also rolls back its fixtures. Concurrent signup and promotion should also be exercised with two database sessions against that disposable project.

The public Supabase key is safe in the browser because the `profiles` table has row-level security. Never add the Supabase secret or service role key to a `NEXT_PUBLIC_` variable.

Production already records migration version `20261011` as `dashboard_teams`. Keep that history row. After pushing the corrected migration layout, check **View Logs** for the `main` branch in Supabase and confirm the migration step succeeded. Only recreate or reset a failed preview branch if a separate preview branch actually exists; never reset the production database.

## Organizer accounts

Establish the first trusted organizer directly in Supabase: verify the person's identity, then set their `profiles.admin` to `true` and `registration_status` to `organizer`. Apply the invitation migration before deploying the invitation pages. The migration normalizes existing `admin = true` profiles to `organizer`, fills open places from the waitlist in `assigned_at` order, and reports any pre-existing confirmed count above 50 for manual review. It preserves all existing confirmed participants.

After that, organizers create seven-day, single-use invitations for specific F&M addresses at `/admin/invitations`. They copy the private link and share it directly with the intended person after verifying their identity. The site does not send invitation emails. An unused invitation can be revoked from the same page. A new invitee creates an organizer account directly, even after public registration closes; an existing participant signs in and accepts. A confirmed participant's freed place is offered automatically to the earliest waitlisted non-organizer, including after registration closes. The organizer must contact that student separately; the site does not send waitlist emails.

To return an organizer to participant status, change `admin` and `registration_status` together in one SQL update, then call `assign_registration` under the registration assignment lock. Changing only the `admin` cell violates the profile constraint. The new status is `confirmed` if a place is open, otherwise `waitlisted`. The follow-up invitation migration lets Supabase Auth delete an account without invitation references blocking its profile deletion.

## Deploy

Run the database migrations **before** deploying the updated website. Connect this repository to Vercel as a Next.js project. Set the three environment variables above, using the production origin for `NEXT_PUBLIC_SITE_URL`. Set Supabase's Site URL to the production origin. Confirmation callbacks are no longer needed.

Public registration closes **November 3, 2026 at 11:59 p.m. Eastern**. The server action and database trigger reject late participant signups; valid organizer invitations remain usable until their own expiry. Students are assigned confirmed or waitlisted status under a database lock so simultaneous signups cannot exceed 50 seats. Existing confirmed registrations are preserved when the new capacity migration runs; if more than 50 students are already confirmed, organizers must review those registrations. The home-page countdown targets the **November 7, 2026 at 9:00 a.m. Eastern** kickoff.

The later [`enforce_capacity_50`](supabase/migrations/20261029000001_enforce_capacity_50.sql) repair replaces an older production assignment function that still used 75. It keeps the earliest 50 student registrations confirmed and moves any later excess confirmed students to the waitlist under the same database lock used for signups. Contact affected students if this repair changes their status.

Confirmed participants can create or join one team of up to four people using a 6-character code. Members can leave before the registration deadline. If the creator leaves, the earliest remaining member becomes creator; an empty team is deleted. Database functions enforce the team limit and deadline even if requests bypass the website. Team names and member names are visible only to members of that team through `get_my_team()`. Applying the six-character-code migration gives existing teams new codes; members must share their new code with anyone joining afterward.

## Email and account limits

Repeating an email catches typing mistakes; it does not prove that a student owns the address or attends F&M. Someone could register with another student's address and prevent its real owner from using it. Organizers should verify student identity separately before relying on the roster or admitting someone to the event.

The **Forgot password** flow still sends a reset email. For that feature to reach arbitrary student addresses, configure custom SMTP in Supabase Auth. Add the production `/auth/callback?next=/reset-password` URL to Supabase's redirect allowlist. Without working SMTP, students who forget their passwords may need organizer help to regain access.

Supabase Auth manages passwords and sessions; passwords are never stored in `profiles`. The student directory exposes only non-organizer names, email addresses, and team status to signed-in students. Other profile fields remain private to their owner and organizers. Organizer access changes only through the database-checked invitation flow or by a trusted Supabase project owner.

## Event day and submissions

At **9:00 a.m. Eastern on November 7, 2026**, the signed-in dashboard switches to event information. Submissions open at **10:00 a.m. Eastern** and close at **10:00 a.m. Eastern on November 8**. The page refreshes at these boundaries, and the database uses its own clock for every write. The event-day migration must be applied before the updated site is deployed.

Organizers verify student identity in person and mark confirmed participants as arrived on `/admin`. A checked-in team member can save a shared draft, upload slides, and submit or resubmit on behalf of the team. A checked-in student without a team can submit alone. A track is required even when saving a draft. Entries become read only at the deadline except for the GitHub repository URL, which participants may correct afterward. Organizers and judges see only submitted projects by track at `/admin/submissions` and verify that the affirmed public GitHub links actually open. Participant drafts remain private to their owners.

Slides live in the private `submission-slides` Supabase Storage bucket created by the migration. Only the submitting team or solo student and organizers can download them. Files are limited to 10 MiB and `.pptx`, `.key`, or `.pdf`; Keynote packages must be exported to PDF. Uploads over 6 MiB use the TUS resumable endpoint. Replacing a slide updates the submission first, then removes the previous object. If removal fails, an organizer may need to remove the unused file in Supabase Storage.

The GitHub integration applies migrations automatically when enabled. If using SQL Editor instead, run the baseline and both later migrations in order; the compatibility marker contains no schema changes.

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

- Open **Review submissions** from `/admin`, or visit `/admin/submissions`. Entries are grouped under **AI**, **Social good**, and **Creative build**. Only **submitted** projects appear there; saved drafts remain visible only to their participants.
- For each team or solo entry, review the title, description, member check-in states, GitHub URL and public-link affirmation, AI-use level and disclosure, slides, and last update time. Open the GitHub URL yourself to confirm that the repository is publicly accessible; the participant's affirmation does not verify it.
- Use **Download slides** on an entry to retrieve its file from the private `submission-slides` bucket. The participant upload limit is 10 MiB and accepted formats are `.pptx`, `.key`, and `.pdf`. Share downloaded files only with people who need them for event review.
- Submissions open November 7 at 10:00 a.m. Eastern and close November 8 at 10:00 a.m. Eastern. Until closing, checked-in participants can revise and resubmit. After closing, their submission is view only except that a checked-in participant can correct the GitHub URL on an existing entry. Refresh the organizer submissions page to see a correction. The organizer view does not edit or submit projects on a participant's behalf.
- If replacing slides leaves an unused old file because cleanup failed, a trusted project owner may remove that unreferenced object in Supabase Storage after confirming it is not the current `slide_path`. The organizer website has no storage cleanup control.
