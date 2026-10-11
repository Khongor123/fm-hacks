import type { Metadata } from "next";
import { SiteHeader } from "@/components/site-header";
import "./globals.css";

export const metadata: Metadata = {
  title: { default: "F&MHacks 2026", template: "%s | F&MHacks 2026" },
  description: "A 24-hour student hackathon at Franklin & Marshall College, November 7–8, 2026.",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body><SiteHeader />{children}<footer className="site-footer"><div className="shell footer-inner"><span>F&MHacks 2026 · CS Club</span><span>Built for curious people at Franklin & Marshall College.</span></div></footer></body></html>;
}
