// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// A value a journey can be made of - one the host can animate lane by lane. This
/// library's own.
///
/// `$x.journey` exists on a binding to one, `@State(animation:)` is declared over
/// one, and a driven property animates one. Text, whole numbers and truth values
/// have no half way and are not `Walked`, so asking for their journey does not
/// compile.
public protocol Walked: StateValue {}

extension Double: Walked {}
extension Point: Walked {}
extension Rect: Walked {}
extension EdgeInsets: Walked {}
extension Color: Walked {}
