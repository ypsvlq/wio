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

public class WioActivity extends Activity implements SurfaceHolder.Callback, OnGlobalLayoutListener {
    static {
        System.loadLibrary("main");
    }

    private native void onDestroyNative();
    private native void onWindowFocusChangedNative(boolean focused);
    private native void onTouchEventNative(int action, int id, int x, int y);
    private native boolean onKeyDownNative(int keycode, int repeat);
    private native boolean onKeyUpNative(int keycode);
    private native void surfaceCreatedNative(Surface surface);
    private native void surfaceChangedNative(float density, int width, int height);
    private native void surfaceDestroyedNative();
    private native void onGlobalLayoutNative();

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        Window window = getWindow();
        window.requestFeature(Window.FEATURE_NO_TITLE);

        SurfaceView view = new SurfaceView(this);
        setContentView(view);

        view.getHolder().addCallback(this);
        view.getViewTreeObserver().addOnGlobalLayoutListener(this);
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
        float density = getWindow().getWindowManager().getCurrentWindowMetrics().getDensity();
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
}
