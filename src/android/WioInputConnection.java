package net.tiredsleepy.wio;

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
}
