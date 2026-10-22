# Linux transport

Internal NIO transport used by SwiftOmniUIFoundation's AsyncImage on Linux.
It exposes async URLSession-shaped data, upload and download APIs over
AsyncHTTPClient. FoundationNetworking supplies request/response/configuration
value types; its URLSession transport is never constructed here.

These sources are an independent copy of LogorythiaShare's Linux networking
implementation. Keep the two packages independent: LogorythiaShare must not
import or depend on a SwiftOmniUI target. Changes to transport semantics should
be reviewed in both copies. There is no public networking product or UI-facing
networking re-export.
