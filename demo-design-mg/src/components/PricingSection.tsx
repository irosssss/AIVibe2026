"use client";

import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";

const plans = [
  {
    name: "Free",
    price: "$0",
    period: "forever",
    description: "Perfect for trying out AI Vibe",
    features: [
      "3 room scans per month",
      "Basic AI design suggestions",
      "USDZ export",
      "Community support",
    ],
    cta: "Get Started",
    variant: "outline" as const,
    popular: false,
  },
  {
    name: "Pro",
    price: "$9.99",
    period: "/month",
    description: "For homeowners redesigning their space",
    features: [
      "Unlimited room scans",
      "All AI providers (YandexGPT, GigaChat, CoreML)",
      "Real-time AR preview",
      "Priority processing",
      "Design history & versioning",
      "Email support",
    ],
    cta: "Start Free Trial",
    variant: "default" as const,
    popular: true,
  },
  {
    name: "Studio",
    price: "$29.99",
    period: "/month",
    description: "For professional interior designers",
    features: [
      "Everything in Pro",
      "Team collaboration",
      "Client sharing links",
      "Custom AI model fine-tuning",
      "API access",
      "Dedicated support",
    ],
    cta: "Contact Sales",
    variant: "outline" as const,
    popular: false,
  },
];

export function PricingSection() {
  return (
    <section id="pricing" className="py-32 px-6">
      <div className="max-w-7xl mx-auto">
        {/* Section Header */}
        <div className="text-center max-w-3xl mx-auto mb-20">
          <p className="text-sm font-semibold text-green-500 uppercase tracking-widest mb-4">
            Pricing
          </p>
          <h2 className="text-4xl md:text-5xl font-bold tracking-tight">
            Simple, transparent
            <br />
            <span className="bg-gradient-to-r from-green-500 to-emerald-500 bg-clip-text text-transparent">
              pricing
            </span>
          </h2>
          <p className="mt-6 text-lg text-muted-foreground">
            Start for free, upgrade when you&apos;re ready.
          </p>
        </div>

        {/* Pricing Cards */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-8 items-start">
          {plans.map((plan) => (
            <Card
              key={plan.name}
              className={`relative overflow-hidden transition-all duration-300 hover:-translate-y-2 ${
                plan.popular
                  ? "border-2 border-blue-500 shadow-xl shadow-blue-500/10 scale-105"
                  : "border hover:shadow-lg"
              }`}
            >
              {plan.popular && (
                <div className="absolute top-4 right-4">
                  <Badge variant="gradient">Most Popular</Badge>
                </div>
              )}
              <CardHeader className="pb-4">
                <CardTitle className="text-lg font-medium text-muted-foreground">
                  {plan.name}
                </CardTitle>
                <div className="flex items-baseline gap-1 mt-2">
                  <span className="text-5xl font-bold">{plan.price}</span>
                  <span className="text-muted-foreground">{plan.period}</span>
                </div>
                <CardDescription className="mt-2">
                  {plan.description}
                </CardDescription>
              </CardHeader>
              <CardContent>
                <ul className="space-y-3 mb-8">
                  {plan.features.map((feature) => (
                    <li key={feature} className="flex items-center gap-3">
                      <svg
                        className="w-5 h-5 text-green-500 flex-shrink-0"
                        fill="none"
                        stroke="currentColor"
                        strokeWidth="2"
                        viewBox="0 0 24 24"
                      >
                        <polyline points="20 6 9 17 4 12" />
                      </svg>
                      <span className="text-sm">{feature}</span>
                    </li>
                  ))}
                </ul>
                <Button
                  variant={plan.variant}
                  className={`w-full ${
                    plan.popular
                      ? "bg-gradient-to-r from-blue-500 to-purple-600 text-white hover:from-blue-600 hover:to-purple-700"
                      : ""
                  }`}
                >
                  {plan.cta}
                </Button>
              </CardContent>
            </Card>
          ))}
        </div>
      </div>
    </section>
  );
}
