# Test the event dashboard before November 7

Use the `event-preview` Git branch and a **separate Supabase project**. A branch isolates code, but `.env.local` decides which database receives check-ins, submissions, and slides. Do not point this preview at the live project.

## 1. Set up the isolated project

1. Create a new Supabase project. In its SQL Editor, run `supabase/schema.sql`, then `supabase/migrations/20261011_event_submissions.sql`. The latter creates the private `submission-slides` bucket and the private event clock. For a fresh project, the other historical migrations are already represented in `schema.sql`.
2. In Supabase Authentication settings, enable email/password signup and turn **Confirm Email** off for this test project. Set the minimum password length to 8 as described in the main README.
3. Put the **test project's** URL and publishable key in the ignored `.env.local`, along with `NEXT_PUBLIC_SITE_URL=http://localhost:3000`. Keep the service-role key out of the app and out of `NEXT_PUBLIC_` variables.
4. Run `npm install` and `npm run dev`, then register two or more test participants with distinct `@fandm.edu` addresses. Register a separate organizer account and set its `profiles.admin = true` and `registration_status = 'organizer'` in the test project's Table Editor. Create a team with two participants; leave one participant solo. Set up these accounts and teams before the real November 3 registration/team cutoff.
5. Run `supabase/tests/preview_smoke.sql` in SQL Editor. It checks that the required tables, private bucket, RPC grants, and Storage policies are present.
6. Sign in as the organizer and mark the test participants arrived on `/admin`. Verify the roster shows who checked them in and when. Sign back in as a participant for the remaining steps.

## 2. Move the test clock

Run **one** of these statements at a time in the **test project's** SQL Editor. Each sets an offset from the database's real clock, so the simulated clock continues to tick. The dashboard polls the same clock and refreshes when the phase changes.

Before kickoff (preparation dashboard):

```sql
update app_private.event_clock_offset
set preview_enabled = true,
    clock_offset = timestamptz '2026-11-07 08:59:00-05' - clock_timestamp()
where singleton = true;
select public.event_now();
```

At kickoff (event information, submissions still closed):

```sql
update app_private.event_clock_offset
set preview_enabled = true,
    clock_offset = timestamptz '2026-11-07 09:00:00-05' - clock_timestamp()
where singleton = true;
select public.event_now();
```

During submissions:

```sql
update app_private.event_clock_offset
set preview_enabled = true,
    clock_offset = timestamptz '2026-11-07 10:00:00-05' - clock_timestamp()
where singleton = true;
select public.event_now();
```

Just before the deadline, to watch the page switch while it stays open:

```sql
update app_private.event_clock_offset
set preview_enabled = true,
    clock_offset = timestamptz '2026-11-08 09:59:00-05' - clock_timestamp()
where singleton = true;
select public.event_now();
```

After the deadline:

```sql
update app_private.event_clock_offset
set preview_enabled = true,
    clock_offset = timestamptz '2026-11-08 10:00:00-05' - clock_timestamp()
where singleton = true;
select public.event_now();
```

Reset the test clock when finished:

```sql
update app_private.event_clock_offset
set preview_enabled = false, clock_offset = interval '0 seconds'
where singleton = true;
```

The offset table has no client grants. Only someone with SQL Editor privileges can change it. Its default is real time, so production event dates remain fixed.

## 3. Check the complete flow

- At 8:59, a signed-in participant sees the preparation dashboard. At 9:00, the event schedule, venue, team, rules, GitHub instructions, and project countdown appear. Before 10:00, the submission form remains closed.
- At 10:00, a checked-in team member can choose a track and save an otherwise incomplete draft, upload `.pptx`, `.key`, or `.pdf` slides up to 10 MiB, and submit once all required fields and confirmations are complete. Try an invalid extension and a file over 10 MiB; both must fail. A file over 6 MiB should use the resumable upload path. Replace the slides and confirm that the old object is removed from Storage.
- Sign in as the second team member. Verify the same entry appears. Change a field and resubmit. If both members edit at once, the later save should report a conflict and require a refresh. Sign in as the solo participant and verify that their submission is independent.
- Remove a participant's check-in from `/admin`; they should see organizer guidance and be unable to save. A waitlisted participant should never receive a submission form. Sign in as a non-organizer and confirm `/admin/submissions` is inaccessible; organizers should see only submitted entries grouped by track and be able to download their slides. A saved draft must stay absent from the organizer list, direct submission reads, and organizer slide downloads; its participant owner must still be able to reopen it.
- At 10:00 Sunday, confirm the form becomes view only, uploads and saves fail at the database, and the GitHub repository URL can still be corrected. Check that organizers can review the corrected link.

The real registration and team cutoff still uses its original timestamp. Create test accounts and teams before shifting the event clock; the offset controls the event dashboard and submission rules, not registration or team membership.
