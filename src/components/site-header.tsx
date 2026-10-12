import Link from "next/link";
import { createClient } from "@/lib/supabase/server";

export async function SiteHeader() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  return (
    <header className="site-header">
      <div className="shell nav-inner">
        <Link href="/" className="brand" aria-label="F&MHacks home"><span className="brand-mark">F&amp;M</span><span>HACKS<span className="brand-year"> / 26</span></span></Link>
        <nav aria-label="Main navigation">
          <Link href="/#about">About</Link>
          <Link href="/#schedule">Schedule</Link>
          <Link href="/#rules">Rules</Link>
          {user ? <Link href="/#dashboard" className="nav-button">Dashboard</Link> : <Link href="/register" className="nav-button">Register <span aria-hidden="true">↗</span></Link>}
        </nav>
      </div>
    </header>
  );
}
