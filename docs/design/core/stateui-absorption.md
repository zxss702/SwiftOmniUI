# StateUI performance absorption

Reviewed on 2026-11-06 against StateUI 0.8.1 and `upstream/code` at
`354c9dec3`. SOUI keeps its SwiftUI-facing API and native SwiftUI facade on
Apple platforms. This is a mechanism-by-mechanism review, not a directory
migration.

## Incorporated in main

| Mechanism | Upstream reference | SOUI integration |
| --- | --- | --- |
| Direct host wake-up | `d568cf67c`, `abcf83122` | Existing `b09c0c773`: shared executor and host posting, with WinUI and GTK entry points. |
| Independent animation runs and monotonic display time | `939e4f7d5`, `79afcab7d`, `added9ec9`, `529190d88` | Existing `f053c8132`: shared animation channels and display cycle; native backend regressions are tested separately. |
| Measured child changes invalidate parent layout | `a90277055` | Existing measured-property classification in MountedElement; retain SOUI's lazy invalidation and arrangement caches. |
| Numeric contract keys and declaration token reuse | `54703ef18`, `689759e63`, `b0576296c`; current KeyName | Cache deterministic numbers for Prop/Event/Act/NodeType; preserve name-based external representation and existing initializers. Keep KeyName internal. |
| Bounded recursive diff stack | `2830b496b` | Expand and prepare before descending, then complete after children return. SOUI carries stage data in a private value type and retains its environment, scene, focus, preference and drawing scopes. Carried subtrees are revisited after the expansion frame returns as well. |

The staged differ addresses a Windows Debug stack overflow reproduced by nested
animated caption selection. A forty-level tree regression checks both the rendered
leaf and a per-level stack budget of 24 KiB (less than 1 MiB across forty levels).
This is a stack-use contract, not a claim about body rebuild counts or throughput.

Native animation regressions use SOUI's frame wrappers and centered stack
placement. They check uninterrupted movement and reversal from the presented
position, including velocity continuity and preservation of the native view.

## SOUI-specific drawing correction

Custom Shape previously built an empty Path, subscribed to frame changes and
rebuilt after geometry feedback. Its Core-owned path now runs synchronously in
WinUI geometry commitment and GTK snapshot drawing. Native path identity,
brushes, transforms and fill rules remain intact. Arc instructions are converted
to cubic curves at the boundary. The current allocation and state reads are
cached in the rendered node; drawing-only changes do not rebuild its body.

The new LUI selection layer uses Canvas(rendersAsynchronously:renderer:).
The overload preserves the existing renderer initializer. It is permission for
native deferred presentation, not permission to delay recording the initial
commands or move state reads off the UI actor.

## Reviewed mechanisms requiring a separate integration

`c1437d94a` avoids an SVG raster before allocation. A trial in SOUI broke its
stronger ready-pixels contract, including newly mounted lazy file rows. That
trial was removed; WinUI keeps its synchronous ready raster and shared cache.
GTK already rasterizes at native allocation. Avoiding the extra intrinsic raster
requires passing a known final allocation into the initial image load, rather
than leaving a mounted image without pixels.


`77ebb9802` rebuilds from each composed body's actual reads. SOUI still records
composed inputs and state ownership differently and also carries keyed SwiftUI
environments, preferences, lazy source dependencies and animation gates. The
drawing-only dependency split above does not constitute this full migration.

`bcdc77a79`, `42c723d7e` and `71d1ffb2e` separate raw Hashable identity from
numeric builder/state paths. Those identities also feed SOUI navigation,
ForEach and lazy row addressing. Numeric contract keys do not change those
identity rules, and no raw-value identity migration is claimed here.

`58474eb4b` batches collection cell arrivals. Its upstream native adoption was
for Web; GTK and WinUI bind their toolkit cells individually. SOUI's lazy
viewport batching is a separate path. Adding an unused Host overload would not
reduce their native work, so it is not included as a performance claim.

`16e50ea04`, `af7346e9b` and `a49ce264c` optimize StateUI AppKit/UIKit image and
decoration handling. SOUI delegates Apple platforms to SwiftUI; those backends
are not copied into this package. Web/Android-only performance changes likewise
do not justify changes to the Windows/GTK products.

No upstream benchmark number is treated as a measured SOUI speedup. Validation
logs distinguish shared Core/Host tests, native pixel/animation tests, and LUI
source merging; LUI is not built as part of this task.
