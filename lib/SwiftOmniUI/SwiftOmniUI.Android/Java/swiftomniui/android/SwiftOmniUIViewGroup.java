// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

package swiftomniui.android;

import android.content.Context;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewParent;

/**
 * A SwiftOmniUI layout: Android asks it to measure and place, and the Swift host
 * answers. It draws its children past its edges, as every SwiftOmniUI layout does.
 */
class SwiftOmniUIViewGroup extends ViewGroup {
    private final long view;

    SwiftOmniUIViewGroup(Context context, long view) {
        super(context);
        this.view = view;
        setClipChildren(false);
        setClipToPadding(false);
    }

    /** The number the Swift view answers to. */
    final long number() {
        return view;
    }

    /** Whether the layout was measured since it last arranged its children, and the size it arranged them in. */
    private boolean measured = true;
    private int arrangedWidth = -1;
    private int arrangedHeight = -1;

    /** The order the children are drawn and touched in, back to front, by index; null for their own. */
    private int[] drawingOrder;

    @Override
    protected void onMeasure(int widthSpec, int heightSpec) {
        long size = SwiftOmniUIHost.measure(view, widthSpec, heightSpec);
        setMeasuredDimension((int) (size >>> 32), (int) size);
        measured = true;
    }

    /** A layout moved but not resized, with nothing in it asking to be measured again, leaves its children be. */
    @Override
    protected void onLayout(boolean changed, int left, int top, int right, int bottom) {
        int width = right - left;
        int height = bottom - top;
        if (!measured && width == arrangedWidth && height == arrangedHeight) return;

        measured = false;
        arrangedWidth = width;
        arrangedHeight = height;
        SwiftOmniUIHost.arrange(view, width, height);
    }

    /** Draws the children, and hands them touches, in `order` - back to front, by index; null for their own order. */
    void setDrawingOrder(int[] order) {
        drawingOrder = order;
        setChildrenDrawingOrderEnabled(order != null);
        invalidate();
    }

    @Override
    protected int getChildDrawingOrder(int childCount, int drawingPosition) {
        int[] order = drawingOrder;
        return order != null && order.length == childCount ? order[drawingPosition] : drawingPosition;
    }

    /** Whether the layout and everything in it take no touch: it goes to whatever is behind. */
    private boolean ignoresInput;

    void setIgnoresInput(boolean ignores) {
        ignoresInput = ignores;
    }

    /**
     * Whether a touch that lands on the layout itself goes on to what is under it: the children answer first,
     * as always, and where none answers the layout takes none either.
     */
    private boolean letsInputThrough;

    void setLetsInputThrough(boolean lets) {
        letsInputThrough = lets;
    }

    /** The touch listener the host set, kept so a passing-through layout can step over it. */
    private OnTouchListener touchListener;

    @Override
    public void setOnTouchListener(OnTouchListener listener) {
        touchListener = listener;
        super.setOnTouchListener(listener);
    }

    /** Which `ContainerShape` the layout answers touches inside - its kind, -1 for all of it - and its radius. */
    private int hitShape = -1;
    private float hitRadius;

    void setHitShape(int kind, float radius) {
        hitShape = kind;
        hitRadius = radius;
    }

    @Override
    public boolean dispatchTouchEvent(MotionEvent event) {
        if (ignoresInput) return false;
        if (hitShape >= 0 && event.getActionMasked() == MotionEvent.ACTION_DOWN
                && !inHitShape(event.getX(), event.getY())) {
            return false;
        }
        if (!letsInputThrough || touchListener == null) return super.dispatchTouchEvent(event);

        // The children answer first, as always; where none does, the touch is not the layout's own -
        // it steps over its listener on the way to whatever stands under it.
        super.setOnTouchListener(null);
        try {
            return super.dispatchTouchEvent(event);
        } finally {
            super.setOnTouchListener(touchListener);
        }
    }

    @Override
    public boolean onTouchEvent(MotionEvent event) {
        return !letsInputThrough && super.onTouchEvent(event);
    }

    /** Whether `x`,`y` stands inside the hit shape - the `ContainerShape` kinds rectangle, rounded, oval,
     *  capsule and circle, the radius in pixels. */
    private boolean inHitShape(float x, float y) {
        int width = getWidth(), height = getHeight();
        switch (hitShape) {
            case 1:
                return insideRounded(x, y, width, height,
                        Math.min(hitRadius, Math.min(width, height) / 2f));
            case 2:
                return insideEllipse(x, y, 0, 0, width, height);
            case 3:
                return insideRounded(x, y, width, height, Math.min(width, height) / 2f);
            case 4: {
                float side = Math.min(width, height);
                return insideEllipse(x, y, (width - side) / 2f, (height - side) / 2f, side, side);
            }
            default:
                return true;
        }
    }

    private static boolean insideRounded(float x, float y, float width, float height, float radius) {
        if (x < 0 || y < 0 || x > width || y > height) return false;
        float near = x < radius ? radius : (x > width - radius ? width - radius : x);
        float top = y < radius ? radius : (y > height - radius ? height - radius : y);
        float across = x - near, down = y - top;
        return across * across + down * down <= radius * radius;
    }

    private static boolean insideEllipse(float x, float y, float left, float top, float width, float height) {
        float across = width / 2f, down = height / 2f;
        if (across <= 0 || down <= 0) return false;
        float nx = (x - left - across) / across, ny = (y - top - down) / down;
        return nx * nx + ny * ny <= 1f;
    }

    /** A layout that does not scroll lets its children show a press at once. */
    @Override
    public boolean shouldDelayChildPressedState() {
        return false;
    }

    /** Holds exactly {@code children}, in order, moving only what moved. */
    void setChildren(View[] children) {
        for (int index = getChildCount() - 1; index >= 0; index--) {
            if (!holds(children, getChildAt(index))) removeViewAt(index);
        }

        for (int index = 0; index < children.length; index++) {
            View child = children[index];
            if (index < getChildCount() && getChildAt(index) == child) continue;

            ViewParent parent = child.getParent();
            if (parent instanceof ViewGroup) ((ViewGroup) parent).removeView(child);
            addView(child, index);
        }
    }

    private static boolean holds(View[] children, View child) {
        for (View each : children) {
            if (each == child) return true;
        }
        return false;
    }
}
