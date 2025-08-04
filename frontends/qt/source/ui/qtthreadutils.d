module ui.qtthreadutils;

import core.stdcpp.new_: cpp_new;

import qt.core.coreapplication;
import qt.core.object;
import qt.core.thread;
import qt.helpers;

/**
 * Utility functions for proper Qt thread management
 * This module provides thread-safe UI updates for the Qt frontend
 */

/**
 * Execute a delegate in the main UI thread
 * This is the proper Qt way to update UI from background threads
 */
void runInUIThread(void delegate() action) {
    if (QThread.currentThread() == QCoreApplication.instance().thread()) {
        // Already in UI thread, execute immediately
        action();
    } else {
        // Schedule execution in UI thread using Qt's event system
        auto invoker = new UIThreadInvoker(action);
        QMetaObject.invokeMethod(
            invoker,
            "execute",
            Qt.ConnectionType.QueuedConnection
        );
    }
}

/**
 * Helper class for executing delegates in the UI thread
 * Uses Qt's meta-object system for thread-safe execution
 */
private class UIThreadInvoker : QObject {
    mixin(Q_OBJECT_D);
    
    private void delegate() action;
    
    this(void delegate() action) {
        this.action = action;
        // Move to main thread to ensure proper execution
        moveToThread(QCoreApplication.instance().thread());
    }
    
    @QSlot
    void execute() {
        if (action) {
            try {
                action();
            } catch (Exception ex) {
                // Log error but don't crash the UI thread
                import slf4d;
                auto log = getLogger();
                log.errorF!"Error in UI thread execution: %s"(ex.msg);
            }
        }
        
        // Clean up - this object is no longer needed
        deleteLater();
    }
}

/**
 * Alternative implementation using QTimer for simpler cases
 * This can be used when QMetaObject.invokeMethod is not available
 */
void runInUIThreadTimer(void delegate() action) {
    import qt.core.timer;
    
    if (QThread.currentThread() == QCoreApplication.instance().thread()) {
        // Already in UI thread, execute immediately
        action();
    } else {
        // Use single-shot timer to execute in UI thread
        auto timer = new QTimer();
        timer.setSingleShot(true);
        timer.timeout.connect(() {
            try {
                action();
            } catch (Exception ex) {
                import slf4d;
                auto log = getLogger();
                log.errorF!"Error in UI thread execution: %s"(ex.msg);
            }
            timer.deleteLater();
        });
        timer.start(0); // Execute as soon as possible
    }
}
