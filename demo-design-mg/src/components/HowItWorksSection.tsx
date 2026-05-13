"use client";

const steps = [
  {
    step: "01",
    title: "Scan Your Room",
    description:
      "Use your iPhone's LiDAR sensor to capture a detailed 3D model of any room in under 30 seconds.",
    visual: "📐",
  },
  {
    step: "02",
    title: "Choose Your Style",
    description:
      "Select from dozens of design styles — minimalist, scandinavian, industrial, japandi, and more.",
    visual: "🎯",
  },
  {
    step: "03",
    title: "AI Generates Design",
    description:
      "Our multi-provider AI engine creates personalized furniture layouts and color schemes for your exact room.",
    visual: "✨",
  },
  {
    step: "04",
    title: "Preview in AR",
    description:
      "Walk around your room and see the new design overlaid in augmented reality. Adjust, swap, and perfect.",
    visual: "👁️",
  },
];

export function HowItWorksSection() {
  return (
    <section id="how-it-works" className="py-32 px-6 bg-muted/30">
      <div className="max-w-6xl mx-auto">
        {/* Section Header */}
        <div className="text-center max-w-3xl mx-auto mb-20">
          <p className="text-sm font-semibold text-purple-500 uppercase tracking-widest mb-4">
            How It Works
          </p>
          <h2 className="text-4xl md:text-5xl font-bold tracking-tight">
            Four steps to your
            <br />
            <span className="bg-gradient-to-r from-purple-500 to-pink-500 bg-clip-text text-transparent">
              dream interior
            </span>
          </h2>
        </div>

        {/* Steps */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-12">
          {steps.map((item, i) => (
            <div
              key={item.step}
              className="relative flex gap-6 group"
            >
              {/* Step number */}
              <div className="flex-shrink-0">
                <div className="w-14 h-14 rounded-2xl bg-gradient-to-br from-purple-500 to-pink-500 flex items-center justify-center text-white font-bold text-lg shadow-lg shadow-purple-500/20 group-hover:scale-110 transition-transform">
                  {item.step}
                </div>
              </div>
              {/* Content */}
              <div>
                <h3 className="text-xl font-semibold mb-2">{item.title}</h3>
                <p className="text-muted-foreground leading-relaxed">
                  {item.description}
                </p>
              </div>
              {/* Visual */}
              <div className="absolute -right-4 -top-4 text-6xl opacity-10 group-hover:opacity-20 transition-opacity">
                {item.visual}
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
