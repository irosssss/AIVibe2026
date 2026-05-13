"use client";

import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";

export function HeroSection() {
  return (
    <section className="relative min-h-screen flex items-center justify-center overflow-hidden">
      {/* Background gradient — Apple style */}
      <div className="absolute inset-0 bg-gradient-to-b from-blue-50/50 via-background to-background dark:from-blue-950/20" />
      
      {/* Floating orbs */}
      <div className="absolute top-1/4 left-1/4 w-96 h-96 bg-blue-400/20 rounded-full blur-3xl animate-float" />
      <div className="absolute bottom-1/4 right-1/4 w-80 h-80 bg-purple-400/20 rounded-full blur-3xl animate-float [animation-delay:2s]" />

      <div className="relative z-10 max-w-5xl mx-auto px-6 text-center">
        {/* Badge */}
        <div className="animate-fade-in">
          <Badge variant="gradient" className="mb-6">
            ✨ Powered by AI + RoomPlan
          </Badge>
        </div>

        {/* Headline */}
        <h1 className="text-5xl md:text-7xl lg:text-8xl font-bold tracking-tight animate-slide-up">
          <span className="bg-gradient-to-r from-foreground via-foreground to-muted-foreground bg-clip-text">
            Design Your Space
          </span>
          <br />
          <span className="bg-gradient-to-r from-blue-500 via-purple-500 to-pink-500 bg-clip-text text-transparent">
            with AI Vibe
          </span>
        </h1>

        {/* Subtitle */}
        <p className="mt-8 text-lg md:text-xl text-muted-foreground max-w-2xl mx-auto animate-slide-up [animation-delay:0.2s]">
          Scan any room with LiDAR, let AI generate stunning interior designs,
          and visualize changes in real-time augmented reality.
        </p>

        {/* CTA Buttons */}
        <div className="mt-10 flex flex-col sm:flex-row items-center justify-center gap-4 animate-slide-up [animation-delay:0.4s]">
          <Button size="lg" className="bg-gradient-to-r from-blue-500 to-purple-600 hover:from-blue-600 hover:to-purple-700 text-white shadow-2xl shadow-blue-500/25">
            Download for iOS
            <svg className="ml-2 w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
              <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/>
            </svg>
          </Button>
          <Button variant="outline" size="lg">
            Watch Demo
            <svg className="ml-2 w-5 h-5" fill="none" stroke="currentColor" strokeWidth="2" viewBox="0 0 24 24">
              <polygon points="5 3 19 12 5 21 5 3" />
            </svg>
          </Button>
        </div>

        {/* Hero Image / Phone Mockup */}
        <div className="mt-16 animate-slide-up [animation-delay:0.6s]">
          <div className="relative mx-auto w-72 h-[580px] rounded-[3rem] border-[8px] border-foreground/10 bg-gradient-to-b from-muted to-background shadow-2xl overflow-hidden">
            {/* Notch */}
            <div className="absolute top-0 left-1/2 -translate-x-1/2 w-32 h-6 bg-foreground/10 rounded-b-2xl" />
            {/* Screen content */}
            <div className="absolute inset-4 top-8 rounded-2xl bg-gradient-to-b from-blue-500/10 to-purple-500/10 flex items-center justify-center">
              <div className="text-center p-6">
                <div className="w-16 h-16 mx-auto mb-4 rounded-2xl bg-gradient-to-br from-blue-500 to-purple-600 flex items-center justify-center">
                  <span className="text-2xl">🏠</span>
                </div>
                <p className="text-sm font-medium">Scanning Room...</p>
                <div className="mt-4 w-full h-2 bg-muted rounded-full overflow-hidden">
                  <div className="h-full w-2/3 bg-gradient-to-r from-blue-500 to-purple-600 rounded-full animate-pulse" />
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
