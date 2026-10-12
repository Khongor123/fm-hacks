import type { Metadata } from "next";
import Link from "next/link";
import { FormNotice } from "@/components/form-notice";
import { registrationOpen } from "@/lib/config";
import { RegistrationForm } from "./registration-form";

export const metadata: Metadata = { title: "Register" };

export default async function Register({ searchParams }: { searchParams: Promise<{ error?: string; confirmation_required?: string }> }) {
  const params = await searchParams;
  const open = registrationOpen();

  return <main className="auth-page"><div className="shell auth-layout">
    <div className="auth-side">
      <p className="section-kicker">JOIN THE HACKATHON</p>
      <h1>Make room for<br/><em>your next idea.</em></h1>
      <p>F&MHacks is free and open to students from every major. Register with your F&M email to save your place or join the waitlist.</p>
      <div className="auth-side-details"><span>November 7–8, 2026</span><span>Stager Auditorium</span><span>75 student places</span></div>
    </div>
    <div className="form-card">
      <div className="form-heading">
        <span className="form-step">01 / YOUR DETAILS</span>
        <h2>{open ? "Create your account" : "Registration is closed"}</h2>
        <p>{open ? "All fields are required. Already registered?" : "Registration closed November 4 at 11:59 p.m. Eastern."} {open && <Link href="/login">Log in</Link>}</p>
      </div>
      <FormNotice error={params.error} />
      {params.confirmation_required && <p role="alert" className="form-notice error">Your account was created, but Supabase still requires email confirmation. Ask an organizer to turn off Confirm Email in Supabase before logging in.</p>}
      {open && <RegistrationForm />}
    </div>
  </div></main>;
}
