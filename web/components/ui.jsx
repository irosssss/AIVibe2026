/* ============================================================
   AIVibe — общие UI-примитивы (иконки, логотип, графики, утилиты)
   Экспортируется в window для других babel-скриптов.
   ============================================================ */
const { useState, useEffect, useRef, useCallback } = React;

/* ---------- Логотип: дековый веер + кинетический леттеринг ---------- */
function Logo({ size = 26, onClick }) {
  return (
    <div onClick={onClick} style={{ display: "inline-flex", alignItems: "center", gap: 11, cursor: onClick ? "pointer" : "default", userSelect: "none" }}>
      <svg width={size} height={size} viewBox="0 0 32 32" fill="none" aria-hidden="true">
        <rect x="1" y="1" width="30" height="30" rx="9" stroke="var(--accent)" strokeWidth="1.5" opacity="0.5" />
        <path d="M16 6 L25 25 H7 Z" fill="none" stroke="var(--accent)" strokeWidth="1.6" />
        <path d="M16 6 L20.5 25 M16 6 L11.5 25 M16 6 L25 25 M16 6 L7 25" stroke="var(--accent)" strokeWidth="1" opacity="0.45" />
        <circle cx="16" cy="6" r="2.4" fill="var(--accent)" />
      </svg>
      <span className="logo-word" style={{ fontFamily: "var(--font-display)", fontWeight: 800, fontSize: size * 0.74, letterSpacing: "-0.04em" }}>
        AI<span style={{ color: "var(--accent)" }}>Vibe</span>
      </span>
    </div>
  );
}

/* ---------- Иконки (тонкая линия, 1.6 stroke) ---------- */
const Icon = ({ d, size = 20, stroke = 1.6, fill = "none", ...p }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill={fill} stroke="currentColor"
       strokeWidth={stroke} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" {...p}>
    {typeof d === "string" ? <path d={d} /> : d}
  </svg>
);
const I = {
  scan: (p) => <Icon {...p} d={<><path d="M4 8V5a1 1 0 0 1 1-1h3M16 4h3a1 1 0 0 1 1 1v3M20 16v3a1 1 0 0 1-1 1h-3M8 20H5a1 1 0 0 1-1-1v-3" /><rect x="8.5" y="8.5" width="7" height="7" rx="1.5" /></>} />,
  spark: (p) => <Icon {...p} d={<><path d="M12 3v4M12 17v4M3 12h4M17 12h4" /><path d="M12 8.5 13 11l2.5 1-2.5 1-1 2.5-1-2.5L8.5 12 11 11z" /></>} />,
  cube: (p) => <Icon {...p} d={<><path d="M12 2.5 21 7v10l-9 4.5L3 17V7z" /><path d="M3 7l9 4.5L21 7M12 11.5V21.5" /></>} />,
  cart: (p) => <Icon {...p} d={<><circle cx="9" cy="20" r="1.4" /><circle cx="18" cy="20" r="1.4" /><path d="M2 3h3l2.4 12.4a1 1 0 0 0 1 .8h8.7a1 1 0 0 0 1-.8L21 7H6" /></>} />,
  arrow: (p) => <Icon {...p} d="M5 12h14M13 6l6 6-6 6" />,
  arrowUp: (p) => <Icon {...p} d="M12 19V5M6 11l6-6 6 6" />,
  check: (p) => <Icon {...p} d="M4 12.5l5 5L20 6.5" />,
  apple: (p) => <Icon {...p} fill="currentColor" stroke="none" d="M17.05 12.04c-.03-2.6 2.13-3.85 2.23-3.91-1.22-1.78-3.11-2.03-3.78-2.05-1.61-.16-3.14.95-3.96.95-.81 0-2.07-.93-3.4-.9-1.75.03-3.36 1.02-4.26 2.58-1.82 3.15-.46 7.8 1.3 10.36.86 1.25 1.88 2.66 3.22 2.61 1.29-.05 1.78-.83 3.34-.83 1.55 0 2 .83 3.37.81 1.39-.03 2.27-1.28 3.12-2.54.98-1.45 1.39-2.85 1.41-2.92-.03-.01-2.7-1.04-2.73-4.11M14.6 4.5c.71-.86 1.19-2.06 1.06-3.25-1.02.04-2.26.68-2.99 1.54-.66.76-1.23 1.98-1.08 3.15 1.14.09 2.3-.58 3.01-1.44" />,
  user: (p) => <Icon {...p} d={<><circle cx="12" cy="8" r="4" /><path d="M4 20c0-4 4-6 8-6s8 2 8 6" /></>} />,
  grid: (p) => <Icon {...p} d={<><rect x="3.5" y="3.5" width="7" height="7" rx="1.5" /><rect x="13.5" y="3.5" width="7" height="7" rx="1.5" /><rect x="3.5" y="13.5" width="7" height="7" rx="1.5" /><rect x="13.5" y="13.5" width="7" height="7" rx="1.5" /></>} />,
  chart: (p) => <Icon {...p} d={<><path d="M4 20V10M10 20V4M16 20v-7M22 20H2" /></>} />,
  news: (p) => <Icon {...p} d={<><rect x="3.5" y="4.5" width="17" height="15" rx="2" /><path d="M7 9h10M7 13h6M7 16h4" /></>} />,
  users: (p) => <Icon {...p} d={<><circle cx="9" cy="8" r="3.2" /><path d="M3 19c0-3 3-4.5 6-4.5s6 1.5 6 4.5" /><path d="M16 5.2A3 3 0 0 1 16 11M21 19c0-2.4-1.8-3.8-4-4.3" /></>} />,
  plus: (p) => <Icon {...p} d="M12 5v14M5 12h14" />,
  edit: (p) => <Icon {...p} d="M4 20h4L18.5 9.5a2 2 0 0 0-2.8-2.8L5 17.2zM14 7l3 3" />,
  trash: (p) => <Icon {...p} d="M4 7h16M9 7V5a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2M6 7l1 13h10l1-13" />,
  close: (p) => <Icon {...p} d="M6 6l12 12M18 6L6 18" />,
  logout: (p) => <Icon {...p} d="M9 4H5a1 1 0 0 0-1 1v14a1 1 0 0 0 1 1h4M16 16l4-4-4-4M20 12H9" />,
  star: (p) => <Icon {...p} d="M12 3.5l2.6 5.6 6 .7-4.5 4.1 1.2 6L12 17l-5.3 3 1.2-6L3.4 9.8l6-.7z" />,
  fork: (p) => <Icon {...p} d={<><circle cx="6" cy="5" r="2" /><circle cx="18" cy="5" r="2" /><circle cx="12" cy="19" r="2" /><path d="M6 7v3a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2V7M12 12v5" /></>} />,
  bug: (p) => <Icon {...p} d={<><rect x="8" y="8" width="8" height="11" rx="4" /><path d="M8 11H4M20 11h-4M8 15H3M21 15h-5M9 6l1.5 2M15 6l-1.5 2" /></>} />,
  search: (p) => <Icon {...p} d={<><circle cx="11" cy="11" r="6" /><path d="M20 20l-3.5-3.5" /></>} />,
  ruler: (p) => <Icon {...p} d={<><rect x="3" y="8" width="18" height="8" rx="1.5" /><path d="M7 8v3M11 8v4M15 8v3M19 8v4" /></>} />,
  layers: (p) => <Icon {...p} d="M12 3l9 5-9 5-9-5zM3 13l9 5 9-5M3 17l9 5 9-5" />,
  wallet: (p) => <Icon {...p} d={<><rect x="3" y="6" width="18" height="13" rx="2.5" /><path d="M3 10h18M16 14.5h2" /></>} />,
  truck: (p) => <Icon {...p} d={<><path d="M3 6h11v9H3zM14 9h4l3 3v3h-7z" /><circle cx="7" cy="17.5" r="1.6" /><circle cx="17.5" cy="17.5" r="1.6" /></>} />,
  chat: (p) => <Icon {...p} d={<><path d="M21 11.5a8.38 8.38 0 0 1-9 8.3 8.5 8.5 0 0 1-3.9-.8L3 20l1-4.1A8.38 8.38 0 0 1 3 11.5a8.5 8.5 0 0 1 9-8.3 8.38 8.38 0 0 1 9 8.3z" /></>} />,
  send: (p) => <Icon {...p} d="M22 2 11 13M22 2l-7 20-4-9-9-4z" />,
  sun: (p) => <Icon {...p} d={<><circle cx="12" cy="12" r="4" /><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4" /></>} />,
  sliders: (p) => <Icon {...p} d={<><path d="M4 21v-7M4 10V3M12 21v-9M12 8V3M20 21v-5M20 12V3M1 14h6M9 8h6M17 16h6" /></>} />,
  heart: (p) => <Icon {...p} d="M20.8 5.6a5.5 5.5 0 0 0-7.8 0L12 6.6l-1-1a5.5 5.5 0 0 0-7.8 7.8l1 1L12 22l7.8-7.6 1-1a5.5 5.5 0 0 0 0-7.8z" />,
  info: (p) => <Icon {...p} d={<><circle cx="12" cy="12" r="9" /><path d="M12 11v5M12 7.5h.01" /></>} />,
  sofa: (p) => <Icon {...p} d={<><path d="M4 12V8a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v4" /><path d="M2 13a2 2 0 0 1 4 0v3h12v-3a2 2 0 0 1 4 0v5a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1z" /><path d="M6 12h12" /></>} />,
  lamp: (p) => <Icon {...p} d={<><path d="M9 2h6l3 7H6zM12 9v9M8 21h8" /></>} />,
  rug: (p) => <Icon {...p} d={<><rect x="3" y="6" width="18" height="12" rx="1" /><path d="M3 9h18M3 15h18M7 6v12M17 6v12" /></>} />,
  plan: (p) => <Icon {...p} d={<><rect x="3" y="3" width="18" height="18" rx="1.5" /><path d="M3 14h7V3M10 14v7M14 3v6h7" /></>} />,
  spinner: (p) => <Icon {...p} d="M12 3a9 9 0 1 0 9 9" />,
};

/* ---------- Картинка с striped-плейсхолдером и fallback ---------- */
function Img({ src, alt, label, style, className, radius }) {
  const [err, setErr] = useState(false);
  const base = { display: "block", width: "100%", height: "100%", objectFit: "cover", borderRadius: radius, ...style };
  if (err || !src) {
    return <div className={"ph " + (className || "")} style={{ ...base, objectFit: undefined }}>{label || "изображение"}</div>;
  }
  return <img src={src} alt={alt || label || ""} loading="lazy" className={className}
              style={base} onError={() => setErr(true)} />;
}

/* ---------- Хук появления при скролле ---------- */
function useReveal() {
  const ref = useRef(null);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const io = new IntersectionObserver((es) => {
      es.forEach((e) => { if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); } });
    }, { threshold: 0.15, rootMargin: "0px 0px -8% 0px" });
    el.querySelectorAll(".reveal").forEach((n) => io.observe(el === n ? n : n));
    if (el.classList.contains("reveal")) io.observe(el);
    return () => io.disconnect();
  }, []);
  return ref;
}

/* ---------- Числовой форматтер ---------- */
const fmt = (n) => new Intl.NumberFormat("ru-RU").format(Math.round(n));
const fmtMoney = (n) => new Intl.NumberFormat("ru-RU").format(Math.round(n)) + " ₽";

/* ============================================================
   ГРАФИКИ (рисуем сами на SVG, цвет --chart / Wasabi)
   ============================================================ */

/* площадь/линия */
function AreaChart({ data, color = "var(--chart)", height = 150, id = "ac" }) {
  const w = 560, h = height, pad = 8;
  const max = Math.max(...data) * 1.12, min = Math.min(...data) * 0.85;
  const px = (i) => pad + (i / (data.length - 1)) * (w - pad * 2);
  const py = (v) => h - pad - ((v - min) / (max - min)) * (h - pad * 2);
  const line = data.map((v, i) => `${i ? "L" : "M"}${px(i).toFixed(1)},${py(v).toFixed(1)}`).join(" ");
  const area = `${line} L${px(data.length - 1).toFixed(1)},${h} L${px(0).toFixed(1)},${h} Z`;
  return (
    <svg viewBox={`0 0 ${w} ${h}`} width="100%" height={h} preserveAspectRatio="none" style={{ display: "block" }}>
      <defs>
        <linearGradient id={id} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={color} stopOpacity="0.32" />
          <stop offset="100%" stopColor={color} stopOpacity="0" />
        </linearGradient>
      </defs>
      <path d={area} fill={`url(#${id})`} />
      <path d={line} fill="none" stroke={color} strokeWidth="2.5" strokeLinejoin="round" strokeLinecap="round" vectorEffect="non-scaling-stroke" />
      {data.map((v, i) => i % 2 === 0 && <circle key={i} cx={px(i)} cy={py(v)} r="2.6" fill={color} />)}
    </svg>
  );
}

/* горизонтальные бары (источники / стили) */
function BarList({ data, color = "var(--chart)", money }) {
  const max = Math.max(...data.map((d) => d.value));
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
      {data.map((d, i) => (
        <div key={i}>
          <div style={{ display: "flex", justifyContent: "space-between", gap: 12, fontSize: 13.5, marginBottom: 8, lineHeight: 1.3 }}>
            <span style={{ color: "var(--muted)" }}>{d.label}</span>
            <span style={{ fontWeight: 700, whiteSpace: "nowrap" }}>{money ? fmtMoney(d.value) : d.value + "%"}</span>
          </div>
          <div style={{ height: 8, borderRadius: 99, background: "var(--glass-2)", overflow: "hidden" }}>
            <div style={{ height: "100%", width: (d.value / max) * 100 + "%", borderRadius: 99,
              background: `linear-gradient(90deg, ${color}, ${color}aa)`, transition: "width .9s cubic-bezier(.2,.7,.2,1)" }} />
          </div>
        </div>
      ))}
    </div>
  );
}

/* донат-кольцо */
function Donut({ data, size = 168 }) {
  const colors = ["var(--accent)", "var(--accent-2)", "var(--info)", "var(--chart)", "var(--accent-soft)", "#8a6fb0"];
  const total = data.reduce((s, d) => s + d.value, 0);
  const r = size / 2 - 14, c = 2 * Math.PI * r;
  let off = 0;
  return (
    <div style={{ display: "flex", gap: 22, alignItems: "center", flexWrap: "wrap" }}>
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} style={{ transform: "rotate(-90deg)" }}>
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="var(--glass-2)" strokeWidth="14" />
        {data.map((d, i) => {
          const len = (d.value / total) * c;
          const el = <circle key={i} cx={size / 2} cy={size / 2} r={r} fill="none" stroke={colors[i % colors.length]}
            strokeWidth="14" strokeDasharray={`${len} ${c - len}`} strokeDashoffset={-off} strokeLinecap="butt" />;
          off += len; return el;
        })}
      </svg>
      <div style={{ display: "flex", flexDirection: "column", gap: 9, minWidth: 150 }}>
        {data.map((d, i) => (
          <div key={i} style={{ display: "flex", alignItems: "center", gap: 9, fontSize: 13.5 }}>
            <span style={{ width: 10, height: 10, borderRadius: 3, background: colors[i % colors.length], flex: "none" }} />
            <span style={{ color: "var(--muted)", flex: 1 }}>{d.label}</span>
            <span style={{ fontWeight: 700 }}>{d.value}%</span>
          </div>
        ))}
      </div>
    </div>
  );
}

Object.assign(window, { Logo, Icon, I, Img, useReveal, fmt, fmtMoney, AreaChart, BarList, Donut });
