# F&MHacks 2026

The first release of the F&MHacks website: public event information, verified F&M student registration, email/password login, a 75-place waitlist, and a private organizer roster. Team codes and project submissions are planned for later releases.

## Run locally

1. Create a Supabase project. In its SQL Editor, run [`supabase/schema.sql`](supabase/schema.sql).
2. In Supabase Auth settings, enable email/password signup and **confirm email**, and set the minimum password length to 12. Set the Site URL to `http://localhost:3000` for local work, and add `http://localhost:3000/auth/callback` to allowed redirect URLs. Add the deployed site's callback URL before launch.
3. Copy `.env.example` to `.env.local` and fill in the project URL and publishable key. Set `NEXT_PUBLIC_SITE_URL` to the actual site origin for each environment.
4. Run `npm install`, then `npm run dev`.

The public Supabase key is safe in the browser because the `profiles` table has row-level security. Never add the Supabase secret or service role key to a `NEXT_PUBLIC_` variable.

## Organizer account

The verified account for `kochirkh@fandm.edu` is automatically marked `admin = true` with status `organizer`; it does not use a participant seat. Register that address with the organizer's real name, grade, and T-shirt size, then verify the email. Choose a **new** password during registration; the password shared in chat is not stored in this project.

To make another verified organizer an admin, update their `profiles` row in the Supabase Table Editor or SQL Editor. Set `admin = true` and `registration_status = 'organizer'`. If that person previously held a confirmed participant seat, promote the earliest waitlisted profile to `confirmed` in the same organizer operation. Only trusted project owners should have Supabase dashboard access.

## Deploy

Before public registration, configure **custom SMTP** in Supabase Auth using an organizer-controlled sending address/domain. Supabase's built-in mail service cannot deliver verification emails to arbitrary students. Review the Auth email rate limit and raise it for the expected launch surge; the custom SMTP default may still be too low for 75 signups in one hour. See [Supabase's SMTP guide](https://supabase.com/docs/guides/auth/auth-smtp).

Connect this repository to Vercel as a Next.js project. Add the three environment variables from `.env.example`, using the production URL for `NEXT_PUBLIC_SITE_URL`. Add `https://YOUR-DOMAIN/auth/callback` to Supabase's allowed redirect URLs and set the Supabase Site URL to the production origin. Deploy, then test the verification and reset links end to end.

Registration closes **November 4, 2026 at 11:59 p.m. Eastern**. The server action and database trigger both reject late signups. Verified students are assigned confirmed or waitlisted status under a database lock so simultaneous confirmations cannot exceed 75 seats. The home-page countdown targets the **November 7, 2026 at 9:00 a.m. Eastern** kickoff.

## Security and operations

- Supabase Auth manages passwords, sessions, email verification, and resets. Passwords are never stored in `profiles`.
- Every profile is private to its owner and organizers. Admin status cannot be changed from the website.
- Keep the Supabase database and Vercel project under an organizer-controlled account so future CS Club officers can maintain them.
- The organizer roster contains student personal information. Give Supabase dashboard access only to trusted organizers.
