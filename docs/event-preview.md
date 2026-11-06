# Rehearse the event with the test Supabase project

Use the `event-preview` Git branch and the separate `fm-hacks-test` Supabase project. The preview site is https://fm-hacks-git-event-preview-k81499320gmailcoms-projects.vercel.app/. Check the Vercel environment variables before testing: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`, and `NEXT_PUBLIC_SITE_URL` must be scoped to the `event-preview` Preview Branch and point to the test project and preview site. Production and preview accounts and submissions must stay separate.

All times below are Eastern Standard Time (UTC−05:00) in 2026. The event dates are after the daylight saving time change.

| Time | What happens |
| --- | --- |
| Fri Nov 6, 11:59 p.m. | Last minute of student registration. Registration closes at Sat Nov 7, 12:00 a.m. |
| Sat Nov 7, 10:00 a.m. | Welcome and kickoff; the signed-in dashboard switches to event information. |
| Sat Nov 7, 11:00 a.m. | Project work and submissions begin. GitHub repositories must be created after this time. |
| Sat Nov 7, 11:30 p.m. | Late-night pizza. |
| Sun Nov 8, 11:00 a.m. | Projects are due; submissions close. |
| Sun Nov 8, 11:30 a.m. | Presentations and judging begin. |
| Sun Nov 8, around 2:00 p.m. | Results and closing. |

There is **no team creation, joining, or leaving deadline**. Team actions still require a confirmed participant account and obey the four-person limit.

## 1. Set up the isolated project

1. In the **test project's** SQL Editor, run the files in `supabase/migrations` in filename order, starting with `20261012000000_baseline.sql` and ending with `20261106000002_allow_video_storage_paths.sql`. The earlier `20261011_dashboard_teams.sql` file is a compatibility marker with no schema changes. The baseline creates the private `submission-slides` bucket and event clock. Run each migration once; continue from the first one not yet applied.
2. In the test project's Authentication settings, enable email/password signup, turn **Confirm Email** off for rehearsal, and set the minimum password length to 8. Set its Site URL to the preview site URL above. Use test credentials only.
3. For the deployed preview, use the Vercel branch-scoped variables described above and redeploy `event-preview` after changing them. For local testing, put the **test project's** URL and publishable key in the ignored `.env.local`, along with `NEXT_PUBLIC_SITE_URL=http://localhost:3000`, then run `npm install` and `npm run dev`. Keep service-role keys out of the app and out of `NEXT_PUBLIC_` variables.
4. Before the real registration cutoff (Nov 6 at 11:59 p.m.), register at least two test participants with distinct `@fandm.edu` addresses. Register a separate organizer account and set its `profiles.admin = true` and `registration_status = 'organizer'` in the test project's Table Editor. Make a two-person team and leave one participant solo. After the cutoff, use accounts created earlier for the event rehearsal; moving the test event clock does not reopen registration.
5. Run `supabase/tests/preview_smoke.sql` in the test project's SQL Editor **before moving the clock**. It checks the required tables, private bucket, RPC grants, Storage policies, and safe real-time clock default.
6. Sign in as the organizer and mark the test participants arrived on `/admin`. Verify the roster shows who checked them in and when. Sign back in as a participant for the remaining steps.

## 2. Move the test clock

Run **one** of these statements at a time in the **test project's** SQL Editor. Each sets an offset from the database's real clock, so the simulated clock continues to tick. The dashboard polls this clock and refreshes when its phase changes. The `select` displays New York local time; a plain `select public.event_now()` may appear five hours later if the SQL Editor displays UTC. The offset affects signed-in event pages and submission rules. The signed-out homepage and registration use the real clock.

Before kickoff (preparation dashboard):

```sql
update app_private.event_clock_offset
set preview_enabled = true,
    clock_offset = timestamptz '2026-11-07 09:59:00-05' - clock_timestamp()
where singleton = true;
select public.event_now() at time zone 'America/New_York' as simulated_eastern_time;
```

At kickoff (event information, submissions still closed):

```sql
update app_private.event_clock_offset
set preview_enabled = true,
    clock_offset = timestamptz '2026-11-07 10:00:00-05' - clock_timestamp()
where singleton = true;
select public.event_now() at time zone 'America/New_York' as simulated_eastern_time;
```

When project work and submissions begin:

```sql
update app_private.event_clock_offset
set preview_enabled = true,
    clock_offset = timestamptz '2026-11-07 11:00:00-05' - clock_timestamp()
where singleton = true;
select public.event_now() at time zone 'America/New_York' as simulated_eastern_time;
```

Just before the deadline, to watch the page switch while it stays open:

```sql
update app_private.event_clock_offset
set preview_enabled = true,
    clock_offset = timestamptz '2026-11-08 10:59:00-05' - clock_timestamp()
where singleton = true;
select public.event_now() at time zone 'America/New_York' as simulated_eastern_time;
```

At the deadline:

```sql
update app_private.event_clock_offset
set preview_enabled = true,
    clock_offset = timestamptz '2026-11-08 11:00:00-05' - clock_timestamp()
where singleton = true;
select public.event_now() at time zone 'America/New_York' as simulated_eastern_time;
```

Reset the **test** clock when finished:

```sql
update app_private.event_clock_offset
set preview_enabled = false, clock_offset = interval '0 seconds'
where singleton = true;
```

The offset table has no client grants. Only someone with SQL Editor privileges can change it. Its default is real time.

## 3. Check the complete flow

- At 9:59 a.m. Saturday, a signed-in participant sees the preparation dashboard. At 10:00 a.m., the event schedule, venue, team, rules, GitHub instructions, and project countdown appear. The submission form stays closed until 11:00 a.m.
- At 11:00 a.m. Saturday, a checked-in team member can choose a track and submit a complete project. For a live presentation, upload `.pptx`, `.key`, or `.pdf` slides up to 10 MiB. For a video demo, upload an `.mp4` up to 50 MiB; the suggested length is 5–7 minutes. Submission requires all fields, a presentation file, and public-repository confirmation. Check that invalid extensions and oversized files fail. Files over 6 MiB use the resumable upload path. Replace a file and confirm the old object is removed from Storage. There is no draft-saving action.
- Sign in as the second team member. Verify the same entry appears. Change a field and resubmit. If both members edit at once, the later save should report a conflict and require a refresh. Sign in as the solo participant and verify that their submission is independent.
- Remove a participant's check-in from `/admin`; they should see organizer guidance and be unable to submit. A waitlisted participant should never receive a submission form. Sign in as a non-organizer and confirm `/admin/submissions` is inaccessible; organizers should see only submitted entries grouped by track and be able to download the presentation file. Any historical draft data must stay absent from the organizer list.
- At 11:00 a.m. Sunday, confirm the form becomes view only and uploads and saves fail at the database. A checked-in participant can still correct the GitHub repository URL on an existing entry. Check that organizers can review the corrected link.

Team creation, joining, and leaving remain available without a deadline. The event clock offset does not change team membership rules or the real registration cutoff.
