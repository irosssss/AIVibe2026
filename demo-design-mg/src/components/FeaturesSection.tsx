"use client";

import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";

const features = [
  {
    icon: "📱",
    title: "LiDAR Room Scanning",
    description:
      "Point your iPhone or iPad at any room and get a precise 3D model in seconds using Apple's RoomPlan framework.",
    gradient: "from-blue-500/10 to-cyan-500/10",
  },
  {
    icon: "🤖",
    title: "AI Design Generation",
    description:
      "Multiple AI providers — YandexGPT, GigaChat, CoreML — generate personalized interior design suggestions instantly.",
    gradient: "from-purple-500/10 to-pink-500/10",
  },
  {
    icon: "🎨",
    title: "Real-time AR Preview",
    description:
      "See AI-generated furniture and decor placed in your actual room through augmented reality before you buy anything.",
    gradient: "from-orange-500/10 to-red-500/10",
  },
  {
    icon: "💾",
    title: "USDZ Export",
    description:
      "Export room scans as USDZ files compatible with Apple's ecosystem — share with designers or open in Reality Composer.",
    gradient: "from-green-500/10 to-emerald-500/10",
  },
  {
    icon: "🔒",
    title: "Privacy First",
    description:
      "All room data stays on your device. TLS pinning, secure storage, and zero telemetry by default.",
    gradient: "from-gray-500/10 to-slate-500/10",
  },
  {
    icon: "⚡",
    title: "Swift 6 + TCA",
    description:
      "Built with The Composable Architecture for predictable state management and strict Swift 6 concurrency safety.",
    gradient: "from-yellow-500/10 to-amber-500/10",
  },
];

export function FeaturesSection() {
  return (
    <section id="features" className="py-32 px-6">
      <div className="max-w-7xl mx-auto">
        {/* Section Header */}
        <div className="text-center max-w-3xl mx-auto mb-20">
          <p className="text-sm font-semibold text-blue-500 uppercase tracking-widest mb-4">
            Features
          </p>
          <h2 className="text-4xl md:text-5xl font-bold tracking-tight">
            Everything you need to
            <br />
            <span className="bg-gradient-to-r from-blue-500 to-purple-500 bg-clip-text text-transparent">
              reimagine your space
            </span>
          </h2>
          <p className="mt-6 text-lg text-muted-foreground">
            AI Vibe combines cutting-edge Apple frameworks with the power of
            multiple AI providers to transform how you design interiors.
          </p>
        </div>

        {/* Feature Grid */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {features.map((feature, i) => (
            <Card
              key={feature.title}
              className={`group hover:shadow-xl hover:-translate-y-1 transition-all duration-300 border-0 bg-gradient-to-br ${feature.gradient}`}
              style={{ animationDelay: `${i * 0.1}s` }}
            >
              <CardHeader>
                <div className="text-4xl mb-2 group-hover:scale-110 transition-transform duration-300">
                  {feature.icon}
                </div>
                <CardTitle className="text-xl">{feature.title}</CardTitle>
              </CardHeader>
              <CardContent>
                <CardDescription className="text-base leading-relaxed">
                  {feature.description}
                </CardDescription>
              </CardContent>
            </Card>
          ))}
        </div>
      </div>
    </section>
  );
}
