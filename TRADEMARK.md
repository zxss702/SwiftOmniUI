# Trademark Policy

**SwiftOmniUI** is a trademark of Huaxia Xufu (Beijing) Technology Co., Ltd.
(华夏旭府（北京）科技有限公司).

The software in this repository is released under the
[Apache License 2.0](LICENSE). That licence grants you rights in the **code**. It
does not grant you rights in the **name** or the logo - its section 6 says so in
as many words, and this file is here to say what you may do with them instead.

The short version: **use the name to talk about this project. Do not use it in a
way that suggests your project is this one, or is endorsed by it.**

## You do not need to ask

- Say that your software uses, supports, is built with, or is compatible with
  SwiftOmniUI.
- Write about SwiftOmniUI: articles, tutorials, courses, books, talks, videos - and
  use the name in the title of such material.
- Redistribute unmodified copies of SwiftOmniUI under the name SwiftOmniUI.
- Link to the project, and use the logo to do so.
- Name a package that extends or integrates with SwiftOmniUI, as long as your own
  name comes first - `Acme.SwiftOmniUI.Charts`, not `SwiftOmniUI.Charts`.

## Please ask first

- Using **SwiftOmniUI** as the leading element in the name of your own product,
  package, service or company - *SwiftOmniUI Pro*, *SwiftOmniUI Cloud*, *SwiftOmniUI for X*.
- Using it as a domain name, an organisation name, or a social media handle.
- Anything that suggests this project endorses, sponsors, or is affiliated with
  you.

## Prior and independent use

"UI" is an ordinary word, and other projects have used it - some of them
earlier. Nothing here is a claim against them. This document describes how to
refer to **this** project, and asks only that you do not present your own work
as if it were this one. SwiftOmniUI derives from upstream StateUI; that
project's own name and marks remain its author's.

## Forks

You may fork and modify SwiftOmniUI - the licence says so. **Give your fork a
different name.** You are welcome to say that it is *based on SwiftOmniUI* or *a fork
of SwiftOmniUI*; please do not release it as SwiftOmniUI, because someone downloading it
will reasonably expect the original.

The name is not scattered through the sources. It is in two places, and a fork
that changes them is rebranded:

- the `Package.swift` manifests - the Swift module names, which is what
  `import SwiftOmniUI` reads.
- `lib/SwiftOmniUI/Core/Sources/Bridge/Exports.swift` - the `@_cdecl("swiftomniui_…")` names.
  They are the C ABI between the Swift library and a host written in another
  language, so a fork that does not also fork such a host can leave them alone.

## The logo

Use it to point at this project. Do not alter its shape, proportions or colours,
and do not use it as the icon of your own application.

The artwork of the sample applications - the application icon and the tiles -
carries the mark. An application started from a sample replaces it with its own
before it ships.

## Asking

Open a discussion - or an issue - on the project's GitHub. Reasonable requests
are usually granted, and asking is not a trap.

In the open on purpose: a permission given once is then one anybody can read.

---

This policy is based on the
[Model Trademark Guidelines](https://modeltrademarkguidelines.org/), available
under CC BY 3.0.
