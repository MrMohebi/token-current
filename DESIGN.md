# Token Current design

The approved surface is an operating instrument. A fixed-width menu bar readout opens a 360-point popover with a large rate, 60-second scrolling graph, provider filter, provider rows, today's three counters, and a compact footer.

Use native regular material (opaque system window background when Reduce Transparency is enabled), system body typography, rounded monospaced measurement digits, subtle separators, and 20-point horizontal padding. Claude uses accessible cyan/teal and a solid trace; Codex uses amber/brown and a dashed trace. Adapt both colors to light and dark appearance. Meaning is always carried by labels and line patterns as well as color.

The main number is total input plus output; cached tokens are a subset of input. Label the rate “Reported usage · 10s average.” Never invent activity while a source is unavailable or waiting. Missing measurements use an em dash. A known source with no recent increments reports zero. Historical imports never animate the live graph.

Motion is limited to brief numeric transitions and graph updates. Reduce Motion disables those transitions. No mascot, gradients, decorative gauges, gamification, or unrelated dashboard sections. Settings use a native grouped form. The approved instrument layout and native type choices take precedence over generic web design heuristics.

Network mode adds a compact radial connection map and machine selector to the popover. A center collector connects to labelled machine nodes; labels and online status carry meaning independently of color. The browser dashboard extends the same cyan/amber instrument palette, with a responsive machine map, rate panel, and complete machine table. Pairing secrets appear only in explicit enrollment controls. Empty, waiting, offline, and authorization error states explain the next action. Network totals are labelled UTC.
