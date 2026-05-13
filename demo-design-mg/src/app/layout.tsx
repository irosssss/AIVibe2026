import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "AI Vibe — AI-Powered Interior Design with AR",
  description:
    "Scan any room with LiDAR, let AI generate stunning interior designs, and visualize changes in real-time augmented reality.",
  openGraph: {
    title: "AI Vibe — AI-Powered Interior Design with AR",
    description:
      "Scan any room with LiDAR, let AI generate stunning interior designs, and visualize changes in real-time augmented reality.",
    type: "website",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className="dark">
      <body className="min-h-screen font-sans antialiased">{children}</body>
    </html>
  );
}
