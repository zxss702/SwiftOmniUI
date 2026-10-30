// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

package swiftomniui.android;

import android.content.Context;
import android.view.MotionEvent;
import android.widget.LinearLayout;

/** A stepper's two buttons side by side, its element's gestures seeing the touches the buttons get. */
final class SwiftOmniUIStepper extends LinearLayout {
    private final SwiftOmniUIWatch watch = new SwiftOmniUIWatch();

    SwiftOmniUIStepper(Context context) {
        super(context);
    }

    /** Lets `listener`'s gestures see what the buttons get. */
    void watch(SwiftOmniUIListener listener) {
        watch.watch(listener);
    }

    @Override
    public boolean dispatchTouchEvent(MotionEvent event) {
        return watch.touch(this, event, super::dispatchTouchEvent);
    }

    @Override
    public boolean dispatchGenericMotionEvent(MotionEvent event) {
        return watch.hover(this, event, super::dispatchGenericMotionEvent);
    }
}
