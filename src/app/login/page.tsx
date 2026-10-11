import type { Metadata } from "next";
import Link from "next/link";
import { login } from "@/app/actions/auth";
import { FormNotice } from "@/components/form-notice";

export const metadata: Metadata = { title: "Log in" };

export default async function Login({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const params = await searchParams;
  return <main className="auth-page"><div className="shell auth-layout"><div className="auth-side"><p className="section-kicker">WELCOME BACK</p><h1>Let’s get<br/><em>to work.</em></h1><p>Log in to see your registration status. Team and project tools are coming next.</p><div className="auth-side-details"><span>F&MHacks 2026</span><span>November 7–8</span><span>Stager Auditorium</span></div></div><div className="form-card"><div className="form-heading"><span className="form-step">YOUR ACCOUNT</span><h2>Log in</h2><p>New to F&MHacks? <Link href="/register">Create an account</Link></p></div><FormNotice error={params.error} /><form action={login} className="form-stack"><div className="field"><label htmlFor="email">F&M email</label><input id="email" name="email" type="email" autoComplete="email" placeholder="you@fandm.edu" required /></div><div className="field"><div className="field-label-row"><label htmlFor="password">Password</label><Link href="/forgot-password">Forgot password?</Link></div><input id="password" name="password" type="password" autoComplete="current-password" required /></div><button type="submit" className="button button-dark full-width">Log in <span aria-hidden="true">→</span></button></form></div></div></main>;
}
