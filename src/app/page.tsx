import Link from "next/link";
import { HeroLogo } from "@/components/hero-logo";
import {
  ParticipantDashboard,
  type Team,
} from "@/components/participant-dashboard";
import { createClient } from "@/lib/supabase/server";
import { EventDashboard } from "@/components/event-dashboard";
import { EventBoundary } from "@/components/event-boundary";
import { EVENT_DAY_START, type Submission } from "@/lib/event";
import { getEventNow } from "@/lib/event-clock";
import { CAPACITY } from "@/lib/config";
import { PrizeModel } from "@/components/prize-model";
import { ProductSpin } from "@/components/product-spin";

export default async function Home({
  searchParams,
}: {
  searchParams: Promise<{ team_error?: string; team_notice?: string }>;
}) {
  const params = await searchParams;
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  const now = user ? await getEventNow(supabase) : Date.now();
  const { data: profile } = user
    ? await supabase
        .from("profiles")
        .select("full_name,registration_status,admin,checked_in_at")
        .eq("id", user.id)
        .single()
    : { data: null };
  const { data: team, error: teamError } =
    profile?.registration_status === "confirmed" && !profile.admin
      ? await supabase.rpc("get_my_team")
      : { data: null, error: null };

  const { data: submission, error: submissionError } =
    profile &&
    now >= Date.parse(EVENT_DAY_START) &&
    profile.registration_status === "confirmed" &&
    !profile.admin
      ? await supabase.rpc("get_my_submission")
      : { data: null, error: null };

  return (
    <main>
      {profile ? (
        now >= Date.parse(EVENT_DAY_START) ? (
          <EventDashboard
            profile={profile}
            userId={user!.id}
            team={team as Team | null}
            submission={submission as Submission | null}
            teamLoadError={!!teamError}
            submissionLoadError={!!submissionError}
            now={now}
          />
        ) : (
          <>
            <EventBoundary initialPhase="before" serverNow={now} />
            <ParticipantDashboard
              profile={profile}
              team={team as Team | null}
              teamLoadError={!!teamError}
              now={now}
              notice={params.team_notice}
              error={params.team_error}
            />
          </>
        )
      ) : user ? (
        <section className="participant-home">
          <div className="shell">
            <h1>Account setup is finishing.</h1>
            <p>
              Refresh this page in a moment. If this persists, contact the
              organizers.
            </p>
            <Link href="/account" className="button button-ghost">
              My account
            </Link>
          </div>
        </section>
      ) : (
        <section className="hero">
          <div className="shell hero-grid">
            <div className="hero-content">
              <p className="eyebrow">
                <span className="eyebrow-dot" aria-hidden="true" /> THE F&M CS CLUB PRESENTS
              </p>
              <h1>
                Build something
                <br />
                <em>worth sharing.</em>
              </h1>
              <p className="hero-description">
                One campus. One day and night. A room full of ideas waiting to
                become real. Join students across every major for F&MHacks 2026.
                No experience needed. Plus, get a free t-shirt.
              </p>
              <div className="hero-actions">
                <Link href="/register" className="button button-primary">
                  Register now <span aria-hidden="true">↗</span>
                </Link>
                <a href="#about" className="button button-ghost">
                  Explore the event <span aria-hidden="true">↓</span>
                </a>
              </div>
              <div className="hero-facts">
                <div>
                  <strong>NOV 7–8</strong>
                  <span>2026</span>
                </div>
                <div>
                  <strong>24 HOURS</strong>
                  <span>of making</span>
                </div>
                <div>
                  <strong>STAGER</strong>
                  <span>Auditorium</span>
                </div>
              </div>
            </div>
            <div className="hero-aside">
              <HeroLogo />
            </div>
          </div>
          <div className="hero-bottom shell">
            <span>Registration closes Nov 3 at 11:59 p.m. ET</span>
            <span>OPEN TO ALL F&M MAJORS</span>
          </div>
        </section>
      )}

      <section className="section intro" id="about">
        <div className="shell two-column">
          <div>
            <p className="section-kicker">01 / ABOUT THE HACKATHON</p>
            <h2>
              Good ideas don’t
              <br />
              wait for permission.
            </h2>
          </div>
          <div className="intro-copy">
            <p>
              F&MHacks is a 24-hour chance to make something with people who
              care about ideas. Bring your curiosity, find a team, and turn a
              small spark into a project you can show.
            </p>
            <p>
              Whether you code, design, write, research, or present, there is a
              place for you. Teams can have up to four members, and each project
              needs at least one person who can program.
            </p>
            <div className="pill-row">
              <span>Free to join</span>
              <span>Free T-shirt</span>
              <span>Food & snacks</span>
            </div>
          </div>
        </div>
      </section>

      <section className="section tracks-prizes-section" id="prizes">
        <div className="shell">
          <div className="section-heading">
            <div>
              <p className="section-kicker">02 / TRACKS &amp; PRIZES</p>
              <h2>Pick a track. Build for the prize.</h2>
            </div>
            <p>
              Choose one track for your project. Descriptions and judging criteria
              are being finalized; each track has its own prize.
            </p>
          </div>
          <div className="track-grid prize-grid">
            <article className="track-card track-prize-card">
              <span className="track-number">01 / Applied AI</span>
              <div className="track-icon">✳</div>
              <h3>APPLIED AI</h3>
              <p className="track-description">
                Build an AI-powered tool that solves a real problem.
              </p>
              <PrizeModel />
              <div className="track-prize-reward">
                <span className="track-prize-label">TRACK PRIZE</span>
                <h4>Google Fitbit Air</h4>
                <p>Obsidian</p>
              </div>
            </article>
            <article className="track-card track-prize-card">
              <span className="track-number">02 / SOCIAL GOOD</span>
              <div className="track-icon">◎</div>
              <h3>Social good</h3>
              <p className="track-description">Make something useful for a community, on campus or beyond.</p>
              <ProductSpin atlasPrefix="/echo-dot-spin" poster="/echo-dot-spin-poster.png" label="Amazon Echo Dot" frameCount={120} frameSize={312} durationMs={2000} />
              <div className="track-prize-reward">
                <span className="track-prize-label">TRACK PRIZE</span>
                <h4>Amazon Echo Dot</h4>
                <p>5th generation · Charcoal</p>
              </div>
            </article>
            <article className="track-card track-prize-card">
              <span className="track-number">03 / CREATIVE BUILD</span>
              <div className="track-icon">✦</div>
              <h3>Creative build</h3>
              <p className="track-description">
                Surprise us with a game, experience, or new form of expression.
              </p>
              <ProductSpin atlasPrefix="/instax-mini-12-spin" poster="/instax-mini-12-spin-poster.png" label="Fujifilm instax mini 12" frameCount={128} frameSize={320} durationMs={2134} />
              <div className="track-prize-reward">
                <span className="track-prize-label">TRACK PRIZE</span>
                <h4>Fujifilm instax mini 12</h4>
                <p>Instant Camera · Lilac Purple</p>
              </div>
            </article>
          </div>
        </div>
      </section>

      <section className="section schedule-section" id="schedule">
        <div className="shell two-column">
          <div>
            <p className="section-kicker">03 / THE PLAN</p>
            <h2>
              24 hours.
              <br />A lot can happen.
            </h2>
            <p className="section-note">
              Times are Eastern. The detailed schedule may change as organizers
              finalize the event.
            </p>
          </div>
          <div className="schedule-list">
            <div className="schedule-day">SATURDAY · NOV 7</div>
            <div className="schedule-row">
              <time>9:00 AM</time>
              <span>Welcome and kickoff</span>
            </div>
            <div className="schedule-row">
              <time>10:00 AM</time>
              <span>Project work begins</span>
            </div>
            <div className="schedule-row">
              <time>Midnight</time>
              <span>Late-night pizza</span>
            </div>
            <div className="schedule-day">SUNDAY · NOV 8</div>
            <div className="schedule-row">
              <time>10:00 AM</time>
              <span>Projects due</span>
            </div>
            <div className="schedule-row">
              <time>10:30 AM</time>
              <span>Presentations and judging</span>
            </div>
            <div className="schedule-row">
              <time>~1:30 PM</time>
              <span>Results and closing</span>
            </div>
          </div>
        </div>
      </section>

      <section className="section rules-section" id="rules">
        <div className="shell">
          <div className="section-heading">
            <div>
              <p className="section-kicker">04 / THE GROUND RULES</p>
              <h2>Make it yours.</h2>
            </div>
            <p>We want to see what your team can build during the event.</p>
          </div>
          <div className="rules-grid">
            <div>
              <span>01</span>
              <p>
                Write your project code during the hackathon. No prebuilt
                project submissions.
              </p>
            </div>
            <div>
              <span>02</span>
              <p>Software projects only; no hardware required or accepted.</p>
            </div>
            <div>
              <span>03</span>
              <p>
                Disclose where and how you used AI. A single prompt alone is not
                a finished project.
              </p>
            </div>
            <div>
              <span>04</span>
              <p>
                You can discuss ideas with other teams, but direct project work
                comes from your own team.
              </p>
            </div>
          </div>
        </div>
      </section>

      <section className="cta-section">
        <div className="shell cta-inner">
          <div>
            <p className="section-kicker">READY TO MAKE SOMETHING?</p>
            <h2>
              Your next idea
              <br />
              starts here.
            </h2>
            <p>
              {user
                ? "Your F&MHacks details and team are at the top of this page."
                : `Seats are limited to ${CAPACITY} students. Register with your F&M email by November 3.`}
            </p>
          </div>
          <Link
            href={user ? "/#dashboard" : "/register"}
            className="button button-light"
          >
            {user ? "Back to dashboard" : "Save your spot"}{" "}
            <span aria-hidden="true">↗</span>
          </Link>
        </div>
      </section>
    </main>
  );
}
