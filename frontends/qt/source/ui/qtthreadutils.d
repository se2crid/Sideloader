module ui.qtthreadutils;

import core.stdcpp.new_: cpp_new;

import qt.core.coreapplication;
import qt.core.object;
import qt.core.thread;
import qt.core.timer;
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
        // Use timer-based approach for thread-safe execution
        runInUIThreadTimer(action);
    }
}

// UIThreadInvoker class removed - using timer-based approach instead

/**
 * Timer-based implementation for UI thread execution
 * This is a reliable approach that works with most Qt bindings
 */
void runInUIThreadTimer(void delegate() action) {
    if (QThread.currentThread() == QCoreApplication.instance().thread()) {
        // Already in UI thread, execute immediately
        action();
    } else {
        // Use single-shot timer to execute in UI thread
        auto timer = new QTimer();
        timer.setSingleShot(true);
        QObject.connect(timer.signal!"timeout", delegate() {
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
