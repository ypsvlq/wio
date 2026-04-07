package net.tiredsleepy.wio;

import android.app.Activity;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.os.Bundle;
import android.view.InputDevice;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.PointerIcon;
import android.view.Surface;
import android.view.SurfaceHolder;
import android.view.SurfaceView;
import android.view.ViewTreeObserver.OnGlobalLayoutListener;
import android.view.Window;
import android.view.inputmethod.InputMethodManager;

public class WioActivity extends Activity implements SurfaceHolder.Callback, OnGlobalLayoutListener {
    static {
        System.loadLibrary("main");
    }

    native void onCreateNative();
    static native void onDestroyNative();
    static native void onWindowFocusChangedNative(boolean focused);
    static native void onTouchEventNative(int action, int id, int x, int y);
    static native void pushMouseEventNative(int x, int y, int buttons);
    static native void pushScrollEventNative(float vertical, float horizontal);
    static native boolean onKeyDownNative(int keycode, int repeat);
    static native boolean onKeyUpNative(int keycode);
    static native void surfaceCreatedNative(Surface surface);
    static native void surfaceChangedNative(float density, int width, int height);
    static native void surfaceDestroyedNative();
    static native void onGlobalLayoutNative();
    static native void onCapturedPointerEventNative(int x, int y);
    static native void pushCharEventNative(int codepoint);

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        requestWindowFeature(Window.FEATURE_NO_TITLE);

        WioSurfaceView view = new WioSurfaceView(this);
        setContentView(view);

        view.setFocusableInTouchMode(true);
        view.requestFocus();

        view.getHolder().addCallback(this);
        view.getViewTreeObserver().addOnGlobalLayoutListener(this);

        onCreateNative();
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        onDestroyNative();
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        onWindowFocusChangedNative(hasFocus);
    }

    @Override
    public boolean onTouchEvent(MotionEvent event) {
        onGenericMotionEvent(event);
        return true;
    }

    @Override
    public boolean onGenericMotionEvent(MotionEvent event) {
        switch (event.getSource()) {
            case InputDevice.SOURCE_TOUCHSCREEN:
                int action = event.getActionMasked();
                switch (action) {
                    case MotionEvent.ACTION_DOWN:
                    case MotionEvent.ACTION_MOVE:
                    case MotionEvent.ACTION_UP:
                    case MotionEvent.ACTION_CANCEL:
                        for (int i = 0; i < event.getPointerCount(); i++) {
                            onTouchEventNative(action, event.getPointerId(i), (int)event.getX(i), (int)event.getY(i));
                        }
                        break;
                    case MotionEvent.ACTION_POINTER_DOWN:
                    case MotionEvent.ACTION_POINTER_UP:
                        onTouchEventNative(action, event.getPointerId(event.getActionIndex()), 0, 0);
                        break;
                }
                break;
            case InputDevice.SOURCE_MOUSE:
                switch (event.getActionMasked()) {
                    case MotionEvent.ACTION_DOWN:
                    case MotionEvent.ACTION_UP:
                    case MotionEvent.ACTION_MOVE:
                    case MotionEvent.ACTION_HOVER_MOVE:
                        pushMouseEventNative((int)event.getX(0), (int)event.getY(0), event.getButtonState());
                        break;
                    case MotionEvent.ACTION_SCROLL:
                        pushScrollEventNative(event.getAxisValue(MotionEvent.AXIS_VSCROLL), event.getAxisValue(MotionEvent.AXIS_HSCROLL));
                        break;
                }
                break;
        }
        return true;
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (onKeyDownNative(keyCode, event.getRepeatCount())) {
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }

    @Override
    public boolean onKeyUp(int keyCode, KeyEvent event) {
        if (onKeyUpNative(keyCode)) {
            return true;
        }
        return super.onKeyUp(keyCode, event);
    }

    @Override
    public void surfaceCreated(SurfaceHolder holder) {
        surfaceCreatedNative(holder.getSurface());
    }

    @Override
    public void surfaceChanged(SurfaceHolder holder, int format, int width, int height) {
        float density = getWindowManager().getCurrentWindowMetrics().getDensity();
        surfaceChangedNative(density, width, height);
    }

    @Override
    public void surfaceDestroyed(SurfaceHolder holder) {
        surfaceDestroyedNative();
    }

    @Override
    public void onGlobalLayout() {
        onGlobalLayoutNative();
    }

    public void enableTextInput() {
        InputMethodManager imm = (InputMethodManager)getSystemService(INPUT_METHOD_SERVICE);
        imm.showSoftInput(getCurrentFocus(), 0);
    }

    public void disableTextInput() {
        InputMethodManager imm = (InputMethodManager)getSystemService(INPUT_METHOD_SERVICE);
        imm.hideSoftInputFromWindow(getCurrentFocus().getWindowToken(), 0);
    }

    static int cursors[] = {
        PointerIcon.TYPE_NULL,
        PointerIcon.TYPE_ARROW,
        PointerIcon.TYPE_ARROW, // .arrow_busy
        PointerIcon.TYPE_WAIT,
        PointerIcon.TYPE_TEXT,
        PointerIcon.TYPE_HAND,
        PointerIcon.TYPE_CROSSHAIR,
        PointerIcon.TYPE_ARROW, // .forbidden
        PointerIcon.TYPE_ALL_SCROLL,
        PointerIcon.TYPE_VERTICAL_DOUBLE_ARROW,
        PointerIcon.TYPE_HORIZONTAL_DOUBLE_ARROW,
        PointerIcon.TYPE_TOP_RIGHT_DIAGONAL_DOUBLE_ARROW,
        PointerIcon.TYPE_TOP_LEFT_DIAGONAL_DOUBLE_ARROW,
    };

    public void setCursor(int cursor) {
        getCurrentFocus().setPointerIcon(PointerIcon.getSystemIcon(this, cursors[cursor + 1]));
    }

    public void setCursorMode(int mode) {
        if (mode == 2) {
            getCurrentFocus().requestPointerCapture();
        } else {
            getCurrentFocus().releasePointerCapture();
        }
    }

    public void setClipboardText(String text) {
        ClipboardManager clipboard = (ClipboardManager)getSystemService(CLIPBOARD_SERVICE);
        clipboard.setPrimaryClip(ClipData.newPlainText(null, text));
    }

    public String getClipboardText() {
        ClipboardManager clipboard = (ClipboardManager)getSystemService(CLIPBOARD_SERVICE);
        try {
            return clipboard.getPrimaryClip().getItemAt(0).getText().toString();
        } catch (NullPointerException e) {
            return null;
        }
    }
}
