"""Shared design system for the REM client (shadcn-flavoured, light theme).

One injected stylesheet drives every screen: CSS custom-property tokens plus a
small set of component classes (`btn`, `card`, `input`, `chip`, `badge`, `tabs`,
chat `msg`, the live `eq`/`rec-dot` bits). Screens use `className=` and keep
inline styles only for genuinely dynamic values. `remCss()` is mounted once by
the app shell (`<style>{remCss()}</style>`).

The CSS is assembled by joining a list of complete rules -- jac2js turns a real
newline inside a cl string into a literal `\\n`, which would corrupt selectors,
so we never rely on source newlines (jac-cl-js-interop, string gotchas).

Also exports three tiny presentational helpers used by the transcript views:
speaker accent colour, avatar initials, and mm:ss clock formatting.
"""


"""The whole design system as one CSS string (no source newlines relied on)."""
def:pub remCss() -> str {
    rules = [
        ":root{",
        "--page:#f6f7f9;--card:#ffffff;--border:#e7e9ee;--border-strong:#d7dae1;",
        "--fg:#0b0f19;--muted:#6b7280;--muted-2:#9aa1ac;",
        "--primary:#4f46e5;--primary-hover:#4338ca;--primary-soft:#eef0ff;--primary-ink:#4338ca;",
        "--success:#16a34a;--success-hover:#15803d;--success-soft:#e9f7ef;--success-ink:#166534;",
        "--danger:#dc2626;--danger-hover:#b91c1c;--danger-soft:#fdeceb;--danger-ink:#b42318;",
        "--warn-soft:#fef3e2;--warn-ink:#b45309;",
        "--ring:rgba(79,70,229,.18);--radius:12px;",
        "--shadow:0 1px 2px rgba(16,24,40,.06),0 1px 3px rgba(16,24,40,.05);",
        "--shadow-lg:0 12px 32px -12px rgba(16,24,40,.22);}",
        "*{box-sizing:border-box}",
        "body{margin:0;background:var(--page)}",
        ".rem-app{min-height:100vh;background:var(--page);color:var(--fg);",
        "font-family:ui-sans-serif,system-ui,-apple-system,'Segoe UI',Roboto,Inter,sans-serif;",
        "-webkit-font-smoothing:antialiased}",
        ".rem-header{display:flex;align-items:center;gap:.85rem;padding:.7rem 1.15rem;",
        "background:rgba(255,255,255,.82);backdrop-filter:blur(10px);",
        "border-bottom:1px solid var(--border);position:sticky;top:0;z-index:30}",
        ".rem-brand{font-weight:800;letter-spacing:.16em;color:var(--primary);font-size:1rem}",
        ".container{max-width:720px;margin:1.6rem auto;padding:0 1.15rem}",
        ".container-sm{max-width:420px;margin:0 auto;padding:0 1.15rem}",
        ".stack{min-height:100vh;display:flex;align-items:center;justify-content:center;padding:1.15rem}",
        ".card{background:var(--card);border:1px solid var(--border);border-radius:16px;",
        "box-shadow:var(--shadow);padding:1.4rem}",
        ".h1{margin:0;font-size:1.45rem;font-weight:700;letter-spacing:-.01em}",
        ".h2{margin:0;font-size:1.05rem;font-weight:700}",
        ".muted{color:var(--muted)}",
        ".muted-sm{color:var(--muted);font-size:.85rem}",
        ".label{display:block;font-size:.8rem;font-weight:600;color:var(--muted);margin-bottom:.35rem}",
        ".field{font-size:.72rem;font-weight:700;letter-spacing:.04em;text-transform:uppercase;color:var(--primary-ink)}",
        ".input,.select,.textarea{width:100%;box-sizing:border-box;font:inherit;font-size:.92rem;",
        "color:var(--fg);background:#fff;border:1px solid var(--border-strong);border-radius:10px;",
        "padding:.6rem .75rem;outline:none;transition:border-color .15s,box-shadow .15s}",
        ".input:focus,.select:focus,.textarea:focus{border-color:var(--primary);box-shadow:0 0 0 3px var(--ring)}",
        ".input:disabled,.textarea:disabled{background:#f4f5f7;color:#7a828e}",
        ".textarea{resize:vertical;min-height:64px;line-height:1.5}",
        ".btn{display:inline-flex;align-items:center;justify-content:center;gap:.5rem;font:inherit;",
        "font-weight:600;font-size:.9rem;line-height:1;padding:.62rem 1rem;border-radius:10px;",
        "border:1px solid transparent;cursor:pointer;transition:background .15s,border-color .15s,box-shadow .15s,transform .04s}",
        ".btn:active{transform:translateY(1px)}",
        ".btn:disabled{opacity:.55;cursor:not-allowed}",
        ".btn-primary{background:var(--primary);color:#fff;box-shadow:var(--shadow)}",
        ".btn-primary:hover:not(:disabled){background:var(--primary-hover)}",
        ".btn-success{background:var(--success);color:#fff;box-shadow:var(--shadow)}",
        ".btn-success:hover:not(:disabled){background:var(--success-hover)}",
        ".btn-danger{background:var(--danger);color:#fff;box-shadow:var(--shadow)}",
        ".btn-danger:hover:not(:disabled){background:var(--danger-hover)}",
        ".btn-outline{background:#fff;color:var(--fg);border-color:var(--border-strong)}",
        ".btn-outline:hover:not(:disabled){background:#f6f7f9}",
        ".btn-ghost{background:transparent;color:var(--muted)}",
        ".btn-ghost:hover:not(:disabled){background:#eef0f3;color:var(--fg)}",
        ".btn-sm{padding:.4rem .7rem;font-size:.82rem;border-radius:8px}",
        ".btn-block{width:100%}",
        ".chip{display:inline-flex;align-items:center;gap:.4rem;padding:.45rem .8rem;border-radius:999px;",
        "border:1px solid var(--border-strong);background:#fff;color:var(--fg);cursor:pointer;",
        "font:inherit;font-size:.85rem;transition:border-color .15s,background .15s,color .15s}",
        ".chip:hover{border-color:#b9bdc6}",
        ".chip-active{border-color:var(--primary);background:var(--primary-soft);color:var(--primary-ink);font-weight:600}",
        ".check{width:18px;height:18px;border-radius:6px;border:1.5px solid var(--border-strong);",
        "display:inline-flex;align-items:center;justify-content:center;font-size:.72rem;color:#fff;flex:0 0 auto}",
        ".check-on{background:var(--primary);border-color:var(--primary)}",
        ".row{display:flex;align-items:center;gap:.7rem;padding:.6rem .75rem;border-radius:10px;",
        "border:1px solid var(--border);background:#fff;cursor:pointer;transition:border-color .15s,background .15s}",
        ".row:hover{border-color:var(--border-strong)}",
        ".row-active{border-color:var(--primary);background:var(--primary-soft)}",
        ".badge{display:inline-flex;align-items:center;gap:.3rem;padding:.2rem .55rem;border-radius:999px;",
        "font-size:.72rem;font-weight:700;letter-spacing:.02em}",
        ".badge-success{background:var(--success-soft);color:var(--success-ink)}",
        ".badge-warn{background:var(--warn-soft);color:var(--warn-ink)}",
        ".badge-muted{background:#eef0f3;color:var(--muted)}",
        ".alert{padding:.6rem .85rem;border-radius:10px;font-size:.85rem;margin:.2rem 0}",
        ".alert-error{background:var(--danger-soft);color:var(--danger-ink);border:1px solid #f6cecb}",
        ".alert-success{background:var(--success-soft);color:var(--success-ink);border:1px solid #bbe7cb}",
        ".tabs{display:inline-flex;padding:.25rem;background:#eef0f3;border-radius:999px;gap:.15rem}",
        ".tab{border:none;background:transparent;padding:.5rem 1.15rem;border-radius:999px;font:inherit;",
        "font-weight:600;font-size:.9rem;color:var(--muted);cursor:pointer;transition:background .15s,color .15s}",
        ".tab-active{background:#fff;color:var(--fg);box-shadow:var(--shadow)}",
        ".divider{height:1px;background:var(--border);border:0;margin:1rem 0}",
        ".feed{display:flex;flex-direction:column;gap:1.15rem}",
        ".msg{display:flex;gap:.7rem}",
        ".msg-av{flex:0 0 auto;width:30px;height:30px;border-radius:50%;display:flex;align-items:center;",
        "justify-content:center;color:#fff;font-size:.72rem;font-weight:700}",
        ".msg-main{min-width:0}",
        ".msg-head{display:flex;align-items:baseline;gap:.5rem;margin-bottom:.12rem}",
        ".msg-name{font-weight:600;font-size:.92rem}",
        ".msg-time{font-size:.74rem;color:var(--muted-2);font-variant-numeric:tabular-nums}",
        ".msg-body{font-size:.98rem;line-height:1.5;color:#1f2430}",
        ".msg-interim .msg-body{color:var(--muted-2);font-style:italic}",
        ".empty{border:1px dashed var(--border-strong);border-radius:14px;padding:2.4rem 1.2rem;",
        "text-align:center;color:var(--muted);background:#fbfcfd}",
        ".dock{display:flex;align-items:center;justify-content:center;gap:1.4rem;padding:1rem;margin-top:1.1rem;",
        "background:var(--card);border:1px solid var(--border);border-radius:16px;box-shadow:var(--shadow)}",
        ".rec-btn{width:62px;height:62px;border-radius:50%;border:none;cursor:pointer;display:flex;",
        "align-items:center;justify-content:center;box-shadow:var(--shadow-lg);transition:transform .05s,background .15s}",
        ".rec-btn:active{transform:scale(.96)}",
        ".rec-btn-stop{background:var(--danger);color:#fff}",
        ".rec-btn-stop:hover{background:var(--danger-hover)}",
        ".rec-square{width:20px;height:20px;border-radius:5px;background:#fff}",
        ".dock-side{display:flex;flex-direction:column;align-items:center;gap:.15rem;min-width:66px;color:var(--muted)}",
        ".dock-num{font-size:1.05rem;font-weight:700;color:var(--fg);font-variant-numeric:tabular-nums}",
        ".dock-lbl{font-size:.68rem;letter-spacing:.03em;text-transform:uppercase}",
        ".rec-dot{width:9px;height:9px;border-radius:50%;background:var(--danger);animation:pulse 1.5s infinite}",
        ".rec-dot-idle{width:9px;height:9px;border-radius:50%;background:#c2c6cd}",
        "@keyframes pulse{0%{box-shadow:0 0 0 0 rgba(220,38,38,.45)}70%{box-shadow:0 0 0 8px rgba(220,38,38,0)}100%{box-shadow:0 0 0 0 rgba(220,38,38,0)}}",
        ".eq{display:inline-flex;align-items:flex-end;gap:3px;height:24px}",
        ".eq span{width:3px;height:5px;background:var(--primary);border-radius:2px;animation:eq 1s ease-in-out infinite}",
        ".eq span:nth-child(1){animation-delay:-.9s}.eq span:nth-child(2){animation-delay:-.7s}",
        ".eq span:nth-child(3){animation-delay:-.5s}.eq span:nth-child(4){animation-delay:-.3s}",
        ".eq span:nth-child(5){animation-delay:-.1s}.eq span:nth-child(6){animation-delay:-.6s}.eq span:nth-child(7){animation-delay:-.2s}",
        "@keyframes eq{0%,100%{height:5px}50%{height:22px}}",
        ".eq-idle span{animation:none;height:6px;background:#c9cdd4}",
        ".spinner{width:44px;height:44px;border:4px solid #e6e8eb;border-top-color:var(--primary);border-radius:50%;animation:spin 1s linear infinite}",
        "@keyframes spin{to{transform:rotate(360deg)}}",
        ".chunk{background:#fff;border:1px solid var(--border);border-radius:12px;padding:.8rem 1rem;transition:border-color .15s}",
        ".chunk:hover{border-color:var(--border-strong)}",
        ".home{max-width:560px;margin:0 auto;padding:1.5rem 1.15rem 5.5rem}",
        ".home-head{display:flex;align-items:flex-start;gap:1rem;margin-bottom:1.1rem}",
        ".home-greet{margin:0;font-size:1.5rem;font-weight:700;letter-spacing:-.02em}",
        ".home-sub{margin:.25rem 0 0;color:var(--muted);font-size:.88rem}",
        ".avatar{flex:0 0 auto;width:44px;height:44px;border-radius:50%;border:1.5px solid var(--border-strong);",
        "background:var(--primary-soft);color:var(--primary-ink);font-weight:700;font-size:.9rem;cursor:pointer;",
        "display:flex;align-items:center;justify-content:center;transition:border-color .15s}",
        ".avatar:hover{border-color:var(--primary)}",
        ".attn{border:1px solid var(--border);border-radius:16px;background:#fff;box-shadow:var(--shadow);",
        "padding:1rem 1.1rem;margin-bottom:1.1rem}",
        ".attn-empty{border-style:dashed;box-shadow:none;background:#fbfcfd}",
        ".attn-head{display:flex;align-items:center;gap:.5rem;font-size:.72rem;font-weight:700;letter-spacing:.06em;",
        "text-transform:uppercase;color:var(--muted);margin-bottom:.7rem}",
        ".attn-count{display:inline-flex;align-items:center;justify-content:center;min-width:20px;height:20px;padding:0 .35rem;",
        "border-radius:999px;background:var(--danger-soft);color:var(--danger-ink);font-size:.72rem;font-weight:800}",
        ".attn-item{display:flex;gap:.55rem;align-items:flex-start;padding:.5rem 0;font-size:.95rem;line-height:1.4}",
        ".attn-item + .attn-item{border-top:1px solid var(--border)}",
        ".attn-room{font-weight:700;flex:0 0 auto}",
        ".attn-reason{flex:1 1 auto;min-width:0}",
        ".attn-resolve{flex:0 0 auto;align-self:center;border:1px solid var(--border-strong);background:#fff;",
        "color:var(--primary-ink);border-radius:999px;padding:.25rem .7rem;font:inherit;font-size:.76rem;",
        "font-weight:600;cursor:pointer;transition:border-color .15s,background .15s}",
        ".attn-resolve:hover{border-color:var(--primary);background:var(--primary-soft)}",
        ".attn-tier1{color:var(--danger)}",
        ".attn-more{margin-top:.55rem;font-size:.82rem;font-weight:600;color:var(--primary-ink);cursor:pointer;background:none;border:none;padding:0}",
        ".cta-note{text-align:center;color:var(--muted);font-size:.82rem;margin:.55rem 0 1.4rem}",
        ".sec-head{display:flex;align-items:center;justify-content:space-between;margin:0 .1rem .7rem}",
        ".sec-title{font-size:.75rem;font-weight:700;letter-spacing:.06em;text-transform:uppercase;color:var(--muted)}",
        ".searchbox{width:150px;padding:.4rem .7rem;font-size:.82rem;border-radius:999px;border:1px solid var(--border-strong);",
        "background:#fff;font:inherit;outline:none;transition:border-color .15s,box-shadow .15s,width .15s}",
        ".searchbox:focus{border-color:var(--primary);box-shadow:0 0 0 3px var(--ring);width:190px}",
        ".res-list{display:flex;flex-direction:column}",
        ".res-row{display:flex;align-items:center;gap:.85rem;padding:.85rem .35rem;border:none;background:none;width:100%;",
        "text-align:left;font:inherit;cursor:pointer;border-bottom:1px solid var(--border);transition:background .12s}",
        ".res-row:hover{background:#f6f7f9}",
        ".dot{flex:0 0 auto;width:12px;height:12px;border-radius:50%}",
        ".dot-concern{background:var(--danger);box-shadow:0 0 0 4px var(--danger-soft)}",
        ".dot-watch{background:#fff;border:2px solid var(--warn-ink)}",
        ".dot-stable{background:#fff;border:2px solid #cfd4dc}",
        ".res-main{min-width:0;flex:1 1 auto;display:flex;flex-direction:column}",
        ".res-name{font-size:1rem;font-weight:600;color:var(--fg)}",
        ".res-reason{font-size:.82rem;color:var(--muted);margin-top:.1rem;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}",
        ".res-reason-hot{color:var(--danger-ink);font-weight:600}",
        ".chev{flex:0 0 auto;color:var(--muted-2);font-size:1.1rem}",
        ".res-empty{padding:1.4rem .35rem;color:var(--muted);font-size:.9rem}",
        ".tabbar{position:fixed;left:0;right:0;bottom:0;z-index:40;display:flex;background:rgba(255,255,255,.9);",
        "backdrop-filter:blur(10px);border-top:1px solid var(--border);padding:.5rem .5rem calc(.5rem + env(safe-area-inset-bottom))}",
        ".tabbar-item{flex:1 1 0;border:none;background:none;font:inherit;font-size:.75rem;font-weight:600;color:var(--muted-2);",
        "cursor:pointer;padding:.4rem 0;display:flex;flex-direction:column;align-items:center;gap:.2rem;transition:color .12s}",
        ".tabbar-item:hover{color:var(--muted)}",
        ".tabbar-active{color:var(--primary)}",
        ".tabbar-ic{font-size:1.05rem;line-height:1}",
        ".belief{position:relative;display:block;width:100%;text-align:left;background:#fff;border:1px solid var(--border);",
        "border-left:3px solid var(--border-strong);border-radius:12px;padding:.75rem .9rem;margin-bottom:.5rem;",
        "cursor:pointer;transition:border-color .15s,box-shadow .15s,background .15s}",
        ".belief:hover{border-color:var(--border-strong);box-shadow:var(--shadow)}",
        ".belief-active{border-color:var(--primary);border-left-color:var(--primary);background:var(--primary-soft)}",
        ".belief-claim{font-size:.95rem;line-height:1.5;color:var(--fg)}",
        ".belief-meta{display:flex;flex-wrap:wrap;align-items:center;gap:.4rem;margin-top:.5rem}"
    ];
    return "".join(rules);
}


"""Accent colour for a diarized speaker label (pink / indigo / sky, then slate)."""
def:pub speakerColor(label: str) -> str {
    palette = {"Speaker 1": "#ec4899", "Speaker 2": "#6366f1", "Speaker 3": "#0ea5e9", "Speaker 4": "#f59e0b"};
    return palette.get(label, "#64748b") as str;
}


"""Up-to-two-letter avatar initials: 'Speaker 1' -> 'S1', 'Maya Ortiz' -> 'MO'."""
def:pub initials(label: str) -> str {
    parts = [p for p in label.split(" ") if p];
    if len(parts) >= 2 {
        return ((parts[0] as str)[0:1] + (parts[1] as str)[0:1]).upper();
    }
    if len(parts) == 1 {
        return (parts[0] as str)[0:1].upper();
    }
    return "?";
}


"""Seconds -> mm:ss (matches the reference transcript timestamps)."""
def:pub fmtClock(sec: float) -> str {
    total: int = int(sec);
    m: int = total // 60;
    s: int = total % 60;
    mm: str = str(m);
    if m < 10 { mm = "0" + mm; }
    ss: str = str(s);
    if s < 10 { ss = "0" + ss; }
    return mm + ":" + ss;
}
