package net.tiredsleepy.wio;

import android.view.SurfaceView;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;

public class WioSurfaceView extends SurfaceView {
    WioInputConnection inputConnection;

    public WioSurfaceView(WioActivity context) {
        super(context);
        inputConnection = new WioInputConnection(this, true);
    }

    @Override
    public InputConnection onCreateInputConnection(EditorInfo outAttrs) {
        return inputConnection;
    }
}
