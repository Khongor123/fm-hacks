import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { ThemeToggle } from "@/components/theme-toggle";

export async function SiteHeader() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  return (
    <header className="site-header">
      <div className="shell nav-inner">
        <nav aria-label="Main navigation">
          <Link href="/#about">About</Link>
          <Link href="/#schedule">Schedule</Link>
          <Link href="/#rules">Rules</Link>
          {user ? <Link href="/#dashboard" className="nav-button">Dashboard</Link> : <Link href="/register" className="nav-button">Register <span aria-hidden="true">↗</span></Link>}
          <ThemeToggle />
        </nav>
      </div>
    </header>
  );
}
