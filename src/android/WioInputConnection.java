package net.tiredsleepy.wio;

import android.view.KeyEvent;
import android.view.inputmethod.BaseInputConnection;

public class WioInputConnection extends BaseInputConnection {
    public WioInputConnection(WioSurfaceView targetView) {
        super(targetView, false);
    }

    @Override
    public boolean setComposingText(CharSequence text, int newCursorPosition) {
        WioActivity.pushPreviewResetEventNative();
        for (int codepoint : text.codePoints().toArray()) {
            WioActivity.pushPreviewCharEventNative(codepoint);
        }
        super.setComposingText(text, newCursorPosition);
        return true;
    }

    @SuppressWarnings("deprecation") // KeyEvent.getCharacters
    @Override
    public boolean sendKeyEvent(KeyEvent event) {
        String characters = event.getCharacters();
        if (characters != null) {
            for (int codepoint : characters.codePoints().toArray()) {
                WioActivity.pushCharEventNative(codepoint);
            }
        }
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
