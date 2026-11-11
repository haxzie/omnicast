import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Omnicast — Spotlight, reimagined",
  description:
    "A native macOS launcher with instant search across apps, files and clipboard history, plus on-device voice dictation.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className="min-h-dvh font-sans antialiased">{children}</body>
    </html>
  );
}
