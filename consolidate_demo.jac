"""Live consolidation demo: seed the raw scenario, run Consolidate, print the
compression (before -> after node count) and the replay log.

Run:  jac clean --all --force && REM_LIVE=1 jac run consolidate_demo.jac
"""

import from fixture { SeedGraph }
import from consolidate { Consolidate }
import from schema { Episode, Clinical }


with entry:__main__ {
    root spawn SeedGraph();
    live_before = len([root -->[?:Episode, archived == False]])
        + len([root -->[?:Clinical, suppressed == False]]);
    print(f"[before] live nodes: {live_before}");

    r = (root spawn Consolidate()).reports[0];
    print(f"[after]  live nodes: {r.after}");
    print(f"[compression] {r.before} -> {r.after}");
    print("\n[replay log]");
    for s in r.log {
        print(f"  {s.phase:10s} {s.before:4d} -> {s.after:4d}  {s.detail}");
    }

    print(f"\n[archived episodes]  {len([root -->[?:Episode, archived == True]])}");
    print(f"[live beliefs]       {len([root -->[?:Clinical, suppressed == False]])}");
    every = [c.claim for c in [root -->[?:Clinical, suppressed == False]]];
    print("[beliefs]");
    for c in every {
        print(f"  - {c}");
    }
}
