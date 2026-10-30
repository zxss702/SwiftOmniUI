// SPDX-License-Identifier: Apache-2.0
/// Native text measurement used by GraphicsContext.ResolvedText.
@_spi(Host) public enum CanvasTextMeasurement {
    public nonisolated(unsafe) static var read: (@MainActor (String, FontMetrics.Descriptor, Size) -> Size?)?
}
