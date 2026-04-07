package net.tiredsleepy.wio;

import android.view.KeyEvent;
import android.view.inputmethod.BaseInputConnection;

public class WioInputConnection extends BaseInputConnection {
    public WioInputConnection(WioSurfaceView targetView, boolean fullEditor) {
        super(targetView, fullEditor);
    }

    @Override
    public boolean commitText(CharSequence text, int newCursorPosition) {
        for (int codepoint : text.codePoints().toArray()) {
            WioActivity.pushCharEventNative(codepoint);
        }
        return true;
    }

    @Override
    public boolean sendKeyEvent(KeyEvent event) {
        int codepoint = event.getUnicodeChar();
        if (codepoint >= ' ') {
            if (event.getAction() == KeyEvent.ACTION_DOWN) {
                WioActivity.pushCharEventNative(codepoint);
            }
        } else {
            super.sendKeyEvent(event);
        }
        return true;
    }
}
