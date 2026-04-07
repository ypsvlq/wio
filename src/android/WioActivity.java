package net.tiredsleepy.wio;

import android.app.Activity;
import android.os.Bundle;
import android.view.KeyEvent;
import android.view.MotionEvent;
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
    static native boolean onKeyDownNative(int keycode, int repeat);
    static native boolean onKeyUpNative(int keycode);
    static native void surfaceCreatedNative(Surface surface);
    static native void surfaceChangedNative(float density, int width, int height);
    static native void surfaceDestroyedNative();
    static native void onGlobalLayoutNative();
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
}
